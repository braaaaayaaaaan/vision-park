"use client";
import { useEffect, useRef, useState } from 'react';

export const sidebarSize = { default: 288, min: 260, max: 360 };
const preferenceKey = 'vp-sidebar-width';
export function boundedSidebarWidth(value) {
  const number = value === null || value === '' ? NaN : Number(value);
  return Number.isFinite(number) ? Math.min(sidebarSize.max, Math.max(sidebarSize.min, Math.round(number))) : sidebarSize.default;
}
function saveWidth(width) {
  try { window.localStorage.setItem(preferenceKey, String(width)); } catch { /* Resizing remains available when storage is disabled. */ }
}

export default function useSidebarWidth() {
  const [width, setWidth] = useState(sidebarSize.default);
  const [dragging, setDragging] = useState(false);
  const drag = useRef(null);
  useEffect(() => {
    const timer = setTimeout(() => {
      try { setWidth(boundedSidebarWidth(window.localStorage.getItem(preferenceKey))); } catch { /* Keep the default width. */ }
    }, 0);
    return () => clearTimeout(timer);
  }, []);
  function commit(value) {
    const next = boundedSidebarWidth(value);
    setWidth(next);
    saveWidth(next);
  }
  function finish() {
    if (!drag.current) return;
    saveWidth(drag.current.width);
    drag.current = null;
    setDragging(false);
  }
  return {
    width, dragging,
    separator: {
      role: 'separator', tabIndex: 0, 'aria-orientation': 'vertical',
      'aria-label': 'Sidebar width', 'aria-valuemin': sidebarSize.min,
      'aria-valuemax': sidebarSize.max, 'aria-valuenow': width,
      'aria-valuetext': `${width} pixels`,
      title: 'Drag to resize. Use the arrow keys to adjust, or double-click to reset.',
      onPointerDown(event) {
        if (event.button !== 0 || event.isPrimary === false) return;
        event.preventDefault();
        const shell = event.currentTarget.closest('[data-admin-shell]');
        const scale = shell?.offsetWidth ? shell.getBoundingClientRect().width / shell.offsetWidth : 1;
        drag.current = { x: event.clientX, start: width, width, scale: scale || 1 };
        event.currentTarget.setPointerCapture(event.pointerId);
        setDragging(true);
      },
      onPointerMove(event) {
        if (!drag.current) return;
        const next = boundedSidebarWidth(drag.current.start + (event.clientX - drag.current.x) / drag.current.scale);
        drag.current.width = next;
        setWidth(next);
      },
      onPointerUp: finish, onPointerCancel: finish, onLostPointerCapture: finish,
      onDoubleClick: () => commit(sidebarSize.default),
      onKeyDown(event) {
        const next = { ArrowLeft: width - 8, ArrowRight: width + 8, Home: sidebarSize.min, End: sidebarSize.max }[event.key];
        if (next === undefined) return;
        event.preventDefault();
        commit(next);
      },
    },
  };
}
