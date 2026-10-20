// Server-side only: imported by Proxy, route handlers and the admin layout.
export const ACCESS_COOKIE = 'vp-access';
export const REFRESH_COOKIE = 'vp-refresh';
export const messages = {
  expired: 'Your session has expired. Please sign in again.',
  denied: 'Access is restricted to approved, active administrators.',
  credentials: 'Unable to sign in. Check your email and password and confirm your email if required.',
  unavailable: 'Authentication services are unavailable. Please try again.',
  input: 'Enter a valid email address and password.',
  rate: 'Too many attempts. Please wait and try again.',
  origin: 'This request could not be verified. Reload the page and try again.',
};

export class AuthError extends Error {
  constructor(code, status = 503) {
    super(messages[code] ?? messages.unavailable);
    this.code = code;
    this.status = status;
  }
}

export function baseUrl(value) {
  try {
    const url = new URL(value);
    if (url.username || url.password || url.search || url.hash ||
        (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)))) throw new Error();
    return url.href.replace(/\/$/, '');
  } catch { throw new AuthError('unavailable'); }
}

function supabaseConfig() {
  const url = baseUrl(process.env.SUPABASE_URL);
  const key = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY;
  let anon = false;
  try { anon = JSON.parse(Buffer.from(key.split('.')[1], 'base64url').toString()).role === 'anon'; } catch {}
  if (!key || (!key.startsWith('sb_publishable_') && !anon)) throw new AuthError('unavailable');
  return { url, key };
}

async function request(url, options = {}) {
  try {
    return await fetch(url, { ...options, cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(10000) });
  } catch { throw new AuthError('unavailable'); }
}

export function isAdministrator(profile) {
  return Boolean(profile && typeof profile.id === 'string' && profile.id &&
    profile.role === 'admin' && profile.approval_status === 'approved' && profile.is_active === true);
}

export async function verifyAdministrator(accessToken) {
  if (!accessToken) throw new AuthError('expired', 401);
  const response = await request(`${baseUrl(process.env.BACKEND_BASE_URL)}/auth/me`, {
    headers: { Authorization: `Bearer ${accessToken}`, Accept: 'application/json' },
  });
  if (response.status === 401) throw new AuthError('expired', 401);
  if (response.status === 403) throw new AuthError('denied', 403);
  if (!response.ok) throw new AuthError('unavailable');
  let profile;
  try { profile = await response.json(); } catch { throw new AuthError('unavailable'); }
  if (!isAdministrator(profile)) throw new AuthError('denied', 403);
  return profile;
}

export async function exchangeToken(grant, body) {
  const { url, key } = supabaseConfig();
  const response = await request(`${url}/auth/v1/token?grant_type=${grant}`, {
    method: 'POST', headers: { apikey: key, 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  });
  if (response.status === 429) throw new AuthError('rate', 429);
  if ([400, 401, 403, 422].includes(response.status)) throw new AuthError(grant === 'password' ? 'credentials' : 'expired', 401);
  if (!response.ok) throw new AuthError('unavailable');
  let session;
  try { session = await response.json(); } catch { throw new AuthError('unavailable'); }
  if (typeof session.access_token !== 'string' || !session.access_token ||
      typeof session.refresh_token !== 'string' || !session.refresh_token ||
      !Number.isFinite(session.expires_in) || session.expires_in <= 0) throw new AuthError('unavailable');
  return session;
}

export async function restoreSession(accessToken, refreshToken) {
  try {
    const profile = await verifyAdministrator(accessToken);
    return { profile, session: null };
  } catch (error) {
    if (error.status !== 401 || !refreshToken) throw error;
  }
  const session = await exchangeToken('refresh_token', { refresh_token: refreshToken });
  try {
    return { profile: await verifyAdministrator(session.access_token), session };
  } catch (error) {
    // Preserve rotated tokens during a temporary backend outage, never grant access.
    if (error.status === 503) error.session = session;
    throw error;
  }
}

export async function revokeSession(accessToken, refreshToken) {
  if (!accessToken && !refreshToken) return true;
  try {
    const { url, key } = supabaseConfig();
    const logout = (token) => request(`${url}/auth/v1/logout?scope=local`, {
      method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}` },
    });
    let response = accessToken ? await logout(accessToken) : null;
    if ((!response || response.status === 401) && refreshToken) {
      const session = await exchangeToken('refresh_token', { refresh_token: refreshToken });
      response = await logout(session.access_token);
    }
    return Boolean(response?.ok);
  } catch { return false; }
}

const cookieOptions = () => ({ httpOnly: true, secure: process.env.NODE_ENV === 'production', sameSite: 'lax', path: '/' });
export function setSessionCookies(response, session) {
  response.cookies.set(ACCESS_COOKIE, session.access_token, { ...cookieOptions(), maxAge: Math.floor(session.expires_in) });
  response.cookies.set(REFRESH_COOKIE, session.refresh_token, { ...cookieOptions(), maxAge: 60 * 60 * 24 * 30 });
}
export function clearSessionCookies(response) {
  for (const name of [ACCESS_COOKIE, REFRESH_COOKIE]) response.cookies.set(name, '', { ...cookieOptions(), maxAge: 0 });
}
export function requireSameOrigin(request) {
  const origin = request.headers.get('origin');
  const url = new URL(request.url);
  // Next's internal URL may use the bind hostname; Host is the browser-facing authority.
  const expected = `${url.protocol}//${request.headers.get('host') || url.host}`;
  if (!origin || origin !== expected || request.headers.get('sec-fetch-site') === 'cross-site') throw new AuthError('origin', 403);
}
