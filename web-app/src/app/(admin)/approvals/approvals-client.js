import { authenticatedFetch } from '../../../lib/auth-client.mjs';
import { notifyPendingApprovalsChanged } from '../../../lib/pending-approvals.mjs';
export async function reviewRequest(path = '', options = {}) {
  const response = await authenticatedFetch(`/api/approvals${path}`, { cache: 'no-store', ...options });
  if (response.status === 401 || response.status === 403) {
    if (typeof window !== 'undefined') window.location.replace(`/login?reason=${response.status === 401 ? 'expired' : 'denied'}`);
    throw Object.assign(new Error('Administrator access could not be verified. Returning to sign in.'), { status: response.status });
  }
  let data;
  try { data = await response.json(); } catch { throw new Error('Unable to read the response. Refresh the list before retrying.'); }
  if (!response.ok) throw Object.assign(new Error(data.error || 'The request failed. Refresh the list before retrying.'), { status: response.status });
  if (options.method === 'POST') notifyPendingApprovalsChanged('accounts');
  return data;
}
