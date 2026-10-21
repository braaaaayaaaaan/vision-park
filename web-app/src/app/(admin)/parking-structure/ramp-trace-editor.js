'use client';
import { useEffect, useRef, useState } from 'react';
import { floorPlanRequest } from './floor-plans-client.mjs';
import { imagePoint, panPosition } from './calibration-utils.mjs';
import { MAX_TRACE_POINTS, referenceChanged, traceDistance, traceError } from './ramp-trace-utils.mjs';
import map from './calibration.module.css';
import fields from './node-editor.module.css';
import styles from './cross-level-ramps.module.css';

function TraceCanvas({ level, trace, onChange, disabled }) {
  const plan = level.floor_plan;
  const [calibration, setCalibration] = useState(null), [loading, setLoading] = useState(true), [error, setError] = useState('');
  const [zoom, setZoom] = useState(1), [tool, setTool] = useState('add'), [selected, setSelected] = useState(null), [ready, setReady] = useState(false);
  const viewport = useRef(null), drawing = useRef(null), gesture = useRef(null);
  const replaced = referenceChanged(trace, level.id, plan.revision);
  const points = replaced ? [] : trace.trace_points;
  // React Compiler reads callback dependencies during render, including while
  // calibration is loading or the API legitimately returns calibration: null.
  const calibrationRevision = calibration?.revision ?? null;
  const busy = disabled || loading || !calibration || !ready || Boolean(error);
  const preview = calibration && traceDistance(points, calibration.metres_per_pixel, plan.width_px, plan.height_px);
  const recalculation = calibrationRevision !== null && trace.reference_calibration_revision !== calibrationRevision;
  useEffect(() => {
    const controller = new AbortController();
    floorPlanRequest(`/levels/${level.id}/calibration?floor_plan_revision=${plan.revision}`, { signal: controller.signal }).then(data => {
      if (!controller.signal.aborted) { setCalibration(data.calibration); setLoading(false); }
    }).catch(failure => { if (!controller.signal.aborted) { setError(failure.message); setLoading(false); } });
    return () => controller.abort();
  }, [level.id, plan.revision]);
  function update(next) {
    if (busy || calibrationRevision === null) return;
    onChange({ reference_level_id: level.id, reference_floor_plan_revision: plan.revision,
      reference_calibration_revision: calibrationRevision, trace_points: next });
  }
  function point(event) { return imagePoint(event.clientX, event.clientY, drawing.current.getBoundingClientRect(), plan.width_px, plan.height_px); }
  function pointerDown(event) {
    if (busy || replaced || event.button !== 0) return;
    const index = event.target.dataset.point, position = point(event);
    const moving = tool === 'move' && index !== undefined && position;
    gesture.current = { x: event.clientX, y: event.clientY, left: viewport.current.scrollLeft, top: viewport.current.scrollTop,
      scale: viewport.current.getBoundingClientRect().width / viewport.current.offsetWidth || 1, moved: false,
      hit: index !== undefined, index: moving ? Number(index) : null,
      dx: moving ? points[index].x - position.x : 0, dy: moving ? points[index].y - position.y : 0 };
    if (index !== undefined) setSelected(Number(index));
    event.currentTarget.setPointerCapture(event.pointerId);
  }
  function pointerMove(event) {
    const start = gesture.current;
    if (!start) return;
    if (Math.hypot(event.clientX - start.x, event.clientY - start.y) > 4) start.moved = true;
    if (tool === 'pan') {
      const position = panPosition(start, event.clientX, event.clientY);
      viewport.current.scrollLeft = position.left; viewport.current.scrollTop = position.top;
    } else if (start.index !== null && start.moved) {
      const position = point(event);
      if (!position) return;
      const next = points.map((value, index) => index === start.index ? {
        x: Math.max(0, Math.min(plan.width_px, position.x + start.dx)), y: Math.max(0, Math.min(plan.height_px, position.y + start.dy)),
      } : value);
      if (next.length === 1 || !traceError(next, plan.width_px, plan.height_px)) update(next);
    }
  }
  function pointerUp(event) {
    const start = gesture.current; gesture.current = null;
    if (!start || busy || replaced) return;
    if (tool === 'add' && !start.moved && !start.hit && points.length < MAX_TRACE_POINTS) {
      const position = point(event);
      if (position && !points.some(value => value.x === position.x && value.y === position.y)) { update([...points, position]); setSelected(points.length); }
    }
  }
  const radius = Math.max(plan.width_px, plan.height_px) / (80 * zoom);
  return <>
    {loading && <p className={map.note} role="status">Loading Reference Calibration…</p>}
    {error && <p className={map.error} role="alert">{error} Refresh Ramps To Retry.</p>}
    {!loading && !calibration && !error && <p className={fields.warning}>Calibrate This Floor Plan Before Tracing.</p>}
    {replaced && <p className={fields.warning}>This Trace Belongs To An Earlier Image. Reset And Retrace On The Current Reference Image.</p>}
    {!replaced && recalculation && points.length > 1 && <p className={fields.warning}>Review The Path, Then Recalculate Using The Current Calibration Before Confirming.</p>}
    <div className={map.toolbar}>
      {['add', 'move', 'pan'].map(mode => <button type="button" key={mode} className={map.button} aria-pressed={tool === mode} disabled={busy || replaced} onClick={() => setTool(mode)}>{ { add: 'Add Points', move: 'Move Points', pan: 'Pan' }[mode]}</button>)}
      <div className={styles.zoom} role="group" aria-label="Trace Zoom">
        <button type="button" className={map.button} aria-label="Zoom Out" disabled={disabled || zoom <= 1} onClick={() => setZoom(value => Math.max(1, value / 1.5))}>−</button>
        <output>{Math.round(zoom * 100)}%</output>
        <button type="button" className={map.button} aria-label="Zoom In" disabled={disabled || zoom >= 8} onClick={() => setZoom(value => Math.min(8, value * 1.5))}>+</button>
        <button type="button" className={map.button} disabled={disabled} onClick={() => { setZoom(1); viewport.current.scrollTo(0, 0); }}>Fit</button>
      </div>
    </div>
    <div className={`${map.viewport} ${tool === 'pan' ? map.pan : map.select}`} ref={viewport}>
      <svg ref={drawing} viewBox={`0 0 ${plan.width_px} ${plan.height_px}`} style={{ width: `${zoom * 100}%` }} role="img" aria-label="Ordered Ramp Centreline Trace"
        onPointerDown={pointerDown} onPointerMove={pointerMove} onPointerUp={pointerUp} onPointerCancel={() => { gesture.current = null; }} onLostPointerCapture={() => { gesture.current = null; }}>
        <image href={`/api/parking-structure/levels/${level.id}/image?revision=${plan.revision}`} width={plan.width_px} height={plan.height_px}
          onLoad={() => setReady(true)} onError={() => { setReady(false); setError('Reference Image Changed Or Could Not Be Loaded.'); }} />
        <polyline points={points.map(value => `${value.x},${value.y}`).join(' ')} fill="none" stroke="white" strokeWidth={7} vectorEffect="non-scaling-stroke" pointerEvents="none" />
        <polyline points={points.map(value => `${value.x},${value.y}`).join(' ')} fill="none" stroke="#14B8A6" strokeWidth={3} strokeDasharray="10 4" vectorEffect="non-scaling-stroke" pointerEvents="none" />
        {points.map((value, index) => <g key={index}>
          <circle data-point={index} cx={value.x} cy={value.y} r={radius} fill={selected === index ? 'var(--primary)' : '#0f766e'} stroke="white" strokeWidth={2} vectorEffect="non-scaling-stroke" />
          <text x={value.x} y={value.y} dy=".35em" fontSize={radius * 1.15} textAnchor="middle" fill="white" pointerEvents="none">{index + 1}</text>
        </g>)}
      </svg>
    </div>
    <div className={map.toolbar}>
      <button type="button" className={map.button} disabled={busy || replaced || !points.length} onClick={() => { update(points.slice(0, -1)); setSelected(null); }}>Undo Last Point</button>
      <button type="button" className={map.button} disabled={busy || replaced || selected === null || selected >= points.length} onClick={() => { update(points.filter((_, index) => index !== selected)); setSelected(null); }}>Remove Selected Point</button>
      <button type="button" className={map.button} disabled={busy} onClick={() => { if (!trace.trace_points.length || window.confirm('Reset This Direction’s Trace?')) { update([]); setSelected(null); } }}>Reset Trace</button>
      {!replaced && recalculation && <button type="button" className={map.button} disabled={busy || preview === null} onClick={() => update(points)}>Recalculate And Review Path</button>}
    </div>
    <dl className={map.summary}>
      <div className={map.summaryCard}><dt>Estimated Horizontal Projected Driving Distance</dt><dd>{preview ? `${preview.toLocaleString('en-MY', { maximumFractionDigits: 3 })} m` : 'Trace At Least Two Points'}</dd></div>
      <div className={map.summaryCard}><dt>Reference Measurement</dt><dd>{points.length} Points <span>· Image {plan.revision} · Calibration {calibration?.revision ?? 'Required'}</span></dd></div>
    </dl>
    {points.length > 1 && traceError(points, plan.width_px, plan.height_px) && <p className={map.error}>{traceError(points, plan.width_px, plan.height_px)}</p>}
    <p className={map.note}>Add Points In Travel Order Along The Complete Ramp Centreline. Use Move Points To Drag A Marker, Or Pan To Move The Image. Maximum 200 Points.</p>
  </>;
}

export default function RampTraceEditor({ label, levels, trace, onChange, disabled, refreshKey }) {
  const level = levels.find(item => item.id === trace?.reference_level_id);
  return <section className={styles.trace} aria-label={`${label} Ramp Trace`}>
    <h4>{label}</h4>
    <label className={fields.field}>Calibrated Reference Floor Plan<select value={trace?.reference_level_id ?? ''} disabled={disabled} onChange={event => {
      if (trace?.trace_points.length && !window.confirm('Discard This Trace And Choose Another Reference Image?')) return;
      const selected = levels.find(item => item.id === event.target.value);
      onChange(selected ? { reference_level_id: selected.id, reference_floor_plan_revision: selected.floor_plan.revision, reference_calibration_revision: 0, trace_points: [] } : null);
    }}><option value="">Select an Image Showing the Completed Ramp</option>{levels.filter(item => item.floor_plan).map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
    {level?.floor_plan && <TraceCanvas key={`${level.id}-${level.floor_plan.revision}-${refreshKey}`} level={level} trace={trace} onChange={onChange} disabled={disabled} />}
    {trace && !level?.floor_plan && <p className={fields.warning}>Reference Image Unavailable. Select A Current Calibrated Floor Plan.</p>}
  </section>;
}
