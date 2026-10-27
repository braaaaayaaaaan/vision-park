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
