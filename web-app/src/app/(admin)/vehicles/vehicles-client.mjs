import { vehicleReadQuery } from '../../../lib/vehicle-read-contracts.mjs';
import { normalizeRejectionReason } from '../../../lib/vehicle-rejection.mjs';

export function vehiclesQuery(filters, offset = 0) {
  const params = new URLSearchParams({ limit: '25', offset: String(offset) });
  const plate = filters.plate.trim().toUpperCase();
  if (plate && !/^[A-Z0-9]{1,32}$/.test(plate)) throw new Error('Use up to 32 letters or digits for number plate search.');
  if (plate) params.set('plate', plate);
  if (filters.status) params.set('status', filters.status);
  if (filters.tenant_id) params.set('tenant_id', filters.tenant_id);
  return params.toString();
}

async function readRequest(url, options = {}) {
  const response = await fetch(url, { ...options, cache: 'no-store' });
  if ([401, 403].includes(response.status)) {
    window.location.replace(`/login?reason=${response.status === 401 ? 'expired' : 'denied'}`);
    throw Object.assign(new Error('Administrator access could not be verified. Returning to sign in.'), { status: response.status });
  }
  let data;
  try { data = await response.json(); } catch { throw new Error('Unable to read vehicle records. Please retry.'); }
  if (!response.ok) throw Object.assign(new Error(data.error || 'Unable to load vehicle records.'), { status: response.status });
  return data;
}

export function fetchVehicles(query, signal) {
  return readRequest(`/api/vehicles?${query}`, { signal });
}

export function fetchDrivers(query, signal) { return readRequest(`/api/vehicle-drivers?${query}`, { signal }); }
export function fetchDriverDetails(id, query, signal) { return readRequest(`/api/vehicle-drivers/${id}?${query}`, { signal }); }
export function fetchVehicleSummary(tenantId, signal) {
  const query = vehicleReadQuery(new URLSearchParams(tenantId ? { tenant_id: tenantId } : {}), 'summary');
  return readRequest(`/api/vehicles/summary?${query}`, { signal });
}

export async function submitVehicleDecision(id, action, rejectionReason) {
  const body = action === 'reject' ? { rejection_reason: normalizeRejectionReason(rejectionReason) } : {};
  return readRequest(`/api/vehicles/${id}/${action}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
}
export function driversQuery(filters, offset = 0) {
  return vehicleReadQuery(new URLSearchParams({ search: filters.search ?? '', status: filters.status ?? '', tenant_id: filters.tenant_id ?? '', offset: String(offset) })).toString();
}
export function detailsQuery(status = '', offset = 0) {
  return vehicleReadQuery(new URLSearchParams({ status, offset: String(offset) }), 'details').toString();
}
