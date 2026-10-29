import { ACCESS_COOKIE, REFRESH_COOKIE, AuthError, baseUrl, restoreSession } from './auth.mjs';
import { validateSessions } from './sessions-contracts.mjs';
export { validateSessions } from './sessions-contracts.mjs';

export async function loadSessions(request) {
  let session;
  try {
    const restored = await restoreSession(request.cookies.get(ACCESS_COOKIE)?.value, request.cookies.get(REFRESH_COOKIE)?.value);
    session = restored.session;
    const params = new URLSearchParams();
    const input = new URL(request.url).searchParams;
    for (const key of ['limit', 'offset', 'plate', 'status', 'level_id', 'start_date', 'end_date']) if (input.has(key)) params.set(key, input.get(key));
    const response = await fetch(`${baseUrl(process.env.BACKEND_BASE_URL)}/admin/parking/sessions?${params}`, {
      headers: { Authorization: `Bearer ${session?.access_token ?? request.cookies.get(ACCESS_COOKIE)?.value}`, Accept: 'application/json' },
      cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(10000),
    });
    if (response.status === 401) throw new AuthError('expired', 401);
    if (response.status === 403) throw new AuthError('denied', 403);
    if (response.status === 422) return { status: 422, session, body: { error: 'Choose a valid plate, status, level, page and date range (up to 90 days, ending no later than today).' } };
    if (!response.ok) throw new Error('Unavailable');
    return { body: validateSessions(await response.json()), status: 200, session };
  } catch (error) {
    return { body: { error: error instanceof AuthError ? error.message : 'Parking sessions are unavailable. Please refresh and try again.' },
      status: error instanceof AuthError ? error.status : 503, session: error.session ?? session,
      clear: error instanceof AuthError && [401, 403].includes(error.status) };
  }
}

