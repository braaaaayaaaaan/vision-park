'use client';
import { useEffect, useId, useRef, useState } from 'react';
import { floorPlanRequest } from './floor-plans-client.mjs';
import { panPosition } from './calibration-utils.mjs';
import { draftError } from './node-draft-utils.mjs';
import { connectionEdges, edgeGeometry, edgeInputs, previewDistance } from './edge-draft-utils.mjs';
import EdgeArrow from './edge-arrow.mjs';
import map from './calibration.module.css';
import styles from './node-editor.module.css';
import local from './edge-editor.module.css';

const metres = value => value === null ? 'Unavailable' : `${value >= .01 ? value.toFixed(2) : value.toPrecision(3)} m`;
export default function EdgeEditor({ level, plan, disabled, refreshKey, onDirtyChange, onSavingChange }) {
  const [data, setData] = useState(null), [edges, setEdges] = useState([]), [snapshot, setSnapshot] = useState([]);
  const [loading, setLoading] = useState(true), [saving, setSaving] = useState(false), [locked, setLocked] = useState(false), [ready, setReady] = useState(false);
  const [error, setError] = useState(''), [message, setMessage] = useState(''), [reloadKey, setReloadKey] = useState(0);
  const [mode, setMode] = useState('select'), [source, setSource] = useState(''), [destination, setDestination] = useState('');
  const [twoWay, setTwoWay] = useState(false), [selected, setSelected] = useState(''), [zoom, setZoom] = useState(1);
  const viewport = useRef(null), gesture = useRef(null), saveController = useRef(null);
  const markerId = useId().replaceAll(':', '');
  const path = `/levels/${level.id}/graph-draft`;
  const nodes = data?.draft?.nodes ?? [];
  const nodeMap = new Map(nodes.map(node => [node.id, node]));
  const scale = data?.calibration?.metres_per_pixel;
  const dirty = JSON.stringify(edges) !== JSON.stringify(snapshot);
  const busy = disabled || loading || saving;
  const editable = !busy && !locked && ready && Boolean(data?.draft && data?.calibration);
  const preview = previewDistance(nodeMap.get(source), nodeMap.get(destination), scale);
  const edge = edges.find(item => item.id === selected);
  const storedEdge = data?.draft?.edges.find(item => item.id === selected);
  const radius = Math.max(plan.width_px, plan.height_px) / (90 * zoom);
  useEffect(() => { onDirtyChange(dirty); }, [dirty, onDirtyChange]);
  useEffect(() => { onSavingChange(saving); }, [saving, onSavingChange]);
  useEffect(() => () => { onDirtyChange(false); onSavingChange(false); }, [onDirtyChange, onSavingChange]);
  useEffect(() => {
    const controller = new AbortController();
    floorPlanRequest(`${path}?floor_plan_revision=${plan.revision}`, { signal: controller.signal }).then(result => {
      if (controller.signal.aborted) return;
      const invalid = draftError(result.draft?.nodes ?? [], plan.width_px, plan.height_px);
      if (invalid) throw new Error(invalid);
      const loaded = edgeInputs(result.draft?.edges ?? []);
      setData(result); setEdges(loaded); setSnapshot(loaded); setSelected(''); setSource(''); setDestination('');
      setLoading(false); setLocked(false); setError('');
    }).catch(failure => {
      if (!controller.signal.aborted) { setError(failure.message); setLoading(false); setLocked(true); }
    });
    return () => { controller.abort(); saveController.current?.abort(); };
  }, [path, plan.revision, plan.width_px, plan.height_px, reloadKey]);
  function reload() {
    if (dirty && !window.confirm('Discard Unsaved Connection Changes And Reload?')) return;
    setLoading(true); setMessage(''); setReloadKey(value => value + 1);
  }
  function add() {
    if (!editable || preview === null) return;
    try {
      const updated = connectionEdges(edges, source, destination, twoWay, () => crypto.randomUUID());
      setEdges(updated); setSelected(updated[edges.length].id); setDestination(''); setSource(''); setError(''); setMessage('Connection Added. Save Draft To Persist It.');
    } catch (failure) { setError(failure.message); }
  }
  function remove() {
    if (!editable || !edge || !window.confirm('Delete This Directed Edge? Its Reverse Direction, If Present, Is Kept. Save Draft To Confirm.')) return;
    setEdges(previous => previous.filter(item => item.id !== selected)); setSelected(''); setMessage('');
  }
  function down(event) {
    if (!editable || event.button !== 0 || !event.isPrimary) return;
    gesture.current = { x: event.clientX, y: event.clientY, left: viewport.current.scrollLeft, top: viewport.current.scrollTop,
      scale: viewport.current.getBoundingClientRect().width / viewport.current.offsetWidth || 1, moved: false,
      node: event.target.closest('[data-node-id]')?.getAttribute('data-node-id'),
      edge: event.target.closest('[data-edge-id]')?.getAttribute('data-edge-id') };
    event.currentTarget.setPointerCapture(event.pointerId);
  }
  function move(event) {
    const start = gesture.current;
    if (!start || !editable) return;
    if (Math.hypot(event.clientX - start.x, event.clientY - start.y) > 4) start.moved = true;
    if (mode === 'pan') {
      const position = panPosition(start, event.clientX, event.clientY);
      viewport.current.scrollLeft = position.left; viewport.current.scrollTop = position.top;
    }
  }
  function up() {
    const start = gesture.current; gesture.current = null;
    if (!editable || !start || start.moved) return;
    if (mode === 'select') { setSelected(start.edge ?? ''); return; }
    if (mode === 'connect' && start.node) {
      if (!source || destination) { setSource(start.node); setDestination(''); }
      else if (source === start.node) setError('Choose Two Different Nodes.');
      else { setDestination(start.node); setError(''); }
    }
  }
  async function save() {
    if (!editable || (!dirty && !data.needs_distance_revalidation)) return;
    setSaving(true); setError(''); setMessage('');
    const controller = new AbortController(); saveController.current = controller;
    try {
      const result = await floorPlanRequest(path, { method: 'PUT', signal: controller.signal, headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ floor_plan_revision: plan.revision, expected_revision: data.draft.revision,
          expected_calibration_revision: data.current_calibration_revision, edges: edgeInputs(edges) }) });
      if (controller.signal.aborted) return;
      const loaded = edgeInputs(result.draft.edges);
      setData(result); setEdges(loaded); setSnapshot(loaded); setMessage('Connections Saved And All Distances Recalculated.');
    } catch (failure) {
      if (!controller.signal.aborted) { setError(failure.message); setLocked(failure.status === 409 || !failure.status || failure.status >= 500); }
    } finally { if (!controller.signal.aborted) setSaving(false); }
  }
  const previewEdges = source && destination && preview !== null ? [
    { id: 'preview-forward', from_node_id: source, to_node_id: destination },
    ...(twoWay ? [{ id: 'preview-reverse', from_node_id: destination, to_node_id: source }] : []),
  ] : [];
  function drawEdge(item, previewOnly = false) {
    const from = nodeMap.get(item.from_node_id), to = nodeMap.get(item.to_node_id);
    if (!from || !to) return null;
    const parallel = (previewOnly ? previewEdges : edges).some(other => other.from_node_id === item.to_node_id && other.to_node_id === item.from_node_id);
    const geometry = edgeGeometry(from, to, radius, parallel);
    if (!geometry) return null;
    const colour = previewOnly ? 'var(--chart-supporting)' : item.id === selected ? 'var(--chart-comparative)' : 'var(--chart-primary)';
    const distance = previewDistance(from, to, scale);
    return <EdgeArrow key={item.id} geometry={geometry} colour={colour} markerId={`${markerId}-${previewOnly ? 'preview' : item.id === selected ? 'selected' : 'edge'}`}
      dashed={previewOnly || data?.needs_distance_revalidation} label={`${from.code} → ${to.code} · ${metres(distance)} Preview`} interactive={!previewOnly}
      data-edge-id={previewOnly ? undefined : item.id} className={local.edge} role={previewOnly ? undefined : 'button'}
      tabIndex={!previewOnly && editable && mode === 'select' ? 0 : undefined} aria-label={previewOnly ? undefined : `${from.code} To ${to.code}: ${metres(distance)} Preview`}
      onKeyDown={event => { if (!previewOnly && editable && mode === 'select' && ['Enter', ' '].includes(event.key)) { event.preventDefault(); setSelected(item.id); } }} />;
  }
  return <section className={map.section} aria-label="Add Edges" aria-busy={busy}>
    <div className={map.heading}><h2>Add Edges</h2><div className={map.toolbar}>
      <button className={map.button} disabled={busy} onClick={reload}>Reload Draft</button>
      <button className={`${map.button} ${map.primary}`} disabled={!editable || (!dirty && !data?.needs_distance_revalidation)} onClick={save}>{saving ? 'Saving…' : data?.needs_distance_revalidation ? 'Recalculate And Save' : 'Save Draft'}</button>
    </div></div>
    <dl className={map.summary} aria-label="Edge Draft Summary">
      <div className={map.summaryCard}><dt>Directed Edges</dt><dd>{loading || !data ? '—' : edges.length}</dd></div>
      <div className={map.summaryCard}><dt>Save Status</dt><dd role="status">{loading ? 'Loading…' : saving ? 'Saving…' : dirty ? 'Unsaved Changes' : !data ? 'Not Loaded' : 'All Changes Saved'}</dd></div>
      <div className={map.summaryCard}><dt>Revisions</dt><dd><span>Draft</span> {data?.draft?.revision ?? '—'} <span>· Calibration</span> {data?.current_calibration_revision ?? '—'}</dd></div>
    </dl>
    {!loading && data && (!data.draft ? <p className={styles.warning}>Add And Save Nodes Before Connecting Them.</p> : !data.calibration ? <p className={styles.warning}>Calibrate This Image Before Connecting Nodes.</p> : data.needs_distance_revalidation && <p className={styles.warning}>Node positions or calibration require revalidating the distance. Dashed edges show the current previews</p>)}
    {error && <p className={map.error} role="alert">{error}{locked ? ' Reload Draft, Or Refresh The Page If The Image Changed. Local Edits Are Retained Until You Confirm Discarding Them.' : ''}</p>}
    {message && <p className={map.success} role="status">{message}</p>}
    <div className={map.toolbar}>
      {[['select', 'Select Edge'], ['connect', 'Connect Nodes'], ['pan', 'Pan']].map(([value, label]) => <button key={value} className={map.button} aria-pressed={mode === value} disabled={!editable} onClick={() => { gesture.current = null; setMode(value); }}>{label}</button>)}
      <div className={styles.zoomControls} role="group" aria-label="Map Zoom">
        <button className={map.button} aria-label="Zoom Out" disabled={busy || zoom <= 1} onClick={() => setZoom(value => Math.max(1, value - .5))}>−</button>
        <span className={styles.zoomValue} aria-live="polite">Zoom {Math.round(zoom * 100)}%</span>
        <button className={map.button} aria-label="Zoom In" disabled={busy || zoom >= 6} onClick={() => setZoom(value => Math.min(6, value + .5))}>+</button>
      </div>
      <button className={map.button} disabled={busy} onClick={() => { setZoom(1); viewport.current.scrollTo(0, 0); }}>Fit Image</button>
    </div>
    <p className={map.note}>{mode === 'pan' ? 'Drag the image to pan, but nodes are not movable in this editor.' : mode === 'connect' ? 'Select a source node, then only the destination node. Choose travel direction and add the connection' : 'Select an arrow or use the edge list to inspect a directed connection.'}</p>
    <div ref={viewport} className={map.viewport} tabIndex={0} aria-label="Scrollable Driving Edge Map">
      <svg viewBox={`0 0 ${plan.width_px} ${plan.height_px}`} style={{ width: `${zoom * 100}%` }} className={mode === 'pan' ? map.pan : map.select}
        aria-label={`Draft Driving Connections On ${level.name}`} onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={() => { gesture.current = null; }}>
        <defs>{[['edge', 'var(--chart-primary)'], ['selected', 'var(--chart-comparative)'], ['preview', 'var(--chart-supporting)']].map(([id, colour]) =>
          <marker key={id} id={`${markerId}-${id}`} markerUnits="userSpaceOnUse" markerWidth={radius} markerHeight={radius} refX="10" refY="5" viewBox="0 0 10 10" orient="auto"><path d="M0 0 L10 5 L0 10 Z" fill={colour} stroke="white" strokeWidth=".5" /></marker>)}</defs>
        <image href={`/api/parking-structure/levels/${level.id}/image?revision=${plan.revision}&refresh=${refreshKey}`} width={plan.width_px} height={plan.height_px}
          onLoad={() => setReady(true)} onError={() => { setReady(false); setLocked(true); setError('Image Could Not Be Loaded. Refresh The Page.'); }} />
        {edges.map(item => drawEdge(item))}{previewEdges.map(item => drawEdge(item, true))}
        {nodes.map(node => <g key={node.id} data-node-id={node.id}>
          <title>{node.code}</title><circle cx={node.x} cy={node.y} r={radius} fill={node.id === source ? 'var(--chart-primary)' : node.id === destination ? 'var(--chart-supporting)' : 'var(--primary)'} stroke="white" strokeWidth={2} vectorEffect="non-scaling-stroke" />
          <text x={node.x + radius * 1.4} y={node.y} fontSize={radius * 1.1} fill="var(--text)" stroke="white" strokeWidth={3} paintOrder="stroke" vectorEffect="non-scaling-stroke">{node.code}</text>
        </g>)}
      </svg>
    </div>
    {mode === 'connect' && <div className={styles.details}>
      <label className={styles.field}>Source Node<select disabled={!editable} value={source} onChange={event => { setSource(event.target.value); setDestination(''); }}><option value="">Select Source</option>{nodes.map(node => <option key={node.id} value={node.id}>{node.code}</option>)}</select></label>
      <label className={styles.field}>Destination Node<select disabled={!editable} value={destination} onChange={event => setDestination(event.target.value)}><option value="">Select Destination</option>{nodes.filter(node => node.id !== source).map(node => <option key={node.id} value={node.id}>{node.code}</option>)}</select></label>
      <label className={styles.field}>Travel Direction<select disabled={!editable} value={twoWay ? 'two' : 'one'} onChange={event => setTwoWay(event.target.value === 'two')}><option value="one">One-Way</option><option value="two">Two-Way</option></select></label>
      <dl className={local.distanceCard}><dt>Distance Preview</dt><dd>{metres(preview)}{twoWay && preview !== null ? ' Each Direction' : ''}</dd></dl>
      <button className={map.button} disabled={!editable || preview === null} onClick={add}>Add Connection</button>
      <button className={map.button} disabled={!editable || (!source && !destination)} onClick={() => { setSource(''); setDestination(''); }}>Reset Selection</button>
    </div>}
    <div className={styles.details}>
      <label className={styles.field}>Select Directed Edge<select value={selected} disabled={!editable} onChange={event => { setSelected(event.target.value); setMode('select'); }}><option value="">Select An Edge</option>{edges.map(item => <option key={item.id} value={item.id}>{nodeMap.get(item.from_node_id)?.code} → {nodeMap.get(item.to_node_id)?.code}</option>)}</select></label>
      {edge && <><dl className={local.distanceCard}><dt>Distance Preview</dt><dd>{metres(previewDistance(nodeMap.get(edge.from_node_id), nodeMap.get(edge.to_node_id), scale))}</dd></dl>
        <dl className={local.distanceCard}><dt>Saved Distance{data.needs_distance_revalidation ? ' (Stale)' : ''}</dt><dd>{storedEdge ? metres(storedEdge.distance_meters) : 'Not Saved'}</dd></dl>
        <button className={local.deleteAction} disabled={!editable} onClick={remove}>Delete Directed Edge</button></>}
    </div>
  </section>;
}
