import { analyticsQuery, malaysiaToday } from '../app/(admin)/analytics/analytics-client.mjs';

export const attemptLabels = { succeeded: 'Paid', processing: 'Pending', unknown: 'Uncertain', declined: 'Declined', failed: 'Failed' };
export const methodLabels = { wallet: 'VisionPark Wallet', mock_card: 'Card Payment', zero: 'No Charge' };
export const uuid = value => typeof value === 'string' && /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(value);
const integer = (value, min = 0, max = Number.MAX_SAFE_INTEGER) => Number.isSafeInteger(value) && value >= min && value <= max;
const timestamp = value => typeof value === 'string' && /(?:Z|[+-]\d{2}:\d{2})$/.test(value) && Number.isFinite(Date.parse(value));
const optionalTime = value => value === null || timestamp(value);
const fail = () => { throw new Error('Payment information could not be verified. Refresh and try again.'); };
export function myr(sen) {
  if (!integer(sen)) return 'Not Available';
  return `MYR ${Math.floor(sen / 100).toLocaleString('en-MY')}.${String(sen % 100).padStart(2, '0')}`;
}
export function moneyInput(value, optional = false) {
  const text = String(value ?? '').trim();
  if (optional && !text) return null;
  if (!/^\d{1,8}(?:\.\d{1,2})?$/.test(text)) throw new Error('Use MYR amounts with up to two decimal places.');
  const [whole, cents = ''] = text.split('.');
  const sen = Number(whole) * 100 + Number(cents.padEnd(2, '0'));
  if (!integer(sen, 0, 1000000000)) throw new Error('Each rate must be between MYR 0.00 and MYR 10,000,000.00.');
  return sen;
}
export function tariffInput(input) {
  const keys = ['expected_version', 'initial_duration_minutes', 'initial_charge_sen', 'subsequent_hourly_rate_sen', 'rounding_minutes', 'grace_minutes', 'maximum_charge_sen', 'effective_from'];
  if (!input || typeof input !== 'object' || Array.isArray(input) || Object.keys(input).some(key => !keys.includes(key)) ||
      !integer(input.expected_version, 0, 9007199254740989) || !integer(input.initial_duration_minutes, 1, 1440) ||
      !integer(input.initial_charge_sen, 0, 1000000000) || !integer(input.subsequent_hourly_rate_sen, 0, 1000000000) ||
      ![1, 15, 30, 60].includes(input.rounding_minutes) || !integer(input.grace_minutes, 0, 1440) ||
      !(input.maximum_charge_sen === null || integer(input.maximum_charge_sen, 0, 1000000000)) ||
      !(input.effective_from === null || timestamp(input.effective_from))) throw new Error('Check the rates and reload the latest version.');
  return Object.fromEntries(keys.map(key => [key, input[key]]));
}
export function tariffForm(draft, expectedVersion) {
  const whole = (value, label) => {
    if (!/^\d+$/.test(String(value))) throw new Error(`${label} must be a whole number of minutes.`);
    return Number(value);
  };
  let effective = null;
  if (draft.effective_from) {
    if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(draft.effective_from)) throw new Error('Choose a valid Malaysia date and time.');
    const date = new Date(`${draft.effective_from}:00+08:00`);
    if (!Number.isFinite(date.getTime()) || new Date(date.getTime() + 8 * 3600000).toISOString().slice(0, 16) !== draft.effective_from) throw new Error('Choose a valid Malaysia date and time.');
    effective = date.toISOString();
  }
  return tariffInput({ expected_version: expectedVersion,
    initial_duration_minutes: whole(draft.initial_duration_minutes, 'Initial duration'), initial_charge_sen: moneyInput(draft.initial_fee),
    subsequent_hourly_rate_sen: moneyInput(draft.hourly_fee), rounding_minutes: whole(draft.rounding_minutes, 'Billing increment'),
    grace_minutes: whole(draft.grace_minutes, 'Grace period'), maximum_charge_sen: moneyInput(draft.maximum_fee, true), effective_from: effective });
}
export function paymentDates(input, now = new Date()) {
  const start = input.get('start_date') || '', end = input.get('end_date') || '';
  if (!start && !end) return new URLSearchParams();
  for (const day of [start, end]) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || day < '1982-01-01' || !Number.isFinite(Date.parse(day)) || new Date(day).toISOString().slice(0, 10) !== day) throw new Error('Choose valid paired Malaysia calendar dates.');
  }
  return new URLSearchParams(analyticsQuery({ preset: 'custom', start_date: start, end_date: end }, now));
}
export function paymentQuery(kind, input = new URLSearchParams(), now = new Date()) {
  const allowed = kind === 'summary' ? ['start_date', 'end_date'] : kind === 'tariffs' ? ['limit', 'offset'] :
    ['limit', 'offset', 'status', 'method', 'driver_id', 'reference', 'start_date', 'end_date'];
  for (const key of input.keys()) if (!allowed.includes(key) || input.getAll(key).length !== 1) throw new Error('Use the supported payment filters only.');
  const query = kind === 'tariffs' ? new URLSearchParams() : paymentDates(input, now);
  if (kind !== 'summary') {
    for (const [key, fallback, max] of [['limit', '25', 100], ['offset', '0', 1000000]]) {
      const text = input.get(key) ?? fallback;
      if (!/^\d+$/.test(text) || !integer(Number(text), key === 'limit' ? 1 : 0, max)) throw new Error('Choose a valid payment page.');
      query.set(key, String(Number(text)));
    }
  }
  if (kind === 'transactions') {
    for (const [key, values] of [['status', attemptLabels], ['method', methodLabels]]) {
      const value = input.get(key); if (value && !Object.hasOwn(values, value)) throw new Error('Choose a valid payment status and method.');
      if (value) query.set(key, value);
    }
    const driver = input.get('driver_id'), reference = (input.get('reference') ?? '').trim();
    if (driver && !uuid(driver)) throw new Error('Use a valid driver reference.');
    if (driver) query.set('driver_id', driver.toLowerCase());
    if (reference && !/^[A-Za-z0-9:_-]{1,100}$/.test(reference)) throw new Error('Use a transaction or receipt reference with letters, numbers, colons, underscores or hyphens.');
    if (reference) query.set('reference', reference);
  }
  return query;
}
export function validatePaymentMeta(data) {
  if (!data || data.simulated !== true || data.currency !== 'MYR' || !['active', 'inactive'].includes(data.payment_mode) || !timestamp(data.server_time)) fail();
  return data;
}
export function validateTariff(row) {
  if (!row || !uuid(row.id) || !uuid(row.published_by) || !integer(row.version_number, 1, 9007199254740990) ||
      !timestamp(row.effective_from) || !timestamp(row.published_at) || row.currency !== 'MYR') fail();
  try { tariffInput({ expected_version: row.version_number - 1, ...Object.fromEntries(['initial_duration_minutes', 'initial_charge_sen', 'subsequent_hourly_rate_sen', 'rounding_minutes', 'grace_minutes', 'maximum_charge_sen', 'effective_from'].map(key => [key, row[key]])) }); } catch { fail(); }
  return row;
}
export function validateTransaction(row) {
  const a = row?.attempt, c = row?.charge, s = c?.session;
  if (!a || !c || !s || !uuid(a.id) || !uuid(c.id) || a.charge_id !== c.id || !uuid(c.session_id) || c.session_id !== s.id ||
      !uuid(c.user_id) || c.user_id !== s.user_id || !uuid(s.vehicle_id) || !uuid(s.zone_id) || !uuid(c.tariff_version_id) ||
      !['allocated', 'occupied', 'completed', 'cancelled'].includes(s.status) || !['open', 'pending', 'paid'].includes(c.status) ||
      !Object.hasOwn(attemptLabels, a.status) || !Object.hasOwn(methodLabels, a.method) || !integer(a.amount_sen, 0, 9000000000000) ||
      !integer(a.quote_revision, 1) || !integer(c.quote_revision) || a.currency !== 'MYR' || c.currency !== 'MYR' ||
      !(c.amount_sen === null || integer(c.amount_sen, 0, 9000000000000)) || typeof a.provider_reference !== 'string' || !a.provider_reference || a.provider_reference.length > 128 ||
      !timestamp(a.created_at) || !timestamp(a.updated_at) || !timestamp(s.entry_time) ||
      ![a.settled_at, c.paid_at, c.quote_expires_at, c.first_exit_detected_at, s.exit_time, s.parking_confirmed_at].every(optionalTime)) fail();
  validateTariff(c.tariff);
  if (c.tariff.id !== c.tariff_version_id || (s.current_vehicle != null && (s.current_vehicle.id !== s.vehicle_id || typeof s.current_vehicle.plate_number !== 'string')) ||
      (c.current_driver != null && (c.current_driver.id !== c.user_id || typeof c.current_driver.full_name !== 'string'))) fail();
  if ((a.method === 'zero' && a.amount_sen !== 0) || (a.status !== 'succeeded' && (a.settled_at !== null || a.receipt_number !== null))) fail();
  if (a.status === 'succeeded' && (c.status !== 'paid' || s.status !== 'completed' || a.amount_sen !== c.amount_sen || a.quote_revision !== c.quote_revision ||
      !timestamp(a.settled_at) || !a.receipt_number || a.settled_at !== c.paid_at || a.settled_at !== s.exit_time)) fail();
  return row;
}
export function validatePaymentPage(data, kind, query) {
  validatePaymentMeta(data);
  if (!integer(data.total) || !integer(data.limit, 1, 100) || !integer(data.offset, 0, 1000000) || typeof data.has_more !== 'boolean' ||
      !Array.isArray(data[kind]) || data[kind].length > data.limit || data[kind].length > Math.max(0, data.total - data.offset) ||
      data.has_more !== (data.offset + data[kind].length < data.total) ||
      (query && (data.limit !== Number(query.get('limit')) || data.offset !== Number(query.get('offset'))))) fail();
  data[kind].forEach(kind === 'tariffs' ? validateTariff : validateTransaction);
  const ids = data[kind].map(row => kind === 'tariffs' ? row.id : row.attempt.id);
  if (new Set(ids).size !== ids.length) fail();
  if (kind === 'tariffs') {
    if (data.effective_tariff !== null) validateTariff(data.effective_tariff);
    if (data.tariffs.some((row, index) => index > 0 && row.version_number >= data.tariffs[index - 1].version_number)) fail();
  }
  if (kind === 'transactions' && query && data.transactions.some(row =>
    (query.get('status') && row.attempt.status !== query.get('status')) || (query.get('method') && row.attempt.method !== query.get('method')) ||
    (query.get('driver_id') && row.charge.user_id !== query.get('driver_id')))) fail();
  return data;
}
export const totalFields = ['parking_revenue_sen', 'successful_payments', 'wallet_parking_revenue_sen', 'mock_card_parking_revenue_sen', 'zero_fee_payments', 'wallet_top_ups_sen', 'wallet_top_up_count', 'unpaid_quoted_sen', 'unpaid_quoted_charges', 'unquoted_sessions'];
export function validatePaymentSummary(data) {
  validatePaymentMeta(data);
  if (data.timezone !== 'Asia/Kuala_Lumpur' || data.unpaid_scope !== 'current_outstanding' || !timestamp(data.period_start) || !timestamp(data.period_end) ||
      Date.parse(data.period_start) >= Date.parse(data.period_end) || !data.totals || totalFields.some(key => !integer(data.totals[key])) ||
      data.totals.parking_revenue_sen !== data.totals.wallet_parking_revenue_sen + data.totals.mock_card_parking_revenue_sen ||
      data.totals.zero_fee_payments > data.totals.successful_payments) fail();
  return data;
}
export function todayPaymentQuery(now = new Date()) {
  const day = malaysiaToday(now); return `start_date=${day}&end_date=${day}`;
}
