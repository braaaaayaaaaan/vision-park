import { ACCESS_COOKIE, AuthError, baseUrl, forwardSession, requireSameOrigin } from './auth.mjs';
import { readLimitedBody } from './parking-structure-api.mjs';
import { roles, uuid, validateContext, validateCameras, validateActivity, validateEvent, validatePlayback, validateProcessing } from './cameras-contracts.mjs';

const errorMessages = {
  processing_busy: 'Recorded processing is still running. Wait and inspect its result before retrying.',
  recording_changed: 'The recording changed. Retry requires the original footage.',
  configuration_changed: 'Parking Structure changed. Refresh before starting a new operation.',
  playback_exists: 'This processing identity already exists. Inspect its results and use Retry.',
  playback_not_found: 'No saved recognition set exists for this identity. Retry cannot start a new scan.',
  playback_conflict: 'The footage or entrance mapping differs from the original run. Keep its original context.',
  anpr_result_unconfirmed: 'The outcome is unconfirmed. Inspect saved results and retry the same identity.',
  anpr_processing_failed: 'Processing did not finish successfully. Inspect saved results before retrying.',
};
export async function cameraRequest(request, path = [], dependencies = {}) {
  const send = dependencies.fetch ?? fetch;
  const restore = dependencies.forwardSession ?? dependencies.restoreSession ?? forwardSession;
  let input;
  const writing = request.method === 'POST';
  const media = path.length === 2 && roles.includes(path[0]) && path[1] === 'recording' && ['GET', 'HEAD'].includes(request.method);
  const processing = path.length === 2 && roles.includes(path[0]) && path[1] === 'process' && writing;
  const list = !path.length && request.method === 'GET';
  const activity = path.length === 1 && path[0] === 'activity' && request.method === 'GET';
  const detail = path.length === 2 && path[0] === 'events' && uuid(path[1]) && request.method === 'GET';
  const playback = path.length === 2 && path[0] === 'playbacks' && uuid(path[1]) && request.method === 'GET';
  if (!media && !processing && !list && !activity && !detail && !playback) return { status: 404, body: { error: 'Not found.' } };
  try {
    if (writing) requireSameOrigin(request);
    const token = request.cookies.get(ACCESS_COOKIE)?.value;
    await restore(token);
    const params = new URL(request.url).searchParams;
    const allowed = activity ? ['role', 'plate', 'result', 'start_date', 'end_date', 'limit', 'offset'] : playback ? ['role'] : [];
    if ([...params.keys()].some(key => !allowed.includes(key)) || playback && !roles.includes(params.get('role'))) throw new AuthError('input', 422);
    const headers = { Authorization: `Bearer ${token}`, Accept: media ? 'video/mp4' : 'application/json' };
    if (media && request.headers.has('range')) headers.Range = request.headers.get('range');
    if (processing) {
      if (request.headers.get('content-type')?.split(';')[0] !== 'application/json') throw new AuthError('input', 415);
      try { input = JSON.parse((await readLimitedBody(request.body, 4096)).toString()); }
      catch (error) { if (error instanceof AuthError) throw error; throw new AuthError('input', 422); }
      try {
        validateContext(input, path[0]);
        if (!['start', 'retry'].includes(input.action) || Object.keys(input).some(key =>
          !['playback_id', 'action', 'recording_identity', 'entrance_node_id', 'publication_revision'].includes(key))) throw new Error();
      } catch { throw new AuthError('input', 422); }
      headers['Content-Type'] = 'application/json';
    }
    const upstream = await send(`${baseUrl(process.env.BACKEND_BASE_URL)}/admin/cameras${path.length ? '/' + path.join('/') : ''}${params.size ? '?' + params : ''}`, {
      method: request.method, headers, ...(input ? { body: JSON.stringify(input) } : {}),
      cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(processing ? 165000 : 20000),
    });
    if ([401, 403].includes(upstream.status)) throw new AuthError(upstream.status === 401 ? 'expired' : 'denied', upstream.status);
    if (media && (upstream.ok || upstream.status === 416)) {
      const safe = {};
      for (const key of ['content-type', 'content-length', 'content-range', 'accept-ranges']) {
        if (upstream.headers.has(key)) safe[key] = upstream.headers.get(key);
      }
      return { status: upstream.status, stream: request.method === 'HEAD' || upstream.status === 416 ? null : upstream.body, media: true, headers: safe };
    }
    const data = await upstream.json().catch(() => null);
    if (!upstream.ok) {
      const code = data?.detail?.code;
      const results = data?.detail?.results;
      let partial;
      if (processing && Array.isArray(results)) {
        try { partial = validateProcessing({ playback_id: input.playback_id, results }, input.playback_id); } catch { /* Retain identity even when partial data is invalid. */ }
      }
      return { status: [404, 409, 413, 415, 422, 429].includes(upstream.status) ? upstream.status : 503,
        body: { code: errorMessages[code] ? code : 'camera_unavailable',
          error: errorMessages[code] ?? (upstream.status === 422 ? 'Check the selected filters or original run context.' :
            processing ? 'Processing could not be confirmed. Inspect this run before retrying.' : 'Camera information is unavailable. Refresh to retry.'),
          ...(partial ? { results: partial.results } : {}), ...(input ? { playback_id: input.playback_id } : {}) } };
    }
    const body = list ? validateCameras(data) : activity ? validateActivity(data) : detail ? validateEvent(data) :
      playback ? validatePlayback(data) : validateProcessing(data, input.playback_id);
    return { status: 200, body };
  } catch (error) {
    return { status: error instanceof AuthError ? error.status : 503, body: {
      error: error instanceof AuthError ? error.message : processing ?
        'The request ended without a confirmed outcome. Inspect saved results; do not start a replacement run.' : 'Camera information could not be verified. Refresh to retry.',
      code: error instanceof AuthError ? error.code : 'outcome_unconfirmed',
      ...(input ? { playback_id: input.playback_id } : {}),
    } };
  }
}
