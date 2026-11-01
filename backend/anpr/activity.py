"""Administrator-only projections of existing ANPR receipts. No writes."""
import re
from backend import database as db

FIELDS = ('id,event_id,playback_id,plate_number,camera_id,camera_role,event_time,'
          'source_time_seconds,vehicle_id,session_id,processing_status,processing_result,'
          'session:parking_sessions!session_id(id,status,entry_time,parking_confirmed_at,exit_time,'
          'zone:parking_zones!zone_id(name,level:parking_levels!level_id(name)))')
OUTCOMES = ('allocated', 'completed', 'rejected', 'payment_required', 'payment_pending',
            'payment_succeeded', 'registered', 'processed', 'pending', 'unmatched', 'error')
REASONS = {
    'unknown_vehicle': 'The recognised plate is not registered.',
    'registration_not_approved': 'Vehicle registration is not approved.',
    'inactive_user': 'The vehicle owner is inactive.',
    'inactive_tenant': 'The associated company is inactive.',
    'no_authorised_zones': 'The company has no authorised parking zones.',
    'zones_full': 'All eligible parking zones are full.',
    'zones_unavailable': 'Eligible parking zones are unavailable.',
    'no_operational_zones': 'No authorised zones are operational.',
    'no_reachable_zones': 'No available zone is reachable from the entrance.',
    'existing_active_session': 'This vehicle already has an active session.',
    'no_active_session': 'No active parking session was found.',
    'payment_required': 'Payment is required by driver before exiting the parking building.',
    'payment_pending': 'Payment is pending; exit has not been confirmed.',
    'database_unavailable': 'The outcome is unconfirmed. Recover the original run.',
    'configuration_changed': 'Parking configuration changed. Inspect the original run.',
    'stale_event': 'A newer stay exists; this event cannot create another stay.',
    'event_rejected': 'This recognition event was already rejected.',
    'invalid_event': 'Recognition did not satisfy the trusted event contract.',
    'zone_not_authorised': 'The assigned zone is not authorised for the company.',
    'zone_unavailable': 'The assigned zone is unavailable.',
    'invalid_graph': 'The operational driving graph is invalid.',
    'invalid_entrance': 'The operational building entrance is invalid.',
    'invalid_zone_entrance': 'An eligible zone does not have a valid entrance.',
}


def outcome(row):
    result = row.get('processing_result') or {}
    allocation = result.get('allocation')
    if isinstance(allocation, dict) and allocation.get('status') == 'allocated':
        return 'allocated'
    # Only use saved outcomes; a current completed session is not proof of an
    # historical exit result. Unknown contracts remain visibly unclassified.
    for candidate in (result.get('exit_result'), result.get('result'), result.get('exit'), result):
        if isinstance(candidate, dict):
            value = candidate.get('status') or candidate.get('stage')
            if value in OUTCOMES:
                return value
    return row['processing_status'] if row.get('processing_status') in OUTCOMES else 'unclassified'


def project(row):
    result = row.get('processing_result') or {}
    allocation = result.get('allocation') or {}
    code = result.get('code')
    code = code if isinstance(code, str) and re.fullmatch(r'[a-z][a-z0-9_]{0,63}', code) else None
    session = row.get('session')
    status = outcome(row)
    return dict(id=row['id'], event_id=row['event_id'], playback_id=row.get('playback_id'),
                plate_number=row['plate_number'], camera_role=row['camera_role'],
                camera_id=row['camera_id'], accepted_event_time=row['event_time'],
                source_time_seconds=row.get('source_time_seconds'),
                processing_status=row['processing_status'], outcome=status,
                reason=REASONS.get(code) or REASONS.get(status) or
                (f'Recorded reason: {code.replace("_", " ")}.' if code else None),
                code=code,
                assigned_level=allocation.get('level_name'), assigned_zone=allocation.get('zone_name'),
                session_id=row.get('session_id'), current_session=session)


def read(*, role=None, plate='', result=None, start=None, end=None, limit=25, offset=0):
    query = db.get_supabase().table('anpr_events').select(FIELDS, count='exact')
    if role:
        query = query.eq('camera_role', role)
    if plate:
        query = query.ilike('plate_number', f'%{plate}%')
    if result:
        # JSON outcome and processing state are separate in the stored contract.
        query = query.or_(f'processing_result->>stage.eq.{result},processing_result->>status.eq.{result},'
                          f'processing_result->allocation->>status.eq.{result},'
                          f'processing_result->exit_result->>status.eq.{result},'
                          f'processing_result->result->>status.eq.{result},'
                          f'processing_result->exit->>status.eq.{result},processing_status.eq.{result}')
    if start:
        query = query.gte('event_time', start)
    if end:
        query = query.lt('event_time', end)
    response = db._execute(query.order('event_time', desc=True).order('id', desc=True)
                           .range(offset, offset + limit - 1))
    return dict(events=[project(row) for row in response.data], total=response.count,
                limit=limit, offset=offset)


def detail(event_id):
    rows = db._execute(db.get_supabase().table('anpr_events').select(FIELDS).eq('id', event_id).limit(1)).data
    if not rows:
        return None
    event = project(rows[0])
    event['current_payment'] = None
    if event['session_id']:
        charges = db._execute(db.get_supabase().table('session_charges')
                              .select('id,status,amount_sen,paid_at').eq('session_id', event['session_id']).limit(1)).data
        event['current_payment'] = charges[0] if charges else None
    return event


def playback(playback_id, role):
    rows = db._execute(db.get_supabase().table('anpr_playbacks')
                      .select('playback_id,camera_role,source_fingerprint,started_at')
                      .eq('playback_id', playback_id).eq('camera_role', role).limit(1)).data
    events = db._execute(db.get_supabase().table('anpr_events').select(FIELDS)
                         .eq('playback_id', playback_id).eq('camera_role', role)
                         .order('event_time').order('id').limit(1000)).data
    return dict(saved=bool(rows), events=[project(row) for row in events])
