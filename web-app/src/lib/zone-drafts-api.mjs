import { ACCESS_COOKIE, REFRESH_COOKIE, AuthError, baseUrl, restoreSession, requireSameOrigin } from './auth.mjs';
import { readLimitedBody } from './parking-structure-api.mjs';
import { uuid, zoneRequestError, validateZoneResponse } from '../app/(admin)/parking-structure/zone-draft-utils.mjs';

export async function zoneDraftRequest(request, path) {
  let session;
  const uncertain = 'Draft zone result could not be confirmed. Refresh before retrying.';
  try {
    const method = request.method;
    if (path[0] !== 'levels' || !uuid(path[1]) || path[2] !== 'zone-drafts' ||
      !(path.length === 3 && ['GET', 'POST'].includes(method) || path.length === 4 && uuid(path[3]) && ['PATCH', 'DELETE'].includes(method)) || new URL(request.url).search) return { status: 404, body: { error: 'Not found.' } };
    if (method !== 'GET') requireSameOrigin(request);
    const restored = await restoreSession(request.cookies.get(ACCESS_COOKIE)?.value, request.cookies.get(REFRESH_COOKIE)?.value);
    session = restored.session;
    const levelId = path[1].toLowerCase(), zoneId = path[3]?.toLowerCase();
    let input;
    if (method !== 'GET') {
      if (request.headers.get('content-type')?.split(';')[0].toLowerCase() !== 'application/json') throw new AuthError('input', 415);
      try { input = JSON.parse((await readLimitedBody(request.body, 32 * 1024)).toString()); }
      catch (error) { if (error instanceof AuthError) throw error; throw new AuthError('input', 422); }
      if (zoneRequestError(input, method)) throw new AuthError('input', 422);
      if (method !== 'DELETE') input = { ...input, code: input.code.trim(), name: input.name.trim() };
    }
    const response = await fetch(`${baseUrl(process.env.BACKEND_BASE_URL)}/admin/parking/levels/${levelId}/zone-drafts${zoneId ? `/${zoneId}` : ''}`, {
      method, headers: { Authorization: `Bearer ${session?.access_token ?? request.cookies.get(ACCESS_COOKIE)?.value}`, ...(input ? { 'Content-Type': 'application/json' } : {}) },
      ...(input ? { body: JSON.stringify(input) } : {}), cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(60000),
    });
    if ([401, 403].includes(response.status)) throw new AuthError(response.status === 401 ? 'expired' : 'denied', response.status);
    if (!response.ok) {
      const body = await response.json().catch(() => null);
      const conflicts = { stale: 'This Draft Zone Changed. Refresh And Review Before Retrying.', duplicate_code: 'This Zone Code Is Already Used On This Level.',
        has_dependencies: 'This Draft Zone Has Mapping Or Publication References And Cannot Be Deleted.', limit: 'The Draft Zone Or Revision Limit Was Reached.' };
      return { status: [404, 409, 413, 415, 422].includes(response.status) ? response.status : 503, session, body: { error:
        response.status === 409 ? conflicts[body?.detail?.code] ?? 'Draft Zones Changed. Refresh Before Retrying.' :
          response.status === 404 ? 'The Level Or Draft Zone Was Not Found. Refresh The List.' : response.status === 422 ? 'Check Zone Codes, Names, Integer Capacities, Intended Status And Revision.' : uncertain } };
    }
    return { status: method === 'POST' ? 201 : 200, session, body: validateZoneResponse(await response.json(), method, levelId, zoneId, input) };
  } catch (error) {
    return { status: error instanceof AuthError ? error.status : 503, session: error.session ?? session,
      clear: error instanceof AuthError && [401, 403].includes(error.status), body: { error: error instanceof AuthError ?
        error.status === 413 ? 'Draft Zone Request Exceeds 32 KiB.' : error.status === 415 ? 'Use A JSON Draft Zone Request.' :
          error.status === 422 ? 'Check Zone Details And The Current Revision.' : error.message : uncertain } };
  }
}
