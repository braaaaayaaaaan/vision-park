export const MAX_CAPACITY = 2147483647;
export const ZONE_FIELDS = ['code', 'name', 'total_capacity', 'unavailable_capacity', 'operational_status'];
export const ZONE_STATUSES = ['open', 'closed', 'maintenance'];
export const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const integer = value => Number.isInteger(value) && value >= 0 && value <= MAX_CAPACITY;
const object = value => value && typeof value === 'object' && !Array.isArray(value);
const exact = (value, fields) => object(value) && Object.keys(value).length === fields.length && fields.every(key => Object.hasOwn(value, key));
export function zoneError(value) {
  if (!object(value)) return 'Enter zone details.';
  for (const [key, max] of [['code', 64], ['name', 100]]) {
    if (typeof value[key] !== 'string' || !value[key].trim() || Array.from(value[key].trim()).length > max || /[\u0000-\u001f\u007f-\u009f]/u.test(value[key])) return `Use a readable zone ${key === 'code' ? 'Code' : 'Name'} of at most ${max} characters.`;
  }
  if (!integer(value.total_capacity) || !integer(value.unavailable_capacity)) return 'Capacities must be whole numbers from 0 to 2147483647.';
  if (value.unavailable_capacity > value.total_capacity) return 'Unavailable capacity cannot exceed total capacity.';
  return ZONE_STATUSES.includes(value.operational_status) ? '' : 'Choose a valid intended status.';
}
export function zoneRequestError(value, method) {
  const fields = method === 'DELETE' ? ['expected_revision'] : [...ZONE_FIELDS, ...(method === 'PATCH' ? ['expected_revision'] : [])];
  if (!exact(value, fields)) return 'Use only draft zone fields and the required revision.';
  if (method !== 'POST' && (!integer(value.expected_revision) || value.expected_revision < 1 || (method === 'PATCH' && value.expected_revision === MAX_CAPACITY))) return 'Refresh to load the current draft zone revision.';
  return method === 'DELETE' ? '' : zoneError(value);
}
export const zoneTotals = zones => ({ total_capacity: zones.reduce((sum, zone) => sum + zone.total_capacity, 0),
  unavailable_capacity: zones.reduce((sum, zone) => sum + zone.unavailable_capacity, 0) });
function validZone(zone, levelId) {
  return object(zone) && !zoneError(zone) && zone.code === zone.code.trim() && zone.name === zone.name.trim() && uuid(zone.id) && zone.level_id === levelId &&
    integer(zone.revision) && zone.revision > 0 && (zone.operational_zone_id === null || uuid(zone.operational_zone_id)) &&
    ['created_at', 'updated_at'].every(key => typeof zone[key] === 'string' && Number.isFinite(Date.parse(zone[key]))) && uuid(zone.updated_by);
}
export function validateZoneResponse(data, method, levelId, zoneId, input) {
  if (method === 'GET') {
    if (data?.level_id !== levelId || !Array.isArray(data.zones) || data.zones.length > 1000 || data.total_count !== data.zones.length ||
      data.zones.some(zone => !validZone(zone, levelId)) || new Set(data.zones.map(zone => zone.id)).size !== data.zones.length ||
      new Set(data.zones.map(zone => zone.code)).size !== data.zones.length) throw new Error('Invalid draft zone listing.');
    const totals = zoneTotals(data.zones);
    if (data.total_capacity !== totals.total_capacity || data.unavailable_capacity !== totals.unavailable_capacity) throw new Error('Incomplete draft zone listing.');
  } else if (method === 'DELETE') {
    if (data?.level_id !== levelId || data.deleted_zone_id !== zoneId) throw new Error('Unconfirmed draft zone deletion.');
  } else if (!validZone(data?.zone, levelId) || (zoneId && data.zone.id !== zoneId) ||
    data.zone.revision !== (method === 'POST' ? 1 : input.expected_revision + 1) ||
    (method === 'POST' && data.zone.operational_zone_id !== null) || ZONE_FIELDS.some(key => data.zone[key] !== (typeof input[key] === 'string' ? input[key].trim() : input[key]))) {
    throw new Error('Unconfirmed draft zone save.');
  }
  return data;
}
