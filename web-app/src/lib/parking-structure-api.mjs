import { ACCESS_COOKIE, REFRESH_COOKIE, AuthError, baseUrl, forwardSession, requireSameOrigin } from './auth.mjs';
import { draftError } from '../app/(admin)/parking-structure/node-draft-utils.mjs';
import { edgeError, previewDistance } from '../app/(admin)/parking-structure/edge-draft-utils.mjs';
import { validLevelSnapshot } from '../app/(admin)/parking-structure/level-management-utils.mjs';

export const MAX_BYTES = 10 * 1024 * 1024;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const validPlan = plan => plan && uuid.test(plan.level_id) && typeof plan.storage_object_key === 'string' && plan.storage_object_key.trim() &&
  ['width_px', 'height_px', 'revision'].every(key => Number.isSafeInteger(plan[key]) && plan[key] > 0) &&
  plan.width_px * plan.height_px <= 20_000_000;
export function validateStructure(data) {
  if (!data || !Array.isArray(data.levels) || data.levels.some(level => !level || !uuid.test(level.id) ||
    !validLevelSnapshot(level) ||
    !(level.floor_plan === null || (validPlan(level.floor_plan) && level.floor_plan.level_id === level.id))) ||
    new Set(data.levels.map(level => level.id)).size !== data.levels.length) throw new Error('Invalid structure response');
  return data;
}

export function validateCalibration(data, levelId, imageRevision) {
  const item = data?.calibration;
  if (data?.floor_plan_revision !== imageRevision || !(item === null || (item &&
    item.level_id === levelId && item.floor_plan_revision === imageRevision &&
    Number.isSafeInteger(item.revision) && item.revision > 0 &&
    ['start_x', 'start_y', 'end_x', 'end_y'].every(key => Number.isFinite(item[key]) && item[key] >= 0) &&
    Number.isFinite(item.known_distance_m) && item.known_distance_m > 0 &&
    Number.isFinite(item.metres_per_pixel) && item.metres_per_pixel > 0))) throw new Error('Invalid calibration response');
  return data;
}

export function validateNodeDraft(data, levelId, imageRevision) {
  const item = data?.draft;
  if (data?.floor_plan_revision !== imageRevision ||
      !Number.isSafeInteger(data.current_calibration_revision) || data.current_calibration_revision < 0 ||
      typeof data.needs_distance_revalidation !== 'boolean' ||
      !(item === null || (item && item.level_id === levelId && item.floor_plan_revision === imageRevision &&
        Number.isSafeInteger(item.revision) && item.revision > 0 &&
        Number.isSafeInteger(item.calibration_revision) && item.calibration_revision >= 0 &&
        !draftError(item.nodes)))) throw new Error('Invalid node draft response');
  return data;
}

export function validateGraphDraft(data, levelId, imageRevision) {
  validateNodeDraft(data, levelId, imageRevision);
  const draft = data.draft, cal = data.calibration;
  if (!(cal === null ? data.current_calibration_revision === 0 : cal && cal.revision === data.current_calibration_revision &&
      Number.isFinite(cal.metres_per_pixel) && cal.metres_per_pixel > 0) ||
      (draft && (!Number.isInteger(draft.distances_validated_revision) || draft.distances_validated_revision < 0 || draft.distances_validated_revision > draft.revision || edgeError(draft.edges, draft.nodes, true)))) throw new Error('Invalid graph draft response');
  const stale = !cal || !draft || draft.calibration_revision !== cal.revision || draft.distances_validated_revision !== draft.revision;
  if (data.needs_distance_revalidation !== stale) throw new Error('Invalid distance validation state');
  if (draft && !stale) {
    const nodes = new Map(draft.nodes.map(node => [node.id, node]));
    if (draft.edges.some(edge => {
      const distance = previewDistance(nodes.get(edge.from_node_id), nodes.get(edge.to_node_id), cal.metres_per_pixel);
      return distance === null || edge.calibration_revision !== cal.revision || Math.abs(distance - edge.distance_meters) > Math.max(distance * 1e-9, 1e-12);
    })) throw new Error('Invalid calculated edge distances');
  }
  return data;
}

export async function readLimitedBody(body, limit = MAX_BYTES) {
  if (!body) throw new AuthError('input', 400);
  const reader = body.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) { await reader.cancel(); throw new AuthError('input', 413); }
      chunks.push(Buffer.from(value));
    }
  } finally { reader.releaseLock(); }
  if (!size) throw new AuthError('input', 400);
  return Buffer.concat(chunks);
}

export async function structureRequest(request, path = []) {
  let session;
  const calibration = path.length === 3 && path[2] === 'calibration';
  const nodeDraft = path.length === 3 && path[2] === 'node-draft';
  const graphDraft = path.length === 3 && path[2] === 'graph-draft';
  try {
    const upload = request.method === 'PUT';
    if (upload) requireSameOrigin(request);
    const list = path.length === 0 && request.method === 'GET';
    const level = path.length >= 2 && path[0] === 'levels' && uuid.test(path[1]);
    const picture = level && path.length === 3 && path[2] === 'image' && request.method === 'GET';
    if (!list && !picture && !(upload && level && path.length === 2) &&
      !((calibration || nodeDraft || graphDraft) && level && ['GET', 'PUT'].includes(request.method))) return { status: 404, body: { error: 'Not found.' } };
    const restored = await forwardSession(request.cookies.get(ACCESS_COOKIE)?.value, request.cookies.get(REFRESH_COOKIE)?.value);
    session = restored.session;
    const headers = { Authorization: `Bearer ${session?.access_token ?? request.cookies.get(ACCESS_COOKIE)?.value}` };
    let body;
    let imageRevision;
    let suffix = list ? '/parking/structure' : `/parking/levels/${path[1]}/floor-plan${picture ? '/image' : calibration ? '/calibration' : nodeDraft ? '/node-draft' : graphDraft ? '/graph-draft' : ''}`;
    if (calibration || nodeDraft || graphDraft) {
      if (upload) {
        if (request.headers.get('content-type')?.split(';')[0] !== 'application/json') throw new AuthError('input', 415);
        const bytes = await readLimitedBody(request.body, nodeDraft || graphDraft ? 512 * 1024 : 8192);
        let input;
        try { input = JSON.parse(bytes.toString()); } catch { throw new AuthError('input', 400); }
        const fields = graphDraft ? ['floor_plan_revision', 'expected_revision', 'expected_calibration_revision', 'edges'] : nodeDraft ? ['floor_plan_revision', 'expected_revision', 'nodes'] : ['floor_plan_revision', 'expected_revision', 'start_x', 'start_y', 'end_x', 'end_y', 'known_distance_m'];
        if (!input || Array.isArray(input) || Object.keys(input).length !== fields.length ||
          fields.some(key => key === 'nodes' ? Boolean(draftError(input.nodes)) : key === 'edges' ? Boolean(edgeError(input.edges)) : !Number.isFinite(input[key])) ||
          !Number.isInteger(input.floor_plan_revision) || input.floor_plan_revision < 1 ||
          !Number.isInteger(input.expected_revision) || input.expected_revision < 0) throw new AuthError('input', 422);
        if (graphDraft && (input.expected_revision < 1 || input.expected_revision > 2147483646 || input.floor_plan_revision > 2147483646 ||
          !Number.isInteger(input.expected_calibration_revision) || input.expected_calibration_revision < 1 || input.expected_calibration_revision > 2147483646)) throw new AuthError('input', 422);
        imageRevision = input.floor_plan_revision;
        headers['Content-Type'] = 'application/json';
        body = JSON.stringify(input);
      } else {
        const revision = new URL(request.url).searchParams.get('floor_plan_revision');
        if (!/^[1-9]\d*$/.test(revision ?? '') || !Number.isSafeInteger(Number(revision))) throw new AuthError('input', 422);
        imageRevision = Number(revision);
        suffix += `?floor_plan_revision=${revision}`;
      }
    } else if (upload) {
      const revision = new URL(request.url).searchParams.get('expected_revision');
      if (!/^(0|[1-9]\d*)$/.test(revision ?? '') || Number(revision) > 2147483646) throw new AuthError('input', 422);
      const type = request.headers.get('content-type')?.split(';')[0].toLowerCase();
      if (!['image/png', 'image/jpeg'].includes(type)) throw new AuthError('input', 415);
      headers['Content-Type'] = type;
      body = await readLimitedBody(request.body);
      suffix += `?expected_revision=${revision}`;
    } else if (picture) {
      const revision = new URL(request.url).searchParams.get('revision');
      if (revision !== null) {
        if (!/^[1-9]\d*$/.test(revision) || !Number.isSafeInteger(Number(revision))) throw new AuthError('input', 422);
        suffix += `?expected_revision=${revision}`;
      }
    }
    const response = await fetch(`${baseUrl(process.env.BACKEND_BASE_URL)}/admin${suffix}`, {
      method: request.method, headers, body, cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(60000),
    });
    if ([401, 403].includes(response.status)) throw new AuthError(response.status === 401 ? 'expired' : 'denied', response.status);
    if (!response.ok) {
      if (response.status === 413) {
        if (nodeDraft || graphDraft) return { status: 413, session, body: { error: 'Draft exceeds 512 KiB.' } };
        const failure = await response.json().catch(() => null);
        const messages = {
          floor_plan_upload_too_large: 'Original upload exceeds 10 MiB (10,485,760 bytes). Choose a smaller file.',
          floor_plan_pixels_too_large: 'Decoded image exceeds 20 megapixels. Reduce its pixel dimensions.',
          floor_plan_processed_too_large: 'Normalized PNG exceeds 10 MiB (10,485,760 bytes), even though the original file may be smaller. Export a smaller PNG or reduce its dimensions.',
        };
        const code = failure?.detail?.code;
        return { status: 413, session, body: { error: messages[code] || 'The upstream service rejected the image size. Its exact size restriction could not be identified.' } };
      }
      const errors = { 404: 'Level or floor plan not found. Refresh the list.', 409: graphDraft ? 'Image, nodes, edges or calibration changed. Reload before saving. Your edits are retained.' : nodeDraft ? 'Image or node draft changed. Reload before saving. Your edits are retained.' : calibration ? 'Image or calibration changed. Refresh the page before saving.' : 'This floor plan changed. Refresh before replacing it.',
        415: nodeDraft || graphDraft ? 'Use a JSON draft.' : 'Use a static PNG or JPEG image.',
        422: graphDraft ? 'Save nodes and calibration first. Use unique connections between distinct saved nodes with positive distances.' : nodeDraft ? 'Check unique nonblank codes, node types, UUIDs and image coordinates.' : calibration ? 'Choose two distinct points inside the image and a positive finite distance.' : 'Invalid image or revision. Choose a valid PNG or JPEG.' };
      return { status: errors[response.status] ? response.status : 503, session, body: { error: errors[response.status] || 'Floor-plan request could not be confirmed. Refresh before retrying.' } };
    }
    if (picture) {
      if (!response.headers.get('content-type')?.startsWith('image/png')) throw new Error('Invalid image response');
      return { status: 200, session, image: await readLimitedBody(response.body) };
    }
    const result = await response.json();
    if (list) validateStructure(result);
    else if (graphDraft) {
      validateGraphDraft(result, path[1], imageRevision);
      if (upload && (!result.draft || result.needs_distance_revalidation)) throw new Error('Missing validated saved graph');
    }
    else if (nodeDraft) {
      validateNodeDraft(result, path[1], imageRevision);
      if (upload && result.draft === null) throw new Error('Missing saved node draft');
    }
    else if (calibration) {
      validateCalibration(result, path[1], imageRevision);
      if (upload && result.calibration === null) throw new Error('Missing saved calibration');
    }
    else if (!validPlan(result) || result.level_id !== path[1]) throw new Error('Invalid response');
    return { status: 200, session, body: result };
  } catch (error) {
    return { status: error instanceof AuthError ? error.status : 503,
      body: { error: error instanceof AuthError ? (error.status === 413 ? (graphDraft || nodeDraft ? 'Draft exceeds 512 KiB.' : calibration ? 'Calibration request exceeds 8 KiB.' : 'Image exceeds the Next.js transfer limit of 10 MiB (10,485,760 bytes).') : error.message) : 'Floor-plan request could not be confirmed. Refresh before retrying.' },
      session: error.session ?? session, clear: error instanceof AuthError && [401, 403].includes(error.status) };
  }
}
