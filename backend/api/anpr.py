from dataclasses import asdict
from contextlib import closing
from uuid import UUID
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from fastapi.encoders import jsonable_encoder
from pydantic import BaseModel, ConfigDict
from backend.anpr.pipeline import ANPRPipeline
from backend.api.parking import require_allocation_access
from backend.parking.entrance import EntranceEventHandler
from backend.parking.exit import ExitEventHandler
from backend.anpr import persistence
from backend.anpr.events import RecognitionEvent
from backend.database import DatabaseError
from datetime import datetime
from backend.auth import require_administrator
from backend.anpr.recordings import RECORDINGS, ENTRANCE_RECORDING, EXIT_RECORDING, processing_slot

router = APIRouter()


@router.get("/test", dependencies=[Depends(require_administrator)])
def test_anpr():
    with processing_slot('entrance', 'recognition-test'):
        pipeline = ANPRPipeline(
            source=str(ENTRANCE_RECORDING), camera_id="test-entrance", camera_role="entrance")
        try:
            with closing(pipeline.run()) as events:
                return {"results": [asdict(event) for event in events]}
        finally:
            pipeline.stop()


class EntranceRunRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    entrance_node_id: UUID
    playback_id: UUID
    action: Literal['start', 'retry'] = 'start'


@router.post("/entrance", dependencies=[Depends(require_allocation_access)])
def run_entrance(request: EntranceRunRequest):
    """Recognise the clip, record its plate set once, then allocate each vehicle."""
    return _process_recording(ENTRANCE_RECORDING, 'entrance', request.playback_id,
                              entrance_node_id=str(request.entrance_node_id), action=request.action)


class ExitRunRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    playback_id: UUID
    action: Literal['start', 'retry'] = 'start'


@router.post("/exit", dependencies=[Depends(require_allocation_access)])
def run_exit(request: ExitRunRequest):
    """Recognise the clip, then settle each saved exit's exact session binding."""
    return _process_recording(EXIT_RECORDING, 'exit', request.playback_id, action=request.action)


def _process_recording(source, role, playback_id, entrance_node_id=None, action='start'):
    with processing_slot(role, playback_id):
        return _process_recording_unlocked(source, role, playback_id, entrance_node_id, action)


def _process_recording_unlocked(source, role, playback_id, entrance_node_id=None, action='start'):
    # Hash exactly the source passed to the existing recognition pipeline. This
    # local step creates no database playback record, even if recognition fails.
    recording = persistence.playback(playback_id, role, source, entrance_node_id or '')
    camera_id = 'recorded-' + role
    results = []
    pipeline = None
    stage = 'recognition'
    try:
        confirmed = {}
        if action == 'start':
            pipeline = ANPRPipeline(source=str(source), camera_id=camera_id, camera_role=role)
            with closing(pipeline.run()) as events:
                for event in events:
                    if (not persistence.valid_event(event) or event.camera_id != camera_id
                            or event.camera_role != role):
                        results.append(dict(event=asdict(event), status='rejected', code='invalid_event'))
                    else:
                        confirmed.setdefault(event.plate_number, event)
            if not confirmed:
                return {'results': results, 'playback_id': playback_id, 'status': 'no_recognition'}
            checked = persistence.playback(playback_id, role, source, entrance_node_id or '')
            if checked['source_fingerprint'] != recording['source_fingerprint']:
                raise HTTPException(409, 'The recording changed during recognition. No vehicles were admitted.')
        # Retry uses the original durable recognition set, not another OCR pass.
        # It cannot create a missing run, even if the caller supplied a new UUID.
        stage = 'registration' if action == 'start' else 'recovery'
        observations = list(confirmed.values())
        receipt = persistence.register_recording(observations, recording, action=action)
        if receipt['status'] != 'registered':
            if receipt['status'] in ('playback_exists', 'playback_not_found', 'playback_conflict'):
                messages = {
                    'playback_exists': 'This run already exists. Use action=retry with the same playback identity.',
                    'playback_not_found': 'No saved run exists. A retry cannot start new processing.',
                    'playback_conflict': 'The recording or entrance mapping differs from the saved run.',
                }
                raise HTTPException(404 if receipt['status'] == 'playback_not_found' else 409,
                                    dict(code=receipt['status'], message=messages[receipt['status']]))
            results.extend(dict(event=asdict(event), status='rejected', code=receipt['status'],
                                event_id=persistence.event_key(event, recording)) for event in observations)
            return {'results': results, 'playback_id': playback_id, 'status': receipt['status']}
        stage = 'admission' if role == 'entrance' else 'settlement'
        handler = (EntranceEventHandler({camera_id: entrance_node_id}, recording=recording)
                   if role == 'entrance' else ExitEventHandler({camera_id}, recording=recording))
        by_key = {persistence.event_key(event, recording): event for event in observations}
        for row in receipt['events']:
            # A replay uses the first saved recognition set. OCR variation may
            # not add a plate or replace the identity of an uncertain operation.
            event = by_key.get(row['event_id']) or RecognitionEvent(
                row['plate_number'], datetime.fromisoformat(row['event_time'].replace('Z', '+00:00')),
                row['camera_id'], row['camera_role'], row['event_id'], row.get('source_time_seconds'))
            results.append(dict(handler(event), accepted_event_time=row['event_time']))
        return {'results': results, 'playback_id': playback_id, 'recovered': receipt['recovered']}
    except HTTPException:
        raise
    except DatabaseError as error:
        raise HTTPException(503, jsonable_encoder(dict(code='anpr_result_unconfirmed', stage=stage,
            message='The run could not be confirmed. Retry the same playback identity; do not start a replacement run.',
            failure_category=getattr(error, 'category', persistence.failure_category(error)),
            playback_id=playback_id, results=results))) from None
    except Exception:
        raise HTTPException(503, jsonable_encoder(dict(code='anpr_processing_failed', stage=stage,
            message='Processing failed. Inspect saved results and retry the same playback identity.',
            playback_id=playback_id, results=results))) from None
    finally:
        if pipeline is not None:
            pipeline.stop()
