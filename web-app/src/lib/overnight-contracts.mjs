import { validateSessions } from './sessions-contracts.mjs';

const day = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
  Number.isFinite(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;
const instant = value => typeof value === 'string' && /(?:Z|[+-]\d{2}:\d{2})$/.test(value) && Number.isFinite(Date.parse(value));
const integer = value => Number.isSafeInteger(value) && value >= 0;
const localDay = value => new Date(Date.parse(value) + 8 * 3600000).toISOString().slice(0, 10);
const sessionFields = ['id', 'vehicle_id', 'zone_id', 'level_id', 'plate_number', 'owner_name', 'tenant_name',
  'zone_name', 'level_name', 'status', 'entry_time', 'parking_confirmed_at', 'exit_time', 'duration_seconds'];
const invalid = () => { throw new Error('Overnight alerts could not be verified. Please retry.'); };

export function overnightQuery(input) {
  const query = input instanceof URLSearchParams ? input : new URLSearchParams(input);
  for (const key of query.keys()) if (!['kind', 'limit', 'offset', 'start_date', 'end_date'].includes(key) || query.getAll(key).length !== 1) throw new Error('Choose valid overnight alert filters.');
  const kind = query.get('kind') || 'current', limit = query.get('limit') || '10', offset = query.get('offset') || '0';
  if (!['current', 'past'].includes(kind) || !/^\d+$/.test(limit) || !/^\d+$/.test(offset) ||
      Number(limit) < 1 || Number(limit) > 100 || Number(offset) > 1000000) throw new Error('Choose a valid overnight alert view and page.');
  const result = new URLSearchParams({ kind, limit: String(Number(limit)), offset: String(Number(offset)) });
  const start = query.get('start_date'), end = query.get('end_date');
  if (start !== null || end !== null) {
    if (kind !== 'past' || !day(start) || !day(end) || start < '1982-01-01' || end < start ||
        (Date.parse(end) - Date.parse(start)) / 86400000 >= 90) throw new Error('Choose an ordered past-stay date range of up to 90 days.');
    result.set('start_date', start); result.set('end_date', end);
  }
  return result;
}

export function validateOvernightAlerts(data, query) {
  if (!data || !['current', 'past'].includes(data.kind) || data.kind !== query.get('kind') || data.timezone !== 'Asia/Kuala_Lumpur' ||
      !instant(data.generated_at) || !integer(data.total) || data.limit !== Number(query.get('limit')) || data.offset !== Number(query.get('offset')) ||
      !Array.isArray(data.alerts) || data.alerts.length > data.limit || data.alerts.length > Math.max(0, data.total - data.offset) ||
      (data.kind === 'current' ? data.start_date !== null || data.end_date !== null :
        !day(data.start_date) || !day(data.end_date) || data.end_date < data.start_date || data.end_date > localDay(data.generated_at) ||
        (Date.parse(data.end_date) - Date.parse(data.start_date)) / 86400000 >= 90 ||
        (query.has('start_date') && (query.get('start_date') !== data.start_date || query.get('end_date') !== data.end_date)))) invalid();
  const alerts = data.alerts.map(alert => {
    if (!alert || !instant(alert.first_midnight) || !integer(alert.midnights_crossed) || alert.midnights_crossed < 1 || !integer(alert.seconds_after_midnight) ||
        !['driver_name', 'driver_company_name'].every(key => alert[key] === null || typeof alert[key] === 'string')) invalid();
    validateSessions({ sessions: [alert.session], levels: [], total: 1, limit: 1, offset: 0, timezone: data.timezone });
    const row = alert.session;
    if (!instant(row.entry_time)) invalid();
    const entry = Date.parse(row.entry_time), end = Date.parse(data.kind === 'current' ? data.generated_at : row.exit_time);
    const firstMidnight = Date.parse(localDay(row.entry_time)) + 86400000 - 8 * 3600000;
    if ((data.kind === 'current' ? !['allocated', 'occupied'].includes(row.status) || row.exit_time !== null :
      row.status !== 'completed' || !instant(row.exit_time) || localDay(row.exit_time) < data.start_date || localDay(row.exit_time) > data.end_date) ||
      entry > Date.parse(data.generated_at) || end > Date.parse(data.generated_at) || end < firstMidnight ||
      Date.parse(alert.first_midnight) !== firstMidnight || alert.seconds_after_midnight !== Math.floor((end - firstMidnight) / 1000) ||
      alert.midnights_crossed !== (Date.parse(localDay(new Date(end).toISOString())) - Date.parse(localDay(row.entry_time))) / 86400000) invalid();
    return { session: Object.fromEntries(sessionFields.map(key => [key, row[key]])), driver_name: alert.driver_name,
      driver_company_name: alert.driver_company_name, first_midnight: alert.first_midnight,
      midnights_crossed: alert.midnights_crossed, seconds_after_midnight: alert.seconds_after_midnight };
  });
  if (new Set(alerts.map(alert => alert.session.id)).size !== alerts.length) invalid();
  return { kind: data.kind, timezone: data.timezone, generated_at: data.generated_at, start_date: data.start_date,
    end_date: data.end_date, alerts, total: data.total, limit: data.limit, offset: data.offset };
}
