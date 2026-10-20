'use client';
import { useEffect, useRef, useState } from 'react';
import { submitVehicleDecision } from './vehicles-client.mjs';
import styles from '../approvals/approvals.module.css';

export default function VehicleDecisionDialog({ vehicle, action, onDismiss, onSuccess }) {
  const dialog = useRef(null);
  const inFlight = useRef(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');
  const [uncertain, setUncertain] = useState(false);
  const approve = action === 'approve';
  useEffect(() => {
    const element = dialog.current;
    element.showModal();
    return () => element.close();
  }, []);
  async function submit(event) {
    event.preventDefault();
    if (inFlight.current || uncertain) return;
    inFlight.current = true;
    setSubmitting(true);
    try {
      const result = await submitVehicleDecision(vehicle.id, action);
      onSuccess(result);
    } catch (failure) {
      setError(failure.message || 'The decision could not be confirmed. Close and refresh the list.');
      setUncertain(true);
      setSubmitting(false);
      inFlight.current = false;
    }
  }
  return <dialog ref={dialog} className={styles.dialog} aria-labelledby="vehicle-decision-title" aria-describedby="vehicle-decision-description"
    onCancel={event => { event.preventDefault(); if (!inFlight.current) onDismiss(uncertain); }}>
    <form onSubmit={submit} aria-busy={submitting}>
      <h2 id="vehicle-decision-title">{approve ? 'Approve Vehicle Registration' : 'Reject Vehicle Registration'}</h2>
      <p id="vehicle-decision-description">Confirm {approve ? 'approval' : 'rejection'} of this pending vehicle registration. This decision cannot be reversed here.</p>
      <div className={styles.applicant}><strong>{vehicle.plate_number}</strong><p>Registered Owner: {vehicle.owner_name || 'Not Available'}</p><p>Company: {vehicle.tenant_name || 'Not Available'}</p></div>
      {error && <p className={styles.error} role="alert">{error}</p>}
      {submitting && <p role="status">Waiting For Backend Confirmation…</p>}
      <div className={styles.dialogActions}>
        <button type="button" className={styles.secondary} disabled={submitting} onClick={() => onDismiss(uncertain)}>{uncertain ? 'Close And Refresh' : 'Cancel'}</button>
        <button type="submit" className={approve ? styles.primary : styles.reject} disabled={submitting || uncertain}>{submitting ? 'Submitting…' : approve ? 'Confirm Approval' : 'Confirm Rejection'}</button>
      </div>
    </form>
  </dialog>;
}
