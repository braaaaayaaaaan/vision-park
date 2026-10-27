"""Ownership-scoped payment workflows. Prices and settlement come only from 021."""
from datetime import datetime, timezone
from functools import wraps
from uuid import UUID

from fastapi import HTTPException
from pydantic import ValidationError

from backend.payments import data, gateway, models
from backend.parking.analytics import analytics_period


def checked(function):
    @wraps(function)
    def wrapped(*args, **kwargs):
        try:
            return function(*args, **kwargs)
        except (ValidationError, ValueError, KeyError, TypeError, OverflowError):
            data.unavailable()
    return wrapped


def context(active=False):
    row = data.control()
    if row is None or 'activated_at' not in row or 'backend_contract' not in row:
        data.fail(503, 'finance_schema_unavailable', 'Payment storage is unavailable. Ask an administrator to check the finance setup.')
    if row['activated_at'] is None:
        if row['backend_contract'] is not None:
            data.unavailable()
        mode = 'inactive'
    else:
        if row['backend_contract'] != 'visionpark-payments-v1':
            data.unavailable()
        stamp = datetime.fromisoformat(str(row['activated_at']).replace('Z', '+00:00'))
        if stamp.tzinfo is None:
            data.unavailable()
        mode = 'active'
    if active and mode != 'active':
        data.fail(409, 'payments_inactive', 'Parking payments have not been activated. Existing parking access is unchanged.')
    return dict(payment_mode=mode, simulated=True, currency='MYR', server_time=datetime.now(timezone.utc))


def key(operation, user_id, client_key):
    return f'{operation}:{UUID(str(user_id))}:{client_key}'


def owned_charge(charge_id, user_id=None):
    row = data.charge(str(charge_id), str(user_id) if user_id else None)
    if row is None or (user_id and row.get('user_id') != str(user_id)):
        data.fail(404, 'payment_not_found', 'Payment request not found.')
    charge = models.Charge.model_validate(row)
    if charge.id != UUID(str(charge_id)):
        raise ValueError('Charge identifier mismatch')
    return charge


def attempt_view(row):
    attempt = models.Attempt.model_validate(row)
    result = attempt.model_dump(mode='json')
    profile = gateway.profile_id(row.get('mock_scenario')) if attempt.method == 'mock_card' else None
    if attempt.method == 'mock_card' and profile is None:
        raise ValueError('Unknown mock provider profile')
    result['card_profile'] = profile
    return result


def transaction_view(row, user_id=None, receipt=False):
    charge = models.Charge.model_validate(row['charge'])
    if user_id and charge.user_id != UUID(str(user_id)):
        data.fail(404, 'payment_not_found', 'Payment record not found.')
    attempt = models.Attempt.model_validate(row)
    if attempt.charge_id != charge.id:
        raise ValueError('Attempt charge mismatch')
    if receipt and attempt.status != 'succeeded':
        data.fail(404, 'receipt_not_found', 'Receipt not found.')
    if attempt.status == 'succeeded' and (charge.status != 'paid' or
            (attempt.amount_sen, attempt.currency, attempt.quote_revision, attempt.settled_at) !=
            (charge.amount_sen, charge.currency, charge.quote_revision, charge.paid_at)):
        raise ValueError('Receipt proof mismatch')
    return dict(attempt=attempt_view(row), charge=charge.model_dump(mode='json'))


def owned_attempt(attempt_id, user_id=None):
    row = data.attempt(str(attempt_id), str(user_id) if user_id else None)
    if row is None:
        data.fail(404, 'payment_not_found', 'Payment record not found.')
    if UUID(str(row['id'])) != UUID(str(attempt_id)):
        raise ValueError('Attempt identifier mismatch')
    transaction_view(row, user_id)
    return row


def page_result(meta, items, total, limit, offset, name):
    return dict(meta, **{name: items}, total=total, limit=limit, offset=offset, has_more=offset+len(items)<total)


CONFLICTS = {
    'stale': 'This record changed. Refresh its revision before saving.',
    'stale_quote': 'The quotation changed. Refresh the payment request.',
    'quote_expired': 'The quotation expired. Renew it before starting payment.',
    'in_progress': 'A payment is already processing. Verify that attempt before starting another.',
    'already_paid': 'This parking charge is already paid. Open its receipt.',
    'manual_required': 'Automatic wallet payment is disabled. Use simulated card checkout or update the preference.',
}


def accepted(payload, statuses):
    status = payload['status']
    if status in CONFLICTS:
        data.fail(409, status, CONFLICTS[status])
    if status not in statuses:
        data.unavailable()
    return payload


def validate_rpc_attempt(payload, charge_id, stored_key=None, attempt_id=None, methods=('mock_card',)):
    accepted(payload, ('processing', 'unknown', 'succeeded', 'declined', 'failed'))
    row = payload['attempt']
    attempt = models.Attempt.model_validate(row)
    if (str(attempt.charge_id) != str(charge_id) or attempt.status != payload['status'] or attempt.method not in methods
            or (stored_key is not None and row.get('idempotency_key') != stored_key)
            or (attempt_id is not None and str(attempt.id) != str(attempt_id))):
        raise ValueError('Unexpected payment RPC result')
    return row


@checked
def wallet(user_id):
    meta = context()
    row = data.wallet(str(user_id))
    result = models.Wallet.model_validate(row if row is not None else dict(user_id=user_id))
    if result.user_id != UUID(str(user_id)):
        raise ValueError('Wallet owner mismatch')
    return dict(meta, wallet=result.model_dump(mode='json'))


@checked
def preferences(user_id, change):
    meta = context()
    result = accepted(data.rpc('set_wallet_preferences', dict(p_user_id=str(user_id),
        p_expected_revision=change.expected_revision, p_enabled=change.automatic_payment_enabled)), ('saved',))
    item = models.Wallet.model_validate(result['wallet'])
    if (item.user_id != UUID(str(user_id)) or item.automatic_payment_enabled != change.automatic_payment_enabled
            or item.preference_revision != change.expected_revision+1):
        raise ValueError('Preference result mismatch')
    return dict(meta, wallet=item.model_dump(mode='json'))


@checked
def top_up(user_id, change, client_key):
    meta = context()
    stored_key = key('topup', user_id, client_key)
    result = accepted(data.rpc('simulate_wallet_top_up', dict(p_user_id=str(user_id),
        p_amount_sen=change.amount_sen, p_idempotency_key=stored_key)), ('credited',))
    item = models.LedgerEntry.model_validate(result['entry'])
    if (item.user_id != UUID(str(user_id)) or item.amount_sen != change.amount_sen or item.entry_type != 'mock_top_up'
            or result['entry'].get('operation_key') != stored_key):
        raise ValueError('Top-up result mismatch')
    return dict(meta, status='credited', entry=item.model_dump(mode='json'))


@checked
def wallet_history(user_id, limit, offset, kind=None):
    meta = context()
    rows, total = data.ledger_page(str(user_id), limit, offset, kind)
    items = [models.LedgerEntry.model_validate(row) for row in rows]
    if any(item.user_id != UUID(str(user_id)) or (kind and item.entry_type != kind) for item in items):
        raise ValueError('Ledger scope mismatch')
    return page_result(meta, [item.model_dump(mode='json') for item in items], total, limit, offset, 'entries')


@checked
def requests(user_id, limit, offset, status='pending'):
    meta = context()
    rows, total = data.charge_page(str(user_id), limit, offset, status)
    items = [models.Charge.model_validate(row) for row in rows]
    if any(item.user_id != UUID(str(user_id)) or (status != 'all' and item.status != status) for item in items):
        raise ValueError('Charge scope mismatch')
    return page_result(meta, [item.model_dump(mode='json') for item in items], total, limit, offset, 'charges')


@checked
def request_details(user_id, charge_id):
    meta = context()
    charge = owned_charge(charge_id, user_id)
    latest = data.latest_attempt(str(charge.id))
    if latest is not None and UUID(str(latest['charge_id'])) != charge.id:
        raise ValueError('Latest attempt mismatch')
    view = attempt_view(latest) if latest else None
    state = 'not_quoted'
    if charge.status == 'paid':
        state = 'paid'
    elif view and view['status'] in ('processing', 'unknown'):
        state = 'in_progress'
    elif charge.status == 'pending':
        state = 'expired' if charge.quote_expires_at <= meta['server_time'] else 'valid'
    return dict(meta, charge=charge.model_dump(mode='json'), latest_attempt=view, quote_state=state)


@checked
def renew(user_id, charge_id, change):
    context(active=True)
    owned_charge(charge_id, user_id)
    result = accepted(data.rpc('refresh_parking_payment_quote', dict(p_user_id=str(user_id),
        p_charge_id=str(charge_id), p_expected_revision=change.expected_revision)), ('valid', 'renewed'))
    if str(result['charge']['id']) != str(charge_id) or str(result['charge']['user_id']) != str(user_id):
        raise ValueError('Renewal identity mismatch')
    return dict(request_details(user_id, charge_id), status=result['status'])


@checked
def card_profiles():
    return dict(context(), profiles=gateway.profiles(), notice='Simulation only. Do not enter real card information.')


@checked
def checkout(user_id, charge_id, change, client_key):
    meta = context(active=True)
    owned_charge(charge_id, user_id)
    stored_key = key('checkout', user_id, client_key)
    result = gateway.begin(str(user_id), str(charge_id), change.quote_revision, stored_key, change.card_profile)
    row = validate_rpc_attempt(result, charge_id, stored_key)
    if gateway.profile_id(row.get('mock_scenario')) != change.card_profile:
        raise ValueError('Card profile mismatch')
    attempt_id = row['id']
    if result['status'] == 'processing':
        try:
            verify_result = gateway.verify(str(user_id), str(attempt_id))
            validate_rpc_attempt(verify_result, charge_id, stored_key, attempt_id)
        except HTTPException as error:
            # Preserve a known durable reference when settlement response is lost.
            if error.status_code == 503:
                error.detail = dict(error.detail, attempt_id=str(attempt_id), provider_reference=row['provider_reference'])
            raise
    return dict(meta, **transaction_view(owned_attempt(attempt_id, user_id), user_id))


@checked
def wallet_payment(user_id, charge_id, change, client_key):
    meta = context(active=True)
    owned_charge(charge_id, user_id)
    stored_key = key('wallet', user_id, client_key)
    result = data.rpc('pay_parking_charge_with_wallet', dict(p_user_id=str(user_id), p_charge_id=str(charge_id),
        p_quote_revision=change.quote_revision, p_idempotency_key=stored_key))
    row = validate_rpc_attempt(result, charge_id, stored_key, methods=('wallet', 'zero'))
    return dict(meta, **transaction_view(owned_attempt(row['id'], user_id), user_id))


@checked
def verify(user_id, attempt_id, reconcile=False):
    meta = context(active=True)
    row = owned_attempt(attempt_id, user_id)
    if row['method'] != 'mock_card':
        data.fail(409, 'not_mock_card', 'Only a simulated card attempt can be verified through this gateway.')
    if row['status'] not in ('succeeded', 'declined', 'failed'):
        result = gateway.verify(str(user_id), str(attempt_id), reconcile)
        validate_rpc_attempt(result, row['charge_id'], attempt_id=attempt_id)
    return dict(meta, **transaction_view(owned_attempt(attempt_id, user_id), user_id))


@checked
def attempt_details(user_id, attempt_id):
    return dict(context(), **transaction_view(owned_attempt(attempt_id, user_id), user_id))


@checked
def attempt_by_key(user_id, client_key):
    meta = context()
    row = data.attempt(user_id=str(user_id), key=key('checkout', user_id, client_key))
    if row is None:
        data.fail(404, 'payment_not_found', 'Payment record not found.')
    return dict(meta, **transaction_view(row, user_id))


def date_range(start, end, now, default=False):
    if start is None and end is None and not default:
        return None, None
    try:
        _, _, first, last = analytics_period(start, end, now)
        return first.isoformat(), last.isoformat()
    except ValueError as error:
        data.fail(422, 'invalid_date_range', str(error))


@checked
def receipts(user_id, limit, offset, start=None, end=None):
    meta = context()
    first, last = date_range(start, end, meta['server_time'])
    rows, total = data.attempt_page(limit, offset, str(user_id), status='succeeded', start=first, end=last, receipts=True)
    return page_result(meta, [transaction_view(row, user_id, receipt=True) for row in rows], total, limit, offset, 'receipts')


@checked
def receipt(user_id, attempt_id):
    return dict(context(), **transaction_view(owned_attempt(attempt_id, user_id), user_id, receipt=True))


@checked
def tariffs(limit, offset):
    meta = context()
    rows, total = data.tariff_page(limit, offset)
    effective = data.effective_tariff(meta['server_time'].isoformat())
    return dict(page_result(meta, [models.Tariff.model_validate(row).model_dump(mode='json') for row in rows],
        total, limit, offset, 'tariffs'), effective_tariff=models.Tariff.model_validate(effective).model_dump(mode='json') if effective else None)


@checked
def publish_tariff(admin_id, change):
    meta = context()
    result = accepted(data.rpc('publish_parking_tariff', dict(p_admin_id=str(admin_id), p_expected_version=change.expected_version,
        p_initial_minutes=change.initial_duration_minutes, p_initial_sen=change.initial_charge_sen,
        p_hourly_sen=change.subsequent_hourly_rate_sen, p_rounding_minutes=change.rounding_minutes,
        p_grace_minutes=change.grace_minutes, p_maximum_sen=change.maximum_charge_sen,
        p_effective_from=change.effective_from.isoformat() if change.effective_from else None)), ('published',))
    item = models.Tariff.model_validate(result['tariff'])
    if item.published_by != UUID(str(admin_id)) or item.version_number != change.expected_version+1:
        raise ValueError('Tariff publication identity mismatch')
    return dict(meta, tariff=item.model_dump(mode='json'))


@checked
def transactions(limit, offset, status=None, method=None, user_id=None, reference='', start=None, end=None):
    meta = context()
    first, last = date_range(start, end, meta['server_time'])
    rows, total = data.attempt_page(limit, offset, str(user_id) if user_id else None, status, method, reference, first, last)
    items = [transaction_view(row, user_id) for row in rows]
    if any((status and item['attempt']['status'] != status) or (method and item['attempt']['method'] != method) for item in items):
        raise ValueError('Transaction filter mismatch')
    return page_result(meta, items, total, limit, offset, 'transactions')


@checked
def transaction_details(attempt_id):
    return dict(context(), **transaction_view(owned_attempt(attempt_id)))


@checked
def summary(start=None, end=None):
    meta = context()
    first, last = date_range(start, end, meta['server_time'], default=True)
    cutoff = meta['server_time'].isoformat()
    totals = dict(parking_revenue_sen=0, successful_payments=0, wallet_parking_revenue_sen=0,
        mock_card_parking_revenue_sen=0, zero_fee_payments=0, wallet_top_ups_sen=0, wallet_top_up_count=0,
        unpaid_quoted_sen=0, unpaid_quoted_charges=0, unquoted_sessions=0)
    for row in data.scan('payment_attempts', 'id,status,method,amount_sen,currency,settled_at',
            [('eq','status','succeeded'), ('gte','settled_at',first), ('lt','settled_at',last), ('lte','settled_at',cutoff)]):
        if row['status'] != 'succeeded' or row['currency'] != 'MYR' or type(row['amount_sen']) is not int or row['amount_sen'] < 0:
            raise ValueError('Invalid revenue record')
        totals['parking_revenue_sen'] += row['amount_sen']
        totals['successful_payments'] += 1
        if row['method'] == 'zero':
            if row['amount_sen'] != 0:
                raise ValueError('Nonzero free exit')
            totals['zero_fee_payments'] += 1
        elif row['method'] in ('wallet', 'mock_card'):
            totals[row['method']+'_parking_revenue_sen'] += row['amount_sen']
        else:
            raise ValueError('Unknown payment method')
    for row in data.scan('wallet_ledger', 'id,entry_type,amount_sen,created_at',
            [('eq','entry_type','mock_top_up'), ('gte','created_at',first), ('lt','created_at',last), ('lte','created_at',cutoff)]):
        if row['entry_type'] != 'mock_top_up' or type(row['amount_sen']) is not int or row['amount_sen'] <= 0:
            raise ValueError('Invalid top-up record')
        totals['wallet_top_ups_sen'] += row['amount_sen']
        totals['wallet_top_up_count'] += 1
    for row in data.scan('session_charges', 'id,status,amount_sen,currency,created_at',
            [('in_','status',['open','pending']), ('lte','created_at',cutoff)]):
        if row['currency'] != 'MYR':
            raise ValueError('Invalid currency')
        if row['status'] == 'open' and row['amount_sen'] is None:
            totals['unquoted_sessions'] += 1
        elif row['status'] == 'pending' and type(row['amount_sen']) is int and row['amount_sen'] >= 0:
            totals['unpaid_quoted_sen'] += row['amount_sen']
            totals['unpaid_quoted_charges'] += 1
        else:
            raise ValueError('Invalid unpaid charge')
    return dict(meta, timezone='Asia/Kuala_Lumpur', period_start=first, period_end=last,
        unpaid_scope='current_outstanding', totals=totals)
