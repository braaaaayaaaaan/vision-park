import { ACCESS_COOKIE, REFRESH_COOKIE, AuthError, baseUrl, restoreSession } from './auth.mjs';
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const nullable = (value, check) => value === null || check(value);
const string = value => typeof value === 'string';
const timestamp = value => string(value) && /(?:Z|[+-]\d{2}:\d{2})$/.test(value) && Number.isFinite(Date.parse(value));
export function validateSessions(data) {
  if (!data || data.timezone !== 'Asia/Kuala_Lumpur' || !Number.isSafeInteger(data.total) || data.total < 0 ||
      !Number.isInteger(data.limit) || data.limit < 1 || data.limit > 100 || !Number.isSafeInteger(data.offset) || data.offset < 0 ||
      !Array.isArray(data.sessions) || data.sessions.length > data.limit || data.sessions.length > Math.max(0, data.total - data.offset) ||
      data.sessions.some(row => !row || !uuid.test(row.id) || !['allocated', 'occupied', 'completed', 'cancelled'].includes(row.status) ||
        !['vehicle_id', 'zone_id', 'level_id'].every(key => nullable(row[key], value => uuid.test(value))) ||
        !['plate_number', 'owner_name', 'tenant_name', 'zone_name', 'level_name'].every(key => nullable(row[key], string)) ||
        !['entry_time', 'parking_confirmed_at', 'exit_time'].every(key => nullable(row[key], timestamp)) ||
        !(row.duration_seconds === null || (row.status === 'completed' && row.entry_time && row.exit_time && Number.isFinite(row.duration_seconds) && row.duration_seconds >= 0 &&
          Date.parse(row.exit_time) >= Date.parse(row.entry_time) && Math.abs(row.duration_seconds - (Date.parse(row.exit_time) - Date.parse(row.entry_time)) / 1000) < 0.002))) ||
      !Array.isArray(data.levels) || data.levels.some(level => !level || !uuid.test(level.id) || !string(level.name) || !Number.isInteger(level.level_number) || typeof level.is_active !== 'boolean')) throw new Error('Invalid session response');
  return data;
}

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

