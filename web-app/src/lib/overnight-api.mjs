import { ACCESS_COOKIE, AuthError, baseUrl, verifyAdministrator } from './auth.mjs';
import { overnightQuery, validateOvernightAlerts } from './overnight-contracts.mjs';

export async function loadOvernightAlerts(request) {
  try {
    const token = request.cookies.get(ACCESS_COOKIE)?.value;
    await verifyAdministrator(token);
    let query;
    try { query = overnightQuery(new URL(request.url).searchParams); }
    catch (error) { return { status: 422, body: { error: error.message } }; }
    const response = await fetch(`${baseUrl(process.env.BACKEND_BASE_URL)}/admin/parking/sessions/overnight?${query}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' }, cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(10000),
    });
    if (response.status === 401) throw new AuthError('expired', 401);
    if (response.status === 403) throw new AuthError('denied', 403);
    if (response.status === 422) return { status: 422, body: { error: 'Choose a valid overnight alert view, page and past-stay date range of up to 90 days, ending no later than today.' } };
    if (!response.ok) throw new Error('Unavailable');
    return { status: 200, body: validateOvernightAlerts(await response.json(), query) };
  } catch (error) {
    return { status: error instanceof AuthError ? error.status : 503,
      body: { error: error instanceof AuthError ? error.message : 'Overnight parking alerts are unavailable. Please retry.' } };
  }
}
