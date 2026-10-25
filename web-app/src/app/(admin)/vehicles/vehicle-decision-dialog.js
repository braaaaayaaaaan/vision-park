'use client';
import { useRef, useState } from 'react';
import ConfirmationDialog from '../../../components/confirmation-dialog';
import { submitVehicleDecision } from './vehicles-client.mjs';
import styles from '../approvals/approvals.module.css';
import vehicleStyles from './vehicles.module.css';
import { normalizeRejectionReason, rejectionReasonLimit } from '../../../lib/vehicle-rejection.mjs';

export default function VehicleDecisionDialog({ vehicle, action, onDismiss, onSuccess }) {
  const inFlight = useRef(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');
  const [uncertain, setUncertain] = useState(false);
  const [reason, setReason] = useState('');
  const approve = action === 'approve';
  async function submit(event) {
    event.preventDefault();
    if (inFlight.current || uncertain) return;
    let rejectionReason;
    try { if (!approve) rejectionReason = normalizeRejectionReason(reason); }
    catch (failure) { setError(failure.message); return false; }
    setError('');
    inFlight.current = true;
    setSubmitting(true);
    try {
      const result = await submitVehicleDecision(vehicle.id, action, rejectionReason);
      onSuccess(result);
    } catch (failure) {
      setError(failure.message || 'The decision could not be confirmed. Close and refresh the list.');
      setUncertain(![400, 422].includes(failure.status));
      setSubmitting(false);
      inFlight.current = false;
    }
  }
  return <ConfirmationDialog id="vehicle-decision" title={approve ? 'Approve Vehicle Registration' : 'Reject Vehicle Registration'}
    description={`Confirm ${approve ? 'approval' : 'rejection'} of this pending vehicle registration. This decision cannot be reversed here.`}
    variant={approve ? 'default' : 'destructive'} onConfirm={submit} onCancel={() => { if (!inFlight.current) onDismiss(uncertain); }}
    pending={submitting} pendingLabel="Submitting…" error={error} disabled={uncertain}
    cancelLabel={uncertain ? 'Close and Refresh' : 'Cancel'} confirmLabel={approve ? 'Confirm Approval' : 'Confirm Rejection'}>
      <div className={styles.applicant}><strong>{vehicle.plate_number}</strong><p>Registered Owner: {vehicle.owner_name || 'Not available'}</p><p>Company: {vehicle.tenant_name || 'Not available'}</p></div>
      {!approve && <div className={vehicleStyles.reasonField}>
        <label htmlFor="vehicle-rejection-reason">Rejection Reason <span className={vehicleStyles.required}>(Required)</span></label>
        <textarea id="vehicle-rejection-reason" rows={4} required maxLength={rejectionReasonLimit}
          value={reason} disabled={submitting || uncertain} aria-describedby="vehicle-rejection-hint" aria-invalid={Boolean(error) && !uncertain}
          onChange={event => { setReason(event.target.value); setError(''); }} />
        <p id="vehicle-rejection-hint" className={vehicleStyles.muted}>Up to {rejectionReasonLimit} characters.</p>
      </div>}
  </ConfirmationDialog>;
}
