export const MAX_CAPACITY = 2147483647;
export const ZONE_FIELDS = ['code', 'name', 'total_capacity', 'unavailable_capacity', 'operational_status'];
export const ZONE_STATUSES = ['open', 'closed', 'maintenance'];
export const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const integer = value => Number.isInteger(value) && value >= 0 && value <= MAX_CAPACITY;
const object = value => value && typeof value === 'object' && !Array.isArray(value);
const exact = (value, fields) => object(value) && Object.keys(value).length === fields.length && fields.every(key => Object.hasOwn(value, key));
export function zoneError(value) {
  if (!object(value)) return 'Enter Zone Details.';
  for (const [key, max] of [['code', 64], ['name', 100]]) {
    if (typeof value[key] !== 'string' || !value[key].trim() || Array.from(value[key].trim()).length > max || /[\u0000-\u001f\u007f-\u009f]/u.test(value[key])) return `Use A Readable Zone ${key === 'code' ? 'Code' : 'Name'} Of At Most ${max} Characters.`;
  }
  if (!integer(value.total_capacity) || !integer(value.unavailable_capacity)) return 'Capacities Must Be Whole Numbers From 0 To 2147483647.';
  if (value.unavailable_capacity > value.total_capacity) return 'Unavailable Capacity Cannot Exceed Total Capacity.';
  return ZONE_STATUSES.includes(value.operational_status) ? '' : 'Choose A Valid Intended Status.';
}
export function zoneRequestError(value, method) {
  const fields = method === 'DELETE' ? ['expected_revision'] : [...ZONE_FIELDS, ...(method === 'PATCH' ? ['expected_revision'] : [])];
  if (!exact(value, fields)) return 'Use Only Draft Zone Fields And The Required Revision.';
  if (method !== 'POST' && (!integer(value.expected_revision) || value.expected_revision < 1 || (method === 'PATCH' && value.expected_revision === MAX_CAPACITY))) return 'Refresh To Load The Current Draft Zone Revision.';
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
      new Set(data.zones.map(zone => zone.code)).size !== data.zones.length) throw new Error('Invalid Draft Zone Listing.');
    const totals = zoneTotals(data.zones);
    if (data.total_capacity !== totals.total_capacity || data.unavailable_capacity !== totals.unavailable_capacity) throw new Error('Incomplete Draft Zone Listing.');
  } else if (method === 'DELETE') {
    if (data?.level_id !== levelId || data.deleted_zone_id !== zoneId) throw new Error('Unconfirmed Draft Zone Deletion.');
  } else if (!validZone(data?.zone, levelId) || (zoneId && data.zone.id !== zoneId) ||
    data.zone.revision !== (method === 'POST' ? 1 : input.expected_revision + 1) ||
    (method === 'POST' && data.zone.operational_zone_id !== null) || ZONE_FIELDS.some(key => data.zone[key] !== (typeof input[key] === 'string' ? input[key].trim() : input[key]))) {
    throw new Error('Unconfirmed Draft Zone Save.');
  }
  return data;
}
