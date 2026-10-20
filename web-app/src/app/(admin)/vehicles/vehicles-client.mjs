export function vehiclesQuery(filters, offset = 0) {
  const params = new URLSearchParams({ limit: '25', offset: String(offset) });
  const plate = filters.plate.trim().toUpperCase();
  if (plate && !/^[A-Z0-9]{1,32}$/.test(plate)) throw new Error('Use up to 32 letters or digits for number plate search.');
  if (plate) params.set('plate', plate);
  if (filters.status) params.set('status', filters.status);
  if (filters.tenant_id) params.set('tenant_id', filters.tenant_id);
  return params.toString();
}

async function vehicleRequest(path, options = {}) {
  const response = await fetch(`/api/vehicles${path}`, { ...options, cache: 'no-store' });
  if ([401, 403].includes(response.status)) {
    window.location.replace(`/login?reason=${response.status === 401 ? 'expired' : 'denied'}`);
    throw new Error('Administrator access could not be verified. Returning to sign in.');
  }
  let data;
  try { data = await response.json(); } catch { throw new Error('Unable to read vehicle records. Please retry.'); }
  if (!response.ok) throw new Error(data.error || 'Unable to load vehicle records.');
  return data;
}

export function fetchVehicles(query, signal) {
  return vehicleRequest(`?${query}`, { signal });
}

export function submitVehicleDecision(id, action) {
  return vehicleRequest(`/${id}/${action}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
}
