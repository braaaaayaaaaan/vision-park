// Browser-only session mutations. Web Locks coordinate tabs and do not depend
// on a Next.js process, a module singleton, or readable credential storage.
export const AUTH_LOCK = 'visionpark-admin-auth';
export const AUTH_GENERATION = 'visionpark-admin-auth-generation';
// This is not an HTTP rejection: an in-flight mutation may already have
// committed. Existing callers must keep its outcome unconfirmed, not retry it.
const changed = () => Object.assign(new Error('Your session changed in another tab. Reload the page before continuing.'), { sessionChanged: true });

export function createAuthCoordinator({ locks, storage, fetch: request, randomId }) {
  const generation = () => storage.getItem(AUTH_GENERATION) ?? '';
  async function mutate(kind, input, expected = generation()) {
    const extended = kind === 'mfa' || kind === 'password';
    if (!locks?.request) throw new Error('Use a current browser with Web Locks support over HTTPS or localhost to sign in securely.');
    return locks.request(AUTH_LOCK, { mode: 'exclusive', signal: AbortSignal.timeout(extended ? 100000 : 40000) }, async () => {
      // A queued logout/refresh/login must not act on a replacement session.
      if (generation() !== expected) throw changed();
      // Reject unavailable storage before sending a credential mutation.
      storage.setItem(AUTH_GENERATION, expected);
      const response = await request(`/api/auth/${kind}`, {
        method: 'POST', credentials: 'same-origin', cache: 'no-store',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(input ?? {}), signal: AbortSignal.timeout(extended ? 90000 : 35000),
      });
      if (((kind === 'logout' || kind === 'login') && response.ok) ||
          (kind === 'mfa' && response.headers.get('X-VisionPark-Session-Changed') === '1')) {
        // No JWTs, refresh tokens or user information are stored here.
        storage.setItem(AUTH_GENERATION, randomId());
      }
      return response;
    });
  }
  return {
    generation,
    login: input => mutate('login', input),
    logout: () => mutate('logout'),
    refresh: expected => mutate('refresh', undefined, expected),
    mfa: input => mutate('mfa', input),
    password: input => mutate('password', input),
  };
}

function browserAuth() {
  return createAuthCoordinator({ locks: navigator.locks, storage: window.localStorage,
    fetch: (...args) => fetch(...args), randomId: () => crypto.randomUUID() });
}

export const loginAdministrator = input => browserAuth().login(input);
export const logoutAdministrator = () => browserAuth().logout();
export const refreshAdministrator = () => browserAuth().refresh(browserAuth().generation());
export const mutateAdministratorMfa = input => browserAuth().mfa(input);
export const mutateAdministratorPassword = input => browserAuth().password(input);

export function createAuthenticatedFetch(auth, request) {
  return async (url, options = {}) => {
    const before = auth.generation();
    const response = await request(url, options);
    if (auth.generation() !== before) throw changed();
    if (response.status !== 401 || options.signal?.aborted) return response;
    const restored = await auth.refresh(before);
    if (auth.generation() !== before) throw changed();
    if (!restored.ok) return restored;
    const state = await restored.clone().json().catch(() => null);
    if (state?.mfa_required) return new Response(JSON.stringify({ code: 'mfa_required', error: 'Complete authenticator verification to continue.' }), {
      status: 403, headers: { 'Content-Type': 'application/json' },
    });
    // A route's 401 means authorization failed before its business operation.
    // Retry once only, using the cookies now applied by the browser.
    const retried = await request(url, options);
    if (auth.generation() !== before) throw changed();
    return retried;
  };
}

export async function authenticatedFetch(url, options = {}) {
  // Keep the existing injectable fetch boundary in non-browser unit tests.
  if (typeof window === 'undefined') return fetch(url, options);
  const response = await createAuthenticatedFetch(browserAuth(), (...args) => fetch(...args))(url, options);
  if (response.status === 403 && !options.signal?.aborted) {
    // Business proxies intentionally return safe generic 403s. A read-only
    // bootstrap check distinguishes a real MFA detour from a role denial.
    const status = await fetch('/api/auth/mfa', { credentials: 'same-origin', cache: 'no-store' }).catch(() => null);
    const state = status?.ok ? await status.json().catch(() => null) : null;
    if (state?.ready === false) window.location.replace('/mfa');
  }
  return response;
}
