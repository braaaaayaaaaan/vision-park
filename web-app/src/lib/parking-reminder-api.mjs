import { ACCESS_COOKIE, AuthError, baseUrl, forwardSession, requireSameOrigin } from './auth.mjs';
import { readLimitedBody } from './parking-structure-api.mjs';
import { reminderIds, reminderInput, validateReminders } from './parking-reminder-contracts.mjs';

const messages = {
  404: 'Parking session not found. Refresh the alerts.',
  409: 'The session changed or its driver cannot receive reminders. Refresh the alerts.',
  429: 'A reminder was sent recently. Wait 15 minutes between reminders for this session.',
  422: 'Use a valid parking reminder request.',
};
export async function handleParkingReminders(request) {
  const writing = request.method === 'POST';
  try {
    if (writing) requireSameOrigin(request);
    const token = request.cookies.get(ACCESS_COOKIE)?.value;
    await forwardSession(token);
    let ids, input;
    try {
      if (writing) {
        if (request.headers.get('content-type')?.split(';')[0].toLowerCase() !== 'application/json') return { status: 415, body: { error: 'Use a JSON reminder request.' } };
        if (new URL(request.url).search) throw new Error('Reminder sends do not accept filters.');
        input = reminderInput(JSON.parse((await readLimitedBody(request.body, 1024)).toString())); ids = [input.session_id];
      } else ids = reminderIds(new URL(request.url).searchParams);
    } catch (error) {
      if (error instanceof AuthError) throw error;
      return { status: 422, body: { error: 'Use a valid parking reminder request.' } };
    }
    const query = writing ? '' : `?${new URLSearchParams({ session_ids: ids.join(',') })}`;
    const response = await fetch(`${baseUrl(process.env.BACKEND_BASE_URL)}/admin/parking/status-reminders${query}`, {
      method: writing ? 'POST' : 'GET', headers: { Authorization: `Bearer ${token}`, Accept: 'application/json', ...(writing ? { 'Content-Type': 'application/json' } : {}) },
      ...(writing ? { body: JSON.stringify(input) } : {}), cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(10000),
    });
    if ([401, 403].includes(response.status)) throw new AuthError(response.status === 401 ? 'expired' : 'denied', response.status);
    if (!response.ok) return { status: messages[response.status] ? response.status : 503, body: { error: messages[response.status] || 'Reminder delivery could not be confirmed. Refresh before retrying the same request.' } };
    return { status: 200, body: validateReminders(await response.json(), ids, writing) };
  } catch (error) {
    return { status: error instanceof AuthError ? error.status : 503, body: { error: error instanceof AuthError ? error.message : 'Reminder delivery could not be confirmed. Refresh before retrying the same request.' } };
  }
}
