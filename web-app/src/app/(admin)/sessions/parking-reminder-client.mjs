import { authenticatedFetch } from '../../../lib/auth-client.mjs';
import { reminderInput, validateReminders } from '../../../lib/parking-reminder-contracts.mjs';

async function request(query, input, signal) {
  const response = await authenticatedFetch(`/api/sessions/reminders${query ? `?${query}` : ''}`, {
    method: input ? 'POST' : 'GET', cache: 'no-store', signal,
    ...(input ? { headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(input) } : {}),
  });
  if ([401, 403].includes(response.status)) {
    if (typeof window !== 'undefined') window.location.replace(`/login?reason=${response.status === 401 ? 'expired' : 'denied'}`);
    throw Object.assign(new Error('Administrator access could not be verified. Returning to sign in.'), { sessionChanged: true });
  }
  const data = await response.json().catch(() => null);
  if (!response.ok) throw new Error(data?.error || 'Reminder delivery could not be confirmed. Refresh before retrying the same request.');
  return data;
}
export async function fetchParkingReminders(ids, signal) {
  return validateReminders(await request(new URLSearchParams({ session_ids: ids.join(',') }), null, signal), ids);
}
export async function sendParkingReminder(input) {
  input = reminderInput(input);
  return validateReminders(await request('', input), [input.session_id], true);
}
