'use client';
import { useEffect, useReducer, useRef, useState } from 'react';
import useConfirmation from '../../../components/use-confirmation';
import { fileError, floorPlanRequest, floorPlanState, initialState, selectedLevelId } from './floor-plans-client.mjs';
import styles from './parking-structure.module.css';
import Calibration from './calibration';
import NodeEditor from './node-editor';
import EdgeEditor from './edge-editor';
import CrossLevelRamps from './cross-level-ramps';
import LevelManagement from './level-management';
import ZoneDrafts from './zone-drafts';
import StructureValidation from './structure-validation';
import FloorPlanWorkspace from './floor-plan-workspace';

export default function FloorPlans() {
  const [state, dispatch] = useReducer(floorPlanState, initialState);
  const [selected, setSelected] = useState('');
  const [revision, setRevision] = useState(0);
  const [file, setFile] = useState(null);
  const [editor, setEditor] = useState('calibration');
  const [nodeDirty, setNodeDirty] = useState(false);
  const [nodeSaving, setNodeSaving] = useState(false);
  const [calEditing, setCalEditing] = useState(false);
  const [levelDirty, setLevelDirty] = useState(false), [levelSaving, setLevelSaving] = useState(false);
  const [zoneDirty, setZoneDirty] = useState(false), [zoneSaving, setZoneSaving] = useState(false);
  const [publishing,setPublishing]=useState(false);
  const input = useRef(null);
  const uploadController = useRef(null);
  useEffect(() => () => uploadController.current?.abort(), []);
  useEffect(() => {
    if (!nodeDirty && !levelDirty && !zoneDirty) return;
    function warn(event) { event.preventDefault(); event.returnValue = ''; }
    window.addEventListener('beforeunload', warn);
    return () => window.removeEventListener('beforeunload', warn);
  }, [nodeDirty, levelDirty, zoneDirty]);
  useEffect(() => {
    const controller = new AbortController();
    floorPlanRequest('', { signal: controller.signal }).then(data => {
      if (controller.signal.aborted) return;
      dispatch({ type: 'loaded', levels: data.levels });
      setSelected(value => selectedLevelId(data.levels, value));
    }).catch(error => {
      if (!controller.signal.aborted) dispatch({ type: 'error', message: error.message });
    });
    return () => controller.abort();
  }, [revision]);
  function refresh(discardConfirmed = false) {
    if (discardConfirmed !== true && (nodeDirty || levelDirty || zoneDirty)) return requestConfirmation({ title: 'Discard Unsaved Changes?', description: 'Unsaved parking configuration changes will be discarded when you refresh.', variant: 'warning', confirmLabel: 'Discard and Refresh' }, () => refresh(true));
    dispatch({ type: 'loading' }); setFile(null); setRevision(value => value + 1);
  }
  const level = state.levels.find(item => item.id === selected);
  const plan = level?.floor_plan;
  const draftBusy = state.loading || state.uploading || nodeSaving || levelSaving || zoneSaving;
  const busy = draftBusy || publishing;
  const { requestConfirmation, confirmationDialog } = useConfirmation({ disabled: busy || calEditing, error: state.error });
  function levelsSaved(message) {
    dispatch({ type: 'levels_saved', message }); refresh(true);
  }
  async function upload(event, confirmed = false) {
    event.preventDefault();
    const message = fileError(file);
    if (message) { dispatch({ type: 'error', message }); return; }
    if (!level || busy || calEditing || levelDirty || zoneDirty || state.conflict) return;
    if (nodeDirty && confirmed !== true) return requestConfirmation({ title: 'Replace Floor Plan?', description: 'Replacing the image will discard unsaved draft changes.', variant: 'warning', confirmLabel: 'Replace Floor Plan' }, () => upload(event, true));
    dispatch({ type: 'uploading' });
    const controller = new AbortController();
    uploadController.current = controller;
    try {
      await floorPlanRequest(`/levels/${level.id}?expected_revision=${plan?.revision ?? 0}`, {
        method: 'PUT', body: file, headers: { 'Content-Type': file.type }, signal: controller.signal,
      });
      if (controller.signal.aborted) return;
      setFile(null); input.current.value = '';
      dispatch({ type: 'saved' }); refresh(true);
    } catch (error) {
      if (!controller.signal.aborted) dispatch({ type: 'error', message: error.message, status: error.status });
      return false;
    }
  }
  function switchLevel(value, confirmed = false) {
    if (nodeDirty && confirmed !== true) return requestConfirmation({ title: 'Discard Draft Changes?', description: 'Unsaved draft changes will be discarded when you switch levels.', variant: 'warning', confirmLabel: 'Discard and Switch' }, () => switchLevel(value, true));
    setSelected(value); setFile(null); if (input.current) input.current.value = '';
  }
  function switchEditor(value, confirmed = false) {
    if (editor === value) return;
    if (nodeDirty && confirmed !== true) return requestConfirmation({ title: 'Discard Draft Changes?', description: 'Unsaved draft changes will be discarded when you switch editing modes.', variant: 'warning', confirmLabel: 'Discard and Switch' }, () => switchEditor(value, true));
    setEditor(value);
  }
  return <div className={styles.page}>
    <div className={styles.heading}><div><h1>Parking Structure</h1><p>Manage parking levels, floor plans and draft navigation.</p></div>
      <button className={styles.button} disabled={busy || calEditing} onClick={refresh}>Refresh</button></div>
    {state.success && <p className={styles.success} role="status">{state.success}</p>}
    {state.error && <div className={styles.error} role="alert"><p>{state.error}</p><button className={styles.button} onClick={refresh} disabled={busy}>{state.conflict ? 'Refresh Latest Version' : 'Try Again'}</button></div>}
    {nodeDirty || calEditing ? <p className={styles.note}>Save or discard current floor-plan edits before managing levels or zones.</p> : null}
    <StructureValidation key={`validation-${revision}`} levels={state.levels} disabled={draftBusy || nodeDirty || calEditing || levelDirty || zoneDirty || Boolean(state.error)} publishing={publishing} onPublishingChange={setPublishing} onPublished={levelsSaved} />
    <LevelManagement key={`levels-${revision}`} levels={state.levels} disabled={busy || nodeDirty || calEditing || zoneDirty || Boolean(state.error)} onSaved={levelsSaved} onDirtyChange={setLevelDirty} onSavingChange={setLevelSaving} />
    <ZoneDrafts key={`zones-${selected}-${revision}`} levels={state.levels} levelId={selected} onLevelChange={value => {
      setSelected(value); setFile(null); if (input.current) input.current.value = '';
    }} disabled={busy || nodeDirty || calEditing || levelDirty || Boolean(state.error)} onDirtyChange={setZoneDirty} onSavingChange={setZoneSaving} />
    {state.loading ? <section className={styles.panel} role="status">Loading parking levels…</section> :
      state.levels.length === 0 ? !state.error && <section className={styles.panel}>No parking levels available.</section> :
      <FloorPlanWorkspace busy={state.uploading}>
        {editor !== 'ramps' && <label className={styles.field}>Parking Level<select value={selected} disabled={busy || calEditing || levelDirty || zoneDirty} onChange={event => switchLevel(event.target.value)}>{state.levels.map(item => <option key={item.id} value={item.id}>{item.name}{item.is_active ? '' : ' (Inactive)'}</option>)}</select></label>}
        <div className={styles.editorModes} aria-label="Floor Plan Editing Mode">
          {[['calibration', 'Calibration'], ['nodes', 'Add Nodes'], ['edges', 'Add Edges'], ['ramps', 'Configure Multi-Level Ramps']].map(([value, label]) => <button key={value}
            className={styles.button} aria-pressed={editor === value} disabled={busy || calEditing || levelDirty || zoneDirty} onClick={() => switchEditor(value)}>{label}</button>)}
        </div>
        {calEditing && <p className={styles.note}>Save or cancel calibration before switching modes</p>}
        {editor === 'ramps' ? <CrossLevelRamps key={`ramps-${revision}`} levels={state.levels} disabled={busy || levelDirty || zoneDirty} onDirtyChange={setNodeDirty} onSavingChange={setNodeSaving} /> : plan ? editor === 'edges' ?
          <EdgeEditor key={`edges-${selected}-${plan.revision}-${revision}`} level={level} plan={plan} disabled={busy || levelDirty || zoneDirty} refreshKey={revision} onDirtyChange={setNodeDirty} onSavingChange={setNodeSaving} /> : editor === 'nodes' ?
          <NodeEditor key={`nodes-${selected}-${plan.revision}-${revision}`} level={level} plan={plan} disabled={busy || levelDirty || zoneDirty} refreshKey={revision} onDirtyChange={setNodeDirty} onSavingChange={setNodeSaving} /> :
          <Calibration key={`${selected}-${plan.revision}-${revision}`} level={level} plan={plan} disabled={busy || levelDirty || zoneDirty} refreshKey={revision} onEditingChange={setCalEditing} /> :
          <div className={styles.preview}><p>No floor plan uploaded for this level.</p></div>}
        {editor !== 'ramps' && plan && <p className={styles.note}>{plan.width_px} × {plan.height_px} Pixels · Revision {plan.revision}</p>}
        {editor !== 'ramps' && <form onSubmit={upload} className={styles.upload}>
          <label className={styles.field}>Floor Plan Image<input ref={input} type="file" accept="image/png,image/jpeg" disabled={busy || calEditing || levelDirty || zoneDirty || state.conflict} onChange={event => {
            const next = event.target.files?.[0] ?? null; setFile(next);
            const message = fileError(next);
            if (message) dispatch({ type: 'error', message });
          }} /></label>
          <button className={`${styles.button} ${styles.primary}`} disabled={busy || calEditing || levelDirty || zoneDirty || !file || Boolean(fileError(file)) || state.conflict}>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false">
              <path d="M12 16V3m-5 5 5-5 5 5M4 15v5a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-5" />
            </svg>
            {state.uploading ? 'Uploading…' : plan ? 'Replace Floor Plan' : 'Upload Floor Plan'}
          </button>
        </form>}
      </FloorPlanWorkspace>}
    {confirmationDialog}
  </div>;
}
