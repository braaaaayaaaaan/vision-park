'use client';
import { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import ConfirmationDialog from '../../../components/confirmation-dialog';
import { tenantInput } from '../../../lib/tenant-contracts.mjs';
import { saveTenant } from './tenants-client.mjs';
import common from '../vehicles/vehicles.module.css';
import shared from '../approvals/approvals.module.css';
import styles from './tenants.module.css';

export default function TenantEditor({ company = null, zones = [], onClose, onSaved }) {
  const creating = !company;
  const [id] = useState(() => company?.id ?? crypto.randomUUID());
  const [name, setName] = useState(company?.name ?? ''), [active, setActive] = useState(company?.is_active ?? true);
  const [selected, setSelected] = useState(company?.zone_ids ?? []), [confirmation, setConfirmation] = useState(null);
  const [error, setError] = useState(''), [busy, setBusy] = useState(false), [reloadRequired, setReloadRequired] = useState(false);
  const dialog = useRef(null), nameInput = useRef(null), inFlight = useRef(false);
  const original = company?.zone_ids ?? [];
  const dirty = name !== (company?.name ?? '') || active !== (company?.is_active ?? true) ||
    selected.length !== original.length || selected.some(zoneId => !original.includes(zoneId));
  const removed = original.filter(zoneId => !selected.includes(zoneId)).length;
  const deactivating = company?.is_active && !active;
  useEffect(() => {
    const element = dialog.current, origin = document.activeElement, overflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden'; element.showModal(); nameInput.current?.focus();
    return () => { element.close(); document.body.style.overflow = overflow; if (origin?.isConnected) origin.focus({ preventScroll: true }); };
  }, []);
  function dismiss() {
    if (inFlight.current) return;
    if (dirty && !reloadRequired) setConfirmation('discard'); else onClose();
  }
  function prepare(event) {
    event.preventDefault();
    if (inFlight.current || reloadRequired) return;
    try {
      tenantInput({ id, name, is_active: active, zone_ids: selected, expected_revision: company?.revision ?? null, confirm_access_change: true }, creating);
      setError(''); setConfirmation('save');
    } catch (cause) { setError(cause.message); }
  }
  async function save() {
    if (inFlight.current || reloadRequired) return false;
    inFlight.current = true; setBusy(true); setError('');
    try {
      const data = await saveTenant({ id, name, is_active: active, zone_ids: selected,
        expected_revision: company?.revision ?? null, confirm_access_change: true }, creating);
      onSaved(data.tenant); return true;
    } catch (cause) {
      setError(cause.message); setConfirmation(null);
      // A stale edit or uncertain response requires a fresh read; never replay a write.
      if (!cause.status || cause.status === 503 || (cause.status === 409 && !/name already exists|Active parking sessions/.test(cause.message))) setReloadRequired(true);
      return false;
    } finally { inFlight.current = false; setBusy(false); }
  }
  const levels = [...new Set(zones.map(zone => zone.level_id))];
  const content = <dialog ref={dialog} className={`${shared.dialog} ${styles.editor}`} aria-modal="true" aria-labelledby="company-editor-title"
    onCancel={event => { event.preventDefault(); event.stopPropagation(); dismiss(); }}>
    <form onSubmit={prepare} aria-busy={busy}>
      <h2 id="company-editor-title">{creating ? 'Register Company' : 'Edit Company'}</h2>
      <p className={common.muted}>{creating ? 'New active companies are available for driver registration and administrator approval.' : 'Update company information and zone access. Driver and parking history are preserved.'}</p>
      <label className={styles.field}>Company Name<input ref={nameInput} value={name} maxLength={120} required disabled={busy || reloadRequired} onChange={event => setName(event.target.value)} autoComplete="organization" /></label>
      <label className={styles.check}><input type="checkbox" checked={active} disabled={busy || reloadRequired || Boolean(company?.is_active && company.active_sessions)} onChange={event => setActive(event.target.checked)} />Active Company</label>
      <p className={common.muted}>Inactive companies are unavailable for new driver registrations, approvals and parking allocations.</p>
      {company?.active_sessions > 0 && <p className={styles.notice}>{company.active_sessions} active parking session(s). Deactivation and access removal for those sessions are blocked until they end.</p>}
      {creating ? <p className={styles.notice}>After registration, open the company details to authorise parking zones. New companies start without parking access.</p> :
        <section className={styles.zoneSection}><h3>Authorised Parking Zones</h3><p className={common.muted}>Select any existing zones. Capacity is shared on a First Come, First Serve (FCFS) basis as there are no spaces reserved for a company.</p>
          {!active && <p className={common.muted}>Activate the company to grant additional zone access.</p>}
          {!zones.length && <p>No parking zones are configured yet.</p>}
          {levels.map(level => <fieldset className={styles.zoneFieldset} key={level} disabled={busy || reloadRequired}>
            <legend>{zones.find(zone => zone.level_id === level).level_name}</legend>
            {zones.filter(zone => zone.level_id === level).map(zone => <label className={styles.zoneOption} key={zone.id}>
              <input type="checkbox" checked={selected.includes(zone.id)} disabled={!active && !original.includes(zone.id) && !selected.includes(zone.id)}
                onChange={event => setSelected(old => event.target.checked ? [...old, zone.id] : old.filter(zoneId => zoneId !== zone.id))} />
              <span><strong>{zone.code} · {zone.name}</strong><small>{zone.total_capacity} Shared Spaces · {zone.operational_status === 'open' && zone.level_active ? 'Open' : 'Currently Unavailable'}</small></span>
            </label>)}
          </fieldset>)}
        </section>}
      {error && <p className={shared.error} role="alert">{error}</p>}
      {reloadRequired && <p className={common.muted}>Close this editor and refresh the company details before making further changes.</p>}
      <div className={shared.dialogActions}><button type="button" className={shared.secondary} disabled={busy} onClick={dismiss}>{reloadRequired ? 'Close Editor' : 'Cancel'}</button>
        <button type="submit" className={shared.primary} disabled={busy || reloadRequired || (!creating && !dirty)}>{busy ? 'Saving…' : creating ? 'Register Company' : 'Save Changes'}</button></div>
    </form>
    {confirmation && <ConfirmationDialog title={confirmation === 'discard' ? 'Discard Company Changes?' : creating ? 'Register Company?' : 'Save Company Changes?'}
      description={confirmation === 'discard' ? 'Your unsaved changes will be discarded.' : deactivating ?
        'Deactivating this company blocks its drivers from new parking allocations and prevents new registrations and approvals. Existing records and permissions are preserved.' :
        removed ? `Removing ${removed} zone permission(s) changes parking eligibility for every driver in this company. Existing parking sessions must end first.` :
          creating ? `Register ${name.trim()} as an ${active ? 'active' : 'inactive'} company. Parking access can be configured after the registration.` : 'Save the company information and zone access for all its drivers.'}
      confirmLabel={confirmation === 'discard' ? 'Discard Changes' : creating ? 'Register Company' : 'Save Changes'}
      variant={confirmation === 'discard' || deactivating || removed ? 'destructive' : 'default'}
      onConfirm={confirmation === 'discard' ? () => { onClose(); } : save} onCancel={() => setConfirmation(null)} />}
  </dialog>;
  return typeof document === 'undefined' ? content : createPortal(content, document.body);
}
