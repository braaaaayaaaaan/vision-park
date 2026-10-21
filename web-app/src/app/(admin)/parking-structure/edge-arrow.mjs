import { createElement } from 'react';

// Small native SVG renderer shared by saved and preview connections.
export default function EdgeArrow({ geometry, colour, markerId, dashed, label, interactive, ...props }) {
  const { x1, y1, x2, y2 } = geometry;
  const line = { x1, y1, x2, y2, vectorEffect: 'non-scaling-stroke' };
  return createElement('g', props,
    createElement('title', null, label),
    interactive && createElement('line', { ...line, stroke: 'transparent', strokeWidth: 16 }),
    createElement('line', { ...line, stroke: 'white', strokeWidth: 6 }),
    createElement('line', { ...line, stroke: colour, strokeWidth: 3,
      strokeDasharray: dashed ? '7 4' : undefined, markerEnd: `url(#${markerId})` }));
}
