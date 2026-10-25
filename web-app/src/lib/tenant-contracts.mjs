export const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const count = value => Number.isSafeInteger(value) && value >= 0;
const revision = value => typeof value === 'string' && /^[a-f0-9]{32}$/.test(value);
const unique = values => new Set(values).size === values.length;
const fail = () => { throw new Error('Company information is unavailable. Refresh and try again.'); };
export const metrics = [['total_companies', 'Total Companies'], ['registered_drivers', 'Registered Drivers'],
  ['approved_drivers', 'Approved Drivers'], ['pending_approvals', 'Pending Approvals']];

export function tenantQuery(input) {
  const output = new URLSearchParams();
  for (const key of input.keys()) if (!['search', 'status', 'sort', 'limit', 'offset'].includes(key) || input.getAll(key).length !== 1) throw new Error('Choose valid company filters.');
  const search = (input.get('search') ?? '').trim(), status = input.get('status') || 'all', sort = input.get('sort') || 'name_asc';
  if (search.length > 120 || !['all', 'active', 'inactive'].includes(status) || !['name_asc', 'name_desc', 'drivers_desc', 'pending_desc'].includes(sort)) throw new Error('Choose valid company filters.');
  for (const [key, fallback, max] of [['limit', '25', 100], ['offset', '0', 1000000]]) {
    const value = input.get(key) ?? fallback;
    if (!/^\d+$/.test(value) || Number(value) > max || (key === 'limit' && Number(value) < 1)) throw new Error('Choose a valid page.');
    output.set(key, String(Number(value)));
  }
  output.set('search', search); output.set('status', status); output.set('sort', sort);
  return output;
}

export function tenantInput(input, creating) {
  if (!input || Array.isArray(input) || Object.keys(input).some(key => !['id', 'name', 'is_active', 'zone_ids', 'expected_revision', 'confirm_access_change'].includes(key)) ||
      !uuid(input.id) || typeof input.name !== 'string' || typeof input.is_active !== 'boolean' ||
      !Array.isArray(input.zone_ids) || input.zone_ids.length > 2000 || !input.zone_ids.every(uuid) ||
      !unique(input.zone_ids.map(id => id.toLowerCase())) || typeof input.confirm_access_change !== 'boolean' ||
      (creating ? input.expected_revision != null : !revision(input.expected_revision))) throw new Error('Check the company information and current revision.');
  const name = input.name.trim().replace(/\s+/gu, ' ');
  if (!name || name.length > 120 || /[\x00-\x1f\x7f]/u.test(name)) throw new Error('Enter a company name of 1–120 characters.');
  return { ...input, id: input.id.toLowerCase(), name, zone_ids: input.zone_ids.map(id => id.toLowerCase()), expected_revision: input.expected_revision ?? null };
}

function tenant(row) {
  if (!row || !uuid(row.id) || typeof row.name !== 'string' || !row.name.trim() || typeof row.is_active !== 'boolean' ||
      !revision(row.revision) || !Array.isArray(row.zone_ids) || !row.zone_ids.every(uuid) || !unique(row.zone_ids) ||
      !['registered_drivers', 'approved_drivers', 'pending_approvals', 'rejected_drivers', 'zone_count', 'active_sessions'].every(key => count(row[key])) ||
      row.zone_count !== row.zone_ids.length || row.registered_drivers !== row.approved_drivers + row.pending_approvals + row.rejected_drivers) fail();
  return row;
}

export function validateTenantResponse(data, id = null, query = null) {
  if (id) {
    tenant(data?.tenant);
    if (data.tenant.id !== id || !Array.isArray(data.zones) || !unique(data.zones.map(zone => zone.id)) ||
        data.zones.some(zone => !uuid(zone.id) || !uuid(zone.level_id) || typeof zone.name !== 'string' || typeof zone.code !== 'string' ||
          typeof zone.level_name !== 'string' || typeof zone.level_active !== 'boolean' || typeof zone.operational_status !== 'string' || !count(zone.total_capacity)) ||
        data.tenant.zone_ids.some(zoneId => !data.zones.some(zone => zone.id === zoneId))) fail();
  } else {
    if (!data || !count(data.total) || !count(data.offset) || !Number.isInteger(data.limit) || data.limit < 1 || data.limit > 100 ||
        !Array.isArray(data.companies) || data.companies.length > Math.min(data.limit, Math.max(0, data.total - data.offset)) ||
        !unique(data.companies.map(row => row.id)) || !data.summary || !metrics.every(([key]) => count(data.summary[key])) || data.total > data.summary.total_companies ||
        data.summary.approved_drivers + data.summary.pending_approvals > data.summary.registered_drivers) fail();
    data.companies.forEach(tenant);
    if (query && (data.limit !== Number(query.get('limit')) || data.offset !== Number(query.get('offset')) || data.companies.some(row =>
      (query.get('status') !== 'all' && row.is_active !== (query.get('status') === 'active')) ||
      !row.name.toLowerCase().includes(query.get('search').toLowerCase())))) fail();
  }
  return data;
}
