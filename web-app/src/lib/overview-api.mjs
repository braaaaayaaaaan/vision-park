import { ACCESS_COOKIE, REFRESH_COOKIE, AuthError, baseUrl, restoreSession } from './auth.mjs';

const count = (value) => Number.isSafeInteger(value) && value >= 0;
const timestamp = (value) => typeof value === 'string' && /(?:Z|[+-]\d{2}:\d{2})$/.test(value) && Number.isFinite(Date.parse(value));
const stats = (value) => value && ['usable_capacity', 'occupied', 'reserved', 'available'].every((key) => count(value[key])) &&
  (value.usable_capacity === 0 ? value.occupancy_percentage === null : Number.isFinite(value.occupancy_percentage) && value.occupancy_percentage >= 0);

export function validateOverview(data) {
  if (!data || data.timezone !== 'Asia/Kuala_Lumpur' || !/^\d{4}-\d{2}-\d{2}$/.test(data.reporting_date) ||
      !['period_start', 'period_end', 'generated_at'].every((key) => timestamp(data[key])) ||
      !stats(data.totals) || !count(data.today_entries) || !count(data.today_exits) ||
      !Array.isArray(data.hourly) || data.hourly.length !== 24 || data.hourly.some((hour, index) => !hour || hour.hour !== index || !count(hour.entries) || !count(hour.exits)) ||
      data.hourly.reduce((sum, hour) => sum + hour.entries, 0) !== data.today_entries ||
      data.hourly.reduce((sum, hour) => sum + hour.exits, 0) !== data.today_exits ||
      !Array.isArray(data.levels) || data.levels.some((level) => !stats(level) || typeof level.id !== 'string' || typeof level.name !== 'string' || !Number.isInteger(level.level_number)) ||
      !Array.isArray(data.recent_sessions) || data.recent_sessions.some((row) => !row || typeof row.id !== 'string' ||
        !['allocated', 'occupied', 'completed'].includes(row.status) || !timestamp(row.entry_time) || (row.exit_time !== null && !timestamp(row.exit_time)) ||
        !['plate_number', 'zone_name', 'level_name'].every((key) => row[key] === null || typeof row[key] === 'string'))) {
    throw new Error('Invalid overview response');
  }
  return data;
}

export async function loadOverview(request) {
  let session;
  try {
    const restored = await restoreSession(request.cookies.get(ACCESS_COOKIE)?.value, request.cookies.get(REFRESH_COOKIE)?.value);
    session = restored.session;
    const token = session?.access_token ?? request.cookies.get(ACCESS_COOKIE)?.value;
    const response = await fetch(`${baseUrl(process.env.BACKEND_BASE_URL)}/admin/parking/overview`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(10000),
    });
    if (response.status === 401) throw new AuthError('expired', 401);
    if (response.status === 403) throw new AuthError('denied', 403);
    if (!response.ok) throw new Error('Overview unavailable');
    return { body: validateOverview(await response.json()), status: 200, session };
  } catch (error) {
    return { body: { error: error instanceof AuthError ? error.message : 'Parking overview is unavailable. Please refresh and try again.' },
      status: error instanceof AuthError ? error.status : 503, session: error.session ?? session,
      clear: error instanceof AuthError && [401, 403].includes(error.status) };
  }
}
