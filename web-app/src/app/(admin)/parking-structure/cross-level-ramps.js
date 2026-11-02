'use client';
import SuccessNotice from '../../../components/success-notice';
import RefreshButton from '../../../components/refresh-button';
import useConfirmation from '../../../components/use-confirmation';
import { useCallback, useEffect, useRef, useState } from 'react';
import { floorPlanRequest } from './floor-plans-client.mjs';
import RampTraceEditor from './ramp-trace-editor';
import { traceFromEdge } from './ramp-trace-utils.mjs';
import { buildRampBatch, initialRampForm, reviewLabels } from './cross-level-utils.mjs';
import map from './calibration.module.css';
import fields from './node-editor.module.css';
import styles from './cross-level-ramps.module.css';

const basePath = '/cross-level-draft-edges';
const metres = value => `${value.toLocaleString('en-MY', value < .01 ? { maximumSignificantDigits: 2 } : { maximumFractionDigits: 2 })} m`;
const rampLabel = (code, level) => level ? `${code} (${level})` : code;
function RampEndpoint({ label, levelId, nodeId, levels, excluded, disabled, onLevel, onNode, onSnapshot }) {
  const [data, setData] = useState(null), [error, setError] = useState('');
  const level = levels.find(item => item.id === levelId), plan = level?.floor_plan;
  const width = plan?.width_px, height = plan?.height_px;
  useEffect(() => {
    if (!levelId || !plan) return;
    const controller = new AbortController();
    floorPlanRequest(`/levels/${levelId}/graph-draft?floor_plan_revision=${plan.revision}`, { signal: controller.signal }).then(result => {
      if (controller.signal.aborted) return;
      setData(result); onSnapshot(result);
    }).catch(failure => { if (!controller.signal.aborted) setError(failure.message); });
    return () => controller.abort();
  }, [levelId, plan, onSnapshot]);
  const nodes = data?.draft?.nodes.filter(node => node.node_type === 'ramp') ?? [];
  const selected = nodes.find(node => node.id === nodeId);
  const radius = Math.max(width ?? 0, height ?? 0) / 55;
  return <section className={styles.card} aria-label={`${label} ramp endpoint`}>
    <h3>{label}</h3>
    <label className={fields.field}>Parking Level<select value={levelId} disabled={disabled} onChange={event => onLevel(event.target.value)}>
      <option value="">Select a level</option>{levels.filter(item => item.id !== excluded).map(item => <option key={item.id} value={item.id}>{item.name}{item.is_active ? '' : ' (Inactive)'}</option>)}
    </select></label>
    <label className={fields.field}>Ramp Node<select value={selected ? nodeId : ''} disabled={disabled || !data} onChange={event => onNode(event.target.value)}>
      <option value="">Select a ramp node</option>{nodes.map(node => <option key={node.id} value={node.id}>{node.code}</option>)}
    </select></label>
    {error && <p className={map.error} role="alert">{error} use refresh to load current floor plans.</p>}
    {levelId && !plan && <p className={map.note}>Upload a floor plan for this level first.</p>}
    {plan && !data && !error && <p className={map.note} role="status">Loading saved ramp nodes…</p>}
    {data && nodes.length === 0 && <p className={map.note}>No saved ramp nodes on this level.</p>}
    {nodeId && data && !selected && <p className={fields.warning}>The previous ramp node is unavailable. Select a current ramp node.</p>}
    {plan && selected && <div className={styles.preview}><svg viewBox={`0 0 ${width} ${height}`} role="img" aria-label={`${selected.code} On ${level.name}`}>
      <image href={`/api/parking-structure/levels/${levelId}/image?revision=${plan.revision}`} width={width} height={height}
        onError={() => { setError('Endpoint image changed or could not be loaded.'); onSnapshot(null); }} />
      <circle cx={selected.x} cy={selected.y} r={radius} fill="var(--chart-primary)" stroke="white" strokeWidth={3} vectorEffect="non-scaling-stroke" />
      <text x={selected.x + radius * 1.4} y={selected.y} fontSize={radius * 1.3} fill="var(--text)" stroke="white" strokeWidth={3} paintOrder="stroke" vectorEffect="non-scaling-stroke">{selected.code}</text>
    </svg></div>}
    {data?.draft && <p className={map.note}>Image {data.floor_plan_revision} · Draft {data.draft.revision}</p>}
  </section>;
}

export default function CrossLevelRamps({ levels: initialLevels, disabled, onDirtyChange, onSavingChange }) {
  const [levels, setLevels] = useState(initialLevels), [listing, setListing] = useState(null), [offset, setOffset] = useState(0), [refreshKey, setRefreshKey] = useState(0);
  const [loading, setLoading] = useState(true), [saving, setSaving] = useState(false), [locked, setLocked] = useState(false);
  const [form, setForm] = useState(initialRampForm), [editing, setEditing] = useState(null), [endpointKey, setEndpointKey] = useState(0);
  const [from, setFrom] = useState(null), [to, setTo] = useState(null), [touched, setTouched] = useState(false);
  const [error, setError] = useState(''), [message, setMessage] = useState('');
  const saveController = useRef(null);
  const busy = disabled || saving || loading;
  const { requestConfirmation, confirmationDialog } = useConfirmation({ disabled: request => busy || (locked && request.variant === 'destructive'), error });
  const receiveFrom = useCallback(value => { setFrom(value); setForm(current => ({ ...current, confirmed: false })); }, []);
  const receiveTo = useCallback(value => { setTo(value); setForm(current => ({ ...current, confirmed: false })); }, []);
  useEffect(() => { onDirtyChange(touched); }, [touched, onDirtyChange]);
  useEffect(() => { onSavingChange(saving); }, [saving, onSavingChange]);
  useEffect(() => () => { saveController.current?.abort(); onDirtyChange(false); onSavingChange(false); }, [onDirtyChange, onSavingChange]);
  useEffect(() => {
    const controller = new AbortController();
    Promise.all([floorPlanRequest(`${basePath}?limit=10&offset=${offset}`, { signal: controller.signal }), floorPlanRequest('', { signal: controller.signal })]).then(([records, structure]) => {
      if (controller.signal.aborted) return;
      setListing(records); setLevels(structure.levels); setLoading(false);
    }).catch(failure => { if (!controller.signal.aborted) { setError(failure.message); setLoading(false); } });
    return () => controller.abort();
  }, [offset, refreshKey]);
  function reset() {
    setForm(initialRampForm()); setEditing(null); setTouched(false); setFrom(null); setTo(null); setEndpointKey(value => value + 1);
  }
  function change(key, value) {
    setForm(current => ({ ...current, [key]: value, confirmed: key === 'confirmed' ? value : false })); setTouched(true); setMessage('');
  }
  function changeLevel(side, value) {
    setForm(current => ({ ...current, [`${side}_level_id`]: value, [`${side}_node_id`]: '', confirmed: false }));
    if (side === 'from') setFrom(null); else setTo(null);
    setTouched(true); setMessage('');
  }
  function refresh(nextOffset = 0, confirmed = false) {
    if (touched && confirmed !== true) return requestConfirmation({ title: 'Discard Ramp Changes?', description: 'Unsaved ramp changes will be discarded when you refresh.', variant: 'warning', confirmLabel: 'Discard and Refresh' }, () => refresh(nextOffset, true));
    reset(); setLoading(true); setListing(null); setLocked(false); setError(''); setMessage(''); setOffset(nextOffset); setRefreshKey(value => value + 1);
  }
  function edit(edge, confirmed = false) {
    if (touched && confirmed !== true) return requestConfirmation({ title: 'Discard Ramp Changes?', description: 'Unsaved ramp changes will be discarded before you review this connection.', variant: 'warning', confirmLabel: 'Discard and Review' }, () => edit(edge, true));
    setFrom(null); setTo(null); setEndpointKey(value => value + 1); setEditing(edge); setTouched(false); setError(''); setMessage('');
    setForm({ from_level_id: edge.from_level_id, from_node_id: edge.from_node_id, to_level_id: edge.to_level_id, to_node_id: edge.to_node_id,
      direction: edge.reverse_edge ? 'two' : 'one', forward_trace: traceFromEdge(edge), reverse_trace: traceFromEdge(edge.reverse_edge), confirmed: false });
  }
  async function submit(batch) {
    setSaving(true); setError(''); setMessage('');
    const controller = new AbortController(); saveController.current = controller;
    try {
      await floorPlanRequest(basePath, { method: 'PUT', signal: controller.signal, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(batch) });
      if (controller.signal.aborted) return;
      reset(); setMessage(batch.upserts.length ? 'Successfully saved and revalidated the traced ramp connections!' : 'Ramp connection has been deleted!');
      setLoading(true); setOffset(0); setRefreshKey(value => value + 1);
    } catch (failure) {
      if (!controller.signal.aborted) { setError(failure.message); setLocked(failure.status === 409 || !failure.status || failure.status >= 500); }
      return false;
    } finally { if (!controller.signal.aborted) setSaving(false); }
  }
  function save(event) {
    event.preventDefault();
    if (busy || locked) return;
    try { const batch = buildRampBatch(form, from, to, editing); submit(batch); }
    catch (failure) { setError(failure.message); }
  }
  function remove(edge, both = false, confirmed = false) {
    if (busy || locked) return false;
    if (confirmed !== true) return requestConfirmation({ title: both ? 'Delete Both Ramp Directions?' : 'Delete Ramp Direction?', description: `${touched ? 'Unsaved ramp changes will be discarded. ' : ''}${both ? 'Both travel directions' : 'Only this travel direction'} will be deleted.`, variant: 'destructive', confirmLabel: both ? 'Delete Both Directions' : 'Delete Direction' }, () => remove(edge, both, true));
    const records = [edge, ...(both && edge.reverse_edge ? [edge.reverse_edge] : [])];
    return submit({ upserts: [], deletes: records.map(item => ({ id: item.id, expected_revision: item.revision })), confirm_measurement: false });
  }
  function cancelChanges(confirmed = false) {
    if (touched && confirmed !== true) return requestConfirmation({ title: 'Discard Ramp Changes?', description: 'Your unsaved ramp changes will be discarded.', variant: 'warning', confirmLabel: 'Discard Changes' }, () => cancelChanges(true));
    reset(); if (!locked) setError('');
  }
  const start = from?.draft?.nodes.find(node => node.id === form.from_node_id && node.node_type === 'ramp');
  const end = to?.draft?.nodes.find(node => node.id === form.to_node_id && node.node_type === 'ramp');
  const sourceLabel = rampLabel(start?.code ?? 'Select source ramp', levels.find(item => item.id === form.from_level_id)?.name);
  const destinationLabel = rampLabel(end?.code ?? 'Select destination ramp', levels.find(item => item.id === form.to_level_id)?.name);
  return <section className={map.section} aria-label="Configure Multi-Level Ramps" aria-busy={busy}>
    <div className={map.heading}><h2>Configure Multi-Level Ramps</h2><RefreshButton label="Refresh Ramps" loading={loading} disabled={busy} onClick={() => refresh()} /></div>
    <p className={map.note}>Connect the saved ramp nodes on different levels using calibrated path traces.</p>
    {error && <p className={map.error} role="alert">{error}{locked ? ' Refresh before retrying. Local edits are retained until you confirm discarding them.' : ''}</p>}
    {message && <SuccessNotice>{message}</SuccessNotice>}
    <form className={styles.form} onSubmit={save}>
      <h3>{editing ? editing.requires_review || editing.reverse_edge?.requires_review ? 'Review and Reconfirm Ramp' : 'Edit Ramp Connection' : 'New Ramp Connection'}</h3>
      {editing && <p className={map.note}>Saved: {rampLabel(editing.from_node_code, editing.from_level_name)} to {rampLabel(editing.to_node_code, editing.to_level_name)}</p>}
      {editing?.requires_review && <ul className={fields.warning}>{editing.review_reasons.map(reason => <li key={reason}>{reviewLabels[reason]}</li>)}</ul>}
      {editing?.reverse_edge?.requires_review && <div className={fields.warning}><p>Reverse direction needs review:</p><ul>{editing.reverse_edge.review_reasons.map(reason => <li key={reason}>{reviewLabels[reason]}</li>)}</ul></div>}
      <div className={styles.endpointGrid}>
        <RampEndpoint key={`from-${form.from_level_id}-${endpointKey}-${levels.find(item => item.id === form.from_level_id)?.floor_plan?.revision}`} label="Source" levelId={form.from_level_id} nodeId={form.from_node_id} levels={levels} excluded={form.to_level_id}
          disabled={busy || locked} onLevel={value => changeLevel('from', value)} onNode={value => change('from_node_id', value)} onSnapshot={receiveFrom} />
        <RampEndpoint key={`to-${form.to_level_id}-${endpointKey}-${levels.find(item => item.id === form.to_level_id)?.floor_plan?.revision}`} label="Destination" levelId={form.to_level_id} nodeId={form.to_node_id} levels={levels} excluded={form.from_level_id}
          disabled={busy || locked} onLevel={value => changeLevel('to', value)} onNode={value => change('to_node_id', value)} onSnapshot={receiveTo} />
      </div>
      <div className={fields.details}>
        <label className={fields.field}>Travel Direction<select value={form.direction} disabled={busy || locked} onChange={event => change('direction', event.target.value)}><option value="one">One-Way</option><option value="two">Two-Way</option></select></label>
      </div>
      <RampTraceEditor label="Source to Destination Path" connectionSummary={`${sourceLabel} to ${destinationLabel}${form.direction === 'two' ? ' · Two-Way' : ''}`} levels={levels} trace={form.forward_trace} onChange={value => change('forward_trace', value)} disabled={busy || locked} refreshKey={endpointKey} />
      {form.direction === 'two' && <>
        <p className={map.note}>Trace the reverse driving lane separately. Ascending and descending ramps may follow different paths.</p>
        <RampTraceEditor label="Destination to Source Path" connectionSummary={`${destinationLabel} to ${sourceLabel} · Two-Way`} levels={levels} trace={form.reverse_trace} onChange={value => change('reverse_trace', value)} disabled={busy || locked} refreshKey={endpointKey} />
      </>}
      {editing?.reverse_edge && form.direction === 'one' && <p className={fields.warning}>Saving one-way will remove the existing reverse direction in the same operation.</p>}
      <label className={styles.checkbox}><input type="checkbox" checked={form.confirmed} disabled={busy || locked || !start || !end} onChange={event => change('confirmed', event.target.checked)} /><span>I have checked the ramp endpoints and confirm the traced path(s).</span></label>
      <div className={map.toolbar}>
        <button className={`${map.button} ${map.primary}`} disabled={busy || locked || !start || !end || !form.confirmed}>{saving ? 'Saving…' : editing?.requires_review || editing?.reverse_edge?.requires_review ? 'Reconfirm Traced Ramp' : 'Save Traced Ramp'}</button>
        <button type="button" className={map.button} disabled={busy} onClick={cancelChanges}>Cancel</button>
        {editing?.reverse_edge && <button type="button" className={styles.deleteAction} disabled={busy || locked} onClick={() => remove(editing, true)}>Delete Both Directions</button>}
        {touched && <span className={map.note} role="status">Unsaved Ramp Changes</span>}
      </div>
    </form>
    <h3>Saved Ramp Directions</h3>
    {loading ? <p className={map.note} role="status">Loading ramp connections…</p> : !listing ? <p className={map.note}>Ramp connections could not be loaded. Use refresh to retry.</p> : listing.edges.length === 0 ?
      <p className={map.note}>{offset ? 'No ramp connections on this page. Return to the previous page.' : 'No cross-level ramp connections have been saved.'}</p> :
      <div className={styles.savedGrid}>{listing.edges.map(edge => <article className={styles.card} key={edge.id}>
        <div className={styles.cardHeading}><h4>{rampLabel(edge.from_node_code, edge.from_level_name)} to {rampLabel(edge.to_node_code, edge.to_level_name)}</h4><span className={edge.requires_review ? styles.review : styles.ready}>{edge.requires_review ? 'Needs Review' : 'Current'}</span></div>
        <div className={styles.distance}><span>Estimated horizontal distance</span><strong>{metres(edge.distance_meters)}</strong></div>
        {edge.requires_review && <ul className={styles.reasons}>{edge.review_reasons.map(reason => <li key={reason}>{reviewLabels[reason]}</li>)}</ul>}
        {edge.reverse_edge && <p className={map.note}>Reverse direction: {metres(edge.reverse_edge.distance_meters)}{edge.reverse_edge.requires_review ? ' · Needs review' : ''}</p>}
        <details className={styles.measurementDetails}>
          <summary>Measurement Details</summary>
          <dl>
            <div><dt>Reference Floor Plan</dt><dd>{levels.find(level => level.id === edge.reference_level_id)?.name ?? 'Unavailable level'}</dd></div>
            <div><dt>Saved Revisions</dt><dd>Image {edge.reference_floor_plan_revision} · Calibration {edge.reference_calibration_revision} · Connection {edge.revision}</dd></div>
            <div><dt>Trace Points</dt><dd>{edge.trace_points.length}</dd></div>
          </dl>
        </details>
        <div className={map.toolbar}><button type="button" className={styles.editAction} disabled={busy || locked} onClick={() => edit(edge)}>{edge.requires_review || edge.reverse_edge?.requires_review ? 'Review or Reconfirm' : 'Edit'}</button>
          <button type="button" className={styles.deleteAction} disabled={busy || locked} onClick={() => remove(edge)}>Delete Direction</button></div>
      </article>)}</div>}
    <nav className={map.toolbar} aria-label="Ramp Connection Pagination"><span className={map.note}>Page {Math.floor(offset / 10) + 1} · {listing?.total ?? '—'} Directions</span>
      <button className={map.button} disabled={busy || offset === 0 || locked} onClick={() => refresh(Math.max(0, offset - 10))}>Previous</button>
      <button className={map.button} disabled={busy || !listing || offset + listing.edges.length >= listing.total || locked} onClick={() => refresh(offset + 10)}>Next</button></nav>
    {confirmationDialog}
  </section>;
}
