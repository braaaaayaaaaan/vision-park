import { traceError, traceDistance } from './ramp-trace-utils.mjs';
import { draftError } from './node-draft-utils.mjs';
export const reviewLabels = {
  reference_image_replaced: 'Reference image replaced: retrace the ramp',
  reference_calibration_missing: 'Reference calibration required',
  reference_calibration_changed: 'Reference calibration changed: recalculate and reconfirm',
  source_image_replaced: 'Source floor plan replaced', source_draft_changed: 'Source Draft Changed',
  source_node_missing: 'Source ramp node missing', source_not_ramp: 'Source node is no longer a ramp',
  destination_image_replaced: 'Destination floor plan replaced', destination_draft_changed: 'Destination Draft Changed',
  destination_node_missing: 'Destination ramp node missing', destination_not_ramp: 'Destination node is no longer a ramp',
};
const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const revision = (value, minimum = 1) => Number.isInteger(value) && value >= minimum && value <= 2147483646;
const edgeKeys = ['id', 'expected_revision', 'from_level_id', 'from_floor_plan_revision', 'from_draft_revision', 'from_node_id',
  'to_level_id', 'to_floor_plan_revision', 'to_draft_revision', 'to_node_id', 'reference_level_id', 'reference_floor_plan_revision', 'reference_calibration_revision', 'trace_points'];
export function rampBatchError(batch) {
  if (!batch || Object.keys(batch).length !== 3 || typeof batch.confirm_measurement !== 'boolean' ||
      !Array.isArray(batch.upserts) || !Array.isArray(batch.deletes) || batch.upserts.length > 2 || batch.deletes.length > 2 ||
      batch.upserts.length + batch.deletes.length === 0) return 'Use a valid ramp connection batch.';
  if (batch.upserts.length && !batch.confirm_measurement) return 'Confirm the current endpoints and traced ramp paths.';
  const ids = new Set(), pairs = new Set();
  for (const edge of [...batch.upserts, ...batch.deletes]) {
    if (!edge || !uuid(edge.id) || ids.has(edge.id.toLowerCase()) || !revision(edge.expected_revision, batch.upserts.includes(edge) ? 0 : 1)) return 'Use unique edge UUIDs and valid revisions.';
    ids.add(edge.id.toLowerCase());
  }
  for (const edge of batch.deletes) if (Object.keys(edge).length !== 2) return 'Use only edge ID and revision for deletion.';
  for (const edge of batch.upserts) {
    if (Object.keys(edge).length !== edgeKeys.length || edgeKeys.some(key => !Object.hasOwn(edge, key)) ||
      !['from_level_id', 'to_level_id', 'from_node_id', 'to_node_id', 'reference_level_id'].every(key => uuid(edge[key])) ||
      !['from_floor_plan_revision', 'to_floor_plan_revision', 'from_draft_revision', 'to_draft_revision', 'reference_floor_plan_revision', 'reference_calibration_revision'].every(key => revision(edge[key])) ||
      edge.from_level_id.toLowerCase() === edge.to_level_id.toLowerCase() || edge.from_node_id.toLowerCase() === edge.to_node_id.toLowerCase() ||
      traceError(edge.trace_points)) return 'Choose ramp nodes on different levels and a valid calibrated trace.';
    const pair = [edge.from_level_id, edge.from_floor_plan_revision, edge.from_node_id, edge.to_level_id, edge.to_floor_plan_revision, edge.to_node_id].join(':').toLowerCase();
    if (pairs.has(pair)) return 'Directed ramp connections must be unique.';
    pairs.add(pair);
  }
  return '';
}
export function reviewReasons(edge) {
  const reasons = [['from', 'source'], ['to', 'destination']].flatMap(([side, label]) => {
    const current = edge[`current_${side}`], reasons = [];
    if (current.floor_plan_revision !== edge[`${side}_floor_plan_revision`]) reasons.push(`${label}_image_replaced`);
    if (current.draft_revision !== edge[`${side}_draft_revision`]) reasons.push(`${label}_draft_changed`);
    if (!current.node) reasons.push(`${label}_node_missing`);
    else if (current.node.node_type !== 'ramp') reasons.push(`${label}_not_ramp`);
    return reasons;
  });
  const reference = edge.current_reference;
  if (reference.floor_plan_revision !== edge.reference_floor_plan_revision) reasons.push('reference_image_replaced');
  if (reference.calibration_revision === null) reasons.push('reference_calibration_missing');
  else if (reference.calibration_revision !== edge.reference_calibration_revision) reasons.push('reference_calibration_changed');
  return reasons;
}
function validEdge(edge) {
  if (!edge || !uuid(edge.id) || !Number.isInteger(edge.revision) || edge.revision < 1 || edge.revision > 2147483647 || edge.distance_source !== 'traced_horizontal' || edge.deleted_at !== null ||
    !Number.isFinite(edge.distance_meters) || edge.distance_meters <= 0 ||
    !['from_level_id','to_level_id','from_node_id','to_node_id','reference_level_id'].every(key => uuid(edge[key])) ||
    edge.from_level_id === edge.to_level_id || edge.from_node_id === edge.to_node_id ||
    !['from_floor_plan_revision','to_floor_plan_revision','from_draft_revision','to_draft_revision','reference_floor_plan_revision','reference_calibration_revision'].every(key => revision(edge[key])) ||
    !['from_node_code', 'to_node_code'].every(key => typeof edge[key] === 'string' && edge[key].trim()) ||
    typeof edge.requires_review !== 'boolean' || !Array.isArray(edge.review_reasons)) return false;
  for (const side of ['from', 'to']) {
    const current = edge[`current_${side}`];
    if (!current || ![current.floor_plan_revision, current.draft_revision].every(value => value === null || revision(value)) ||
      !(current.node === null || !draftError([current.node]))) return false;
    if (current.node && current.node.id !== edge[`${side}_node_id`]) return false;
  }
  const ref = edge.current_reference;
  if (!ref || ![ref.floor_plan_revision, ref.calibration_revision].every(value => value === null || revision(value))) return false;
  const distance = traceDistance(edge.trace_points, edge.reference_metres_per_pixel, edge.reference_width_px, edge.reference_height_px);
  if (!Number.isInteger(edge.reference_width_px) || !Number.isInteger(edge.reference_height_px) || edge.reference_width_px <= 0 || edge.reference_height_px <= 0 ||
      distance === null || Math.abs(distance - edge.distance_meters) > distance * 1e-10) return false;
  if (ref.floor_plan_revision === edge.reference_floor_plan_revision && ref.calibration_revision === edge.reference_calibration_revision &&
    (ref.metres_per_pixel !== edge.reference_metres_per_pixel || ref.width_px !== edge.reference_width_px || ref.height_px !== edge.reference_height_px)) return false;
  const reasons = reviewReasons(edge);
  return edge.requires_review === Boolean(reasons.length) && JSON.stringify(reasons) === JSON.stringify(edge.review_reasons);
}
export function validateRampResponse(data, batch = null) {
  if (!data || !Array.isArray(data.edges) || data.edges.some(edge => !validEdge(edge)) || new Set(data.edges.map(edge => edge.id)).size !== data.edges.length) throw new Error('Invalid ramp connection response');
  if (batch) {
    if (!Array.isArray(data.deleted_ids) || data.edges.length !== batch.upserts.length ||
      JSON.stringify([...data.deleted_ids].sort()) !== JSON.stringify(batch.deletes.map(edge => edge.id).sort()) ||
      data.edges.some(edge => {
        const input = batch.upserts.find(item => item.id === edge.id);
        return !input || edge.requires_review || edge.revision !== input.expected_revision + 1 || edgeKeys.filter(key => !['id', 'expected_revision'].includes(key)).some(key => key === 'trace_points' ? edge[key].length !== input[key].length || edge[key].some((point, index) => point.x !== input[key][index].x || point.y !== input[key][index].y) : edge[key] !== input[key]);
      })) throw new Error('Ramp save could not be confirmed');
  } else {
    if (!Number.isSafeInteger(data.total) || data.total < 0 || !Number.isInteger(data.limit) || data.limit < 1 || data.limit > 50 ||
      !Number.isSafeInteger(data.offset) || data.offset < 0 || data.edges.length > data.limit || data.total < data.offset + data.edges.length && data.edges.length > 0) throw new Error('Invalid ramp pagination');
    for (const edge of data.edges) {
      const reverse = edge.reverse_edge;
      if (reverse !== null && (!validEdge(reverse) || reverse.id === edge.id ||
        ['level_id', 'floor_plan_revision', 'node_id'].some(key => reverse[`from_${key}`] !== edge[`to_${key}`] || reverse[`to_${key}`] !== edge[`from_${key}`]))) throw new Error('Invalid reverse ramp connection');
    }
  }
  return data;
}
export const initialRampForm = () => ({ from_level_id: '', from_node_id: '', to_level_id: '', to_node_id: '',
  direction: 'one', forward_trace: null, reverse_trace: null, confirmed: false });
export function buildRampBatch(form, from, to, editing = null, makeId = () => crypto.randomUUID()) {
  const start = from?.draft?.nodes.find(node => node.id === form.from_node_id && node.node_type === 'ramp');
  const end = to?.draft?.nodes.find(node => node.id === form.to_node_id && node.node_type === 'ramp');
  if (!start || !end) throw new Error('Select current saved ramp nodes for both levels.');
  const forward = {
    id: editing?.id ?? makeId(), expected_revision: editing?.revision ?? 0,
    from_level_id: form.from_level_id, from_floor_plan_revision: from.floor_plan_revision, from_draft_revision: from.draft.revision, from_node_id: start.id,
    to_level_id: form.to_level_id, to_floor_plan_revision: to.floor_plan_revision, to_draft_revision: to.draft.revision, to_node_id: end.id,
    ...form.forward_trace,
  };
  const upserts = [forward], deletes = [];
  if (form.direction === 'two') upserts.push({
    id: editing?.reverse_edge?.id ?? makeId(), expected_revision: editing?.reverse_edge?.revision ?? 0,
    from_level_id: forward.to_level_id, from_floor_plan_revision: forward.to_floor_plan_revision, from_draft_revision: forward.to_draft_revision, from_node_id: forward.to_node_id,
    to_level_id: forward.from_level_id, to_floor_plan_revision: forward.from_floor_plan_revision, to_draft_revision: forward.from_draft_revision, to_node_id: forward.from_node_id,
    ...form.reverse_trace,
  });
  else if (editing?.reverse_edge) deletes.push({ id: editing.reverse_edge.id, expected_revision: editing.reverse_edge.revision });
  const batch = { upserts, deletes, confirm_measurement: form.confirmed };
  const error = rampBatchError(batch);
  if (error) throw new Error(error);
  return batch;
}
