'use client';
import RefreshButton from '../../../components/refresh-button';
import { useEffect, useId, useRef, useState } from 'react';
import useConfirmation from '../../../components/use-confirmation';
import { floorPlanRequest } from './floor-plans-client.mjs';
import { floorPlanWidth, panPosition } from './calibration-utils.mjs';
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
  const { requestConfirmation, confirmationDialog } = useConfirmation({ disabled: busy });
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
  function reload(confirmed = false) {
    if (dirty && confirmed !== true) return requestConfirmation({ title: 'Discard Connection Changes?', description: 'Unsaved driving connections will be discarded when you reload.', variant: 'warning', confirmLabel: 'Discard and Reload' }, () => reload(true));
    setLoading(true); setMessage(''); setReloadKey(value => value + 1);
  }
  function add() {
    if (!editable || preview === null) return;
    try {
      const updated = connectionEdges(edges, source, destination, twoWay, () => crypto.randomUUID());
      setEdges(updated); setSelected(updated[edges.length].id); setDestination(''); setSource(''); setError(''); setMessage('Connection added. Save draft to persist it.');
    } catch (failure) { setError(failure.message); }
  }
  function remove(confirmed = false) {
    if (!editable || !edge) return;
    if (confirmed !== true) return requestConfirmation({ title: 'Delete Driving Connection?', description: 'Only this travel direction will be removed. Its reverse direction, if present, is kept. Save Draft to apply the deletion.', variant: 'destructive', confirmLabel: 'Delete Connection' }, () => remove(true));
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
    if (!editable || !start || start.moved || mode === 'pan') return;
    if (start.node) {
      setSelected('');
      if (!source || destination) { setSource(start.node); setDestination(''); setError(''); }
      else if (source === start.node) setError('Choose two different nodes.');
      else { setDestination(start.node); setError(''); }
    } else setSelected(start.edge ?? '');
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
      setData(result); setEdges(loaded); setSnapshot(loaded); setMessage('Successfully saved the connections and recalculated all distances!');
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
  return <section className={`${map.section} ${styles.nodeEditor}`} aria-label="Add Edges" aria-busy={busy}>
    <div className={map.heading}><h2>Add Edges</h2></div>
    <dl className={map.summary} aria-label="Edge Draft Summary">
      <div className={map.summaryCard}><dt>Directed Edges</dt><dd>{loading || !data ? '—' : edges.length}</dd></div>
      <div className={map.summaryCard}><dt>Save Status</dt><dd role="status">{loading ? 'Loading…' : saving ? 'Saving…' : dirty ? 'Unsaved changes' : !data ? 'Not loaded' : 'All changes saved'}</dd></div>
      <div className={map.summaryCard}><dt>Revisions</dt><dd><span>Draft</span> {data?.draft?.revision ?? '—'} <span>· Calibration</span> {data?.current_calibration_revision ?? '—'}</dd></div>
    </dl>
    {!loading && data && (!data.draft ? <p className={styles.warning}>Add and save nodes before connecting them.</p> : !data.calibration ? <p className={styles.warning}>Calibrate this image before connecting nodes.</p> : data.needs_distance_revalidation && <p className={styles.warning}>Gentle reminder: node positions and calibration require revalidating the distance</p>)}
    {error && <p className={map.error} role="alert">{error}{locked ? ' Reload draft, or refresh the page if the image changed. Local edits are retained until you confirm discarding them.' : ''}</p>}
    {message && <p className={map.success} role="status">{message}</p>}
    <div className={styles.nodeLayout}>
    <div className={styles.canvas}>
    <div className={`${map.toolbar} ${styles.mapTools}`}>
      <div className={styles.toolGroup} role="group" aria-label="Map Tools">
        <button type="button" className={map.button} aria-pressed={mode === 'pan'} disabled={!editable} onClick={() => { gesture.current = null; setMode(value => value === 'pan' ? 'select' : 'pan'); }}>Pan</button>
      </div>
      <div className={styles.toolGroup}>
      <div className={styles.zoomControls} role="group" aria-label="Map Zoom">
        <button className={map.button} aria-label="Zoom Out" disabled={busy || zoom <= 1} onClick={() => setZoom(value => Math.max(1, value - .5))}>−</button>
        <span className={styles.zoomValue} aria-live="polite">Zoom {Math.round(zoom * 100)}%</span>
        <button className={map.button} aria-label="Zoom In" disabled={busy || zoom >= 6} onClick={() => setZoom(value => Math.min(6, value + .5))}>+</button>
      </div>
      <button className={map.button} disabled={busy} onClick={() => { setZoom(1); viewport.current.scrollTo(0, 0); }}>Fit Image</button>
      </div>
    </div>
    <p className={map.note}>{mode === 'pan' ? 'Drag the image to pan. Turn pan off to select edges or connect nodes.' : 'Click an arrow to inspect an edge, or click two different node markers to choose a source and destination.'}</p>
    <div ref={viewport} className={map.viewport} tabIndex={0} aria-label="Scrollable Driving Edge Map">
      <svg viewBox={`0 0 ${plan.width_px} ${plan.height_px}`} style={{ width: floorPlanWidth(plan.width_px, plan.height_px, zoom) }} className={mode === 'pan' ? map.pan : map.select}
        aria-label={`Draft driving connections on ${level.name}`} onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={() => { gesture.current = null; }}>
        <defs>{[['edge', 'var(--chart-primary)'], ['selected', 'var(--chart-comparative)'], ['preview', 'var(--chart-supporting)']].map(([id, colour]) =>
          <marker key={id} id={`${markerId}-${id}`} markerUnits="userSpaceOnUse" markerWidth={radius} markerHeight={radius} refX="10" refY="5" viewBox="0 0 10 10" orient="auto"><path d="M0 0 L10 5 L0 10 Z" fill={colour} stroke="white" strokeWidth=".5" /></marker>)}</defs>
        <image href={`/api/parking-structure/levels/${level.id}/image?revision=${plan.revision}&refresh=${refreshKey}`} width={plan.width_px} height={plan.height_px}
          onLoad={() => setReady(true)} onError={() => { setReady(false); setLocked(true); setError('Image could not be loaded. Refresh the page.'); }} />
        {edges.map(item => drawEdge(item))}{previewEdges.map(item => drawEdge(item, true))}
        {nodes.map(node => <g key={node.id} data-node-id={node.id}>
          <title>{node.code}</title><circle cx={node.x} cy={node.y} r={radius} fill={node.id === source ? 'var(--chart-primary)' : node.id === destination ? 'var(--chart-supporting)' : 'var(--primary)'} stroke="white" strokeWidth={2} vectorEffect="non-scaling-stroke" />
          <text x={node.x + radius * 1.4} y={node.y} fontSize={radius * 1.1} fill="var(--text)" stroke="white" strokeWidth={3} paintOrder="stroke" vectorEffect="non-scaling-stroke">{node.code}</text>
        </g>)}
      </svg>
    </div>
    </div>
    <aside className={styles.inspector} aria-label="Edge Controls">
    <section className={styles.controlGroup} aria-label="Create Connections">
      <h3>Connect Nodes</h3>
      <p className={styles.help}>Choose the source and destination here, or click two node markers on the map. Then, choose a direction and add the connection.</p>
      <label className={styles.field}>Source Node<select className={styles.nodeSelect} title={nodeMap.get(source)?.code || 'Select Source'} disabled={!editable} value={source} onChange={event => { setSource(event.target.value); setDestination(''); setMode('select'); }}><option value="">Select source</option>{nodes.map(node => <option key={node.id} value={node.id}>{node.code}</option>)}</select></label>
      <label className={styles.field}>Destination Node<select className={styles.nodeSelect} title={nodeMap.get(destination)?.code || 'Select Destination'} disabled={!editable} value={destination} onChange={event => { setDestination(event.target.value); setMode('select'); }}><option value="">Select destination</option>{nodes.filter(node => node.id !== source).map(node => <option key={node.id} value={node.id}>{node.code}</option>)}</select></label>
      <label className={styles.field}>Travel Direction<select disabled={!editable} value={twoWay ? 'two' : 'one'} onChange={event => setTwoWay(event.target.value === 'two')}><option value="one">One-Way</option><option value="two">Two-Way</option></select></label>
      <dl className={local.distanceCard}><dt>Distance Preview</dt><dd>{metres(preview)}{twoWay && preview !== null ? ' Each direction' : ''}</dd></dl>
      <div className={styles.coordinates}>
        <button type="button" className={map.button} disabled={!editable || preview === null} onClick={add}>Add Connection</button>
        <button type="button" className={map.button} disabled={!editable || (!source && !destination)} onClick={() => { setSource(''); setDestination(''); }}>Reset Selection</button>
      </div>
    </section>
    <section className={styles.controlGroup} aria-label="Selected Edge Details">
      <h3>Select Edge</h3>
      <label className={styles.field}>Select Directed Edge<select className={styles.nodeSelect} title={edge ? `${nodeMap.get(edge.from_node_id)?.code} → ${nodeMap.get(edge.to_node_id)?.code}` : 'Select an Edge'} value={selected} disabled={!editable} onChange={event => { setSelected(event.target.value); setMode('select'); }}><option value="">Select an edge</option>{edges.map(item => <option key={item.id} value={item.id}>{nodeMap.get(item.from_node_id)?.code} → {nodeMap.get(item.to_node_id)?.code}</option>)}</select></label>
      {edge && <><dl className={local.distanceCard}><dt>Distance Preview</dt><dd>{metres(previewDistance(nodeMap.get(edge.from_node_id), nodeMap.get(edge.to_node_id), scale))}</dd></dl>
        <dl className={local.distanceCard}><dt>Saved Distance{data.needs_distance_revalidation ? ' (Stale)' : ''}</dt><dd>{storedEdge ? metres(storedEdge.distance_meters) : 'Not saved'}</dd></dl>
        <button type="button" className={local.deleteAction} disabled={!editable} onClick={remove}>Delete Directed Edge</button></>}
      {!edge && <p className={styles.help}>Choose an edge from the list or select an arrow on the map to inspect its distances.</p>}
    </section>
    <div className={styles.inspectorActions}>
      <button type="button" className={`${map.button} ${map.primary}`} disabled={!editable || (!dirty && !data?.needs_distance_revalidation)} onClick={save}>{saving ? 'Saving…' : data?.needs_distance_revalidation ? 'Recalculate and Save' : 'Save Draft'}</button>
      <RefreshButton label="Reload Draft" loading={loading} disabled={busy} onClick={reload} />
    </div>
    </aside>
    </div>
    {confirmationDialog}
  </section>;
}
