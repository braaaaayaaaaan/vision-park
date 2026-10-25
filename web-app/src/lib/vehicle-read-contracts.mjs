// Pure contracts shared by the authenticated proxy and browser query builders.
import { validStoredRejectionReason } from './vehicle-rejection.mjs';
export const vehicleStatuses = ['approved', 'pending', 'rejected'];
export const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const integer = value => Number.isSafeInteger(value) && value >= 0;
const nullable = (value, check) => value === null || check(value);
const string = value => typeof value === 'string';
const uuid = value => string(value) && uuidPattern.test(value);
const fail = () => { throw new Error('Invalid vehicle read response'); };

export function vehicleReadQuery(input, kind = 'drivers') {
  const query = input instanceof URLSearchParams ? input : new URLSearchParams(input);
  const allowed = kind === 'summary' ? ['tenant_id'] : kind === 'details'
    ? ['limit', 'offset', 'status'] : ['limit', 'offset', 'search', 'tenant_id', 'status'];
  for (const key of allowed) if (query.getAll(key).length > 1) throw new Error('Choose one value for each filter.');
  const result = new URLSearchParams();
  if (kind !== 'summary') {
    for (const [key, fallback, min, max] of [['limit', '25', 1, 100], ['offset', '0', 0, 1000000]]) {
      const value = query.get(key) ?? fallback;
      if (!/^\d+$/.test(value) || !Number.isSafeInteger(Number(value)) || Number(value) < min || Number(value) > max) {
        throw new Error('Choose a valid page size and page.');
      }
      result.set(key, String(Number(value)));
    }
  }
  if (allowed.includes('search')) {
    const search = (query.get('search') ?? '').trim();
    if ([...search].length > 150 || /[\u0000-\u001f\u007f]/.test(search)) throw new Error('Use a driver name of up to 150 characters.');
    if (search) result.set('search', search);
  }
  if (allowed.includes('status') && query.get('status')) {
    if (!vehicleStatuses.includes(query.get('status'))) throw new Error('Choose a valid registration status.');
    result.set('status', query.get('status'));
  }
  if (allowed.includes('tenant_id') && query.get('tenant_id')) {
    if (!uuid(query.get('tenant_id'))) throw new Error('Choose a valid company.');
    result.set('tenant_id', query.get('tenant_id').toLowerCase());
  }
  return result;
}

function counts(value) {
  if (!value || !['approved', 'pending', 'rejected', 'counted'].every(key => integer(value[key])) || value.limit !== 5 ||
      value.counted !== value.approved + value.pending || value.limit_reached !== (value.counted >= 5)) fail();
  return Object.fromEntries(['approved', 'pending', 'rejected', 'counted', 'limit', 'limit_reached'].map(key => [key, value[key]]));
}
function identity(value) {
  if (!value || !uuid(value.id) || !nullable(value.full_name, string) || !nullable(value.tenant_id, uuid) ||
      !nullable(value.company_name, string) || !vehicleStatuses.includes(value.approval_status) || typeof value.is_active !== 'boolean') fail();
  return { id: value.id, full_name: value.full_name, tenant_id: value.tenant_id, company_name: value.company_name,
    approval_status: value.approval_status, is_active: value.is_active, vehicle_counts: counts(value.vehicle_counts) };
}
function preview(value) {
  if (!value || !uuid(value.id) || !string(value.plate_number) || !value.plate_number || !vehicleStatuses.includes(value.registration_status)) fail();
  return { id: value.id, plate_number: value.plate_number, registration_status: value.registration_status };
}
function page(value, rows, query) {
  if (!value || !integer(value.total) || !integer(value.offset) || value.offset > 1000000 ||
      !Number.isInteger(value.limit) || value.limit < 1 || value.limit > 100 || !Array.isArray(rows) ||
      rows.length > Math.min(value.limit, Math.max(0, value.total - value.offset)) ||
      (query && (value.limit !== Number(query.get('limit')) || value.offset !== Number(query.get('offset')))) ||
      new Set(rows.map(row => row?.id)).size !== rows.length) fail();
}
export function validateDriverPage(value, query) {
  page(value, value?.drivers, query);
  const drivers = value.drivers.map(row => {
    const driver = identity(row);
    if (!Array.isArray(row.vehicle_previews) || row.vehicle_previews.length > 3 ||
        new Set(row.vehicle_previews.map(item => item?.id)).size !== row.vehicle_previews.length ||
        (query?.get('tenant_id') && driver.tenant_id !== query.get('tenant_id')) ||
        (query?.get('status') && driver.vehicle_counts[query.get('status')] < 1)) fail();
    return { ...driver, vehicle_previews: row.vehicle_previews.map(preview) };
  });
  return { drivers, total: value.total, limit: value.limit, offset: value.offset };
}
export function validateDriverDetails(value, driverId, query) {
  page(value, value?.vehicles, query);
  const driver = identity(value.driver), status = query?.get('status');
  if (driver.id !== driverId || value.driver.email !== null || value.total !== (status
    ? driver.vehicle_counts[status] : driver.vehicle_counts.counted + driver.vehicle_counts.rejected)) fail();
  const vehicles = value.vehicles.map(row => {
    const vehicle = preview(row);
    for (const key of ['created_at', 'updated_at']) {
      if (!nullable(row[key], item => string(item) && Number.isFinite(Date.parse(item)) && /(?:Z|[+-]\d\d:\d\d)$/.test(item))) fail();
    }
    if (status && vehicle.registration_status !== status) fail();
    if (!validStoredRejectionReason(row.rejection_reason, vehicle.registration_status)) fail();
    return { ...vehicle, rejection_reason: row.rejection_reason ?? null, created_at: row.created_at, updated_at: row.updated_at };
  });
  return { driver: { ...driver, email: null }, vehicles, total: value.total, limit: value.limit, offset: value.offset };
}
export function validateVehicleSummary(value, tenantId = null) {
  if (!value?.scope || value.scope.tenant_id !== tenantId || !nullable(value.scope.company_name, string) ||
      (!tenantId && value.scope.company_name !== null) ||
      !['registered_vehicles', 'approved_vehicles', 'pending_approval', 'drivers_at_limit'].every(key => integer(value[key])) ||
      value.approved_vehicles + value.pending_approval > value.registered_vehicles ||
      value.drivers_at_limit * 5 > value.approved_vehicles + value.pending_approval) fail();
  return { scope: { tenant_id: tenantId, company_name: value.scope.company_name },
    registered_vehicles: value.registered_vehicles, approved_vehicles: value.approved_vehicles,
    pending_approval: value.pending_approval, drivers_at_limit: value.drivers_at_limit };
}
