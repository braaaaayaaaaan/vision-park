export const MAX_EDGES = 2000;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function edgeError(edges, nodes = null, stored = false) {
  if (!Array.isArray(edges) || edges.length > MAX_EDGES) return 'A Draft Can Contain At Most 2,000 Directed Edges.';
  const ids = new Set(), pairs = new Set();
  const nodeIds = nodes && new Set(nodes.map(node => node.id.toLowerCase()));
  const keys = stored ? ['id', 'from_node_id', 'to_node_id', 'distance_meters', 'calibration_revision'] : ['id', 'from_node_id', 'to_node_id'];
  for (const edge of edges) {
    if (!edge || Object.keys(edge).length !== keys.length || keys.some(key => !Object.hasOwn(edge, key)) ||
      ![edge.id, edge.from_node_id, edge.to_node_id].every(value => typeof value === 'string' && uuid.test(value))) return 'Use Valid Edge And Node UUIDs. Distances Are Calculated By The Server.';
    const id = edge.id.toLowerCase(), from = edge.from_node_id.toLowerCase(), to = edge.to_node_id.toLowerCase(), pair = `${from}:${to}`;
    if (from === to) return 'Choose Two Different Nodes.';
    if (ids.has(id) || pairs.has(pair)) return 'Each Directed Connection And Edge ID Must Be Unique.';
    if (nodeIds && (!nodeIds.has(from) || !nodeIds.has(to))) return 'Connections Must Reference Saved Nodes On This Floor Plan.';
    if (stored && (!(Number.isFinite(edge.distance_meters) && edge.distance_meters > 0) || !Number.isInteger(edge.calibration_revision) || edge.calibration_revision < 1)) return 'Invalid Saved Edge Distance Or Calibration.';
    ids.add(id); pairs.add(pair);
  }
  return '';
}
export function edgeInputs(edges) {
  return edges.map(({ id, from_node_id, to_node_id }) => ({ id, from_node_id, to_node_id }));
}
export function previewDistance(from, to, scale) {
  if (!from || !to || ![from.x, from.y, to.x, to.y, scale].every(Number.isFinite) || scale <= 0) return null;
  const value = Math.hypot(to.x - from.x, to.y - from.y) * scale;
  return Number.isFinite(value) && value > 0 ? value : null;
}
export function connectionEdges(edges, from, to, twoWay, makeId) {
  const added = [{ id: makeId(), from_node_id: from, to_node_id: to }];
  if (twoWay) added.push({ id: makeId(), from_node_id: to, to_node_id: from });
  const error = edgeError([...edges, ...added]);
  if (error) throw new Error(error);
  return [...edges, ...added];
}
// Trim arrows outside node markers. Opposite directions use parallel visual
// offsets; physical weights always use the original node centres instead.
export function edgeGeometry(from, to, radius, parallel = false) {
  const length = Math.hypot(to.x - from.x, to.y - from.y);
  if (!Number.isFinite(length) || length <= 0) return null;
  const ux = (to.x - from.x) / length, uy = (to.y - from.y) / length;
  const trim = Math.min(radius * 1.6, length * .25);
  const offset = parallel ? Math.min(radius * .55, length * .1) : 0;
  const x1 = from.x + ux * trim - uy * offset, y1 = from.y + uy * trim + ux * offset;
  const x2 = to.x - ux * trim - uy * offset, y2 = to.y - uy * trim + ux * offset;
  return { x1, y1, x2, y2, labelX: (x1 + x2) / 2, labelY: (y1 + y2) / 2 };
}
