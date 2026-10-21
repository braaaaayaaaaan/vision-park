import { uuid, validateZoneResponse } from './zone-draft-utils.mjs';

export function linksFromRows(rows) {
  return Object.fromEntries(rows.map(row => [row.zone_id, { node_id: row.node_id, floor_plan_revision: row.floor_plan_revision }]));
}
export function linksChanged(links, saved) {
  const ids = new Set([...Object.keys(links), ...Object.keys(saved)]);
  return [...ids].some(id => links[id]?.node_id !== saved[id]?.node_id || links[id]?.floor_plan_revision !== saved[id]?.floor_plan_revision);
}
export function entranceReview(link, nodes, imageRevision) {
  if (!link) return [];
  if (link.floor_plan_revision !== imageRevision) return ['Image Replaced'];
  const node = nodes.find(node => node.id === link.node_id);
  return !node ? ['Node Missing'] : node.node_type !== 'zone_entrance' ? ['Node Type Changed'] : [];
}
export function assignZone(links, nodeId, zoneId, imageRevision) {
  const next = Object.fromEntries(Object.entries(links).filter(([, link]) => link.node_id !== nodeId));
  if (zoneId) next[zoneId] = { node_id: nodeId, floor_plan_revision: imageRevision };
  return next;
}
export function zoneChanges(links, saved, zones) {
  return [...new Set([...Object.keys(links), ...Object.keys(saved)])].filter(id => linksChanged({ [id]: links[id] }, { [id]: saved[id] })).map(id => {
    const zone = zones.find(zone => zone.id === id);
    if (!zone) throw new Error('A Draft Zone Is Missing. Reload Before Saving.');
    return { zone_id: id, node_id: links[id]?.node_id ?? null, expected_zone_revision: zone.revision };
  });
}
export function changesError(changes, nodes) {
  if (!Array.isArray(changes) || changes.length > 1000) return 'Use At Most 1,000 Zone Link Changes.';
  const zones = new Set(), entrances = new Set();
  for (const change of changes) {
    if (!change || Object.keys(change).length !== 3 || !uuid(change.zone_id) || zones.has(change.zone_id.toLowerCase()) ||
      !Number.isInteger(change.expected_zone_revision) || change.expected_zone_revision < 1 || change.expected_zone_revision > 2147483646 ||
      !(change.node_id === null || uuid(change.node_id))) return 'Use Unique Draft Zones And Current Zone Revisions.';
    if (change.node_id !== null && (!nodes.some(node => node.id.toLowerCase() === change.node_id.toLowerCase() && node.node_type === 'zone_entrance') || entrances.has(change.node_id.toLowerCase()))) return 'Select A Distinct Zone Entrance For Each Zone.';
    zones.add(change.zone_id.toLowerCase()); if (change.node_id) entrances.add(change.node_id.toLowerCase());
  }
  return '';
}
export function validateEntranceResponse(data, levelId, imageRevision) {
  validateZoneResponse(data?.zone_configuration, 'GET', levelId);
  if (!Array.isArray(data.zone_entrances) || data.zone_entrances.length > 1000) throw new Error('Invalid Zone Links.');
  const zones = new Set(), nodes = new Set();
  for (const link of data.zone_entrances) {
    if (!link || !uuid(link.zone_id) || !uuid(link.node_id) || zones.has(link.zone_id) || nodes.has(link.node_id) ||
      !Number.isSafeInteger(link.floor_plan_revision) || link.floor_plan_revision < 1 || !data.zone_configuration.zones.some(zone => zone.id === link.zone_id) ||
      !Array.isArray(link.review_reasons) || link.review_reasons.some(reason => !['image_replaced', 'node_missing', 'node_type_changed'].includes(reason))) throw new Error('Invalid Zone Link Record.');
    const review = entranceReview(link, data.draft?.nodes ?? [], imageRevision);
    const reasons = { 'Image Replaced': 'image_replaced', 'Node Missing': 'node_missing', 'Node Type Changed': 'node_type_changed' };
    if (link.state !== (review.length ? 'needs_review' : 'linked') || JSON.stringify(link.review_reasons) !== JSON.stringify(review.map(reason => reasons[reason]))) throw new Error('Invalid Zone Link Review State.');
    zones.add(link.zone_id); nodes.add(link.node_id);
  }
  return data;
}
