import { authenticatedFetch } from './auth-client.mjs';

export const PENDING_APPROVALS_CHANGED = 'visionpark-pending-approvals-changed';
const sources = {
  accounts: ['/api/approvals/summary', 'pending_approvals'],
  vehicles: ['/api/vehicles/summary', 'pending_approval'],
};

export async function fetchPendingApprovals(kind, signal) {
  const [path, field] = sources[kind];
  const response = await authenticatedFetch(path, { cache: 'no-store', signal });
  if ([401, 403].includes(response.status)) {
    if (typeof window !== 'undefined') window.location.replace(`/login?reason=${response.status === 401 ? 'expired' : 'denied'}`);
    throw Object.assign(new Error('Administrator access could not be verified.'), { sessionChanged: true });
  }
  if (!response.ok) throw new Error('Pending approvals are unavailable.');
  const data = await response.json();
  if (!Number.isSafeInteger(data?.[field]) || data[field] < 0) throw new Error('Invalid pending approval count.');
  return data[field];
}

export function notifyPendingApprovalsChanged(kind) {
  if (typeof document !== 'undefined') {
    document.dispatchEvent(new CustomEvent(PENDING_APPROVALS_CHANGED, { detail: kind }));
  }
}
