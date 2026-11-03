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
  mfa: 'Complete authenticator verification to continue.',
  mfa_code: 'That code was not accepted or has expired. Enter the current six-digit code and try again.',
  mfa_setup: 'Authenticator setup changed. Check the current setup before trying again.',
  mfa_input: 'Select your authenticator and enter its six-digit code.',
  reset_link: 'This reset link is invalid, expired or already used. Request a new link in this browser.',
  reset_pending: 'Check your inbox and spam first. Start over to request a new link; earlier links will stop working in this browser.',
  password_input: 'Use 8 to 72 bytes with an uppercase letter, a lowercase letter, a number and a special character.',
  password_current: 'Current password is incorrect.',
  password_same: 'Choose a different new password.',
  password_update: 'The update could not be confirmed. Try signing in with your new password, or request a fresh reset link.',
  password_reauth: 'Sign in again before changing your password.',
  reset_signedin: 'Sign out of your current account before opening a password reset link.',
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

export function authDiagnostic(stage, outcome, { appStatus, upstreamStatus, startedAt } = {}) {
  if (process.env.NODE_ENV !== 'development' || process.env.AUTH_DIAGNOSTICS !== 'true') return;
  // Only fixed caller labels, bounded statuses and timing; never input/error objects.
  const validStatus = value => Number.isInteger(value) && value >= 100 && value <= 599;
  console.info('[auth_diagnostic]', JSON.stringify({
    stage, outcome,
    ...(validStatus(appStatus) ? { app_status: appStatus } : {}),
    ...(validStatus(upstreamStatus) ? { upstream_status: upstreamStatus } : {}),
    ...(Number.isFinite(startedAt) ? { elapsed_ms: Math.round(Math.max(0, performance.now() - startedAt) * 100) / 100 } : {}),
    at: new Date().toISOString(),
  }));
}

async function request(url, options = {}, diagnosticStage) {
  const startedAt = performance.now();
  try {
    const response = await fetch(url, { ...options, cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(10000) });
    if (diagnosticStage) authDiagnostic(diagnosticStage, 'response_received', { upstreamStatus: response.status, startedAt });
    return response;
  } catch (error) {
    if (diagnosticStage) authDiagnostic(diagnosticStage,
      error?.name === 'TimeoutError' || error?.name === 'AbortError' ? 'timeout' : 'transport_unavailable', { startedAt });
    throw new AuthError('unavailable');
  }
}

export function isAdministrator(profile) {
  return Boolean(profile && typeof profile.id === 'string' && profile.id &&
    profile.role === 'admin' && profile.approval_status === 'approved' && profile.is_active === true);
}

export async function verifyAdministratorIdentity(accessToken) {
  if (!accessToken) throw new AuthError('expired', 401);
  const response = await request(`${baseUrl(process.env.BACKEND_BASE_URL)}/auth/me`, {
    headers: { Authorization: `Bearer ${accessToken}`, Accept: 'application/json' },
  }, 'fastapi_verification_request');
  if (response.status === 401) throw new AuthError('expired', 401);
  if (response.status === 403) throw new AuthError('denied', 403);
  if (!response.ok) throw new AuthError('unavailable');
  let profile;
  try { profile = await response.json(); } catch { throw new AuthError('unavailable'); }
  if (!isAdministrator(profile)) throw new AuthError('denied', 403);
  return profile;
}

export async function verifyAdministrator(accessToken) {
  const profile = await verifyAdministratorIdentity(accessToken);
  if (profile.mfa_verified !== true || profile.aal !== 'aal2') throw new AuthError('mfa', 403);
  return profile;
}

export function validatedSession(session) {
  if (typeof session?.access_token !== 'string' || !session.access_token ||
      typeof session.refresh_token !== 'string' || !session.refresh_token ||
      !Number.isFinite(session.expires_in) || session.expires_in <= 0) throw new AuthError('unavailable');
  return session;
}

export async function exchangeToken(grant, body) {
  const { url, key } = supabaseConfig();
  const response = await request(`${url}/auth/v1/token?grant_type=${grant}`, {
    method: 'POST', headers: { apikey: key, 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  }, grant === 'password' ? 'supabase_password_request' : undefined);
  if (response.status === 429) throw new AuthError('rate', 429);
  if ([400, 401, 403, 422].includes(response.status)) throw new AuthError(grant === 'password' ? 'credentials' : 'expired', 401);
  if (!response.ok) throw new AuthError('unavailable');
  let session;
  try { session = await response.json(); } catch { throw new AuthError('unavailable'); }
  return validatedSession(session);
}

// Native user-scoped Auth only: never admin APIs, shared SDK sessions, or raw
// upstream messages. Returned credentials are handled only in server routes.
export async function mfaAuthRequest(path, token, method = 'POST', body) {
  if (!/^factors(?:\/[0-9a-f-]{36}(?:\/(?:challenge|verify))?)?$/.test(path)) throw new AuthError('mfa_input', 400);
  const { url, key } = supabaseConfig();
  const response = await request(`${url}/auth/v1/${path}`, {
    method, headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  let data;
  try { data = await response.json(); } catch { throw new AuthError('unavailable'); }
  if (response.status === 429) throw new AuthError('rate', 429);
  if (response.status === 401) throw new AuthError('expired', 401);
  if (!response.ok) {
    if ([400, 403, 404, 409, 422].includes(response.status)) {
      throw new AuthError(path.endsWith('/verify') ? 'mfa_code' : 'mfa_setup', path.endsWith('/verify') ? 400 : 409);
    }
    throw new AuthError('unavailable');
  }
  return data;
}

// Existing native, user-scoped password endpoints only. Recovery never uses a
// service key or changes application profiles, roles, approval or MFA factors.
export async function passwordAuthRequest(path, token, method, body, redirectTo) {
  if (!['recover', 'user'].includes(path)) throw new AuthError('input', 400);
  const { url, key } = supabaseConfig();
  const destination = new URL(`${url}/auth/v1/${path}`);
  if (path === 'recover') destination.searchParams.set('redirect_to', redirectTo);
  let response;
  try {
    response = await request(destination.href, {
      method, headers: { apikey: key, 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
  } catch (error) {
    if (method === 'PUT') throw new AuthError('password_update');
    throw error;
  }
  // Account existence, SMTP restrictions and mail limits have the same result.
  // Keep the verifier even after a rejected/uncertain request; never auto-retry.
  if (path === 'recover') return {};
  const data = await response.json().catch(() => null);
  if (response.status === 429) throw new AuthError('rate', 429);
  if (response.status === 401) throw new AuthError('expired', 401);
  if (!response.ok) {
    const code = { current_password_mismatch: 'password_current', same_password: 'password_same', weak_password: 'password_input',
      reauthentication_needed: 'password_reauth', reauthentication_not_valid: 'password_reauth', insufficient_aal: 'mfa' }[data?.code];
    throw new AuthError(code || (method === 'PUT' ? 'password_update' : 'expired'), code ? 400 : method === 'PUT' ? 503 : 401);
  }
  if (!data) throw new AuthError(method === 'PUT' ? 'password_update' : 'unavailable');
  return data;
}

// Page/data requests must never rotate tokens or mutate browser cookies.
// Only the browser-coordinated refresh endpoint calls refreshSession.
export async function restoreSession(accessToken) {
  return { profile: await verifyAdministrator(accessToken), session: null };
}

// Only for allowlisted API proxies whose FastAPI destination requires an admin.
// This is not an authorization decision: every resource request verifies current
// Auth state, approval and role in FastAPI. Pages and auth flows use restoreSession.
export async function forwardSession(accessToken) {
  if (!accessToken) throw new AuthError('expired', 401);
  return { session: null };
}

export async function refreshSession(accessToken, refreshToken) {
  try {
    const profile = await verifyAdministratorIdentity(accessToken);
    return { profile, session: null };
  } catch (error) {
    if (error.status !== 401 || !refreshToken) throw error;
  }
  const session = await exchangeToken('refresh_token', { refresh_token: refreshToken });
  try {
    return { profile: await verifyAdministratorIdentity(session.access_token), session };
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
