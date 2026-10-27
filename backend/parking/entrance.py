"""Translate confirmed entrance events into the existing allocation workflow."""

from dataclasses import asdict
from threading import Lock

from backend.anpr.events import RecognitionEvent
from backend.anpr import persistence
from backend.database import DatabaseError
from backend.parking.allocation import AllocationError, allocate_parking


class EntranceEventHandler:
    """One recording run (or camera-manager lifetime), with serialised delivery.

    The opt-in integration persists event identity and the admission result.
    Legacy mode retains its existing in-memory duplicate suppression.
    """

    def __init__(self, entrance_nodes: dict[str, str], *, recording=None):
        self.entrance_nodes = dict(entrance_nodes)
        self._seen: set[str] = set()
        self._lock = Lock()
        self.integration = persistence.enabled()
        self.recording = recording

    def __call__(self, event: RecognitionEvent) -> dict:
        result = {"event": asdict(event)}
        if event.camera_role != "entrance":
            return {**result, "status": "ignored", "code": "not_entrance"}
        entrance = self.entrance_nodes.get(event.camera_id)
        if entrance is None:
            return {**result, "status": "rejected", "code": "unmapped_camera"}
        if not persistence.valid_event(event):
            return {**result, "status": "rejected", "code": "invalid_event"}
        if self.integration:
            return {**result, **self._durable(event,entrance)}
        with self._lock:
            if event.event_id in self._seen:
                return {**result, "status": "duplicate", "code": "duplicate_event"}
            # Mark before attempting the write: a lost RPC response might follow
            # a committed reservation. Do not automatically retry ambiguous writes.
            self._seen.add(event.event_id)
            try:
                allocation = allocate_parking(event.plate_number, entrance)
            except AllocationError as error:
                return {**result, "status": "rejected", "code": error.code,
                        "message": str(error)}
            except DatabaseError as error:
                return {**result, "status": "error", "code": "database_unavailable",
                        "message": str(error)}
            return {**result, "status": "allocated", "allocation": allocation}

    def _durable(self, event, entrance):
        event_key = None
        try:
            registered = persistence.register(event,self.recording)
            if registered['status']!='registered':
                return dict(status='rejected',code=registered['status'])
            row = registered['event']
            event_key = row['event_id']
            saved = persistence.saved_entrance(row)
            if saved:
                return saved
            allocation = allocate_parking(event.plate_number,entrance,anpr_event_id=event_key)
            return dict(status='allocated',allocation=allocation,recovered=registered.get('recovered',False),accepted_event_time=row['event_time'])
        except AllocationError as error:
            if event_key:
                try:
                    row = persistence.finish(event_key,error.code)
                    saved = persistence.saved_entrance(row)
                    if saved:
                        return saved
                except DatabaseError:
                    return dict(status='error',code='database_unavailable',event_id=event_key,message='Admission outcome could not be verified. Recover the same event.')
            return dict(status='rejected',code=error.code,message=str(error))
        except DatabaseError:
            # Do not mark a possibly committed admission rejected or re-resolve
            # another event. The same durable key recovers its original session.
            return dict(status='error',code='database_unavailable',event_id=event_key,
                message='Admission outcome is unconfirmed. Recover the same playback/event.')
