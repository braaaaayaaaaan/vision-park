'use client';
import { useEffect, useRef, useState } from 'react';
import shared from './parking-structure.module.css';
import styles from './floor-plan-workspace.module.css';

export default function FloorPlanWorkspace({ children, busy = false }) {
  const panel = useRef(null), toggle = useRef(null);
  const [fullscreen, setFullscreen] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    const element = panel.current;
    let wasFullscreen = false;
    function changed() {
      const active = document.fullscreenElement === element;
      setFullscreen(active);
      if (wasFullscreen && !active) toggle.current?.focus({ preventScroll: true });
      wasFullscreen = active;
    }
    document.addEventListener('fullscreenchange', changed);
    return () => document.removeEventListener('fullscreenchange', changed);
  }, []);

  async function toggleFullscreen() {
    if (pending) return;
    setError('');
    const element = panel.current;
    if (!element?.requestFullscreen || !document.exitFullscreen) {
      setError('Full screen is unavailable in this browser. You can continue editing here.');
      return;
    }
    setPending(true);
    try {
      if (document.fullscreenElement === element) await document.exitFullscreen();
      else await element.requestFullscreen();
    } catch {
      setError('Unable to change full-screen mode. Please try again. Your edits are retained.');
    } finally {
      setPending(false);
    }
  }

  return <section ref={panel} data-floor-plan-workspace className={`${shared.panel} ${styles.workspace}`} aria-label="Floor Plan Workspace" aria-busy={busy}>
    <div className={styles.header}>
      <div><h2>Floor Plan Workspace</h2>{fullscreen && <p>Press Esc or use Exit Full Screen to return.</p>}</div>
      <button ref={toggle} type="button" className={shared.button} aria-pressed={fullscreen} disabled={pending} onClick={toggleFullscreen}>
        {fullscreen ? 'Exit Full Screen' : 'Enter Full Screen'}
      </button>
    </div>
    {error && <p className={shared.error} role="alert">{error}</p>}
    {children}
  </section>;
}
