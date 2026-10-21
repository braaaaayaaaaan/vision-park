'use client';
import { useEffect, useRef, useState } from 'react';
import { floorPlanRequest } from './floor-plans-client.mjs';
import { levelRowsError, levelSnapshot, MAX_LEVEL_BATCH, MAX_LEVEL_NUMBER, MIN_LEVEL_NUMBER, previewLevels, validLevelSnapshot } from './level-management-utils.mjs';
import shared from './parking-structure.module.css';
import styles from './level-management.module.css';

export default function LevelManagement({ levels, disabled, onSaved, onDirtyChange, onSavingChange }) {
  const [mode, setMode] = useState(null), [editing, setEditing] = useState(null), [rows, setRows] = useState([]), [count, setCount] = useState('3');
  const [confirmed, setConfirmed] = useState(false), [saving, setSaving] = useState(false), [locked, setLocked] = useState(false), [error, setError] = useState('');
  const controller = useRef(null);
  const deleteDialog = useRef(null), deleting = useRef(false);
  const busy = disabled || saving;
  useEffect(() => { onDirtyChange(Boolean(mode)); }, [mode, onDirtyChange]);
  useEffect(() => { onSavingChange(saving); }, [saving, onSavingChange]);
  useEffect(() => () => { controller.current?.abort(); onDirtyChange(false); onSavingChange(false); }, [onDirtyChange, onSavingChange]);
  useEffect(() => {
    if (mode !== 'delete') return;
    const dialog = deleteDialog.current;
    dialog.showModal();
    return () => dialog.close();
  }, [mode]);
  function begin(nextMode, level = null) {
    if (mode && !window.confirm('Discard Unsaved Level Details?')) return;
    setError(''); setConfirmed(false); setMode(nextMode); setEditing(level); setCount('3');
    if (level) setRows([{ level_number: String(level.level_number), name: level.name }]);
    else if (nextMode === 'bulk') setRows([]);
    else { try { setRows(previewLevels(1, levels)); } catch { setRows([{ level_number: '', name: '' }]); } }
  }
  function preview() {
    try {
      if (rows.length && !window.confirm('Replace The Current Preview?')) return;
      setRows(previewLevels(Number(count), levels)); setConfirmed(false); setError('');
    } catch (failure) { setError(failure.message); }
  }
  function change(index, key, value) {
    setRows(current => current.map((row, position) => position === index ? { ...row, [key]: value } : row)); setConfirmed(false);
  }
  const validation = rows.length ? levelRowsError(rows, levels, editing?.id) : '';
  const previewOutdated = mode === 'bulk' && rows.length !== Number(count);
  async function save(event) {
    event.preventDefault();
    if (busy || locked || !rows.length || validation || previewOutdated || (mode === 'bulk' && !confirmed)) return;
    if (editing && !validLevelSnapshot(editing)) { setError('Refresh The Level List Before Editing.'); return; }
    if (editing && !window.confirm('Save These Level Details? Existing Reports Will Use The Updated Name.')) return;
    const parsed = rows.map(row => ({ level_number: Number(row.level_number), name: row.name.trim() }));
    const path = mode === 'bulk' ? '/levels/bulk' : editing ? `/levels/${editing.id}` : '/levels';
    const body = mode === 'bulk' ? { levels: parsed } : editing ? { ...parsed[0], expected: levelSnapshot(editing) } : parsed[0];
    const pending = new AbortController(); controller.current = pending;
    setSaving(true); setError('');
    try {
      await floorPlanRequest(path, { method: editing ? 'PATCH' : 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal: pending.signal });
      if (!pending.signal.aborted) onSaved(editing ? 'Level Details Saved.' : `${parsed.length === 1 ? 'Level' : `${parsed.length} Levels`} Created.`);
    } catch (failure) {
      if (!pending.signal.aborted) { setError(failure.message); setLocked(failure.status === 409 || !failure.status || failure.status >= 500); }
    } finally { if (!pending.signal.aborted) setSaving(false); }
  }
  function closeDelete() {
    if (deleting.current) return;
    setMode(null); setEditing(null); setRows([]); if (!locked) setError('');
  }
  async function remove(event) {
    event.preventDefault();
    if (busy || locked || deleting.current || !editing || editing.is_active || !validLevelSnapshot(editing)) return;
    deleting.current = true;
    const pending = new AbortController(); controller.current = pending;
    setSaving(true); setError('');
    try {
      const result = await floorPlanRequest(`/levels/${editing.id}`, { method: 'DELETE', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ expected_metadata_revision: editing.metadata_revision }), signal: pending.signal });
      if (result.deleted_level_id !== editing.id) throw new Error('Level Deletion Could Not Be Confirmed. Refresh Before Retrying.');
      if (!pending.signal.aborted) onSaved('Parking level has been deleted.');
    } catch (failure) {
      if (!pending.signal.aborted) { setError(failure.message); setLocked(failure.status === 404 || failure.status === 409 || !failure.status || failure.status >= 500); }
    } finally {
      deleting.current = false;
      if (!pending.signal.aborted) setSaving(false);
    }
  }
  return <section className={`${shared.panel} ${styles.section}`} aria-label="Parking Levels" aria-busy={saving}>
    <div className={styles.heading}><div><h2>Parking Levels</h2><p className={shared.note}></p></div>
      <div className={styles.actions}>
        <button type="button" className={shared.button} disabled={busy || locked} onClick={() => begin('create')}>Add Level</button>
        <button type="button" className={shared.button} disabled={busy || locked} onClick={() => begin('bulk')}>Add Multiple Levels</button>
      </div>
    </div>
    {levels.length === 0 ? <p className={shared.note}>No parking levels yet. Add one level or preview multiple levels to get started.</p> :
      <div className={styles.tableScroll}><table className={styles.table}><caption className={styles.srOnly}>Configured Parking Levels</caption>
        <thead><tr><th>Level Number</th><th>Level Name</th><th>Status</th><th>Actions</th></tr></thead>
        <tbody>{levels.map(level => <tr key={level.id}><td>{level.level_number}</td><td>{level.name}</td><td>{level.is_active ? 'Active' : 'Inactive'}</td>
          <td><div className={styles.actions}><button type="button" className={styles.edit} disabled={busy || locked || !validLevelSnapshot(level)} onClick={() => begin('edit', level)}>Edit<span className={styles.srOnly}> {level.name}</span></button>
            {!level.is_active && !level.floor_plan && <button type="button" className={styles.delete} disabled={busy || locked || !validLevelSnapshot(level)} onClick={() => begin('delete', level)}>Delete<span className={styles.srOnly}> {level.name}</span></button>}
          </div></td></tr>)}</tbody>
      </table></div>}
    {error && mode !== 'delete' && <p className={shared.error} role="alert">{error}{locked ? ' Refresh to load the current levels before retrying.' : ''}</p>}
    {mode === 'delete' && editing && <dialog ref={deleteDialog} className={styles.dialog} aria-labelledby="delete-level-title" aria-describedby="delete-level-description"
      onCancel={event => { event.preventDefault(); closeDelete(); }}>
      <form onSubmit={remove} aria-busy={saving}>
        <h2 id="delete-level-title">Delete Parking Level?</h2>
        <p><strong>{editing.name}</strong> · Level Number {editing.level_number}</p>
        <p id="delete-level-description">Deletion Is Permanent. Only An Inactive Level With No Associated Records Can Be Deleted.</p>
        {error && <p className={shared.error} role="alert">{error}{locked ? ' Close And Refresh The Level List Before Retrying.' : ''}</p>}
        {saving && <p role="status">Waiting For Deletion Confirmation…</p>}
        <div className={styles.actions}>
          <button type="button" className={shared.button} disabled={saving} onClick={closeDelete}>{locked ? 'Close' : 'Cancel'}</button>
          <button type="submit" className={styles.delete} disabled={busy || locked}>{saving ? 'Deleting…' : 'Delete Level Permanently'}</button>
        </div>
      </form>
    </dialog>}
    {mode && mode !== 'delete' && <form onSubmit={save} className={styles.form}>
      <h3>{mode === 'bulk' ? 'Add Multiple Levels' : editing ? 'Edit Level' : 'Add Level'}</h3>
      {mode === 'bulk' && <div className={styles.actions}>
        <label className={shared.field}>Number Of Levels<input type="number" min="1" max={MAX_LEVEL_BATCH} step="1" value={count} disabled={busy || locked} onChange={event => { setCount(event.target.value); setConfirmed(false); }} /></label>
        <button type="button" className={shared.button} disabled={busy || locked} onClick={preview}>Generate Preview</button>
      </div>}
      {rows.length > 0 && <div className={styles.rows}>{rows.map((row, index) => <div className={styles.row} key={index}>
        <label className={shared.field}>Level Number{mode === 'bulk' ? ` ${index + 1}` : ''}<input type="number" step="1" min={MIN_LEVEL_NUMBER} max={MAX_LEVEL_NUMBER} required value={row.level_number} disabled={busy || locked} onChange={event => change(index, 'level_number', event.target.value)} /></label>
        <label className={shared.field}>Level Name{mode === 'bulk' ? ` ${index + 1}` : ''}<input type="text" required value={row.name} disabled={busy || locked} onChange={event => change(index, 'name', event.target.value)} /></label>
      </div>)}</div>}
      {validation && <p className={shared.error} role="status">{validation}</p>}
      {previewOutdated && <p className={shared.note}>Generate A New Preview For The Requested Number Of Levels.</p>}
      {mode === 'bulk' && rows.length > 0 && <label className={styles.confirm}><input type="checkbox" checked={confirmed} disabled={busy || locked || Boolean(validation) || previewOutdated} onChange={event => setConfirmed(event.target.checked)} />I have reviewed these {rows.length} new levels.</label>}
      <div className={styles.actions}>
        <button className={`${shared.button} ${shared.primary}`} disabled={busy || locked || !rows.length || Boolean(validation) || previewOutdated || (mode === 'bulk' && !confirmed)}>{saving ? 'Saving…' : editing ? 'Save Changes' : mode === 'bulk' ? 'Create All Levels' : 'Create Level'}</button>
        <button type="button" className={shared.button} disabled={saving} onClick={() => { if (window.confirm('Discard Unsaved Level Details?')) { setMode(null); setRows([]); setEditing(null); if (!locked) setError(''); } }}>Cancel</button>
      </div>
    </form>}
  </section>;
}
