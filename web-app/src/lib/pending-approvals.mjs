import { authenticatedFetch } from './auth-client.mjs';

export const PENDING_APPROVALS_CHANGED = 'visionpark-pending-approvals-changed';
const sources = {
  accounts: ['/api/approvals/summary', 'pending_approvals'],
  vehicles: ['/api/vehicles/summary', 'pending_approval'],
};
const totalFields = { accounts: 'total_registrations', vehicles: 'registered_vehicles' };

export async function fetchPendingApprovalSnapshot(kind, signal) {
  const [path, field] = sources[kind];
  const response = await authenticatedFetch(path, { cache: 'no-store', signal });
  if ([401, 403].includes(response.status)) {
    if (typeof window !== 'undefined') window.location.replace(`/login?reason=${response.status === 401 ? 'expired' : 'denied'}`);
    throw Object.assign(new Error('Administrator access could not be verified.'), { sessionChanged: true });
  }
  if (!response.ok) throw new Error('Pending approvals are unavailable.');
  const data = await response.json();
  if (!Number.isSafeInteger(data?.[field]) || data[field] < 0) throw new Error('Invalid pending approval count.');
  const total = data[totalFields[kind]];
  if (!Number.isSafeInteger(total) || total < data[field]) throw new Error('Invalid registration total.');
  return { pending: data[field], total };
}

export async function fetchPendingApprovals(kind, signal) {
  return (await fetchPendingApprovalSnapshot(kind, signal)).pending;
}

export function createApprovalArrivalTracker() {
  const previous = new Map();
  return (kind, snapshot) => {
    const before = previous.get(kind);
    previous.set(kind, snapshot);
    // A simultaneous approval can lower the queue while a new request arrives.
    return Boolean(before && snapshot.pending > 0 &&
      (snapshot.pending > before.pending || snapshot.total > before.total));
  };
}

export function notifyPendingApprovalsChanged(kind) {
  if (typeof document !== 'undefined') {
    document.dispatchEvent(new CustomEvent(PENDING_APPROVALS_CHANGED, { detail: kind }));
  }
}
