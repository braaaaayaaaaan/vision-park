"""Service-role reads and a closed set of 021 RPCs. No direct finance writes."""
from fastapi import HTTPException

from backend import database

RPCS = frozenset({'set_wallet_preferences', 'simulate_wallet_top_up', 'refresh_parking_payment_quote',
                  'pay_parking_charge_with_wallet', 'begin_mock_parking_payment', 'settle_mock_parking_payment',
                  'publish_parking_tariff'})
SESSION = ('session:parking_sessions!session_id(id,vehicle_id,user_id,zone_id,entry_time,parking_confirmed_at,exit_time,status,'
           'current_vehicle:vehicles!vehicle_id(id,plate_number),current_zone:parking_zones!zone_id(id,name,level:parking_levels!level_id(id,name)))')
CHARGE = ('*,tariff:parking_tariff_versions!tariff_version_id(*),'
          'current_driver:users!user_id(id,full_name,tenant_id,tenant:tenants!tenant_id(id,name)),'+SESSION)
ATTEMPT = '*,charge:session_charges!charge_id!inner('+CHARGE+')'


def fail(status, code, message, **extra):
    raise HTTPException(status, detail=dict(code=code, message=message, **extra), headers={'Cache-Control':'private, no-store'})


def unavailable():
    fail(503, 'payments_unavailable', 'Payment information could not be verified. Please retry.')


def execute(query, operation=None):
    try:
        return database._execute(query)
    except database.DatabaseError as error:
        classify(error, operation)


def classify(error, operation=None):
    code = getattr(error.__context__, 'code', None)
    if code in ('PGRST200', 'PGRST202', 'PGRST204', '42P01', '42703', '42883'):
        fail(503, 'finance_schema_unavailable', 'Payment storage is unavailable. Ask an administrator to check the finance setup.')
    if code in ('55P03', '40P01', '40001'):
        fail(409, 'payment_busy', 'Another operation is in progress. Verify the result before retrying with the same key.', retry_same_key=True)
    if operation:
        if code == 'P0002':
            fail(404, 'payment_not_found', 'Payment record not found.')
        if code == '42501':
            fail(403, 'payment_forbidden', 'This payment operation is not permitted.')
        if code == '22023':
            if operation == 'publish_parking_tariff':
                fail(422, 'invalid_tariff', 'Use valid tariff rules and a chronological effective time.')
            fail(409, 'idempotency_conflict', 'This operation conflicts with the saved request. Reuse a key only with the original details.')
        if code in ('23505', '23514', '23503', '23502', '25001', '22003'):
            fail(409, 'payment_conflict', 'Payment state changed or could not be safely updated. Refresh the saved result before retrying.')
        fail(503, 'payment_result_unconfirmed', 'The result could not be confirmed. Check the saved record and retry only with the same key.', retry_same_key=True)
    unavailable()


def client():
    try:
        return database.get_supabase()
    except database.DatabaseError:
        unavailable()


def rpc(name, params):
    if name not in RPCS:
        raise ValueError('Payment RPC not permitted')
    payload = execute(client().rpc(name, params), name).data
    if not isinstance(payload, dict) or not isinstance(payload.get('status'), str):
        unavailable()
    return payload


def one(query):
    rows = execute(query.limit(1)).data
    if not isinstance(rows, list) or (rows and not isinstance(rows[0], dict)):
        unavailable()
    return rows[0] if rows else None


def control():
    return one(client().table('parking_payment_control').select('activated_at,backend_contract').eq('singleton', True))


def wallet(user_id):
    return one(client().table('wallets').select('*').eq('user_id', user_id))


def charge(charge_id, user_id=None):
    query = client().table('session_charges').select(CHARGE).eq('id', charge_id)
    if user_id is not None:
        query = query.eq('user_id', user_id)
    return one(query)


def attempt(attempt_id=None, user_id=None, key=None):
    query = client().table('payment_attempts').select(ATTEMPT)
    query = query.eq('id', attempt_id) if attempt_id is not None else query.eq('idempotency_key', key)
    if user_id is not None:
        query = query.eq('charge.user_id', user_id)
    return one(query)


def latest_attempt(charge_id):
    return one(client().table('payment_attempts').select('*').eq('charge_id', charge_id)
               .order('created_at', desc=True).order('id', desc=True))


def page(make_query, limit, offset, order='created_at'):
    # Each builder is fresh; SDK range/order methods mutate its parameters.
    query = make_query().order(order, desc=True).order('id', desc=True).range(offset, offset+limit-1)
    try:
        result = database._execute(query)
    except database.DatabaseError as error:
        if offset and getattr(error.__context__, 'code', None) == 'PGRST103':
            result = execute(make_query().range(0, 0))
            if type(result.count) is int and offset >= result.count:
                return [], result.count
        classify(error)
    if (not isinstance(result.data, list) or type(result.count) is not int or result.count < 0
            or len(result.data) > limit or result.count < len(result.data)):
        unavailable()
    if len({row.get('id') for row in result.data if isinstance(row, dict)}) != len(result.data):
        unavailable()
    return result.data, result.count


def ledger_page(user_id, limit, offset, kind=None, start=None, end=None):
    def query():
        q = client().table('wallet_ledger').select('*', count='exact').eq('user_id', user_id)
        if kind:
            q = q.eq('entry_type', kind)
        if start is not None:
            q = q.gte('created_at', start).lt('created_at', end)
        return q
    return page(query, limit, offset)


def charge_page(user_id, limit, offset, status='pending'):
    def query():
        q = client().table('session_charges').select(CHARGE, count='exact').eq('user_id', user_id)
        return q.eq('status', status) if status != 'all' else q
    return page(query, limit, offset)


def attempt_page(limit, offset, user_id=None, status=None, method=None, reference='', start=None, end=None, receipts=False):
    def query():
        q = client().table('payment_attempts').select(ATTEMPT, count='exact')
        if user_id is not None:
            q = q.eq('charge.user_id', user_id)
        if status:
            q = q.eq('status', status)
        if method:
            q = q.eq('method', method)
        if reference:
            q = q.or_(f'provider_reference.ilike.%{reference}%,receipt_number.ilike.%{reference}%')
        if start is not None:
            q = q.gte('settled_at' if receipts else 'created_at', start).lt('settled_at' if receipts else 'created_at', end)
        return q
    return page(query, limit, offset, 'settled_at' if receipts else 'created_at')


def tariff_page(limit, offset):
    return page(lambda: client().table('parking_tariff_versions').select('*', count='exact'), limit, offset, 'version_number')


def effective_tariff(now):
    return one(client().table('parking_tariff_versions').select('*').lte('effective_from', now).order('effective_from', desc=True))


def scan(table, fields, filters):
    """Keyset batches avoid Supabase row caps and offset shifts on unpaid rows."""
    last = None
    while True:
        query = client().table(table).select(fields)
        for operation, field, value in filters:
            query = getattr(query, operation)(field, value)
        if last:
            query = query.gt('id', last)
        rows = execute(query.order('id').limit(500)).data
        if not isinstance(rows, list):
            unavailable()
        if not rows:
            return
        previous = last
        for row in rows:
            if not isinstance(row, dict) or not isinstance(row.get('id'), str) or (previous and row['id'] <= previous):
                unavailable()
            previous = row['id']
            yield row
        last = previous
