import { ACCESS_COOKIE, REFRESH_COOKIE, AuthError, baseUrl, forwardSession, requireSameOrigin } from './auth.mjs';
import { readLimitedBody } from './parking-structure-api.mjs';
import { duplicateLevelNumbers, levelRequestError, validateLevelResponse } from '../app/(admin)/parking-structure/level-management-utils.mjs';

export async function levelManagementRequest(request, path) {
  let session;
  const unconfirmed = request.method === 'DELETE' ? 'Level deletion could not be confirmed. Refresh before retrying.' : 'Level save could not be confirmed. Refresh before retrying.';
  const invalid = request.method === 'DELETE' ? 'Refresh to load the current level revision.' : 'Check level numbers, names and the current edit snapshot.';
  try {
    const mode = request.method === 'POST' && path.length === 1 && path[0] === 'levels' ? 'create' :
      request.method === 'POST' && path.length === 2 && path[0] === 'levels' && path[1] === 'bulk' ? 'bulk' :
      ['PATCH', 'DELETE'].includes(request.method) && path.length === 2 && path[0] === 'levels' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(path[1]) ? request.method === 'DELETE' ? 'delete' : 'edit' : null;
    if (!mode) return { status: 404, body: { error: 'Not found.' } };
    requireSameOrigin(request);
    const restored = await forwardSession(request.cookies.get(ACCESS_COOKIE)?.value, request.cookies.get(REFRESH_COOKIE)?.value);
    session = restored.session;
    if (request.headers.get('content-type')?.split(';')[0].toLowerCase() !== 'application/json') throw new AuthError('input', 415);
    const bytes = await readLimitedBody(request.body, 32 * 1024);
    let input;
    try { input = JSON.parse(bytes.toString()); } catch { throw new AuthError('input', 422); }
    if (levelRequestError(input, mode)) throw new AuthError('input', 422);
    if (mode === 'bulk' && duplicateLevelNumbers(input.levels)) throw new AuthError('duplicate', 409);
    // Names being saved are trimmed; the original edit snapshot stays byte-for-byte intact.
    input = mode === 'bulk' ? { levels: input.levels.map(item => ({ ...item, name: item.name.trim() })) } : mode === 'delete' ? input : { ...input, name: input.name.trim() };
    const suffix = mode === 'bulk' ? '/bulk' : ['edit', 'delete'].includes(mode) ? `/${path[1].toLowerCase()}` : '';
    const response = await fetch(`${baseUrl(process.env.BACKEND_BASE_URL)}/admin/parking/levels${suffix}`, {
      method: request.method, headers: { Authorization: `Bearer ${session?.access_token ?? request.cookies.get(ACCESS_COOKIE)?.value}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(input), cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(60000),
    });
    if ([401, 403].includes(response.status)) throw new AuthError(response.status === 401 ? 'expired' : 'denied', response.status);
    if (!response.ok) {
      const data = await response.json().catch(() => null);
      const conflicts = {
        duplicate_number: 'A level number is already in use. Refresh and choose unique numbers. Nothing was saved.',
        stale: 'This level has already been changed. Please refresh and review before trying again.',
        active: 'Active levels cannot be deleted. No changes were made.',
        has_dependencies: 'This level has zones, navigation or other associated records and cannot be deleted. No changes were made.',
      };
      return { status: [404, 409, 413, 415, 422].includes(response.status) ? response.status : 503, session, body: { error:
        response.status === 409 ? conflicts[data?.detail?.code] ?? 'The level or its number changed. Refresh and review before retrying.' :
          response.status === 404 ? 'Parking level not found. Refresh the list.' : response.status === 422 ? invalid : unconfirmed } };
    }
    return { status: ['edit', 'delete'].includes(mode) ? 200 : 201, session, body: validateLevelResponse(await response.json(), input, mode, path[1]?.toLowerCase()) };
  } catch (error) {
    return { status: error instanceof AuthError ? error.status : 503, session: error.session ?? session,
      clear: error instanceof AuthError && [401, 403].includes(error.status), body: { error: error instanceof AuthError ?
        error.status === 413 ? 'Level request exceeds 32 KiB.' : error.status === 415 ? 'Use a JSON level request.' : error.status === 422 ? invalid :
          error.status === 409 ? 'Use unique level numbers in the batch.' : error.message : unconfirmed } };
  }
}
