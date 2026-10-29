export const reminderMessage = 'Your vehicle has remained in the parking building past midnight. Please confirm your status.';
const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const timestamp = value => typeof value === 'string' && /(Z|[+-]\d{2}:\d{2})$/.test(value) && Number.isFinite(Date.parse(value));
export function reminderIds(params) {
  if ([...params.keys()].some(key => key !== 'session_ids') || params.getAll('session_ids').length !== 1) throw new Error('Choose 1–10 distinct parking sessions.');
  const ids = params.get('session_ids').split(',');
  if (!ids.length || ids.length > 10 || ids.some(id => !uuid(id)) || new Set(ids).size !== ids.length) throw new Error('Choose 1–10 distinct parking sessions.');
  return ids;
}
export function reminderInput(input) {
  if (!input || Array.isArray(input) || Object.keys(input).length !== 2 || !uuid(input.session_id) || !uuid(input.request_id)) throw new Error('Use a valid parking session and reminder request.');
  return { session_id: input.session_id, request_id: input.request_id };
}
export function validateReminders(data, ids, sent = false) {
  if (!Array.isArray(data?.reminders) || (sent && data.status !== 'sent') || data.reminders.length > ids.length) throw new Error('Unconfirmed reminder result.');
  const seen = new Set();
  const reminders = data.reminders.map(row => {
    if (!uuid(row?.id) || !ids.includes(row.session_id) || seen.has(row.session_id) || typeof row.plate_number !== 'string' ||
      !timestamp(row.entry_time) || !timestamp(row.sent_at) || Date.parse(row.sent_at) < Date.parse(row.entry_time) ||
      ![null, 'still_parked', 'already_left'].includes(row.response) ||
      (row.response === null ? row.responded_at !== null : !timestamp(row.responded_at) || Date.parse(row.responded_at) < Date.parse(row.sent_at)) || row.message !== reminderMessage) throw new Error('Unconfirmed reminder result.');
    seen.add(row.session_id);
    const { id, session_id, plate_number, entry_time, sent_at, response, responded_at } = row;
    return { id, session_id, plate_number, entry_time, sent_at, response, responded_at, message: reminderMessage };
  });
  if (sent && reminders.length !== 1) throw new Error('Unconfirmed reminder result.');
  return { ...(sent ? { status: 'sent' } : {}), reminders };
}
