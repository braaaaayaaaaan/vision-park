'use client';
import RefreshButton from '../../../components/refresh-button';
import { useEffect, useRef, useState } from 'react';
import useConfirmation from '../../../components/use-confirmation';
import { floorPlanRequest } from './floor-plans-client.mjs';
import { floorPlanWidth, imagePoint, panPosition } from './calibration-utils.mjs';
import { NODE_TYPES, MAX_NODES, createNode, deleteNode, draftError, editNode, movedNodePoint, nodesChanged } from './node-draft-utils.mjs';
import { linksFromRows, linksChanged, zoneChanges } from './zone-entrance-utils.mjs';
import ZoneEntranceFields from './zone-entrance-fields';
import map from './calibration.module.css';
import styles from './node-editor.module.css';
import FloorPlanImage from './floor-plan-image.mjs';

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
  const [nodeType, setNodeType] = useState('building_entrance');
  const [zoom, setZoom] = useState(1);
  const [links, setLinks] = useState({}), [savedLinks, setSavedLinks] = useState({});
  const viewport = useRef(null), drawing = useRef(null), gesture = useRef(null), saveController = useRef(null);
  const path = `/levels/${level.id}/node-zone-draft`;
  const dirty = nodesChanged(nodes, snapshot) || linksChanged(links, savedLinks);
  const validation = draftError(nodes, plan.width_px, plan.height_px);
  const busy = disabled || loading || saving;
  const editable = !busy && !locked && ready;
  const node = nodes.find(item => item.id === selected);
  const { requestConfirmation, confirmationDialog } = useConfirmation({ disabled: busy });
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
  function reload(confirmed = false) {
    if (dirty && confirmed !== true) return requestConfirmation({ title: 'Discard Node Changes?', description: 'Unsaved node and zone-link changes will be discarded when you reload.', variant: 'warning', confirmLabel: 'Discard and Reload' }, () => reload(true));
    setLoading(true); setMessage(''); setReloadKey(value => value + 1);
  }
  function change(changes) {
    if (!editable || !node) return;
    setNodes(previous => editNode(previous, selected, changes)); setMessage('');
  }
  function remove(confirmed = false) {
    if (!editable || !node) return;
    if (confirmed !== true) return requestConfirmation({ title: 'Delete Draft Node?', description: `Delete draft node "${node.code || 'Unnamed'}"? Saving also removes its connected edges. This change takes effect when you Save Draft.`, variant: 'destructive', confirmLabel: 'Delete Node' }, () => remove(true));
    setNodes(previous => deleteNode(previous, selected)); setSelected(''); setMessage('');
  }
  function keyDown(event) {
    if (event.key !== 'Delete' || event.defaultPrevented || event.repeat || event.isComposing ||
        event.ctrlKey || event.metaKey || event.altKey || event.shiftKey || !editable || !node) return;
    if (event.target.closest('dialog, input, textarea, select, [contenteditable]:not([contenteditable="false"]), [role="textbox"]')) return;
    event.preventDefault();
    event.stopPropagation();
    gesture.current = null;
    remove();
  }
  function point(event) {
    return imagePoint(event.clientX, event.clientY, drawing.current, plan.width_px, plan.height_px);
  }
  function down(event) {
    if (!editable || event.button !== 0 || !event.isPrimary) return;
    viewport.current.focus({ preventScroll: true });
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
    if (nodes.length >= MAX_NODES) { setError('A draft can contain at most 1,000 nodes.'); return; }
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
      setData(result); setNodes(result.draft.nodes); setSnapshot(result.draft.nodes); setMessage('Successfully saved node draft and zone links!');
    } catch (failure) {
      if (!controller.signal.aborted) {
        setError(failure.message);
        setLocked(failure.status === 409 || !failure.status || failure.status >= 500);
      }
    } finally { if (!controller.signal.aborted) setSaving(false); }
  }
  const marker = Math.max(plan.width_px, plan.height_px) / (90 * zoom);
  return <section className={`${map.section} ${styles.nodeEditor}`} aria-label="Add Nodes" aria-busy={busy} onKeyDownCapture={keyDown}>
    <div className={map.heading}><h2>Add Nodes</h2></div>
    <dl className={map.summary} aria-label="Node Draft Summary">
      <div className={map.summaryCard}><dt>Nodes</dt><dd>{loading || !data ? '—' : nodes.length}</dd></div>
      <div className={map.summaryCard}><dt>Save Status</dt><dd role="status">{loading ? 'Loading…' : saving ? 'Saving…' : dirty ? 'Unsaved changes' : !data ? 'Not loaded' : 'All Changes Saved'}</dd></div>
      <div className={map.summaryCard}><dt>Revisions</dt><dd><span>Image</span> {plan.revision} <span>· Draft</span> {loading || !data ? '—' : data.draft?.revision ?? 0}</dd></div>
    </dl>
    {data?.needs_distance_revalidation && <p className={styles.warning} role="status">{data.current_calibration_revision === 0 ?
      'Gentle Reminder: No calibration is saved for this image. Distances will require validation' :
      'Gentle Reminder: Editing nodes or calibrations require revalidating the distance'}</p>}
    {error && <p className={map.error} role="alert">{error}{locked ? ' Reload draft, or use the page refresh if the image changed. Unsaved edits are retained until you confirm discarding them.' : ''}</p>}
    {validation && <p className={map.error} role="alert">{validation}</p>}
    {message && <p className={map.success} role="status">{message}</p>}
    <div className={styles.nodeLayout}>
    <div className={styles.canvas}>
    <div className={`${map.toolbar} ${styles.mapTools}`}>
      <div className={styles.toolGroup} role="group" aria-label="Map Tools">
        {[['select', 'Select and Move'], ['pan', 'Pan']].map(([value, label]) => <button className={map.button} key={value} aria-pressed={mode === value} disabled={!editable} onClick={() => { gesture.current = null; setMode(value); }}>{label}</button>)}
      </div>
      <div className={styles.toolGroup}>
      <div className={styles.zoomControls} role="group" aria-label="Map Zoom">
        <button className={map.button} aria-label="Zoom Out" title="Zoom out" disabled={busy || zoom <= 1} onClick={() => setZoom(value => Math.max(1, value - .5))}>−</button>
        <span className={styles.zoomValue} aria-live="polite">Zoom {Math.round(zoom * 100)}%</span>
        <button className={map.button} aria-label="Zoom In" title="Zoom in" disabled={busy || zoom >= 6} onClick={() => setZoom(value => Math.min(6, value + .5))}>+</button>
      </div>
      <button className={map.button} disabled={busy} onClick={() => { setZoom(1); viewport.current.scrollTo(0, 0); }}>Fit Image</button>
      </div>
    </div>
    <p className={map.note}>{mode === 'add' ? 'Click on an empty space to add a node based on the chosen type.' : mode === 'pan' ? 'Drag the image or use the scrollbars to pan.' : 'Select a node to edit or drag its marker to move it. Press Del to delete the selected node.'}</p>
    <div ref={viewport} className={map.viewport} tabIndex={0} aria-label="Scrollable Draft Node Map">
      <svg ref={drawing} viewBox={`0 0 ${plan.width_px} ${plan.height_px}`} style={{ width: floorPlanWidth(plan.width_px, plan.height_px, zoom) }}
        className={mode === 'pan' ? map.pan : map.select} role="img" aria-label={`Draft nodes on ${level.name}`}
        onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={cancelGesture}>
        <FloorPlanImage href={`/api/parking-structure/levels/${level.id}/image?revision=${plan.revision}&refresh=${refreshKey}`}
          width={plan.width_px} height={plan.height_px} onLoad={() => setReady(true)}
          onError={() => { setReady(false); setLocked(true); setError('Image could not be loaded. Refresh the page.'); }} />
        {nodes.filter(item => Number.isFinite(item.x) && Number.isFinite(item.y)).map(item => <g key={item.id} data-node-id={item.id}>
          <title>{`${item.code} — ${NODE_TYPES[item.node_type]}`}</title>
          {item.id === selected && <circle cx={item.x} cy={item.y} r={marker * 1.3} fill="none" stroke="var(--primary)" strokeWidth={2} vectorEffect="non-scaling-stroke" />}
          <circle cx={item.x} cy={item.y} r={marker} fill={item.id === selected ? 'var(--primary)' : 'var(--text-muted)'} stroke="white" strokeWidth={item.id === selected ? 3 : 2} vectorEffect="non-scaling-stroke" />
          <text x={item.x} y={item.y} dy=".35em" textAnchor="middle" fill="white" fontSize={marker * .9} fontWeight="bold">{{ building_entrance: 'E', junction: 'J', ramp: 'R', zone_entrance: 'Z' }[item.node_type]}</text>
          <text x={item.x + marker * 1.3} y={item.y} fontSize={marker * 1.1} fill="var(--text)" stroke="white" strokeWidth={3} paintOrder="stroke" vectorEffect="non-scaling-stroke">{item.code}</text>
        </g>)}
      </svg>
    </div>
    </div>
    <aside className={styles.inspector} aria-label="Node Controls">
    <section className={styles.controlGroup} aria-label="Create Nodes">
      <h3>Add a Node</h3>
      <p className={styles.help}>Choose a type, then press Add Node and click the floor plan.</p>
      <label className={styles.field}>New Node<select value={nodeType} disabled={!editable} onChange={event => setNodeType(event.target.value)}>{Object.entries(NODE_TYPES).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
      <button type="button" className={map.button} aria-pressed={mode === 'add'} disabled={!editable} onClick={() => { gesture.current = null; setMode('add'); }}>Add Node</button>
    </section>
    <section className={styles.controlGroup} aria-label="Selected Node Details">
      <h3>Edit a Node</h3>
      <label className={styles.field}>Select Draft Node<select className={styles.nodeSelect} title={node ? `${node.code} · ${NODE_TYPES[node.node_type]}` : 'Select a Node'} value={selected} disabled={!editable} onChange={event => { setSelected(event.target.value); setMode('select'); }}>
        <option value="">Select a node</option>{nodes.map(item => <option key={item.id} value={item.id}>{item.code || 'Unnamed Node'} · {NODE_TYPES[item.node_type]}</option>)}
      </select></label>
      {node && <>
        <label className={styles.field}>Node Code<input value={node.code} maxLength={64} disabled={!editable} onChange={event => change({ code: event.target.value })} /></label>
        <label className={styles.field}>Node Type<select value={node.node_type} disabled={!editable} onChange={event => change({ node_type: event.target.value })}>{Object.entries(NODE_TYPES).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
        <div className={styles.coordinates}>
        <label className={styles.field}>X (Pixels)<input type="number" step="any" min="0" max={plan.width_px} value={node.x} disabled={!editable} onChange={event => change({ x: event.target.value === '' ? '' : Number(event.target.value) })} /></label>
        <label className={styles.field}>Y (Pixels)<input type="number" step="any" min="0" max={plan.height_px} value={node.y} disabled={!editable} onChange={event => change({ y: event.target.value === '' ? '' : Number(event.target.value) })} /></label>
        </div>
        <button className={`${map.button} ${styles.delete}`} aria-keyshortcuts="Delete" title="Delete selected node (Del)" disabled={!editable} onClick={remove}>Delete Node</button>
      </>}
      {!node && <p className={styles.help}>Choose a node from the list or select its marker on the map to edit it.</p>}
    </section>
    {data?.zone_configuration && <ZoneEntranceFields node={node} nodes={nodes} plan={plan} zones={data.zone_configuration.zones}
      links={links} disabled={!editable} onChange={value => { setLinks(value); setMessage(''); }} />}
    <div className={styles.inspectorActions}>
      <button type="button" className={`${map.button} ${map.primary}`} disabled={!editable || !dirty || Boolean(validation)} onClick={save}>{saving ? 'Saving…' : 'Save Draft'}</button>
      <RefreshButton label="Reload Draft" loading={loading} disabled={busy} onClick={reload} />
    </div>
    </aside>
    </div>
    {confirmationDialog}
  </section>;
}
