import { ACCESS_COOKIE, REFRESH_COOKIE, AuthError, baseUrl, restoreSession } from './auth.mjs';
const count = (value) => Number.isSafeInteger(value) && value >= 0;
const date = (value) => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) && Number.isFinite(Date.parse(value));
const timestamp = (value) => typeof value === 'string' && /(?:Z|[+-]\d{2}:\d{2})$/.test(value) && Number.isFinite(Date.parse(value));
function validateUtilisation(data) {
  const fields = ['historical_occupancy', 'parking_demand', 'tenant_activity'];
  // Permit an older Stage 5A server, but never substitute invented zero datasets.
  if (fields.every((key) => data[key] === undefined)) return;
  const history = data.historical_occupancy, demand = data.parking_demand, activity = data.tenant_activity;
  const named = (item) => item && typeof item.id === 'string' && typeof item.name === 'string';
  if (!history || !['hour_start', 'day_end_or_refresh'].includes(history.checkpoint) || !Array.isArray(history.points) ||
      history.points.some((point, index, points) => !point || !timestamp(point.timestamp) || !count(point.occupied) ||
        Date.parse(point.timestamp) < Date.parse(data.period_start) || Date.parse(point.timestamp) >= Date.parse(data.period_end) || Date.parse(point.timestamp) > Date.parse(data.generated_at) ||
        (index > 0 && Date.parse(point.timestamp) <= Date.parse(points[index - 1].timestamp))) ||
      !demand || !count(demand.unmapped_assignments) || !Array.isArray(demand.levels) || demand.levels.some((level) => !named(level) || !Number.isInteger(level.level_number) || !count(level.assignments) || !Array.isArray(level.zones) ||
        level.zones.some((zone) => !named(zone) || !count(zone.assignments)) || level.zones.reduce((sum, zone) => sum + zone.assignments, 0) !== level.assignments) ||
      !activity || activity.association !== 'session_user_current_tenant' || !count(activity.unattributed_sessions) || !Array.isArray(activity.tenants) || activity.tenants.some((tenant) => !named(tenant) || !count(tenant.sessions)) ||
      demand.levels.reduce((sum, level) => sum + level.assignments, demand.unmapped_assignments) !== data.summary.total_entries ||
      activity.tenants.reduce((sum, tenant) => sum + tenant.sessions, activity.unattributed_sessions) !== data.summary.total_entries) {
    throw new Error('Invalid utilisation response');
  }
}
export function validateAnalytics(data) {
  const s = data?.summary;
  const d = data?.durations;
  const peak = (value) => value === null || (value && Number.isInteger(value.hour) && value.hour >= 0 && value.hour <= 23 && count(value.count) && value.count > 0);
  const movement = (row) => row && typeof row.period === 'string' && count(row.entries) && count(row.exits);
  const days = (Date.parse(data?.end_date) - Date.parse(data?.start_date)) / 86400000 + 1;
  if (!data || !date(data.start_date) || !date(data.end_date) || !Number.isInteger(days) || days < 1 || days > 90 || data.timezone !== 'Asia/Kuala_Lumpur' ||
      !['period_start', 'period_end', 'generated_at'].every((key) => timestamp(data[key])) ||
      !(data.level_id === null || typeof data.level_id === 'string') || !Array.isArray(data.levels) || data.levels.some((level) => !level || typeof level.id !== 'string' || typeof level.name !== 'string' || !Number.isInteger(level.level_number) || typeof level.is_active !== 'boolean') ||
      !s || !count(s.total_entries) || !count(s.total_exits) || !peak(s.peak_entry_hour) || !peak(s.peak_exit_hour) ||
      !d || !count(d.valid_completed_sessions) || (d.valid_completed_sessions === 0 ? s.average_duration_seconds !== null : !Number.isFinite(s.average_duration_seconds) || s.average_duration_seconds < 0) ||
      !Array.isArray(d.distribution) || d.distribution.length !== 5 || d.distribution.some((bucket) => !bucket || typeof bucket.label !== 'string' || !count(bucket.count)) || d.distribution.reduce((sum, bucket) => sum + bucket.count, 0) !== d.valid_completed_sessions ||
      data.granularity !== (days === 1 ? 'hour' : 'day') || !Array.isArray(data.movements) || data.movements.length !== (days === 1 ? 24 : days) || data.movements.some((row) => !movement(row)) ||
      !Array.isArray(data.hourly_pattern) || data.hourly_pattern.length !== 24 || data.hourly_pattern.some((row, index) => !row || row.hour !== index || !count(row.entries) || !count(row.exits)) ||
      [data.movements, data.hourly_pattern].some((rows) => rows.reduce((sum, row) => sum + row.entries, 0) !== s.total_entries || rows.reduce((sum, row) => sum + row.exits, 0) !== s.total_exits)) {
    throw new Error('Invalid analytics response');
  }
  validateUtilisation(data);
  return data;
}

export async function loadAnalytics(request) {
  let session;
  try {
    const restored = await restoreSession(request.cookies.get(ACCESS_COOKIE)?.value, request.cookies.get(REFRESH_COOKIE)?.value);
    session = restored.session;
    const params = new URLSearchParams();
    const input = new URL(request.url).searchParams;
    for (const key of ['start_date', 'end_date', 'level_id']) if (input.has(key)) params.set(key, input.get(key));
    const response = await fetch(`${baseUrl(process.env.BACKEND_BASE_URL)}/admin/parking/analytics?${params}`, {
      headers: { Authorization: `Bearer ${session?.access_token ?? request.cookies.get(ACCESS_COOKIE)?.value}`, Accept: 'application/json' },
      cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(10000),
    });
    if (response.status === 401) throw new AuthError('expired', 401);
    if (response.status === 403) throw new AuthError('denied', 403);
    if (response.status === 422) return { status: 422, session, body: { error: 'Choose valid start/end dates (maximum 90 days, ending no later than today) and an existing level.' } };
    if (!response.ok) throw new Error('Unavailable');
    return { body: validateAnalytics(await response.json()), status: 200, session };
  } catch (error) {
    return { body: { error: error instanceof AuthError ? error.message : 'Parking analytics are unavailable. Please refresh and try again.' },
      status: error instanceof AuthError ? error.status : 503, session: error.session ?? session,
      clear: error instanceof AuthError && [401, 403].includes(error.status) };
  }
}
