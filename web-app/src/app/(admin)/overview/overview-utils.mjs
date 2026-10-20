import { malaysiaToday } from '../analytics/analytics-client.mjs';

export const PAGE_SIZE = 5;
export const occupancyBands = [
  { label: 'Available', threshold: '0%–85%', colour: '#25804B' },
  { label: 'Nearly Full', threshold: '>85%–<100%', colour: '#E0B326' },
  { label: 'Full', threshold: '100%', colour: '#C53D3D' },
];
export function occupancyPercentage({ occupied, usable_capacity }) {
  return usable_capacity === 0 ? null : occupied / usable_capacity * 100;
}
export function occupancyBand(percentage) {
  if (percentage === null) return { label: 'No Usable Capacity', colour: '#8794a5' };
  return occupancyBands[percentage >= 100 ? 2 : percentage > 85 ? 1 : 0];
}
export function todaySessionsQuery(offset = 0, now = new Date()) {
  const today = malaysiaToday(now);
  return new URLSearchParams({ start_date: today, end_date: today, limit: String(PAGE_SIZE), offset: String(offset) }).toString();
}
