'use client';
import { useEffect, useRef, useState } from 'react';
import { floorPlanRequest } from './floor-plans-client.mjs';
import { imagePoint, panPosition, previewScale } from './calibration-utils.mjs';
import styles from './calibration.module.css';

export default function Calibration({ level, plan, disabled, refreshKey, onEditingChange }) {
  const [active, setActive] = useState(false);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(null);
  const [points, setPoints] = useState([]);
  const [metres, setMetres] = useState('');
  const [zoom, setZoom] = useState(1);
  const [tool, setTool] = useState('select');
  const [ready, setReady] = useState(false);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');
  const [conflict, setConflict] = useState(false);
  const viewport = useRef(null);
  const drawing = useRef(null);
  const gesture = useRef(null);
  const saveController = useRef(null);
  const path = `/levels/${level.id}/calibration`;
  useEffect(() => {
    onEditingChange?.(active);
    return () => onEditingChange?.(false);
  }, [active, onEditingChange]);
  useEffect(() => {
    const controller = new AbortController();
    floorPlanRequest(`${path}?floor_plan_revision=${plan.revision}`, { signal: controller.signal }).then(data => {
      if (!controller.signal.aborted) { setSaved(data.calibration); setLoading(false); }
    }).catch(failure => {
      if (!controller.signal.aborted) { setError(failure.message); setConflict(true); setLoading(false); }
    });
    return () => { controller.abort(); saveController.current?.abort(); };
  }, [path, plan.revision]);
  const busy = disabled || saving || loading;
  const preview = previewScale(points, metres);
  function begin() {
    setPoints(saved ? [{ x: saved.start_x, y: saved.start_y }, { x: saved.end_x, y: saved.end_y }] : []);
    setMetres(saved ? String(saved.known_distance_m) : '');
    setMessage(''); setActive(true); setTool('select');
  }
  function pointerDown(event) {
    if (!active || busy || !ready || event.button !== 0) return;
    gesture.current = { x: event.clientX, y: event.clientY, left: viewport.current.scrollLeft, top: viewport.current.scrollTop,
      scale: viewport.current.getBoundingClientRect().width / viewport.current.offsetWidth || 1, moved: false };
    event.currentTarget.setPointerCapture(event.pointerId);
  }
  function pointerMove(event) {
    const start = gesture.current;
    if (!start) return;
    const dx = event.clientX - start.x, dy = event.clientY - start.y;
    if (Math.hypot(dx, dy) > 4) start.moved = true;
    if (tool === 'pan') {
      const position = panPosition(start, event.clientX, event.clientY);
      viewport.current.scrollLeft = position.left;
      viewport.current.scrollTop = position.top;
    }
  }
  function pointerUp(event) {
    const start = gesture.current;
    gesture.current = null;
    if (!start || start.moved || tool !== 'select' || busy || !active || conflict) return;
    const point = imagePoint(event.clientX, event.clientY, drawing.current.getBoundingClientRect(), plan.width_px, plan.height_px);
    if (point) { setPoints(previous => previous.length < 2 ? [...previous, point] : previous); setMessage(''); }
  }
  async function save() {
    if (!preview || busy || conflict) return;
    setSaving(true); setError(''); setMessage('');
    const controller = new AbortController();
    saveController.current = controller;
    try {
      const result = await floorPlanRequest(path, {
        method: 'PUT', signal: controller.signal, headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ floor_plan_revision: plan.revision, expected_revision: saved?.revision ?? 0,
          start_x: points[0].x, start_y: points[0].y, end_x: points[1].x, end_y: points[1].y, known_distance_m: Number(metres) }),
      });
      if (!controller.signal.aborted) { setSaved(result.calibration); setMessage('Calibration Saved.'); setActive(false); }
    } catch (failure) {
      if (!controller.signal.aborted) {
        setError(failure.message);
        // A lost response may hide a committed save; refresh to reconcile first.
        setConflict(failure.status === 409 || !failure.status || failure.status >= 500);
      }
    } finally { if (!controller.signal.aborted) setSaving(false); }
  }
  const displayed = active ? points : saved ? [{ x: saved.start_x, y: saved.start_y }, { x: saved.end_x, y: saved.end_y }] : [];
  const mark = Math.max(plan.width_px, plan.height_px) / (100 * (active ? zoom : 1));
  return <section className={styles.section} aria-label="Floor Plan Calibration">
    <div className={styles.heading}><h2>Floor Plan Calibration</h2>
      {!active ? <button className={styles.button} disabled={busy || !ready || conflict} onClick={begin}>{saved ? 'Edit Calibration' : 'Calibrate Floor Plan'}</button> :
        <button className={styles.button} disabled={saving} onClick={() => { setActive(false); setMessage(''); }}>Cancel Calibration</button>}
    </div>
    {loading ? <p role="status">Loading Calibration…</p> : saved ?
      <dl className={styles.summary} aria-label="Saved Calibration">
        <div className={styles.summaryCard}><dt>Saved Scale</dt><dd>{saved.metres_per_pixel.toPrecision(6)} <span>m/px</span></dd></div>
        <div className={styles.summaryCard}><dt>Reference Distance</dt><dd>{saved.known_distance_m} <span>m</span></dd></div>
        <div className={styles.summaryCard}><dt>Revisions</dt><dd><span>Image</span> {saved.floor_plan_revision} <span>· Calibration</span> {saved.revision}</dd></div>
        <div className={styles.summaryCard}><dt>Reference Points (Pixels)</dt><dd>
          <div><span>A</span> ({saved.start_x.toFixed(2)}, {saved.start_y.toFixed(2)})</div>
          <div><span>B</span> ({saved.end_x.toFixed(2)}, {saved.end_y.toFixed(2)})</div>
        </dd></div>
      </dl> : <p className={styles.note}>This Image Revision Has Not Been Calibrated.</p>}
    {error && <p className={styles.error} role="alert">{error}{conflict ? ' Use Refresh at the top of the page to load the latest configuration.' : ''}</p>}
    {message && <p className={styles.success} role="status">{message}</p>}
    {active && <div className={styles.toolbar}>
      <button className={styles.button} aria-pressed={tool === 'select'} disabled={busy} onClick={() => setTool('select')}>Select Points</button>
      <button className={styles.button} aria-pressed={tool === 'pan'} disabled={busy} onClick={() => setTool('pan')}>Pan</button>
      <button className={styles.button} disabled={busy || zoom <= 1} onClick={() => setZoom(value => Math.max(1, value - .5))}>Zoom Out</button>
      <span>{Math.round(zoom * 100)}%</span>
      <button className={styles.button} disabled={busy || zoom >= 6} onClick={() => setZoom(value => Math.min(6, value + .5))}>Zoom In</button>
      <button className={styles.button} disabled={busy} onClick={() => { setZoom(1); viewport.current.scrollTo(0, 0); }}>Fit Image</button>
      <button className={styles.button} disabled={busy} onClick={() => { setPoints([]); setMessage(''); setTool('select'); }}>Reset Points</button>
    </div>}
    {active && <p className={styles.note} aria-live="polite">{tool === 'pan' ? 'Drag the image to pan, or use the scrollbars.' : points.length < 2 ? `Select Endpoint ${points.length + 1} on the image.` : 'Reference Line Selected. Enter The Known Distance Or Reset Points.'}</p>}
    <div ref={viewport} className={styles.viewport} tabIndex={0} aria-label="Scrollable Floor Plan">
      <svg ref={drawing} className={active ? tool === 'pan' ? styles.pan : styles.select : styles.image}
        style={{ width: `${active ? zoom * 100 : 100}%` }} viewBox={`0 0 ${plan.width_px} ${plan.height_px}`}
        onPointerDown={pointerDown} onPointerMove={pointerMove} onPointerUp={pointerUp} onPointerCancel={() => { gesture.current = null; }}
        role="img" aria-label={`Floor Plan For ${level.name}, With Calibration Reference Points`}>
        <image href={`/api/parking-structure/levels/${level.id}/image?revision=${plan.revision}&refresh=${refreshKey}`}
          width={plan.width_px} height={plan.height_px} onLoad={() => setReady(true)}
          onError={() => { setReady(false); setConflict(true); setError('Image Could Not Be Loaded. Refresh Before Calibrating.'); }} />
        {displayed.length === 2 && <g>
          <line x1={displayed[0].x} y1={displayed[0].y} x2={displayed[1].x} y2={displayed[1].y} stroke="white" strokeWidth={6} vectorEffect="non-scaling-stroke" />
          <line x1={displayed[0].x} y1={displayed[0].y} x2={displayed[1].x} y2={displayed[1].y} stroke="var(--primary)" strokeWidth={3} vectorEffect="non-scaling-stroke" />
        </g>}
        {displayed.map((point, index) => <g key={index}>
          <circle cx={point.x} cy={point.y} r={mark} fill="var(--primary)" stroke="white" strokeWidth={2} vectorEffect="non-scaling-stroke" />
          <text x={point.x} y={point.y} dy=".35em" textAnchor="middle" fill="white" fontSize={mark * 1.2} fontWeight="bold">{index === 0 ? 'A' : 'B'}</text>
        </g>)}
      </svg>
    </div>
    {active && <div className={styles.measurement}>
      <label>Known Distance (Metres)<input type="number" step="any" min="0" value={metres} disabled={busy || conflict} onChange={event => setMetres(event.target.value)} /></label>
      <p aria-live="polite">{preview ? `Reference: ${preview.pixels.toFixed(2)} px · Preview Scale: ${preview.scale.toPrecision(6)} m/px` : 'Choose Two Distinct Points And Enter A Positive Distance.'}</p>
      <button className={`${styles.button} ${styles.primary}`} disabled={busy || !preview || conflict || !ready} onClick={save}>{saving ? 'Saving…' : 'Save Calibration'}</button>
    </div>}
  </section>;
}
