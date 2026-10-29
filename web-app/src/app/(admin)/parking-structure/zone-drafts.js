'use client';
import RefreshButton from '../../../components/refresh-button';
import { useEffect, useRef, useState } from 'react';
import useConfirmation from '../../../components/use-confirmation';
import { floorPlanRequest } from './floor-plans-client.mjs';
import { MAX_CAPACITY, ZONE_STATUSES, zoneError } from './zone-draft-utils.mjs';
import shared from './parking-structure.module.css';
import layout from './level-management.module.css';
import styles from './zone-drafts.module.css';

const emptyForm = { code: '', name: '', total_capacity: '0', unavailable_capacity: '0', operational_status: 'open' };
const label = status => ({ open: 'Open', closed: 'Closed', maintenance: 'Maintenance' })[status];
export default function ZoneDrafts({ levels, levelId, onLevelChange, disabled, onDirtyChange, onSavingChange }) {
  const [data, setData] = useState(null), [form, setForm] = useState(null), [editing, setEditing] = useState(null);
  const [saving, setSaving] = useState(false), [locked, setLocked] = useState(false), [error, setError] = useState('');
  const [message, setMessage] = useState(''), [attempt, setAttempt] = useState(0);
  const pending = useRef(null), inFlight = useRef(false);
  const loading = Boolean(levelId) && !data && !error;
  const busy = disabled || saving || loading;
  const { requestConfirmation, confirmationDialog } = useConfirmation({ disabled: request => busy || (locked && request.variant === 'destructive'), error });
  const path = `/levels/${levelId}/zone-drafts`;
  useEffect(() => { onDirtyChange(Boolean(form)); }, [form, onDirtyChange]);
  useEffect(() => { onSavingChange(saving); }, [saving, onSavingChange]);
  useEffect(() => () => { pending.current?.abort(); onDirtyChange(false); onSavingChange(false); }, [onDirtyChange, onSavingChange]);
  useEffect(() => {
    if (!levelId) return;
    const controller = new AbortController();
    floorPlanRequest(path, { signal: controller.signal }).then(result => {
      if (!controller.signal.aborted) { setData(result); setError(''); setLocked(false); }
    }).catch(failure => { if (!controller.signal.aborted) { setError(failure.message); setLocked(true); } });
    return () => controller.abort();
  }, [levelId, path, attempt]);
  function reload(confirmed = false) {
    if (form && confirmed !== true) return requestConfirmation({ title: 'Discard Zone Changes?', description: 'Unsaved zone details will be discarded when you refresh.', variant: 'warning', confirmLabel: 'Discard and Refresh' }, () => reload(true));
    setForm(null); setEditing(null); setData(null); setError(''); setMessage(''); setAttempt(value => value + 1);
  }
  function begin(zone = null) {
    setEditing(zone); setMessage(''); setError('');
    setForm(zone ? { code: zone.code, name: zone.name, total_capacity: String(zone.total_capacity),
      unavailable_capacity: String(zone.unavailable_capacity), operational_status: zone.operational_status } : { ...emptyForm });
  }
  const values = form && { ...form, total_capacity: form.total_capacity === '' ? NaN : Number(form.total_capacity),
    unavailable_capacity: form.unavailable_capacity === '' ? NaN : Number(form.unavailable_capacity) };
  const validation = values ? zoneError(values) || (data?.zones.some(zone => zone.id !== editing?.id && zone.code === values.code.trim()) ? 'This zone code is already used on this level.' : '') : '';
  async function mutate(method, zone, body) {
    if (busy || locked || inFlight.current) return false;
    inFlight.current = true;
    const controller = new AbortController(); pending.current = controller;
    setSaving(true); setError(''); setMessage('');
    try {
      await floorPlanRequest(`${path}${zone ? `/${zone.id}` : ''}`, { method, headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body), signal: controller.signal });
      if (!controller.signal.aborted) {
        setForm(null); setEditing(null); setData(null); setAttempt(value => value + 1);
        setMessage(method === 'DELETE' ? 'Draft zone deleted.' : 'Draft zone has been successfully saved!');
      }
    } catch (failure) {
      if (!controller.signal.aborted) { setError(failure.message); setLocked([404, 409].includes(failure.status) || !failure.status || failure.status >= 500); }
      return false;
    } finally { inFlight.current = false; if (!controller.signal.aborted) setSaving(false); }
  }
  function save(event) {
    event.preventDefault();
    if (!values || validation) return;
    mutate(editing ? 'PATCH' : 'POST', editing, { ...values, code: values.code.trim(), name: values.name.trim(), ...(editing ? { expected_revision: editing.revision } : {}) });
  }
  function remove(zone, confirmed = false) {
    if (confirmed !== true) return requestConfirmation({ title: 'Delete Draft Zone?', description: `Delete draft zone "${zone.name}" (${zone.code})? This does not delete an operational zone.`, variant: 'destructive', confirmLabel: 'Delete Zone' }, () => remove(zone, true));
    return mutate('DELETE', zone, { expected_revision: zone.revision });
  }
  return <section id="parking-zones" className={`${shared.panel} ${layout.section}`} aria-label="Parking Zones" aria-busy={saving || loading}>
    <div className={layout.heading}><div><h2>Parking Zones</h2></div>
      <div className={layout.actions}>
        <button type="button" className={shared.button} disabled={busy || locked || !levelId || Boolean(form) || !data || data.zones.length >= 1000} onClick={() => begin()}>Add Zone</button>
        <RefreshButton label="Refresh Zones" disabled={disabled || saving || !levelId} onClick={reload} />
      </div>
    </div>
    <label className={shared.field}>Parking Level<select value={levelId} disabled={disabled || saving || Boolean(form)} onChange={event => onLevelChange(event.target.value)}>
      {levels.length === 0 && <option value="">No parking levels available</option>}
      {levels.map(level => <option value={level.id} key={level.id}>{level.name}{level.is_active ? '' : ' (Inactive)'}</option>)}
    </select></label>
    {!levelId ? <p className={shared.note}>Add a parking level to configure zones.</p> : loading ? <p role="status">Loading draft zones…</p> : null}
    {message && <p className={shared.success} role="status">{message}</p>}
    {error && <p className={shared.error} role="alert">{error}{locked ? ' Refresh zones to load current data before retrying.' : ''}</p>}
    {data && <>
      <div className={styles.summary} aria-label="Draft Level Capacity">
        <div><span>Configured capacity</span><strong>{data.total_capacity.toLocaleString('en-MY')}</strong></div>
        <div><span>Unavailable capacity</span><strong>{data.unavailable_capacity.toLocaleString('en-MY')}</strong></div>
        <div><span>Draft {data.zones.length === 1 ? 'Zone' : 'Zones'}</span><strong>{data.zones.length.toLocaleString('en-MY')}</strong></div>
      </div>
      {data.zones.length === 0 ? <p className={shared.note}>There are no zones for this level yet.</p> :
        <div className={layout.tableScroll}><table className={layout.table}><caption className={layout.srOnly}>Draft Parking Zones</caption>
          <thead><tr><th>Code</th><th>Zone Name</th><th>Total Capacity</th><th>Unavailable</th><th>Intended Status</th><th>Actions</th></tr></thead>
          <tbody>{data.zones.map(zone => <tr key={zone.id}><td>{zone.code}</td><td>{zone.name}</td><td>{zone.total_capacity.toLocaleString('en-MY')}</td>
            <td>{zone.unavailable_capacity.toLocaleString('en-MY')}</td><td>{label(zone.operational_status)}</td><td><div className={layout.actions}>
              <button type="button" className={layout.edit} disabled={busy || locked || Boolean(form)} onClick={() => begin(zone)}>Edit Zone<span className={layout.srOnly}> {zone.code}</span></button>
              <button type="button" className={layout.delete} disabled={busy || locked || Boolean(form) || zone.operational_zone_id !== null} onClick={() => remove(zone)}>Delete Draft Zone<span className={layout.srOnly}> {zone.code}</span></button>
            </div></td></tr>)}</tbody>
        </table></div>}
    </>}
    {form && <form className={layout.form} onSubmit={save}>
      <h3>{editing ? 'Edit Zone' : 'Add Zone'}</h3>
      <div className={layout.row}>{[['code', 'Zone Code', 64, 'A'], ['name', 'Zone Name', 100, 'Zone A']].map(([key, title, max, example]) =>
        <label key={key} className={shared.field}>{title}<input type="text" className={styles.exampleInput} placeholder={editing ? undefined : example} required maxLength={max} value={form[key]} disabled={busy || locked}
          onChange={event => setForm(current => ({ ...current, [key]: event.target.value }))} /></label>)}</div>
      <div className={layout.row}>{[['total_capacity', 'Total Capacity'], ['unavailable_capacity', 'Unavailable Capacity']].map(([key, title]) =>
        <label key={key} className={shared.field}>{title}<input type="number" required min="0" max={MAX_CAPACITY} step="1" value={form[key]} disabled={busy || locked}
          onChange={event => setForm(current => ({ ...current, [key]: event.target.value }))} /></label>)}</div>
      <label className={shared.field}>Intended Status<select value={form.operational_status} disabled={busy || locked} onChange={event => setForm(current => ({ ...current, operational_status: event.target.value }))}>
        {ZONE_STATUSES.map(status => <option key={status} value={status}>{label(status)}</option>)}
      </select></label>
      {validation && <p className={shared.error} role="status">{validation}</p>}
      <div className={`${layout.actions} ${styles.formActions}`}>
        <button className={`${shared.button} ${shared.primary}`} disabled={busy || locked || Boolean(validation)}>{saving ? 'Saving…' : 'Save Zone'}</button>
        <button type="button" className={shared.button} disabled={saving} onClick={() => { setForm(null); setEditing(null); if (!locked) setError(''); }}>Cancel</button>
      </div>
    </form>}
    {confirmationDialog}
  </section>;
}
