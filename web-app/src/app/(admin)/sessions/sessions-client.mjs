import { authenticatedFetch } from '../../../lib/auth-client.mjs';
import { analyticsQuery } from '../analytics/analytics-client.mjs';
import { formatMalaysiaDateTime } from '../../../lib/date-format.mjs';

export const sessionLabels = { allocated: 'Allocated', occupied: 'Occupied', completed: 'Completed', cancelled: 'Cancelled' };
export function formatAssignedZone(zoneName, levelName) {
  const zone = zoneName?.trim();
  const level = levelName?.trim();
  if (!zone) return 'Not available';
  if (level && zone.startsWith(level)) {
    const suffix = zone.slice(level.length);
    if (/^\s*[-–—]\s*\S/.test(suffix)) return suffix.replace(/^\s*[-–—]\s*/, '');
  }
  return zone;
}
export function formatTimestamp(value) {
  const formatted = formatMalaysiaDateTime(value, { seconds: true });
  return formatted === 'Not available' ? formatted : `${formatted} MYT`;
}
export function formatDuration(seconds) {
  if (seconds === null) return 'Not available';
  const value = Math.floor(seconds);
  return `${Math.floor(value / 3600)}h ${Math.floor(value % 3600 / 60)}m ${value % 60}s`;
}
export function sessionsQuery(filters, offset = 0, now = new Date()) {
  const params = filters.start_date || filters.end_date ? new URLSearchParams(analyticsQuery({ ...filters, preset: 'custom' }, now)) : new URLSearchParams();
  const plate = filters.plate.trim().toUpperCase();
  if (plate && !/^[A-Z0-9]{1,32}$/.test(plate)) throw new Error('Use up to 32 letters or digits for number plate search.');
  if (plate) params.set('plate', plate);
  if (filters.status) params.set('status', filters.status);
  if (filters.level_id) params.set('level_id', filters.level_id);
  params.set('limit', '25'); params.set('offset', String(offset));
  return params.toString();
}
export function sessionSummaryQuery(filters, now = new Date()) {
  const params = new URLSearchParams(sessionsQuery({ ...filters, status: '' }, 0, now));
  params.delete('limit'); params.delete('offset');
  return params.toString();
}
export async function fetchSessionSummary(query, signal) {
  // Read the server's exact totals, rather than counting the paginated rows.
  const counts = await Promise.all(Object.keys(sessionLabels).map(async status => {
    const params = new URLSearchParams(query);
    params.set('status', status); params.set('limit', '1'); params.set('offset', '0');
    const data = await fetchSessions(params.toString(), signal);
    if (!Number.isSafeInteger(data.total) || data.total < 0) throw new Error('Session counts could not be verified. Please retry.');
    return [status, data.total];
  }));
  return Object.fromEntries(counts);
}
export async function fetchSessions(query, signal) {
  const response = await authenticatedFetch(`/api/sessions?${query}`, { cache: 'no-store', signal });
  if ([401, 403].includes(response.status)) {
    window.location.replace(`/login?reason=${response.status === 401 ? 'expired' : 'denied'}`);
    throw new Error('Administrator access could not be verified. Returning to sign in.');
  }
  let data;
  try { data = await response.json(); } catch { throw new Error('Unable to read parking sessions. Please retry.'); }
  if (!response.ok) throw new Error(data.error || 'Unable to load parking sessions.');
  return data;
}

// A selected row can leave a status-filtered page after parking or settlement.
// Reuse the list contract to keep that open detail current without resetting it.
export async function fetchSessionSnapshot(session, signal) {
  const filters = { plate: session.plate_number ?? '', status: '', level_id: '', start_date: '', end_date: '' };
  for (let offset = 0; !signal.aborted; offset += 25) {
    const page = await fetchSessions(sessionsQuery(filters, offset), signal);
    const found = page.sessions.find(row => row.id === session.id);
    if (found) return found;
    if (!page.sessions.length || offset + 25 >= page.total) return session;
  }
  return session;
}
