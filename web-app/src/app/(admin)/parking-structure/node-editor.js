'use client';
import { useEffect, useRef, useState } from 'react';
import { floorPlanRequest } from './floor-plans-client.mjs';
import { imagePoint, panPosition } from './calibration-utils.mjs';
import { NODE_TYPES, MAX_NODES, createNode, deleteNode, draftError, editNode, movedNodePoint, nodesChanged } from './node-draft-utils.mjs';
import { linksFromRows, linksChanged, zoneChanges } from './zone-entrance-utils.mjs';
import ZoneEntranceFields from './zone-entrance-fields';
import map from './calibration.module.css';
import styles from './node-editor.module.css';

export default function NodeEditor({ level, plan, disabled, refreshKey, onDirtyChange, onSavingChange }) {
  const [nodes, setNodes] = useState([]);
  const [snapshot, setSnapshot] = useState([]);
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [locked, setLocked] = useState(false);
  const [ready, setReady] = useState(false);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');
  const [reloadKey, setReloadKey] = useState(0);
  const [selected, setSelected] = useState('');
  const [mode, setMode] = useState('select');
  const [nodeType, setNodeType] = useState('junction');
  const [zoom, setZoom] = useState(1);
  const [links, setLinks] = useState({}), [savedLinks, setSavedLinks] = useState({});
  const viewport = useRef(null), drawing = useRef(null), gesture = useRef(null), saveController = useRef(null);
  const path = `/levels/${level.id}/node-zone-draft`;
  const dirty = nodesChanged(nodes, snapshot) || linksChanged(links, savedLinks);
  const validation = draftError(nodes, plan.width_px, plan.height_px);
  const busy = disabled || loading || saving;
  const editable = !busy && !locked && ready;
  const node = nodes.find(item => item.id === selected);
  useEffect(() => { onDirtyChange(dirty); }, [dirty, onDirtyChange]);
  useEffect(() => { onSavingChange(saving); }, [saving, onSavingChange]);
  useEffect(() => () => { onDirtyChange(false); onSavingChange(false); }, [onDirtyChange, onSavingChange]);
  useEffect(() => {
    const controller = new AbortController();
    floorPlanRequest(`${path}?floor_plan_revision=${plan.revision}`, { signal: controller.signal }).then(result => {
      if (controller.signal.aborted) return;
      const loaded = result.draft?.nodes ?? [];
      const invalid = draftError(loaded, plan.width_px, plan.height_px);
      if (invalid) throw new Error(invalid);
      setData(result); setNodes(loaded); setSnapshot(loaded); setSelected('');
      const saved = linksFromRows(result.zone_entrances);
      setLinks(saved); setSavedLinks(saved);
      setLocked(false); setLoading(false); setError('');
    }).catch(failure => {
      if (!controller.signal.aborted) { setError(failure.message); setLocked(true); setLoading(false); }
    });
    return () => { controller.abort(); saveController.current?.abort(); };
  }, [path, plan.revision, plan.width_px, plan.height_px, reloadKey]);
  function reload() {
    if (dirty && !window.confirm('Discard Unsaved Node Changes And Reload?')) return;
    setLoading(true); setMessage(''); setReloadKey(value => value + 1);
  }
  function change(changes) {
    if (!editable || !node) return;
    setNodes(previous => editNode(previous, selected, changes)); setMessage('');
  }
  function remove() {
    if (!editable || !node || !window.confirm(`Delete Draft Node "${node.code || 'Unnamed'}"? Saving Also Removes Its Connected Edges.`)) return;
    setNodes(previous => deleteNode(previous, selected)); setSelected(''); setMessage('');
  }
  function point(event) {
    return imagePoint(event.clientX, event.clientY, drawing.current.getBoundingClientRect(), plan.width_px, plan.height_px);
  }
  function down(event) {
    if (!editable || event.button !== 0 || !event.isPrimary) return;
    const start = point(event);
    if (!start) return;
    const id = event.target.closest('[data-node-id]')?.getAttribute('data-node-id');
    const target = nodes.find(item => item.id === id);
    if (mode === 'select') setSelected(target?.id ?? '');
    gesture.current = { x: event.clientX, y: event.clientY, point: start,
      left: viewport.current.scrollLeft, top: viewport.current.scrollTop,
      scale: viewport.current.getBoundingClientRect().width / viewport.current.offsetWidth || 1, node: target, moved: false };
    event.currentTarget.setPointerCapture(event.pointerId);
  }
  function move(event) {
    const start = gesture.current;
    if (!start || !editable) return;
    const dx = event.clientX - start.x, dy = event.clientY - start.y;
    if (Math.hypot(dx, dy) > 4) start.moved = true;
    if (mode === 'pan') {
      const position = panPosition(start, event.clientX, event.clientY);
      viewport.current.scrollLeft = position.left;
      viewport.current.scrollTop = position.top;
    } else if (mode === 'select' && start.node && start.moved) {
      const position = point(event);
      if (position) {
        const updated = movedNodePoint(start.node, start.point, position, plan.width_px, plan.height_px);
        setNodes(previous => editNode(previous, start.node.id, updated)); setMessage('');
      }
    }
  }
  function up(event) {
    const start = gesture.current;
    gesture.current = null;
    if (!editable || !start || start.moved || mode !== 'add' || start.node) return;
    const position = point(event);
    if (!position) return;
    if (nodes.length >= MAX_NODES) { setError('A Draft Can Contain At Most 1,000 Nodes.'); return; }
    const added = createNode(nodes, nodeType, position, crypto.randomUUID());
    setNodes(previous => [...previous, added]); setSelected(added.id); setMessage(''); setError('');
  }
  function cancelGesture() {
    const start = gesture.current;
    if (mode === 'select' && start?.node && start.moved) setNodes(previous => editNode(previous, start.node.id, { x: start.node.x, y: start.node.y }));
    gesture.current = null;
  }
  async function save() {
    if (!editable || validation || !dirty) return;
    setSaving(true); setError(''); setMessage('');
    const controller = new AbortController(); saveController.current = controller;
    try {
      const result = await floorPlanRequest(path, {
        method: 'PUT', signal: controller.signal, headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ floor_plan_revision: plan.revision, expected_revision: data?.draft?.revision ?? 0,
          nodes: nodes.map(item => ({ ...item, code: item.code.trim() })),
          zone_changes: zoneChanges(links, savedLinks, data.zone_configuration.zones) }),
      });
      if (controller.signal.aborted) return;
      const saved = linksFromRows(result.zone_entrances);
      setLinks(saved); setSavedLinks(saved);
      setData(result); setNodes(result.draft.nodes); setSnapshot(result.draft.nodes); setMessage('Successfully saved node draft and zone links.');
    } catch (failure) {
      if (!controller.signal.aborted) {
        setError(failure.message);
        setLocked(failure.status === 409 || !failure.status || failure.status >= 500);
      }
    } finally { if (!controller.signal.aborted) setSaving(false); }
  }
  const marker = Math.max(plan.width_px, plan.height_px) / (90 * zoom);
  return <section className={map.section} aria-label="Add Nodes" aria-busy={busy}>
    <div className={map.heading}><h2>Add Nodes</h2>
      <div className={map.toolbar}><button className={map.button} disabled={busy} onClick={reload}>Reload Draft</button>
        <button className={`${map.button} ${map.primary}`} disabled={!editable || !dirty || Boolean(validation)} onClick={save}>{saving ? 'Saving…' : 'Save Draft'}</button></div>
    </div>
    <dl className={map.summary} aria-label="Node Draft Summary">
      <div className={map.summaryCard}><dt>Nodes</dt><dd>{loading || !data ? '—' : nodes.length}</dd></div>
      <div className={map.summaryCard}><dt>Save Status</dt><dd role="status">{loading ? 'Loading…' : saving ? 'Saving…' : dirty ? 'Unsaved Changes' : !data ? 'Not Loaded' : 'All Changes Saved'}</dd></div>
      <div className={map.summaryCard}><dt>Revisions</dt><dd><span>Image</span> {plan.revision} <span>· Draft</span> {loading || !data ? '—' : data.draft?.revision ?? 0}</dd></div>
    </dl>
    {data?.needs_distance_revalidation && <p className={styles.warning} role="status">{data.current_calibration_revision === 0 ?
      'No Calibration Is Saved For This Image. Future Distances Will Require Validation.' :
      'Editing nodes or calibrations require revalidating the distance.'}</p>}
    {error && <p className={map.error} role="alert">{error}{locked ? ' Reload Draft, or use the page Refresh if the image changed. Unsaved edits are retained until you confirm discarding them.' : ''}</p>}
    {validation && <p className={map.error} role="alert">{validation}</p>}
    {message && <p className={map.success} role="status">{message}</p>}
    <div className={map.toolbar}>
      {[['select', 'Select and Move'], ['add', 'Add Node'], ['pan', 'Pan']].map(([value, label]) => <button className={map.button} key={value} aria-pressed={mode === value} disabled={!editable} onClick={() => { gesture.current = null; setMode(value); }}>{label}</button>)}
      <div className={styles.zoomControls} role="group" aria-label="Map Zoom">
        <button className={map.button} aria-label="Zoom Out" title="Zoom Out" disabled={busy || zoom <= 1} onClick={() => setZoom(value => Math.max(1, value - .5))}>−</button>
        <span className={styles.zoomValue} aria-live="polite">Zoom {Math.round(zoom * 100)}%</span>
        <button className={map.button} aria-label="Zoom In" title="Zoom In" disabled={busy || zoom >= 6} onClick={() => setZoom(value => Math.min(6, value + .5))}>+</button>
      </div>
      <button className={map.button} disabled={busy} onClick={() => { setZoom(1); viewport.current.scrollTo(0, 0); }}>Fit Image</button>
    </div>
    <p className={map.note}>{mode === 'add' ? 'Click on an empty space to add a node based on the chosen type.' : mode === 'pan' ? 'Drag the image or use the scrollbars to pan.' : 'Select a node to edit or drag its marker to move it.'}</p>
    <div ref={viewport} className={map.viewport} tabIndex={0} aria-label="Scrollable Draft Node Map">
      <svg ref={drawing} viewBox={`0 0 ${plan.width_px} ${plan.height_px}`} style={{ width: `${zoom * 100}%` }}
        className={mode === 'pan' ? map.pan : map.select} role="img" aria-label={`Draft Nodes On ${level.name}`}
        onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={cancelGesture}>
        <image href={`/api/parking-structure/levels/${level.id}/image?revision=${plan.revision}&refresh=${refreshKey}`}
          width={plan.width_px} height={plan.height_px} onLoad={() => setReady(true)}
          onError={() => { setReady(false); setLocked(true); setError('Image Could Not Be Loaded. Refresh The Page.'); }} />
        {nodes.filter(item => Number.isFinite(item.x) && Number.isFinite(item.y)).map(item => <g key={item.id} data-node-id={item.id}>
          <title>{`${item.code} — ${NODE_TYPES[item.node_type]}`}</title>
          {item.id === selected && <circle cx={item.x} cy={item.y} r={marker * 1.3} fill="none" stroke="var(--primary)" strokeWidth={2} vectorEffect="non-scaling-stroke" />}
          <circle cx={item.x} cy={item.y} r={marker} fill={item.id === selected ? 'var(--primary)' : 'var(--text-muted)'} stroke="white" strokeWidth={item.id === selected ? 3 : 2} vectorEffect="non-scaling-stroke" />
          <text x={item.x} y={item.y} dy=".35em" textAnchor="middle" fill="white" fontSize={marker * .9} fontWeight="bold">{{ building_entrance: 'E', junction: 'J', ramp: 'R', zone_entrance: 'Z' }[item.node_type]}</text>
          <text x={item.x + marker * 1.3} y={item.y} fontSize={marker * 1.1} fill="var(--text)" stroke="white" strokeWidth={3} paintOrder="stroke" vectorEffect="non-scaling-stroke">{item.code}</text>
        </g>)}
      </svg>
    </div>
    <div className={styles.details}>
      <label className={styles.field}>New Node Type<select value={nodeType} disabled={!editable} onChange={event => setNodeType(event.target.value)}>{Object.entries(NODE_TYPES).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
      <label className={styles.field}>Select Draft Node<select value={selected} disabled={!editable} onChange={event => { setSelected(event.target.value); setMode('select'); }}>
        <option value="">Select A Node</option>{nodes.map(item => <option key={item.id} value={item.id}>{item.code || 'Unnamed Node'} · {NODE_TYPES[item.node_type]}</option>)}
      </select></label>
      {node && <>
        <label className={styles.field}>Node Code<input value={node.code} maxLength={64} disabled={!editable} onChange={event => change({ code: event.target.value })} /></label>
        <label className={styles.field}>Node Type<select value={node.node_type} disabled={!editable} onChange={event => change({ node_type: event.target.value })}>{Object.entries(NODE_TYPES).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
        <label className={styles.field}>X (Pixels)<input type="number" step="any" min="0" max={plan.width_px} value={node.x} disabled={!editable} onChange={event => change({ x: event.target.value === '' ? '' : Number(event.target.value) })} /></label>
        <label className={styles.field}>Y (Pixels)<input type="number" step="any" min="0" max={plan.height_px} value={node.y} disabled={!editable} onChange={event => change({ y: event.target.value === '' ? '' : Number(event.target.value) })} /></label>
        <button className={`${map.button} ${styles.delete}`} disabled={!editable} onClick={remove}>Delete Node</button>
      </>}
    </div>
    {data?.zone_configuration && <ZoneEntranceFields node={node} nodes={nodes} plan={plan} zones={data.zone_configuration.zones}
      links={links} disabled={!editable} onChange={value => { setLinks(value); setMessage(''); }} />}
  </section>;
}
