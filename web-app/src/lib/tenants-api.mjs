import { ACCESS_COOKIE, REFRESH_COOKIE, AuthError, baseUrl, restoreSession, requireSameOrigin } from './auth.mjs';
import { readLimitedBody } from './parking-structure-api.mjs';
import { uuid, tenantInput, tenantQuery, validateTenantResponse } from './tenant-contracts.mjs';

const conflicts = {
  stale: 'This company or its access changed. Close and reopen the details before saving.',
  duplicate_name: 'A company with this name already exists, including inactive companies.',
  active_sessions: 'Active parking sessions depend on this access. Wait for them to end before deactivating or removing access.',
  tenant_limit: 'The 1,000-company publication limit has been reached. Existing companies can still be edited.',
  permission_limit: 'The 20,000 zone-permission publication limit would be exceeded. Remove permissions before granting more access.',
  code_conflict: 'The generated company code is already in use. Refresh and register the company again.',
};
export async function handleTenants(request, path = []) {
  let session;
  const writing = ['POST', 'PUT'].includes(request.method);
  const id = path[0]?.toLowerCase();
  try {
    if (path.length > 1 || (path.length && !uuid(id)) ||
        !(request.method === 'GET' || (request.method === 'POST' && !id) || (request.method === 'PUT' && id))) return { status: 404, body: { error: 'Company endpoint not found.' } };
    if (writing) requireSameOrigin(request);
    const restored = await restoreSession(request.cookies.get(ACCESS_COOKIE)?.value, request.cookies.get(REFRESH_COOKIE)?.value);
    session = restored.session;
    let input, query;
    try {
      if (writing) {
        if (request.headers.get('content-type')?.split(';')[0].toLowerCase() !== 'application/json') throw new AuthError('input', 415);
        input = tenantInput(JSON.parse((await readLimitedBody(request.body, 128 * 1024)).toString()), !id);
        if (id && input.id !== id) throw new Error('The company identifier does not match.');
      } else {
        query = tenantQuery(new URL(request.url).searchParams);
        if (id && new URL(request.url).search) throw new Error('Company details do not accept filters.');
      }
    } catch (error) {
      if (error instanceof AuthError) throw error;
      return { status: 422, session, body: { error: error instanceof SyntaxError ? 'Use a valid JSON company request.' : error.message } };
    }
    const response = await fetch(`${baseUrl(process.env.BACKEND_BASE_URL)}/admin/tenants${id ? `/${id}` : ''}${!writing && !id ? `?${query}` : ''}`, {
      method: request.method, headers: { Authorization: `Bearer ${session?.access_token ?? request.cookies.get(ACCESS_COOKIE)?.value}`, Accept: 'application/json',
        ...(writing ? { 'Content-Type': 'application/json' } : {}) },
      ...(writing ? { body: JSON.stringify(input) } : {}), cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(15000),
    });
    if ([401, 403].includes(response.status)) throw new AuthError(response.status === 401 ? 'expired' : 'denied', response.status);
    if (!response.ok) {
      const error = await response.json().catch(() => null);
      return { status: [404, 409, 413, 415, 422].includes(response.status) ? response.status : 503, session, body: { error:
        response.status === 409 ? conflicts[error?.detail?.code] ?? 'The company changed. Refresh before retrying.' :
          response.status === 404 ? 'Company not found. Refresh the list.' : response.status === 422 ? 'Check the company information. Activate the company before granting new access.' :
            'Company information could not be confirmed. Refresh before retrying.' } };
    }
    const data = validateTenantResponse(await response.json(), writing ? input.id : id, writing || id ? null : query);
    if (writing && (data.tenant.name !== input.name || data.tenant.is_active !== input.is_active ||
      data.tenant.zone_ids.length !== input.zone_ids.length || input.zone_ids.some(zoneId => !data.tenant.zone_ids.includes(zoneId)))) throw new Error('Unconfirmed save');
    return { status: writing && !id ? 201 : 200, session, body: data };
  } catch (error) {
    return { status: error instanceof AuthError ? error.status : 503, session: error.session ?? session,
      clear: error instanceof AuthError && [401, 403].includes(error.status), body: { error: error instanceof AuthError ?
        error.status === 413 ? 'Company request exceeds 128 KiB.' : error.status === 415 ? 'Use a JSON company request.' : error.message :
          'Company information could not be confirmed. Refresh before retrying.' } };
  }
}
