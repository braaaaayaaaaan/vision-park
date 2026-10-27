import { ACCESS_COOKIE, AuthError, baseUrl, restoreSession, requireSameOrigin } from './auth.mjs';
import { readLimitedBody } from './parking-structure-api.mjs';
import { uuid, paymentQuery, tariffInput, validatePaymentMeta, validateTariff, validateTransaction, validatePaymentPage, validatePaymentSummary } from './payment-contracts.mjs';

export async function handlePayments(request, path = []) {
  const writing = request.method === 'POST';
  try {
    const kind = path[0], id = path[1]?.toLowerCase();
    if (!['tariffs', 'transactions', 'summary'].includes(kind) || path.length > 2 ||
        (path.length === 2 && (kind !== 'transactions' || !uuid(id))) ||
        !(request.method === 'GET' || (writing && kind === 'tariffs' && path.length === 1))) return { status: 404, body: { error: 'Payment endpoint not found.' } };
    if (writing) requireSameOrigin(request);
    await restoreSession(request.cookies.get(ACCESS_COOKIE)?.value);
    let query, input;
    try {
      const params = new URL(request.url).searchParams;
      if ((writing || id) && params.size) throw new Error('This payment operation does not accept filters.');
      query = writing || id ? null : paymentQuery(kind, params);
      if (writing) {
        if (request.headers.get('content-type')?.split(';')[0].toLowerCase() !== 'application/json') throw new AuthError('input', 415);
        input = tariffInput(JSON.parse((await readLimitedBody(request.body, 4096)).toString()));
      }
    } catch (error) {
      if (error instanceof AuthError) throw error;
      return { status: 422, body: { error: error instanceof SyntaxError ? 'Use valid JSON tariff fields.' : error.message } };
    }
    const response = await fetch(`${baseUrl(process.env.BACKEND_BASE_URL)}/admin/payments/${kind}${id ? `/${id}` : ''}${query?.size ? `?${query}` : ''}`, {
      method: request.method, headers: { Authorization: `Bearer ${request.cookies.get(ACCESS_COOKIE)?.value}`, Accept: 'application/json', ...(writing ? { 'Content-Type': 'application/json' } : {}) },
      ...(writing ? { body: JSON.stringify(input) } : {}), cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(20000),
    });
    if ([401, 403].includes(response.status)) throw new AuthError(response.status === 401 ? 'expired' : 'denied', response.status);
    if (!response.ok) {
      const code = (await response.json().catch(() => null))?.detail?.code;
      const status = [404, 409, 413, 415, 422, 429].includes(response.status) ? response.status : 503;
      const safeCode = ['stale', 'busy', 'payments_inactive', 'finance_schema_unavailable'].includes(code) ? code : 'payment_unavailable';
      return { status, body: { code: safeCode, error: status === 409 ? 'Rates changed or publication is busy. Close the form and reload the latest version before publishing.' :
        status === 422 ? 'Check the tariff values, effective time and latest version.' : status === 404 ? 'Payment transaction not found.' :
          status === 429 ? 'Too many requests. Wait briefly and refresh.' : writing ? 'Publication could not be confirmed. Reload rates to check whether it committed before trying again.' :
            'Unable to load payments. Refresh to try again.' } };
    }
    const data = await response.json();
    if (writing) {
      validatePaymentMeta(data); validateTariff(data.tariff);
      if (data.tariff.version_number !== input.expected_version + 1 || Object.keys(input).some(key => !['expected_version', 'effective_from'].includes(key) && input[key] !== data.tariff[key])) throw new Error('Unconfirmed tariff');
    } else if (id) {
      validatePaymentMeta(data); validateTransaction(data); if (data.attempt.id !== id) throw new Error('Unexpected transaction');
    } else if (kind === 'summary') validatePaymentSummary(data);
    else validatePaymentPage(data, kind, query);
    return { status: writing ? 201 : 200, body: data };
  } catch (error) {
    return { status: error instanceof AuthError ? error.status : 503, body: { error: error instanceof AuthError ?
      error.status === 413 ? 'Tariff requests must be at most 4 KiB.' : error.status === 415 ? 'Use a JSON tariff request.' : error.message :
        writing ? 'Publication could not be confirmed. Reload rates before trying again.' : 'Financial data could not be verified. Refresh and try again.' } };
  }
}
