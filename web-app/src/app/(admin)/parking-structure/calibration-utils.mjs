// Fit both dimensions at 100%; zoom enlarges that fitted image, not just its width.
export function floorPlanWidth(width, height, zoom = 1) {
  return `min(${zoom * 100}%, calc((var(--floor-plan-height) - 2px) * ${width / height * zoom}))`;
}

// The element's bounding box can include letterboxing. Invert the actual SVG
// transform so fitted images, CSS zoom, scrolling and fullscreen share one space.
export function imagePoint(clientX, clientY, drawing, width, height) {
  if (![clientX, clientY, width, height].every(Number.isFinite) || width <= 0 || height <= 0) return null;
  try {
    const matrix = drawing?.getScreenCTM();
    if (!matrix) return null;
    const cursor = drawing.createSVGPoint();
    cursor.x = clientX; cursor.y = clientY;
    const { x, y } = cursor.matrixTransform(matrix.inverse());
    // Allow only floating-point noise at the image boundary, not letterbox clicks.
    const epsilon = 1e-6;
    if (![x, y].every(Number.isFinite) || x < -epsilon || y < -epsilon || x > width + epsilon || y > height + epsilon) return null;
    return { x: Math.max(0, Math.min(width, x)), y: Math.max(0, Math.min(height, y)) };
  } catch {
    // Detached or temporarily non-invertible SVGs cannot supply image coordinates.
    return null;
  }
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
