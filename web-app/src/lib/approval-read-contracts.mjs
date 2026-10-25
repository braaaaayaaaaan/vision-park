const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const integer = value => Number.isSafeInteger(value) && value >= 0;
const statuses = ['pending', 'approved', 'rejected'];
const fail = () => { throw new Error('Invalid registration response'); };

export function approvalQuery(input = {}) {
  const query = input instanceof URLSearchParams ? input : new URLSearchParams(input);
  for (const key of ['limit', 'offset', 'status', 'tenant_id', 'sort']) if (query.getAll(key).length > 1) throw new Error('Choose one value for each filter.');
  const result = new URLSearchParams();
  for (const [key, fallback, min, max] of [['limit', '10', 1, 99], ['offset', '0', 0, 1000000]]) {
    const value = query.get(key) ?? fallback;
    if (!/^\d+$/.test(value) || !Number.isSafeInteger(Number(value)) || Number(value) < min || Number(value) > max) throw new Error('Choose a valid page size and page.');
    result.set(key, String(Number(value)));
  }
  const status = query.get('status') ?? 'pending', sort = query.get('sort') ?? 'name_asc';
  if (![...statuses, 'all'].includes(status) || !['name_asc', 'name_desc'].includes(sort)) throw new Error('Choose a valid approval status and name order.');
  result.set('status', status); result.set('sort', sort);
  if (query.get('tenant_id')) {
    if (!uuid(query.get('tenant_id'))) throw new Error('Select a valid company.');
    result.set('tenant_id', query.get('tenant_id').toLowerCase());
  }
  return result;
}

function company(value, id) {
  if (value == null) return null;
  if (!uuid(value.id) || value.id !== id || typeof value.name !== 'string' || typeof value.is_active !== 'boolean') fail();
  return { id: value.id, name: value.name, is_active: value.is_active };
}

export function validateRegistrations(data, query) {
  if (!Array.isArray(data) || data.length > Number(query.get('limit'))) fail();
  return data.map(item => {
    if (!item || !uuid(item.id) || !statuses.includes(item.approval_status) ||
        (query.get('status') !== 'all' && item.approval_status !== query.get('status')) ||
        !(item.full_name === null || typeof item.full_name === 'string') || typeof item.is_active !== 'boolean' ||
        !(item.requested_tenant_id === null || uuid(item.requested_tenant_id)) ||
        !(item.tenant_id == null || uuid(item.tenant_id))) fail();
    const tenantId = item.tenant_id ?? null;
    if (query.get('tenant_id') && (item.approval_status === 'approved' ? tenantId : item.requested_tenant_id) !== query.get('tenant_id')) fail();
    return { id: item.id, full_name: item.full_name, approval_status: item.approval_status, is_active: item.is_active,
      requested_tenant_id: item.requested_tenant_id, requested_company: company(item.requested_company, item.requested_tenant_id),
      tenant_id: tenantId, company: company(item.company, tenantId) };
  });
}

export function validateRegistrationSummary(value) {
  const keys = ['total_registrations', 'pending_approvals', 'approved_accounts', 'rejected_accounts', 'represented_companies', 'unassigned_drivers'];
  if (!value || !keys.every(key => integer(value[key])) || !Array.isArray(value.companies) ||
      value.total_registrations !== value.pending_approvals + value.approved_accounts + value.rejected_accounts) fail();
  const companies = value.companies.map(row => {
    if (!row || !uuid(row.id) || typeof row.name !== 'string' || !['total', ...statuses].every(key => integer(row[key])) ||
        row.total !== row.pending + row.approved + row.rejected) fail();
    return { id: row.id, name: row.name, total: row.total, pending: row.pending, approved: row.approved, rejected: row.rejected };
  });
  if (new Set(companies.map(row => row.id)).size !== companies.length ||
      companies.reduce((sum, row) => sum + row.total, 0) + value.unassigned_drivers !== value.total_registrations ||
      companies.filter(row => row.total > 0).length !== value.represented_companies ||
      ['pending', 'approved', 'rejected'].some((status, index) => companies.reduce((sum, row) => sum + row[status], 0) > value[keys[index + 1]])) fail();
  return { ...Object.fromEntries(keys.map(key => [key, value[key]])), companies };
}
