import { ACCESS_COOKIE, REFRESH_COOKIE, AuthError, baseUrl, forwardSession, requireSameOrigin } from './auth.mjs';
import { readLimitedBody } from './parking-structure-api.mjs';
import { uuid } from '../app/(admin)/parking-structure/zone-draft-utils.mjs';

export function validScope(input) {
  return input && Object.keys(input).length === 1 && Array.isArray(input.level_ids) && input.level_ids.length > 0 && input.level_ids.length <= 64 &&
    input.level_ids.every(uuid) && new Set(input.level_ids.map(id => id.toLowerCase())).size === input.level_ids.length;
}

export function validationReport(data, ids) {
  const bad = () => {
    const error = new Error('Invalid validation report.');
    error.code = 'invalid_report_metadata';
    throw error;
  };
  const count = value => Number.isSafeInteger(value) && value >= 0;
  if (!data || data.report_version !== 1 || !['ready', 'needs_attention'].includes(data.readiness) || typeof data.allocation_ready !== 'boolean' ||
    !Number.isFinite(Date.parse(data.snapshot_at)) || !Array.isArray(data.levels) || data.levels.length !== ids.length ||
    new Set(data.levels.map(level => level.id)).size !== ids.length || data.levels.some(level => !ids.includes(level.id) || typeof level.name !== 'string' ||
      !Number.isInteger(level.level_number) || !Number.isInteger(level.metadata_revision) || level.metadata_revision < 1 ||
      ['floor_plan_revision', 'calibration_revision', 'draft_revision', 'distances_validated_revision'].some(key => level[key] !== null && !count(level[key])) ||
      !Array.isArray(level.zone_revisions) || !Array.isArray(level.mappings)) ||
    !Array.isArray(data.zones) || !Array.isArray(data.issues) || !Array.isArray(data.ramp_revisions) ||
    !Array.isArray(data.checked) || !data.checked.length || data.checked.some(value => typeof value !== 'string') ||
    !(data.building_entrance_id === null || uuid(data.building_entrance_id))) bad();
  const fields = ['levels', 'nodes', 'directed_edges', 'routable_edges', 'mapped_zones', 'zones', 'errors', 'warnings'];
  if (fields.some(key => !count(data.summary?.[key])) || data.summary.levels !== ids.length || data.summary.zones !== data.zones.length || data.summary.routable_edges > data.summary.directed_edges ||
    data.summary.errors !== data.issues.filter(issue => issue.severity === 'error').length || data.summary.warnings !== data.issues.filter(issue => issue.severity === 'warning').length ||
    data.issues.some(issue => !['error', 'warning'].includes(issue.severity) || typeof issue.code !== 'string' || typeof issue.message !== 'string' ||
      !(issue.level_id === null || ids.includes(issue.level_id)) || !(issue.zone_id === null || uuid(issue.zone_id)) || !(issue.edge_id === null || uuid(issue.edge_id)))) bad();
  const seen = new Set();
  for (const zone of data.zones) {
    if (!uuid(zone.zone_id) || seen.has(zone.zone_id) || !ids.includes(zone.level_id) || typeof zone.code !== 'string' || typeof zone.name !== 'string' ||
      !['open', 'closed', 'maintenance'].includes(zone.intended_status) || !Number.isInteger(zone.revision) || zone.revision < 1 ||
      ![zone.total_capacity, zone.unavailable_capacity, zone.usable_capacity].every(count) || zone.usable_capacity !== zone.total_capacity - zone.unavailable_capacity ||
      zone.allocation_candidate !== (zone.intended_status === 'open' && zone.usable_capacity > 0) ||
      !['linked', 'unlinked', 'needs_review'].includes(zone.mapping_state) || !(zone.entrance_node_id === null || uuid(zone.entrance_node_id)) ||
      !['reachable', 'unreachable', 'not_checked', 'not_applicable'].includes(zone.reachability) || typeof zone.message !== 'string' ||
      !(zone.node_ids === null || Array.isArray(zone.node_ids) && zone.node_ids.length > 0 && zone.node_ids.every(uuid)) ||
      (zone.reachability === 'reachable' ? !Number.isFinite(zone.distance_meters) || zone.distance_meters < 0 || zone.mapping_state !== 'linked' || !zone.allocation_candidate ||
        zone.node_ids !== null && (zone.node_ids[0] !== data.building_entrance_id || zone.node_ids.at(-1) !== zone.entrance_node_id) : zone.distance_meters !== null || zone.node_ids !== null) ||
      !zone.allocation_candidate && zone.reachability !== 'not_applicable') bad();
    seen.add(zone.zone_id);
  }
  if ((data.readiness === 'ready') !== (data.summary.errors === 0) || data.allocation_ready !== (data.readiness === 'ready' && data.zones.some(zone => zone.allocation_candidate)) ||
    data.readiness === 'ready' && (!data.building_entrance_id || data.zones.some(zone => zone.allocation_candidate && zone.reachability !== 'reachable'))) bad();
  return data;
}

export async function structureValidationRequest(request) {
  let session, stage = 'request', upstreamStatus = null;
  const started = Date.now();
  try {
    if (request.method !== 'POST' || new URL(request.url).search) return { status: 404, body: { error: 'Not found.' } };
    requireSameOrigin(request);
    stage = 'authentication';
    const restored = await forwardSession(request.cookies.get(ACCESS_COOKIE)?.value, request.cookies.get(REFRESH_COOKIE)?.value);
    session = restored.session;
    stage = 'request_body';
    if (request.headers.get('content-type')?.split(';')[0].toLowerCase() !== 'application/json') throw new AuthError('input', 415);
    let input;
    try { input = JSON.parse((await readLimitedBody(request.body, 8192)).toString()); }
    catch (error) { if (error instanceof AuthError) throw error; throw new AuthError('input', 422); }
    if (!validScope(input)) throw new AuthError('input', 422);
    const ids = input.level_ids.map(id => id.toLowerCase());
    stage = 'upstream_fetch';
    const response = await fetch(`${baseUrl(process.env.BACKEND_BASE_URL)}/admin/parking/structure/validate`, {
      method: 'POST', headers: { Authorization: `Bearer ${session?.access_token ?? request.cookies.get(ACCESS_COOKIE)?.value}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ level_ids: ids }), cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(60000),
    });
    upstreamStatus = response.status;
    if ([401, 403].includes(response.status)) throw new AuthError(response.status === 401 ? 'expired' : 'denied', response.status);
    if (!response.ok) {
      if (response.status >= 500) console.error('[Stage5C validation]', { stage: 'upstream_response', upstream_status: upstreamStatus, elapsed_ms: Date.now() - started });
      const body = await response.json().catch(() => null), missing = body?.detail?.required_level_ids;
      return { status: [404, 413, 415, 422].includes(response.status) ? response.status : 503, session, body: {
        error: body?.detail?.code === 'incomplete_scope' ? 'Include all connected ramp endpoint and measurement reference levels before validating.' :
          response.status === 404 ? 'A selected level is missing. Refresh parking levels.' : response.status === 413 ? 'Validation scope exceeds the graph size limit.' :
            response.status === 422 ? 'Select 1–64 distinct parking levels with a complete connected scope.' : 'Draft validation is unavailable. Retry after checking setup.',
        required_level_ids: Array.isArray(missing) && missing.length <= 1000 && missing.every(uuid) ? missing : [],
      } };
    }
    stage = 'response_json';
    const data = await response.json();
    stage = 'response_contract';
    return { status: 200, session, body: validationReport(data, ids) };
  } catch (error) {
    if (!(error instanceof AuthError) || error.status >= 500) {
      const codes = ['ECONNREFUSED', 'ECONNRESET', 'ENOTFOUND', 'EAI_AGAIN', 'UND_ERR_CONNECT_TIMEOUT'];
      const names = ['TypeError', 'SyntaxError', 'TimeoutError', 'AbortError'];
      console.error('[Stage5C validation]', { stage, upstream_status: upstreamStatus, elapsed_ms: Date.now() - started,
        reason: stage === 'response_contract' && error.code === 'invalid_report_metadata' ? error.code : names.includes(error.name) ? error.name : 'Error',
        ...(codes.includes(error.cause?.code) ? { connection_code: error.cause.code } : {}),
      });
    }
    return { status: error instanceof AuthError ? error.status : 503, session: error.session ?? session,
      clear: error instanceof AuthError && [401, 403].includes(error.status), body: { error: error instanceof AuthError ?
        error.status === 413 ? 'Validation scope exceeds 8 KiB.' : error.status === 415 ? 'Use a JSON validation scope.' :
          error.status === 422 ? 'Select 1–64 distinct parking level IDs.' : error.message : 'Draft validation report could not be confirmed. Retry.' } };
  }
}
