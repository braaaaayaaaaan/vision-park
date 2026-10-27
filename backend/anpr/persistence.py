"""Trusted camera/event boundary over 022. Never falls back after a failed write."""
from datetime import datetime, timezone
from hashlib import sha256
import math
import os
from pathlib import Path
import re
from uuid import uuid5, NAMESPACE_URL

from fastapi import HTTPException

from backend import database as db


def enabled():
    return os.getenv('ANPR_PAYMENT_INTEGRATION_ENABLED','false').strip().lower() == 'true'


def valid_event(event):
    return (isinstance(event.event_id,str) and 1 <= len(event.event_id.strip()) <= 128
        and isinstance(event.plate_number,str) and re.fullmatch(r'[A-Z0-9]{1,32}',event.plate_number)
        and isinstance(event.timestamp,datetime) and event.timestamp.tzinfo is not None
        and event.timestamp.utcoffset() is not None and event.timestamp <= datetime.now(timezone.utc)
        and (event.source_time_seconds is None or (type(event.source_time_seconds) in (int,float)
            and math.isfinite(event.source_time_seconds) and 0 <= event.source_time_seconds <= 999999999.999)))


RPCS = frozenset({'begin_anpr_playback','register_parking_anpr_event','finish_parking_anpr_event',
                 'bind_exit_anpr_event','process_exit_anpr_event'})


class ExitPersistenceError(db.DatabaseError):
    def __init__(self, event_key, row):
        super().__init__('Exit outcome is unconfirmed. Recover the same playback/event.')
        self.binding = dict(event_id=event_key,vehicle_id=row.get('vehicle_id'),parking_session_id=row.get('session_id'))


def call(name, params):
    if name not in RPCS:
        raise ValueError('Unsupported ANPR persistence operation')
    try:
        result = db._execute(db.get_supabase().rpc(name,params)).data
    except db.DatabaseError:
        raise db.DatabaseError('ANPR persistence could not be verified. Check migration 022 and recover the same playback/event before retrying.') from None
    if not isinstance(result,dict) or not isinstance(result.get('status'),str):
        raise db.DatabaseError('ANPR persistence returned an invalid response.')
    return result


def playback(playback_id, role, source, context=''):
    if not enabled():
        return None
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
    try:
        result = call('begin_anpr_playback',dict(p_playback_id=str(playback_id),p_camera_role=role,p_source_fingerprint=digest.hexdigest()))
    except db.DatabaseError:
        raise HTTPException(503,'ANPR integration storage is unavailable. Keep the same playback_id; check migration 022 before retrying.') from None
    if result['status'] == 'playback_conflict':
        raise HTTPException(409,'This playback_id belongs to a different recording or entrance mapping. Recover the original run or deliberately start a new one.')
    item = result.get('playback') or {}
    if result['status'] not in ('created','recovered') or item.get('playback_id') != str(playback_id) or item.get('camera_role') != role:
        raise HTTPException(503,'Playback registration returned an invalid response.')
    return dict(playback_id=str(playback_id),allow_create=result['status']=='created')


def register(event, recording=None):
    # A recording deliberately treats a plate once per camera/role, matching the
    # original per-run suppression. OCR track IDs and processing times may vary.
    identity = (f"playback:{recording['playback_id']}:{event.camera_role}:{event.camera_id}:{event.plate_number}"
                if recording else f'live:{event.camera_role}:{event.camera_id}:{event.event_id}')
    event_key = 'vp-anpr:'+str(uuid5(NAMESPACE_URL,identity))
    result = call('register_parking_anpr_event',dict(p_event_id=event_key,p_plate_number=event.plate_number,
        p_camera_id=event.camera_id,p_camera_role=event.camera_role,p_event_time=event.timestamp.astimezone(timezone.utc).isoformat(),
        p_source_time_seconds=event.source_time_seconds,p_playback_id=recording['playback_id'] if recording else None,
        p_allow_create=recording['allow_create'] if recording else True))
    if result['status'] in ('event_conflict','unrecorded_replay'):
        return result
    row = result.get('event') or {}
    if (result['status']!='registered' or row.get('event_id')!=event_key or row.get('camera_id')!=event.camera_id
            or row.get('camera_role')!=event.camera_role or row.get('plate_number')!=event.plate_number
            or row.get('processing_result',{}).get('contract')!='visionpark-anpr-v1'):
        raise db.DatabaseError('ANPR event registration returned an invalid identity.')
    return result


def saved_entrance(row):
    outcome = row.get('processing_result') or {}
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
