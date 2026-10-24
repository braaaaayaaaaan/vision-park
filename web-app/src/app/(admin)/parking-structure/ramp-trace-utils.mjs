export const MAX_TRACE_POINTS = 200;
// Original-image pixels only. A trace always belongs to one reference image.
export function traceError(points, width = Infinity, height = Infinity) {
  if (!Array.isArray(points) || points.length < 2 || points.length > MAX_TRACE_POINTS) return 'Place 2–200 distinct trace points.';
  const seen = new Set();
  for (const point of points) {
    if (!point || Object.keys(point).length !== 2 || !Number.isFinite(point.x) || !Number.isFinite(point.y) ||
      point.x < 0 || point.x > width || point.y < 0 || point.y > height) return 'Keep trace points within the reference image.';
    const key = `${point.x}:${point.y}`;
    if (seen.has(key)) return 'Trace points must be distinct.';
    seen.add(key);
  }
  return '';
}
export function traceDistance(points, scale, width = Infinity, height = Infinity) {
  if (traceError(points, width, height) || !Number.isFinite(scale) || scale <= 0) return null;
  const distance = points.slice(1).reduce((sum, point, index) => sum + Math.hypot(point.x - points[index].x, point.y - points[index].y), 0) * scale;
  return Number.isFinite(distance) && distance > 0 ? distance : null;
}
export function traceFromEdge(edge) {
  return edge ? Object.fromEntries(['reference_level_id', 'reference_floor_plan_revision', 'reference_calibration_revision', 'trace_points'].map(key => [key, edge[key]])) : null;
}
export function referenceChanged(trace, levelId, imageRevision) {
  return Boolean(trace && (trace.reference_level_id !== levelId || trace.reference_floor_plan_revision !== imageRevision));
}
