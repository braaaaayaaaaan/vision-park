'use client';
import { useEffect, useRef, useState } from 'react';
import ConfirmationDialog from '../../../components/confirmation-dialog';
import { approveSelectedVehicles } from './bulk-vehicle-approval.mjs';

export default function BulkVehicleApprovalDialog({ vehicles, onDismiss, onComplete }) {
  const inFlight = useRef(false), mounted = useRef(false), controller = useRef(null);
  const [pending, setPending] = useState(false), [progress, setProgress] = useState(0), [error, setError] = useState('');
  useEffect(() => {
    mounted.current = true;
    controller.current = new AbortController();
    return () => { mounted.current = false; controller.current.abort(); };
  }, []);
  async function submit(event) {
    event.preventDefault();
    if (inFlight.current) return false;
    inFlight.current = true; setPending(true);
    try {
      const results = await approveSelectedVehicles(vehicles, { signal: controller.current?.signal,
        onProgress: value => { if (mounted.current) setProgress(value); } });
      if (mounted.current) onComplete(results);
    } catch {
      if (mounted.current) {
        setError('Approval could not be confirmed. Close and refresh the list before trying again.');
        setPending(false);
      }
    }
    return false;
  }
  return <ConfirmationDialog id="bulk-vehicle-approval" title="Approve Selected Vehicles"
    description={`Approve ${vehicles.length} selected pending ${vehicles.length === 1 ? 'vehicle' : 'vehicles'} on this page? Each registration is checked individually. This decision cannot be reversed here.`}
    confirmLabel="Confirm Approval" cancelLabel={error ? 'Close and Refresh' : 'Cancel'}
    pending={pending} pendingLabel={`Approving vehicles… ${progress} of ${vehicles.length} processed.`}
    disabled={Boolean(error)} error={error} onConfirm={submit}
    onCancel={() => { if (!pending) onDismiss(Boolean(error)); }}>
    <p>Only the selected registrations will be approved. Any unsuccessful or unconfirmed approvals will be listed after the records refresh.</p>
  </ConfirmationDialog>;
}
