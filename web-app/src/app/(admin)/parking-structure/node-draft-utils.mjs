export const NODE_TYPES = {
  building_entrance: 'Building Entrance',
  junction: 'Junction',
  ramp: 'Ramp',
  zone_entrance: 'Zone Entrance',
};
export const MAX_NODES = 1000;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function draftError(nodes, width = Infinity, height = Infinity) {
  if (!Array.isArray(nodes) || nodes.length > MAX_NODES) return 'A draft can contain at most 1,000 nodes.';
  const ids = new Set(), codes = new Set();
  for (const node of nodes) {
    if (!node || Object.keys(node).length !== 5 || !uuid.test(node.id) || ids.has(node.id.toLowerCase())) return 'Each node must have a unique UUID.';
    if (typeof node.code !== 'string' || !node.code.trim() || node.code.trim().length > 64) return 'Use a nonblank node code of at most 64 characters.';
    if (codes.has(node.code.trim())) return 'Node codes must be unique within this draft.';
    if (!Object.hasOwn(NODE_TYPES, node.node_type)) return 'Choose a valid node type.';
    if (!Number.isFinite(node.x) || !Number.isFinite(node.y) || node.x < 0 || node.y < 0 || node.x > width || node.y > height) return 'Node coordinates must be inside the image.';
    ids.add(node.id.toLowerCase()); codes.add(node.code.trim());
  }
  return '';
}
export function createNode(nodes, nodeType, point, id) {
  const prefix = { building_entrance: 'ENT', junction: 'JCT', ramp: 'RMP', zone_entrance: 'ZONE' }[nodeType];
  let number = 1;
  const codes = new Set(nodes.map(node => node.code.trim()));
  while (codes.has(`${prefix}-${number}`)) number += 1;
  return { id, code: `${prefix}-${number}`, node_type: nodeType, x: point.x, y: point.y };
}
export function editNode(nodes, id, changes) {
  return nodes.map(node => node.id === id ? { ...node, ...changes, id: node.id } : node);
}
export function deleteNode(nodes, id) {
  return nodes.filter(node => node.id !== id);
}
export function nodesChanged(nodes, saved) {
  return JSON.stringify(nodes) !== JSON.stringify(saved);
}
export function movedNodePoint(startNode, startPointer, pointer, width, height) {
  return {
    x: Math.max(0, Math.min(width, startNode.x + pointer.x - startPointer.x)),
    y: Math.max(0, Math.min(height, startNode.y + pointer.y - startPointer.y)),
  };
}
