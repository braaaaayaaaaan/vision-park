// The SVG rect already includes responsive sizing, zoom and viewport scrolling.
export function imagePoint(clientX, clientY, rect, width, height) {
  if (!(rect.width > 0 && rect.height > 0)) return null;
  const x = (clientX - rect.left) * width / rect.width;
  const y = (clientY - rect.top) * height / rect.height;
  return [x, y].every(Number.isFinite) && x >= 0 && y >= 0 && x <= width && y <= height ? { x, y } : null;
}
// Pointer deltas use rendered pixels; scroll offsets use unscaled layout pixels.
export function panPosition(start, clientX, clientY) {
  return { left: start.left - (clientX - start.x) / start.scale,
    top: start.top - (clientY - start.y) / start.scale };
}
export function previewScale(points, metres) {
  if (points.length !== 2 || !points.every(point => Number.isFinite(point.x) && Number.isFinite(point.y))) return null;
  const distance = Number(metres);
  const pixels = Math.hypot(points[1].x - points[0].x, points[1].y - points[0].y);
  const scale = distance / pixels;
  return distance > 0 && pixels > 0 && Number.isFinite(scale) && scale > 0 ? { pixels, scale } : null;
}
