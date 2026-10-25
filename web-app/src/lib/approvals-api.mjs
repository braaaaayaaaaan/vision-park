import { ACCESS_COOKIE, REFRESH_COOKIE, AuthError, baseUrl, restoreSession, requireSameOrigin } from './auth.mjs';
import { approvalQuery, validateRegistrations, validateRegistrationSummary } from './approval-read-contracts.mjs';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
class ReviewError extends Error {
  constructor(message, status = 503) { super(message); this.status = status; }
}
const unavailable = () => new ReviewError('Registration service is unavailable. Refresh the list before retrying a decision.');

async function backend(path, token, body, method = body === undefined ? 'GET' : 'POST') {
  let response;
  try {
    response = await fetch(`${baseUrl(process.env.BACKEND_BASE_URL)}/${path}`, {
      method,
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json', ...(body === undefined ? {} : { 'Content-Type': 'application/json' }) },
      body: body === undefined ? undefined : JSON.stringify(body),
      cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(10000),
    });
  } catch { throw unavailable(); }
  if (response.status === 401) throw new AuthError('expired', 401);
  if (response.status === 403) throw new AuthError('denied', 403);
  if (!response.ok) {
    const messages = {
      400: 'Select a valid, active company and try again.',
      404: 'This application was not found. Refresh the pending list.',
      409: 'This application is no longer eligible or was already processed. Refresh the pending list.',
      422: 'The application or company selection is invalid. Refresh and try again.',
      429: 'Too many requests. Please wait and try again.',
    };
    throw messages[response.status] ? new ReviewError(messages[response.status], response.status) : unavailable();
  }
  try { return await response.json(); } catch { throw unavailable(); }
}

function companies(data) {
  if (!Array.isArray(data) || data.some((item) => !item || !uuid.test(item.id) || typeof item.name !== 'string')) throw unavailable();
  return data.map(({ id, name }) => ({ id, name }));
}

// Only the registration-review operations are exposed; this is not an open proxy.
export async function handleApprovals(request, segments = []) {
  let session;
  try {
    if (request.method === 'POST') requireSameOrigin(request);
    const restored = await restoreSession(request.cookies.get(ACCESS_COOKIE)?.value, request.cookies.get(REFRESH_COOKIE)?.value);
    session = restored.session;
    const token = session?.access_token ?? request.cookies.get(ACCESS_COOKIE)?.value;
    let body;
    if (request.method === 'GET' && segments.length === 0) {
      let params;
      try { params = approvalQuery(new URL(request.url).searchParams); }
      catch (error) { throw new ReviewError(error.message, 400); }
      const limit = Number(params.get('limit')), offset = Number(params.get('offset'));
      params.set('limit', String(limit + 1));
      const rows = validateRegistrations(await backend(`admin/registrations?${params}`, token), params);
      body = { applications: rows.slice(0, limit), hasNext: rows.length > limit, limit, offset };
    } else if (request.method === 'GET' && segments.length === 1 && segments[0] === 'summary') {
      body = validateRegistrationSummary(await backend('admin/registrations/summary', token));
    } else if (request.method === 'GET' && segments.length === 1 && segments[0] === 'companies') {
      body = { companies: companies(await backend('auth/companies', token)) };
    } else if (request.method === 'POST' && segments.length === 2 && uuid.test(segments[0]) && ['approve', 'reject'].includes(segments[1])) {
      const [id, action] = segments;
      let input;
      try { input = await request.json(); } catch { throw new ReviewError('Invalid decision request.', 400); }
      if (!input || typeof input !== 'object' || Array.isArray(input) || Object.keys(input).some((key) => action !== 'approve' || key !== 'tenant_id')) throw new ReviewError('Invalid decision request.', 400);
      const tenant = action === 'approve' ? input.tenant_id : null;
      if (action === 'approve') {
        if (!uuid.test(tenant)) throw new ReviewError('Select a company before approving.', 400);
        const available = companies(await backend('auth/companies', token));
        if (!available.some((item) => item.id === tenant)) throw new ReviewError('The selected company is no longer available. Reopen the dialog to refresh companies.', 400);
      }
      // FastAPI/RPC independently checks applicant eligibility and company validity atomically.
      const result = await backend(`admin/registrations/${id}/${action}`, token, action === 'approve' ? { tenant_id: tenant } : undefined, 'POST');
      const status = action === 'approve' ? 'approved' : 'rejected';
      if (result?.id !== id || result.approval_status !== status || result.is_active !== (action === 'approve') || result.tenant_id !== tenant) throw unavailable();
      body = { id: result.id, approval_status: result.approval_status, is_active: result.is_active, tenant_id: result.tenant_id };
    } else throw new ReviewError('Review endpoint not found.', 404);
    return { body, status: 200, session };
  } catch (error) {
    const known = error instanceof AuthError || error instanceof ReviewError;
    return { body: { error: known ? error.message : unavailable().message }, status: known ? error.status : 503,
      session: error.session ?? session, clear: error instanceof AuthError && ['expired', 'denied'].includes(error.code) };
  }
}
