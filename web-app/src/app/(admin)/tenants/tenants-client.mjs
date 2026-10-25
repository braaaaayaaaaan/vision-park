import { tenantInput, tenantQuery, validateTenantResponse } from '../../../lib/tenant-contracts.mjs';

async function request(url, options) {
  const response = await fetch(url, { cache: 'no-store', ...options });
  const data = await response.json().catch(() => null);
  if (!response.ok) {
    const error = new Error(data?.error || 'Company information could not be confirmed. Refresh before retrying.');
    error.status = response.status;
    throw error;
  }
  return data;
}
export function listingQuery(filters, offset = 0) {
  return tenantQuery(new URLSearchParams({ ...filters, limit: '25', offset: String(offset) })).toString();
}
export async function fetchTenants(query, signal) {
  return validateTenantResponse(await request(`/api/tenants?${query}`, { signal }), null, new URLSearchParams(query));
}
export async function fetchTenant(id, signal) {
  return validateTenantResponse(await request(`/api/tenants/${id}`, { signal }), id);
}
export async function saveTenant(change, creating) {
  const input = tenantInput(change, creating);
  return validateTenantResponse(await request(`/api/tenants${creating ? '' : `/${input.id}`}`, {
    method: creating ? 'POST' : 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(input), signal: AbortSignal.timeout(20000),
  }), input.id);
}
