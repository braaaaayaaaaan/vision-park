import { ACCESS_COOKIE, REFRESH_COOKIE, AuthError, baseUrl, restoreSession, requireSameOrigin } from './auth.mjs';
import { readLimitedBody } from './parking-structure-api.mjs';
import { rampBatchError, validateRampResponse } from '../app/(admin)/parking-structure/cross-level-utils.mjs';

export async function crossLevelRequest(request) {
  let session;
  try {
    if (!['GET', 'PUT'].includes(request.method)) return { status: 405, body: { error: 'Method not allowed.' } };
    if (request.method === 'PUT') requireSameOrigin(request);
    const restored = await restoreSession(request.cookies.get(ACCESS_COOKIE)?.value, request.cookies.get(REFRESH_COOKIE)?.value);
    session = restored.session;
    const headers = { Authorization: `Bearer ${session?.access_token ?? request.cookies.get(ACCESS_COOKIE)?.value}` };
    let body, batch, suffix = '';
    if (request.method === 'PUT') {
      if (request.headers.get('content-type')?.split(';')[0].toLowerCase() !== 'application/json') throw new AuthError('input', 415);
      const bytes = await readLimitedBody(request.body, 32 * 1024);
      try { batch = JSON.parse(bytes.toString()); } catch { throw new AuthError('input', 422); }
      if (rampBatchError(batch)) throw new AuthError('input', 422);
      batch = { ...batch,
        upserts: batch.upserts.map(edge => Object.fromEntries(Object.entries(edge).map(([key, value]) => [key, key === 'id' || key.endsWith('_id') ? value.toLowerCase() : value]))),
        deletes: batch.deletes.map(edge => ({ ...edge, id: edge.id.toLowerCase() })),
      };
      headers['Content-Type'] = 'application/json'; body = JSON.stringify(batch);
    } else {
      const query = new URL(request.url).searchParams, params = new URLSearchParams();
      const level = query.get('level_id');
      if (level) {
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(level)) throw new AuthError('input', 422);
        params.set('level_id', level);
      }
      for (const [key, fallback, min, max] of [['limit', '10', 1, 50], ['offset', '0', 0, 1000000]]) {
        const value = query.get(key) ?? fallback;
        if (!/^(0|[1-9]\d*)$/.test(value) || Number(value) < min || Number(value) > max) throw new AuthError('input', 422);
        params.set(key, value);
      }
      suffix = `?${params}`;
    }
    const response = await fetch(`${baseUrl(process.env.BACKEND_BASE_URL)}/admin/parking/cross-level-draft-edges${suffix}`, {
      method: request.method, headers, body, cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(60000),
    });
    if ([401, 403].includes(response.status)) throw new AuthError(response.status === 401 ? 'expired' : 'denied', response.status);
    if (!response.ok) return { status: [409, 413, 415, 422].includes(response.status) ? response.status : 503, session,
      body: { error: response.status === 409 ? 'Ramp connections, endpoint drafts or reference calibration changed. Refresh and review; local edits are retained.' :
        response.status === 422 ? 'Use current ramp nodes on different levels, unique directions and confirmed calibrated ramp traces.' : 'Ramp request could not be confirmed. Refresh before retrying.' } };
    return { status: 200, session, body: validateRampResponse(await response.json(), batch) };
  } catch (error) {
    return { status: error instanceof AuthError ? error.status : 503, session: error.session ?? session,
      clear: error instanceof AuthError && [401, 403].includes(error.status), body: { error: error instanceof AuthError ?
        (error.status === 413 ? 'Ramp connection batch exceeds 32 KiB.' : error.status === 422 ? 'Choose current ramp nodes on different levels and confirm calibrated ramp traces.' :
          error.status === 415 ? 'Use a JSON ramp connection batch.' : error.message) : 'Ramp request could not be confirmed. Refresh before retrying.' } };
  }
}
