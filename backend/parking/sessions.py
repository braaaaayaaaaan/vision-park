"""Reusable parking confirmation service; no allocation or capacity mutations."""

from uuid import UUID

from pydantic import AwareDatetime, BaseModel, ValidationError
from typing import Literal

from backend import database as db


class SessionError(ValueError):
    def __init__(self, code: str, message: str, status_code: int):
        super().__init__(message)
        self.code = code
        self.status_code = status_code


class ConfirmationResult(BaseModel):
    parking_session_id: UUID
    vehicle_id: UUID
    zone_id: UUID
    status: Literal["occupied"]
    parking_confirmed_at: AwareDatetime


def confirm_parking(session_id: str, vehicle_id: str) -> dict:
    """Confirm one exact session/vehicle pair; caller must enforce access.

    Vehicle ID is a consistency check, not proof of driver identity. A future
    driver API must obtain authorised identity from its authentication context.
    """
    try:
        session_id, vehicle_id = str(UUID(str(session_id))), str(UUID(str(vehicle_id)))
    except (ValueError, TypeError, AttributeError):
        raise SessionError("invalid_identifier", "Session and vehicle IDs must be UUIDs.", 422) from None
    result = db.confirm_session(session_id, vehicle_id)
    errors = {
        "session_not_found": ("No session matches this session and vehicle ID.", 404),
        "invalid_session_status": ("Only an active allocated or occupied session can be confirmed.", 409),
        "invalid_session_state": ("The session has inconsistent confirmation timestamps.", 409),
    }
    if result["status"] in errors:
        message, status = errors[result["status"]]
        raise SessionError(result["status"], message, status)
    try:
        confirmation = ConfirmationResult.model_validate(result)
        if str(confirmation.parking_session_id) != session_id or str(confirmation.vehicle_id) != vehicle_id:
            raise ValueError("Mismatched identity")
    except (ValidationError, ValueError):
        raise db.DatabaseError("Confirmation RPC returned an invalid result; check the session before retrying.") from None
    return confirmation.model_dump(mode="json")
