import { authenticatedFetch } from '../../../lib/auth-client.mjs';
export async function reviewRequest(path = '', options = {}) {
  const response = await authenticatedFetch(`/api/approvals${path}`, { cache: 'no-store', ...options });
  if (response.status === 401 || response.status === 403) {
    window.location.replace(`/login?reason=${response.status === 401 ? 'expired' : 'denied'}`);
    throw new Error('Administrator access could not be verified. Returning to sign in.');
  }
  let data;
  try { data = await response.json(); } catch { throw new Error('Unable to read the response. Refresh the list before retrying.'); }
  if (!response.ok) throw new Error(data.error || 'The request failed. Refresh the list before retrying.');
  return data;
}
