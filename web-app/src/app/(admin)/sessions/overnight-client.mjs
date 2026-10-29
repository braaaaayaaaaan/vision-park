import { authenticatedFetch } from '../../../lib/auth-client.mjs';
import { overnightQuery, validateOvernightAlerts } from '../../../lib/overnight-contracts.mjs';

export async function fetchOvernightAlerts(query, signal) {
  const params = overnightQuery(new URLSearchParams(query));
  const response = await authenticatedFetch(`/api/sessions/overnight?${params}`, { cache: 'no-store', signal });
  if ([401, 403].includes(response.status)) {
    if (typeof window !== 'undefined') window.location.replace(`/login?reason=${response.status === 401 ? 'expired' : 'denied'}`);
    throw Object.assign(new Error('Administrator access could not be verified. Returning to sign in.'), { sessionChanged: true });
  }
  let data;
  try { data = await response.json(); } catch { throw new Error('Unable to read overnight alerts. Please retry.'); }
  if (!response.ok) throw new Error(data.error || 'Overnight alerts are unavailable. Please retry.');
  return validateOvernightAlerts(data, params);
}
