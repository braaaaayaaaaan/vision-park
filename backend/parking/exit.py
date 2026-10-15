"""Close existing sessions from exit recognition; one handler per recording run."""

from dataclasses import asdict
import re
from threading import Lock

from backend import database as db
from backend.anpr.events import RecognitionEvent
from backend.parking.sessions import SessionError, close_parking


class ExitEventHandler:
    """Serialised, in-memory duplicate protection, not durable replay prevention.

    Remember attempts before I/O and pin resolved pairs before closure. Even an
    ambiguous failure must not cause another track to resolve a newer session.
    Explicit retries of a known pair belong to the existing closure endpoint.
    """

    def __init__(self, exit_camera_ids: set[str]):
        self.exit_camera_ids = frozenset(exit_camera_ids)
        self._seen: set[str] = set()
        self._plates: dict[str, dict] = {}
        self._vehicles: dict[str, dict] = {}
        self._lock = Lock()

    def __call__(self, event: RecognitionEvent) -> dict:
        result = {"event": asdict(event)}
        if event.camera_role != "exit":
            return {**result, "status": "ignored", "code": "not_exit"}
        if not isinstance(event.camera_id, str) or event.camera_id not in self.exit_camera_ids:
            return {**result, "status": "rejected", "code": "unmapped_camera"}
        if (not isinstance(event.event_id, str) or not event.event_id.strip()
                or not isinstance(event.plate_number, str)
                or not re.fullmatch(r"[A-Z0-9]{1,32}", event.plate_number)):
            return {**result, "status": "rejected", "code": "invalid_event"}
        with self._lock:
            target = self._plates.get(event.plate_number, {})
            if event.event_id in self._seen:
                return {**result, **target, "status": "duplicate", "code": "duplicate_event"}
            self._seen.add(event.event_id)
            if event.plate_number in self._plates:
                return {**result, **target, "status": "duplicate", "code": "duplicate_vehicle"}
            self._plates[event.plate_number] = target
            try:
                vehicle = db.get_vehicle(event.plate_number)
                if vehicle is None:
                    return {**result, "status": "rejected", "code": "unknown_vehicle"}
                vehicle_id = vehicle["id"]
                if vehicle_id in self._vehicles:
                    self._plates[event.plate_number] = self._vehicles[vehicle_id]
                    return {**result, **self._vehicles[vehicle_id],
                            "status": "duplicate", "code": "duplicate_vehicle"}
                target["vehicle_id"] = vehicle_id
                self._vehicles[vehicle_id] = target
                # Exit deliberately does not recheck registration/user/tenant eligibility.
                session = db.get_active_session(vehicle_id)
                if session is None:
                    return {**result, **target, "status": "rejected", "code": "no_active_session"}
                if session["vehicle_id"] != vehicle_id or session["status"] not in db.ACTIVE_STATUSES:
                    raise db.DatabaseError("Active-session lookup returned an inconsistent session.")
                target["parking_session_id"] = session["id"]
                closure = close_parking(target["parking_session_id"], vehicle_id)
            except SessionError as error:
                return {**result, **target, "status": "rejected", "code": error.code,
                        "message": str(error)}
            except db.DatabaseError as error:
                return {**result, **target, "status": "error", "code": "database_unavailable",
                        "message": str(error)}
            return {**result, **target, "status": "completed", "closure": closure}
