"""Translate confirmed entrance events into the existing allocation workflow."""

from dataclasses import asdict
import re
from threading import Lock

from backend.anpr.events import RecognitionEvent
from backend.database import DatabaseError
from backend.parking.allocation import AllocationError, allocate_parking


class EntranceEventHandler:
    """One recording run (or camera-manager lifetime), with serialised delivery.

    Event IDs suppress redelivery within this handler. Across handlers, new track
    IDs, replays and processes, the existing active-session check and atomic RPC
    remain the authority. This is not a durable event ledger or retry queue.
    """

    def __init__(self, entrance_nodes: dict[str, str]):
        self.entrance_nodes = dict(entrance_nodes)
        self._seen: set[str] = set()
        self._lock = Lock()

    def __call__(self, event: RecognitionEvent) -> dict:
        result = {"event": asdict(event)}
        if event.camera_role != "entrance":
            return {**result, "status": "ignored", "code": "not_entrance"}
        entrance = self.entrance_nodes.get(event.camera_id)
        if entrance is None:
            return {**result, "status": "rejected", "code": "unmapped_camera"}
        if not event.event_id.strip() or not re.fullmatch(r"[A-Z0-9]{1,32}", event.plate_number):
            return {**result, "status": "rejected", "code": "invalid_event"}
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
