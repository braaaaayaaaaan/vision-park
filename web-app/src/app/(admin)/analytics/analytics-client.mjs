export function malaysiaToday(now = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kuala_Lumpur', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(now);
  return ['year', 'month', 'day'].map((type) => parts.find((part) => part.type === type).value).join('-');
}
export function analyticsQuery(filters, now = new Date()) {
  const end = filters.preset === 'custom' ? filters.end_date : malaysiaToday(now);
  const start = filters.preset === 'custom' ? filters.start_date : new Date(Date.parse(end) - (Number(filters.preset) - 1) * 86400000).toISOString().slice(0, 10);
  const days = (Date.parse(end) - Date.parse(start)) / 86400000 + 1;
  if (!start || !end || !Number.isInteger(days) || days < 1 || days > 90 || end > malaysiaToday(now)) throw new Error('Choose an ordered date range of up to 90 days, ending no later than today.');
  const params = new URLSearchParams({ start_date: start, end_date: end });
  if (filters.level_id) params.set('level_id', filters.level_id);
  return params.toString();
}
export async function fetchAnalytics(query, signal) {
  const response = await fetch(`/api/analytics${query ? `?${query}` : ''}`, { cache: 'no-store', signal });
  if ([401, 403].includes(response.status)) {
    window.location.replace(`/login?reason=${response.status === 401 ? 'expired' : 'denied'}`);
    throw new Error('Administrator access could not be verified. Returning to sign in.');
  }
  let data;
  try { data = await response.json(); } catch { throw new Error('Unable to read analytics. Please try again.'); }
  if (!response.ok) throw new Error(data.error || 'Unable to load parking analytics.');
  return data;
}
