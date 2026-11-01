const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const nullable = (value, check) => value === null || check(value);
const string = value => typeof value === 'string';
const timestamp = value => string(value) && /(?:Z|[+-]\d{2}:\d{2})$/.test(value) && Number.isFinite(Date.parse(value));
export function validateSessionSummary(data) {
  const states = ['allocated', 'occupied', 'completed', 'cancelled'];
  if (!data || data.timezone !== 'Asia/Kuala_Lumpur' || !data.counts ||
      Object.keys(data.counts).length !== 4 || states.some(state =>
        !Number.isSafeInteger(data.counts[state]) || data.counts[state] < 0)) throw new Error('Invalid session counts');
  return data;
}
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
