'use client';
import { useEffect, useState } from 'react';
import { createApprovalArrivalTracker, fetchPendingApprovalSnapshot, PENDING_APPROVALS_CHANGED } from '../lib/pending-approvals.mjs';
import { startVisiblePolling } from '../lib/visible-polling.mjs';

export default function usePendingApprovals(onArrival) {
  const [counts, setCounts] = useState({ accounts: null, vehicles: null });
  useEffect(() => {
    const stops = new Map();
    let sessionChanged = false;
    const arrived = createApprovalArrivalTracker();
    function start(kind) {
      stops.get(kind)?.();
      stops.set(kind, startVisiblePolling({
        interval: 30000,
        load: signal => fetchPendingApprovalSnapshot(kind, signal),
        success: snapshot => {
          setCounts(previous => ({ ...previous, [kind]: snapshot.pending }));
          if (arrived(kind, snapshot)) onArrival?.();
        },
        failure: error => {
          if (error.sessionChanged) {
            sessionChanged = true;
            stops.forEach(stop => stop());
            setCounts({ accounts: null, vehicles: null });
          } else {
            // An unavailable count must not look like an empty approval queue.
            setCounts(previous => ({ ...previous, [kind]: null }));
          }
        },
      }));
    }
    function refresh(event) {
      if (!sessionChanged && ['accounts', 'vehicles'].includes(event.detail)) start(event.detail);
    }
    start('accounts');
    start('vehicles');
    document.addEventListener(PENDING_APPROVALS_CHANGED, refresh);
    return () => {
      stops.forEach(stop => stop());
      document.removeEventListener(PENDING_APPROVALS_CHANGED, refresh);
    };
  }, [onArrival]);
  return counts;
}
