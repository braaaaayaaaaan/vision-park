const dateFormat = new Intl.DateTimeFormat('en-MY', {
  timeZone: 'Asia/Kuala_Lumpur', year: 'numeric', month: '2-digit', day: '2-digit',
});
const timeFormats = [false, true].map(seconds => new Intl.DateTimeFormat('en-MY', {
  timeZone: 'Asia/Kuala_Lumpur', hour: '2-digit', minute: '2-digit',
  ...(seconds ? { second: '2-digit' } : {}), hourCycle: 'h23',
}));

// Calendar dates are already Malaysia reporting days; do not shift them in UTC.
export function formatMalaysiaDate(value) {
  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return value.split('-').reverse().join('-');
  }
  const date = value == null ? null : new Date(value);
  if (!date || Number.isNaN(date.getTime())) return 'Not available';
  const parts = dateFormat.formatToParts(date);
  return ['day', 'month', 'year'].map(type => parts.find(part => part.type === type).value).join('-');
}

export function formatMalaysiaDateTime(value, { seconds = false } = {}) {
  const date = value == null ? null : new Date(value);
  if (!date || Number.isNaN(date.getTime())) return 'Not available';
  return `${formatMalaysiaDate(date)}, ${timeFormats[Number(seconds)].format(date)}`;
}
