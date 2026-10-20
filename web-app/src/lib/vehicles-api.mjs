import { ACCESS_COOKIE, REFRESH_COOKIE, AuthError, baseUrl, restoreSession, requireSameOrigin } from './auth.mjs';
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const nullable = (value, check) => value === null || check(value);
const string = (value) => typeof value === 'string';
export function validateVehicles(data) {
  if (!data || !Number.isSafeInteger(data.total) || data.total < 0 || !Number.isInteger(data.limit) || data.limit < 1 || data.limit > 100 ||
      !Number.isSafeInteger(data.offset) || data.offset < 0 || !Array.isArray(data.vehicles) || data.vehicles.length > data.limit ||
      data.vehicles.length > Math.max(0, data.total - data.offset) ||
      data.vehicles.some(row => !row || !uuid.test(row.id) || !string(row.plate_number) || !['approved', 'pending', 'rejected'].includes(row.registration_status) ||
        !nullable(row.owner_id, value => uuid.test(value)) || !nullable(row.owner_name, string) || !nullable(row.tenant_id, value => uuid.test(value)) || !nullable(row.tenant_name, string)) ||
      !Array.isArray(data.companies) || data.companies.some(row => !row || !uuid.test(row.id) || !string(row.name))) throw new Error('Invalid vehicle response');
  return data;
}

export async function loadVehicles(request) {
  let session;
  try {
    const restored = await restoreSession(request.cookies.get(ACCESS_COOKIE)?.value, request.cookies.get(REFRESH_COOKIE)?.value);
    session = restored.session;
    const params = new URLSearchParams();
    const input = new URL(request.url).searchParams;
    for (const key of ['limit', 'offset', 'plate', 'status', 'tenant_id']) if (input.has(key)) params.set(key, input.get(key));
    const response = await fetch(`${baseUrl(process.env.BACKEND_BASE_URL)}/admin/vehicles?${params}`, {
      headers: { Authorization: `Bearer ${session?.access_token ?? request.cookies.get(ACCESS_COOKIE)?.value}`, Accept: 'application/json' },
      cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(10000),
    });
    if (response.status === 401) throw new AuthError('expired', 401);
    if (response.status === 403) throw new AuthError('denied', 403);
    if (response.status === 422) return { status: 422, session, body: { error: 'Choose a valid plate search, registration status, company and page.' } };
    if (!response.ok) throw new Error('Unavailable');
    return { body: validateVehicles(await response.json()), status: 200, session };
  } catch (error) {
    return { body: { error: error instanceof AuthError ? error.message : 'Vehicle records are unavailable. Please refresh and try again.' },
      status: error instanceof AuthError ? error.status : 503, session: error.session ?? session,
      clear: error instanceof AuthError && [401, 403].includes(error.status) };
  }
}

export async function decideVehicle(request, vehicleId, action) {
  let session;
  try {
    requireSameOrigin(request);
    if (!uuid.test(vehicleId) || !['approve', 'reject'].includes(action)) {
      return { status: 404, body: { error: 'Vehicle decision endpoint not found.' } };
    }
    const restored = await restoreSession(request.cookies.get(ACCESS_COOKIE)?.value, request.cookies.get(REFRESH_COOKIE)?.value);
    session = restored.session;
    let input;
    try { input = await request.json(); } catch { return { status: 400, session, body: { error: 'Invalid vehicle decision request.' } }; }
    if (!input || typeof input !== 'object' || Array.isArray(input) || Object.keys(input).length > 0) {
      return { status: 400, session, body: { error: 'Vehicle decisions do not accept editable fields.' } };
    }
    const response = await fetch(`${baseUrl(process.env.BACKEND_BASE_URL)}/admin/vehicles/${vehicleId}/${action}`, {
      method: 'POST', headers: { Authorization: `Bearer ${session?.access_token ?? request.cookies.get(ACCESS_COOKIE)?.value}`, Accept: 'application/json' },
      cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(10000),
    });
    if (response.status === 401) throw new AuthError('expired', 401);
    if (response.status === 403) throw new AuthError('denied', 403);
    const errors = {
      404: 'Vehicle not found. Close this dialog and refresh the list.',
      409: 'This registration has already been processed. Close this dialog and refresh the list.',
      422: 'Invalid vehicle decision. Close this dialog and refresh the list.',
    };
    if (errors[response.status]) return { status: response.status, session, body: { error: errors[response.status] } };
    if (!response.ok) throw new Error('Unavailable');
    const result = await response.json();
    if (result?.id !== vehicleId || typeof result.plate_number !== 'string' || !result.plate_number || result.registration_status !== (action === 'approve' ? 'approved' : 'rejected')) throw new Error('Invalid decision response');
    return { status: 200, session, body: { id: result.id, plate_number: result.plate_number, registration_status: result.registration_status } };
  } catch (error) {
    return { body: { error: error instanceof AuthError ? error.message : 'Vehicle decision could not be confirmed. Close this dialog and refresh the list before retrying.' },
      status: error instanceof AuthError ? error.status : 503, session: error.session ?? session,
      clear: error instanceof AuthError && ['expired', 'denied'].includes(error.code) };
  }
}
