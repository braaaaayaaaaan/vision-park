import { ACCESS_COOKIE, REFRESH_COOKIE, AuthError, baseUrl, restoreSession, requireSameOrigin } from './auth.mjs';
import { readLimitedBody, validateNodeDraft } from './parking-structure-api.mjs';
import { draftError } from '../app/(admin)/parking-structure/node-draft-utils.mjs';
import { uuid } from '../app/(admin)/parking-structure/zone-draft-utils.mjs';
import { changesError, validateEntranceResponse } from '../app/(admin)/parking-structure/zone-entrance-utils.mjs';

export async function nodeZoneRequest(request, path) {
  let session;
  try {
    if (path.length !== 3 || path[0] !== 'levels' || !uuid(path[1]) || path[2] !== 'node-zone-draft' || !['GET', 'PUT'].includes(request.method)) return { status: 404, body: { error: 'Not found.' } };
    if (request.method === 'PUT') requireSameOrigin(request);
    const restored = await restoreSession(request.cookies.get(ACCESS_COOKIE)?.value, request.cookies.get(REFRESH_COOKIE)?.value);
    session = restored.session;
    const levelId = path[1].toLowerCase(), query = new URL(request.url).searchParams;
    let input, imageRevision;
    if (request.method === 'PUT') {
      if (query.size) throw new AuthError('input', 422);
      if (request.headers.get('content-type')?.split(';')[0].toLowerCase() !== 'application/json') throw new AuthError('input', 415);
      const bytes = await readLimitedBody(request.body, 768 * 1024);
      try { input = JSON.parse(bytes.toString()); } catch { throw new AuthError('input', 422); }
      if (!input || Object.keys(input).length !== 4 || !['floor_plan_revision', 'expected_revision'].every(key => Number.isInteger(input[key]) && input[key] >= (key === 'floor_plan_revision' ? 1 : 0) && input[key] <= 2147483646) ||
        draftError(input.nodes) || changesError(input.zone_changes, input.nodes)) throw new AuthError('input', 422);
      input = { ...input, nodes: input.nodes.map(node => ({ ...node, id: node.id.toLowerCase(), code: node.code.trim() })),
        zone_changes: input.zone_changes.map(change => ({ ...change, zone_id: change.zone_id.toLowerCase(), node_id: change.node_id?.toLowerCase() ?? null })) };
      imageRevision = input.floor_plan_revision;
    } else {
      if (query.size !== 1 || !/^\d+$/.test(query.get('floor_plan_revision') ?? '')) throw new AuthError('input', 422);
      imageRevision = Number(query.get('floor_plan_revision'));
      if (!Number.isInteger(imageRevision) || imageRevision < 1 || imageRevision > 2147483646) throw new AuthError('input', 422);
    }
    const response = await fetch(`${baseUrl(process.env.BACKEND_BASE_URL)}/admin/parking/levels/${levelId}/floor-plan/node-zone-draft${input ? '' : `?floor_plan_revision=${imageRevision}`}`, {
      method: request.method, headers: { Authorization: `Bearer ${session?.access_token ?? request.cookies.get(ACCESS_COOKIE)?.value}`, ...(input ? { 'Content-Type': 'application/json' } : {}) },
      ...(input ? { body: JSON.stringify(input) } : {}), cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(60000),
    });
    if ([401, 403].includes(response.status)) throw new AuthError(response.status === 401 ? 'expired' : 'denied', response.status);
    if (!response.ok) {
      const body = await response.json().catch(() => null);
      const conflicts = { conflict: 'Image Or Node Draft Changed. Reload Before Saving.', stale_zone: 'A Zone Or Association Changed. Reload Before Saving.',
        duplicate_assignment: 'Each Draft Zone And Entrance May Have Only One Association.' };
      return { status: [404, 409, 413, 415, 422].includes(response.status) ? response.status : 503, session, body: { error:
        response.status === 409 ? conflicts[body?.detail?.code] ?? 'Draft Configuration Changed. Reload Before Retrying.' :
          response.status === 404 ? 'A Level, Image Or Draft Zone Is Missing. Reload Current Data.' : response.status === 422 ? 'Check Draft Nodes, Same-Level Zone Entrances And Revisions.' : 'Node And Zone-Link Result Could Not Be Confirmed. Reload Before Retrying.' } };
    }
    const data = validateEntranceResponse(validateNodeDraft(await response.json(), levelId, imageRevision), levelId, imageRevision);
    if (input) {
      const nodes = input.nodes;
      if (!data.draft || ![input.expected_revision, input.expected_revision + 1].includes(data.draft.revision) || data.draft.nodes.length !== nodes.length ||
        nodes.some(node => !data.draft.nodes.some(saved => ['id', 'code', 'node_type', 'x', 'y'].every(key => saved[key] === node[key]))) ||
        input.zone_changes.some(change => {
          const zone = data.zone_configuration.zones.find(zone => zone.id === change.zone_id), link = data.zone_entrances.find(link => link.zone_id === change.zone_id);
          return zone?.revision !== change.expected_zone_revision + 1 || (change.node_id === null ? Boolean(link) : link?.node_id !== change.node_id || link.floor_plan_revision !== imageRevision || link.state !== 'linked');
        })) throw new Error('Unconfirmed Combined Save.');
    }
    return { status: 200, session, body: data };
  } catch (error) {
    return { status: error instanceof AuthError ? error.status : 503, session: error.session ?? session,
      clear: error instanceof AuthError && [401, 403].includes(error.status), body: { error: error instanceof AuthError ?
        error.status === 413 ? 'Node And Zone-Link Draft Exceeds 768 KiB.' : error.status === 415 ? 'Use A JSON Node And Zone-Link Draft.' :
          error.status === 422 ? 'Use Valid Draft Nodes, Zone Links And Current Revisions.' : error.message : 'Node And Zone-Link Result Could Not Be Confirmed. Reload Before Retrying.' } };
  }
}
