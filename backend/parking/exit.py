"""Resolve exits through payment settlement, or the disabled-mode legacy path."""

from dataclasses import asdict
from threading import Lock

from backend import database as db
from backend.anpr.events import RecognitionEvent
from backend.anpr import persistence
from backend.parking.sessions import SessionError, close_parking


class ExitEventHandler:
    """Opt-in durable bindings; legacy mode retains per-run duplicate protection."""

    def __init__(self, exit_camera_ids: set[str], *, recording=None):
        self.exit_camera_ids = frozenset(exit_camera_ids)
        self._seen: set[str] = set()
        self._plates: dict[str, dict] = {}
        self._vehicles: dict[str, dict] = {}
        self._lock = Lock()
        self.integration = persistence.enabled()
        self.recording = recording

    def __call__(self, event: RecognitionEvent) -> dict:
        result = {"event": asdict(event)}
        if event.camera_role != "exit":
            return {**result, "status": "ignored", "code": "not_exit"}
        if not isinstance(event.camera_id, str) or event.camera_id not in self.exit_camera_ids:
            return {**result, "status": "rejected", "code": "unmapped_camera"}
        if not persistence.valid_event(event):
            return {**result, "status": "rejected", "code": "invalid_event"}
        if self.integration:
            event_key = None
            try:
                registered = persistence.register(event,self.recording)
                if registered['status']!='registered':
                    return {**result,'status':'rejected','code':registered['status']}
                event_key = registered['event']['event_id']
                outcome = persistence.exit_payment(event_key)
                return {**result,**outcome,'recovered':registered.get('recovered',False)}
            except db.DatabaseError as error:
                return {**result,**getattr(error,'binding',{}),'event_id':event_key,'status':'error','code':'database_unavailable',
                    'message':'Exit outcome is unconfirmed. Recover the same playback/event; do not resolve a new session.'}
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
                return {**result, **target, "status": "payment_required" if error.code=='payment_required' else "rejected", "code": error.code,
                        "message": str(error)}
            except db.DatabaseError as error:
                return {**result, **target, "status": "error", "code": "database_unavailable",
                        "message": str(error)}
            return {**result, **target, "status": "completed", "closure": closure}
