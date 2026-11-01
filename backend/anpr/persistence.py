"""Trusted camera/event boundary over 022. Never falls back after a failed write."""
from datetime import datetime, timezone
from hashlib import sha256
import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path
import re
import traceback
from uuid import UUID, uuid5, NAMESPACE_URL

from fastapi import HTTPException

from backend import database as db
from backend.anpr.registration_input import invalid_fields
from backend.anpr.events import RecognitionEvent


logger = logging.getLogger('uvicorn.error')


def configure_diagnostics(directory=None):
    """Keep bounded, credential-free ANPR errors after the terminal scrolls."""
    if any(handler.name == 'visionpark-anpr-diagnostics' for handler in logger.handlers):
        return
    try:
        directory = Path(directory) if directory is not None else Path(__file__).resolve().parents[2] / 'logs'
        directory.mkdir(parents=True, exist_ok=True)
        handler = RotatingFileHandler(directory / 'anpr.log', maxBytes=1024 * 1024, backupCount=2, encoding='utf-8')
    except OSError:
        logger.warning('ANPR diagnostic file unavailable; errors will remain in the server console.')
        return
    handler.name = 'visionpark-anpr-diagnostics'
    handler.setLevel(logging.ERROR)
    handler.addFilter(lambda record: str(record.msg).startswith('ANPR '))
    handler.setFormatter(logging.Formatter('%(asctime)s %(levelname)s %(message)s'))
    logger.addHandler(handler)


def _failure_details(error):
    # _execute suppresses the SDK traceback, but retains its exception context.
    # Never log SDK messages/details, request headers, plates, or credentials.
    cause = error
    while isinstance(cause, db.DatabaseError) and cause.__context__ is not None:
        cause = cause.__context__
    code = getattr(cause, 'code', None)
    code = code if isinstance(code, str) and re.fullmatch(r'(?:[A-Z0-9]{5}|PGRST[0-9]{3})', code) else 'unknown'
    message = getattr(cause, 'message', None)
    reason = {
        ('22023', 'Invalid trusted recognition event'): 'invalid_trusted_event',
        ('22023', 'Register playback first'): 'playback_not_registered',
        ('22023', 'Confirmation precedes playback start'): 'confirmation_before_playback',
        ('22023', 'Invalid trusted event identity'): 'invalid_event_identity',
        ('22023', 'Invalid trusted plate format'): 'invalid_plate_format',
        ('22023', 'Invalid trusted camera identity'): 'invalid_camera_identity',
        ('22023', 'Invalid trusted camera role'): 'invalid_camera_role',
        ('22023', 'Invalid trusted creation permission'): 'invalid_creation_permission',
        ('22023', 'Invalid trusted event timestamp'): 'invalid_event_timestamp',
        ('22023', 'Recognition timestamp is ahead of database clock'): 'event_ahead_of_database',
        ('22023', 'Invalid trusted recording offset'): 'invalid_recording_offset',
        ('22023', 'Invalid recorded recognition context'): 'invalid_recording_context',
    }.get((code, message), 'unconfirmed') if isinstance(message, str) else 'unconfirmed'
    return code, reason, type(cause).__name__


def _safe_event_id(event_id):
    return event_id if isinstance(event_id, str) and re.fullmatch(r'vp-anpr:[a-f0-9-]{36}', event_id) else 'none'


def _log_failure(name, params, error):
    code, reason, error_type = _failure_details(error)
    try:
        playback_id = str(UUID(str(params.get('p_playback_id'))))
    except ValueError:
        playback_id = 'none'
    event_id = _safe_event_id(params.get('p_event_id'))
    logger.error('ANPR persistence failed rpc=%s database_code=%s reason=%s error_type=%s playback_id=%s event_id=%s category=%s',
                 name, code, reason, error_type, playback_id, event_id, failure_category(error))


def failure_category(error):
    assigned = getattr(error, 'category', None)
    if assigned in ('response_contract', 'database_validation', 'database_access',
                    'database_contract', 'database_constraint', 'database_contention',
                    'transport_unconfirmed', 'result_unconfirmed'):
        return assigned
    code, _, error_type = _failure_details(error)
    if code == '22023':
        return 'database_validation'
    if code in ('42501', 'PGRST301', 'PGRST302'):
        return 'database_access'
    if code in ('PGRST202', '42883', '42P01', '42703'):
        return 'database_contract'
    if code.startswith('23'):
        return 'database_constraint'
    if code in ('55P03', '40P01', '40001'):
        return 'database_contention'
    if error_type in ('ConnectError', 'ConnectTimeout', 'ReadTimeout', 'WriteTimeout',
                      'PoolTimeout', 'RemoteProtocolError', 'ReadError', 'WriteError'):
        return 'transport_unconfirmed'
    return 'result_unconfirmed'


def _contract_error(message):
    error = db.DatabaseError(message)
    error.category = 'response_contract'
    return error


def log_admission_failure(stage, event_id, error):
    code, reason, error_type = _failure_details(error)
    # Local function names locate failed reads/reservation or contract checks;
    # no query URLs, parameters, SQL messages, or response bodies are recorded.
    frames = [frame for frame in traceback.extract_tb(error.__traceback__)
              if Path(frame.filename).parent in (Path(db.__file__).parent, Path(__file__).parent,
                                                  Path(db.__file__).parent / 'parking')
              and frame.name != '_execute']
    operation = frames[-1].name if frames else 'unknown'
    logger.error('ANPR admission failed stage=%s operation=%s database_code=%s reason=%s error_type=%s event_id=%s',
                 stage, operation, code, reason, error_type, _safe_event_id(event_id))


def enabled():
    return os.getenv('ANPR_PAYMENT_INTEGRATION_ENABLED','false').strip().lower() == 'true'


def valid_event(event, *, recorded=False):
    # Persisted database acceptance times are not application-clock observations.
    return not invalid_fields(event, check_future=not recorded)


RPCS = frozenset({'register_parking_anpr_event','finish_parking_anpr_event',
                 'bind_exit_anpr_event','process_exit_anpr_event', 'register_recorded_parking_anpr_events'})


class ExitPersistenceError(db.DatabaseError):
    def __init__(self, event_key, row):
        super().__init__('Exit outcome is unconfirmed. Recover the same playback/event.')
        self.binding = dict(event_id=event_key,vehicle_id=row.get('vehicle_id'),parking_session_id=row.get('session_id'))


def call(name, params):
    if name not in RPCS:
        raise ValueError('Unsupported ANPR persistence operation')
    try:
        result = db._execute(db.get_supabase().rpc(name,params)).data
    except db.DatabaseError as error:
        _log_failure(name, params, error)
        failure = db.DatabaseError('ANPR persistence could not be verified. Inspect the same playback/event before retrying.')
        failure.category = failure_category(error)
        raise failure from None
    if not isinstance(result,dict) or not isinstance(result.get('status'),str):
        logger.error('ANPR persistence returned invalid response rpc=%s', name)
        raise _contract_error('ANPR persistence returned an invalid response.')
    return result


def playback(playback_id, role, source, context=''):
    """Build the recorded-run identity locally. Never writes a playback row."""
    if playback_id is None:
        raise HTTPException(422, 'Provide a playback_id UUID and reuse it when recovering this recording.')
    digest = sha256()
    digest.update(context.encode())
    try:
        with Path(source).open('rb') as stream:
            for chunk in iter(lambda:stream.read(1024*1024),b''):
                digest.update(chunk)
    except OSError:
        raise HTTPException(503,'The configured ANPR recording is unavailable.') from None
    return dict(playback_id=str(playback_id), camera_role=role,
                source_fingerprint=digest.hexdigest())


def event_key(event, recording=None):
    # A recording deliberately treats a plate once per camera/role, matching the
    # original per-run suppression. OCR track IDs and processing times may vary.
    identity = (f"playback:{recording['playback_id']}:{event.camera_role}:{event.camera_id}:{event.plate_number}"
                if recording else f'live:{event.camera_role}:{event.camera_id}:{event.event_id}')
    return 'vp-anpr:'+str(uuid5(NAMESPACE_URL,identity))


def register(event, recording=None):
    if recording is not None:
        # The endpoint registered the complete recognition set once. Handlers
        # consume that receipt; they never start another registration write.
        rows = recording.get('registered_events')
        row = rows.get(event_key(event, recording)) if isinstance(rows, dict) else None
        if row is None or any(row.get(field) != getattr(event, field) for field in
                              ('plate_number', 'camera_id', 'camera_role')):
            raise _contract_error('No verified recorded event is available for this recognition.')
        return dict(status='registered', event=row, recovered=recording['recovered'])
    issues = invalid_fields(event)
    if issues:
        logger.error('ANPR registration input rejected fields=%s', ','.join(issues))
        return dict(status='invalid_event')
    durable_key = event_key(event, recording)
    params = dict(p_event_id=durable_key, p_plate_number=event.plate_number,
        p_camera_id=event.camera_id, p_camera_role=event.camera_role,
        p_source_time_seconds=event.source_time_seconds,
        p_playback_id=None,
        p_event_time=event.timestamp.astimezone(timezone.utc).isoformat(), p_allow_create=True)
    operation = 'register_parking_anpr_event'
    # Log only comparisons and fixed labels, never the payload. An application
    # age cannot determine the database's clock at an earlier failure.
    age_ms = round((datetime.now(timezone.utc) - event.timestamp).total_seconds() * 1000)
    logger.debug('ANPR registration request rpc=%s event_id=%s application_age_ms=%s allow_create=%s',
                 operation, durable_key, age_ms, True)
    result = call(operation, params)
    if result['status'] in ('event_conflict','unrecorded_replay','playback_conflict'):
        return result
    row = result.get('event') or {}
    outcome = row.get('processing_result') if isinstance(row, dict) else None
    if (result['status']!='registered' or not isinstance(row,dict) or row.get('event_id')!=durable_key or row.get('camera_id')!=event.camera_id
            or row.get('camera_role')!=event.camera_role or row.get('plate_number')!=event.plate_number
            or row.get('playback_id') != (recording['playback_id'] if recording else None)
            or not isinstance(outcome,dict) or outcome.get('contract')!='visionpark-anpr-v1'):
        logger.error('ANPR event registration returned invalid identity event_id=%s', durable_key)
        raise _contract_error('ANPR event registration returned an invalid identity.')
    try:
        accepted = datetime.fromisoformat(row['event_time'].replace('Z', '+00:00'))
        if accepted.tzinfo is None or accepted.utcoffset() is None:
            raise ValueError()
    except (KeyError, AttributeError, TypeError, ValueError):
        raise _contract_error('ANPR event registration returned an invalid timestamp.') from None
    return result


def register_recording(events, recording, *, action='start'):
    """Persist one complete plate set, or recover its original saved set.

    Existing anpr_events are the operation receipts. No continuation capability,
    new state table, automatic retry or replacement run identity is involved.
    """
    if action not in ('start', 'retry'):
        raise _contract_error('Use start or retry for recorded processing.')
    if not events and action == 'start':
        return dict(status='no_recognition', events=[])
    payload = []
    for event in events if action == 'start' else ():
        if (invalid_fields(event) or event.camera_role != recording['camera_role']):
            return dict(status='invalid_event', events=[])
        payload.append(dict(event_id=event_key(event, recording), plate_number=event.plate_number,
                            camera_id=event.camera_id, source_time_seconds=event.source_time_seconds))
    result = call('register_recorded_parking_anpr_events', dict(
        p_playback_id=recording['playback_id'], p_camera_role=recording['camera_role'],
        p_source_fingerprint=recording['source_fingerprint'], p_events=payload, p_action=action))
    if result['status'] in ('playback_conflict', 'playback_exists', 'playback_not_found',
                            'event_conflict', 'unrecorded_replay', 'no_recognition'):
        return result
    rows = result.get('events')
    if (result['status'] != 'registered' or not isinstance(rows, list) or not rows
            or type(result.get('recovered')) is not bool
            or result['recovered'] != (action == 'retry')):
        raise _contract_error('Recorded recognition set could not be verified.')
    by_id = {}
    plates = set()
    for row in rows:
        try:
            event = RecognitionEvent(row['plate_number'], datetime.fromisoformat(row['event_time'].replace('Z', '+00:00')),
                                     row['camera_id'], row['camera_role'], row['event_id'], row.get('source_time_seconds'))
            if (not valid_event(event, recorded=True) or row['playback_id'] != recording['playback_id']
                    or row['camera_role'] != recording['camera_role']
                    or row['event_id'] != event_key(event, recording)
                    or not isinstance(row['processing_result'], dict)
                    or row['processing_result'].get('contract') != 'visionpark-anpr-v1'
                    or row['event_id'] in by_id or row['plate_number'] in plates):
                raise ValueError()
        except (AttributeError, KeyError, TypeError, ValueError):
            raise _contract_error('Recorded recognition identity could not be verified.') from None
        by_id[row['event_id']] = row
        plates.add(row['plate_number'])
    if not result['recovered'] and set(by_id) != {item['event_id'] for item in payload}:
        raise _contract_error('The new recorded recognition set is incomplete.')
    recording['registered_events'] = by_id
    recording['recovered'] = result['recovered']
    return result


def saved_entrance(row):
    outcome = row.get('processing_result') or {}
    if not isinstance(outcome, dict):
        raise _contract_error('Stored admission response is invalid.')
    if row.get('session_id'):
        allocation = outcome.get('allocation')
        if (not isinstance(allocation,dict) or allocation.get('parking_session_id') != row['session_id']
                or allocation.get('plate_number') != row['plate_number'] or allocation.get('status')!='allocated'):
            raise db.DatabaseError('Stored admission response does not match its event binding.')
        return dict(status='allocated',allocation=allocation,recovered=True,accepted_event_time=row['event_time'])
    if row.get('processing_status') in ('rejected','unmatched'):
        return dict(status='rejected',code=outcome.get('code','event_rejected'),recovered=True)
    return None


def finish(event_key, code, retryable=False):
    result = call('finish_parking_anpr_event',dict(p_event_id=event_key,p_code=code,p_retryable=retryable))
    if result['status']!='recorded' or result.get('event',{}).get('event_id')!=event_key:
        raise db.DatabaseError('ANPR outcome recording returned an invalid response.')
    return result['event']


def exit_payment(event_key):
    binding = call('bind_exit_anpr_event',dict(p_event_id=event_key))
    row = binding.get('event') or {}
    if binding['status']!='bound' or row.get('event_id')!=event_key or row.get('camera_role')!='exit':
        raise db.DatabaseError('Exit binding returned an invalid event.')
    try:
        result = call('process_exit_anpr_event',dict(p_event_id=event_key))
        if result['status'] not in ('completed','rejected','payment_required','payment_pending','payment_succeeded'):
            raise db.DatabaseError('Exit processing returned an invalid outcome.')
        if row.get('session_id') and (result.get('parking_session_id')!=row['session_id'] or result.get('vehicle_id')!=row['vehicle_id']):
            raise db.DatabaseError('Exit processing returned a different session.')
    except db.DatabaseError:
        raise ExitPersistenceError(event_key,row) from None
    return result
