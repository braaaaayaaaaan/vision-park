"""Recorded-camera administration. Credentials stay at the existing boundaries."""
from datetime import date, datetime, timedelta, timezone
from time import perf_counter
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from fastapi.responses import FileResponse
from pydantic import BaseModel, ConfigDict, Field

from backend import database as db
from backend.auth import require_administrator
from backend.anpr import activity, recordings
from backend.api.anpr import _process_recording

Role = Literal['entrance', 'exit']
router = APIRouter(dependencies=[Depends(require_administrator)])


def published_entrance():
    state = db.get_publication_state()
    if state['revision'] <= 0:
        raise HTTPException(409, 'Publish the Parking Structure before processing entrance footage.')
    node_id = str(UUID(state['entrance_node_id']))
    nodes, _ = db.get_graph()
    levels = {row['id'] for row in db.get_levels() if row['is_active']}
    if not any(row['id'] == node_id and row['node_type'] == 'building_entrance'
               and row['level_id'] in levels for row in nodes):
        raise HTTPException(409, 'The published building entrance is unavailable. Review Parking Structure.')
    return dict(entrance_node_id=node_id, publication_revision=state['revision'])


@router.get('')
def listing(response: Response):
    response.headers['Cache-Control'] = 'private, no-store'
    entrance, problem = None, None
    try:
        entrance = published_entrance()
    except HTTPException as error:
        problem = error.detail
    except (db.DatabaseError, ValueError, KeyError, TypeError):
        problem = 'The published entrance could not be verified. Refresh before starting.'
    cameras = []
    for role in ('entrance', 'exit'):
        path = recordings.source(role)
        try:
            recording_id = recordings.metadata_identity(path)
        except HTTPException:
            recording_id = None
        cameras.append(dict(role=role, name=f'{role.title()} Camera', filename=path.name,
                            recording_identity=recording_id, available=recording_id is not None,
                            start_context=entrance if role == 'entrance' else
                            dict(entrance_node_id=None, publication_revision=0),
                            start_problem=problem if role == 'entrance' else None))
    return dict(cameras=cameras, active_run=recordings.active_run(), execution_mode='synchronous')


@router.api_route('/{role}/recording', methods=['GET', 'HEAD'])
def recording(role: Role):
    path = recordings.source(role)
    if not path.is_file():
        raise HTTPException(404, 'The configured recording is unavailable.')
    return FileResponse(path, media_type='video/mp4', headers={
        'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff',
        'Content-Disposition': 'inline'})


class ProcessRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    playback_id: UUID
    action: Literal['start', 'retry']
    recording_identity: str = Field(pattern=r'^[a-f0-9]{64}$')
    entrance_node_id: UUID | None = None
    publication_revision: int = Field(ge=0)


@router.post('/{role}/process')
def process(role: Role, change: ProcessRequest, response: Response):
    response.headers['Cache-Control'] = 'private, no-store'
    path = recordings.source(role)
    if recordings.identity(path) != change.recording_identity:
        raise HTTPException(409, {'code': 'recording_changed', 'message':
                                 'The recording changed. The original run cannot be retried with different footage.'})
    node = str(change.entrance_node_id) if change.entrance_node_id else None
    try:
        if role == 'entrance':
            if node is None or change.publication_revision <= 0:
                raise HTTPException(422, 'The original published entrance context is required.')
            if change.action == 'start' and published_entrance() != dict(
                    entrance_node_id=node, publication_revision=change.publication_revision):
                raise HTTPException(409, {'code': 'configuration_changed', 'message':
                                         'Parking Structure changed. Refresh before starting a new operation.'})
        elif node is not None or change.publication_revision != 0:
            raise HTTPException(422, 'Exit processing does not accept entrance context.')
        started = perf_counter()
        result = _process_recording(path, role, change.playback_id, node, change.action)
        return dict(result, duration_seconds=round(perf_counter() - started, 3))
    except db.DatabaseError:
        raise HTTPException(503, {'code': 'anpr_result_unconfirmed', 'playback_id': str(change.playback_id),
                                 'message': 'The outcome could not be verified. Keep this run identity and inspect saved results.'}) from None


@router.get('/activity')
def recent(response: Response, role: Role | None = None,
           plate: Annotated[str, Query(max_length=32, pattern=r'^[A-Za-z0-9]*$')] = '',
           result: Literal[*activity.OUTCOMES] | None = None,
           start_date: date | None = None, end_date: date | None = None,
           limit: Annotated[int, Query(ge=1, le=100)] = 25,
           offset: Annotated[int, Query(ge=0, le=100000)] = 0):
    response.headers['Cache-Control'] = 'private, no-store'
    if end_date == date.max or start_date and end_date and start_date > end_date:
        raise HTTPException(422, 'Start date must be before end date.')
    local = timezone(timedelta(hours=8))
    stamp = lambda day: datetime.combine(day, datetime.min.time(), local).isoformat()
    try:
        return activity.read(role=role, plate=plate.upper(), result=result,
                             start=stamp(start_date) if start_date else None,
                             end=stamp(end_date + timedelta(days=1)) if end_date else None,
                             limit=limit, offset=offset)
    except (db.DatabaseError, KeyError, TypeError, ValueError):
        raise HTTPException(503, 'Recognition activity is unavailable. Refresh to retry.') from None


@router.get('/events/{event_id}')
def event_detail(event_id: UUID, response: Response):
    response.headers['Cache-Control'] = 'private, no-store'
    try:
        item = activity.detail(str(event_id))
        if item is None:
            raise HTTPException(404, 'Recognition event not found.')
        return item
    except (db.DatabaseError, KeyError, TypeError, ValueError):
        raise HTTPException(503, 'Recognition details are unavailable. Refresh to retry.') from None


@router.get('/playbacks/{playback_id}')
def playback(playback_id: UUID, role: Role, response: Response):
    response.headers['Cache-Control'] = 'private, no-store'
    try:
        return dict(activity.playback(str(playback_id), role), active_run=recordings.active_run())
    except (db.DatabaseError, KeyError, TypeError, ValueError):
        raise HTTPException(503, 'Saved processing results could not be verified. Keep the original identity.') from None
