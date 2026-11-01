'use client';
import { createElement } from 'react';

// SVG image load/error events do not propagate to React's delegated handlers.
// Attach native listeners before setting href, including for cached images.
export default function FloorPlanImage({ href, onLoad, onError, ...props }) {
  function attach(image) {
    if (!image) return;
    const loaded = event => onLoad?.(event);
    const failed = event => onError?.(event);
    image.addEventListener('load', loaded);
    image.addEventListener('error', failed);
    if (image.getAttribute('href') !== href) image.setAttribute('href', href);
    return () => {
      image.removeEventListener('load', loaded);
      image.removeEventListener('error', failed);
    };
  }
  return createElement('image', { ...props, ref: attach });
}
