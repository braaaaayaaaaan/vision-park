import { authenticatedFetch } from '../../../lib/auth-client.mjs';
import { paymentQuery, tariffInput, validatePaymentPage, validatePaymentSummary, validatePaymentMeta, validateTransaction, validateTariff } from '../../../lib/payment-contracts.mjs';

async function request(path, options = {}) {
  const response = await authenticatedFetch(`/api/payments/${path}`, { cache: 'no-store', ...options });
  const data = await response.json().catch(() => null);
  if (!response.ok) {
    const error = new Error(data?.error || 'Financial data could not be confirmed. Refresh to try again.');
    error.status = response.status; error.code = data?.code; throw error;
  }
  return data;
}
export function transactionQuery(filters = {}, offset = 0, limit = 25, now = new Date()) {
  return paymentQuery('transactions', new URLSearchParams({ ...filters, limit: String(limit), offset: String(offset) }), now).toString();
}
export async function fetchTransactions(query, signal) {
  const params = paymentQuery('transactions', new URLSearchParams(query));
  return validatePaymentPage(await request(`transactions?${params}`, { signal }), 'transactions', params);
}
export async function fetchTransaction(id, signal) {
  const result = await request(`transactions/${id}`, { signal }); validatePaymentMeta(result); validateTransaction(result);
  if (result.attempt.id !== id) throw new Error('Unexpected payment transaction.');
  return result;
}
export async function fetchTariffs(offset = 0, signal) {
  const params = paymentQuery('tariffs', new URLSearchParams({ limit: '25', offset: String(offset) }));
  return validatePaymentPage(await request(`tariffs?${params}`, { signal }), 'tariffs', params);
}
export async function publishTariff(input) {
  const body = tariffInput(input);
  const result = await request('tariffs', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal: AbortSignal.timeout(25000) });
  validatePaymentMeta(result); validateTariff(result.tariff);
  if (result.tariff.version_number !== body.expected_version + 1) throw new Error('Reload rates to verify the publication result.');
  return result;
}
export async function fetchPaymentSummary(query = '', signal) {
  const params = paymentQuery('summary', new URLSearchParams(query));
  return validatePaymentSummary(await request(`summary${params.size ? `?${params}` : ''}`, { signal }));
}
// No administrator session-charge endpoint exists. Check transaction pages
// explicitly; a partial scan must never be reported as no payment recorded.
export async function findSessionPayment(sessionId, offset, signal) {
  const data = await fetchTransactions(transactionQuery({}, offset, 100), signal);
  return { transaction: data.transactions.find(row => row.charge.session_id === sessionId) ?? null,
    hasMore: data.has_more, nextOffset: data.offset + data.transactions.length };
}
