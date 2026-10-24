"""Driver-owned vehicles; existing foreign keys protect all historical records."""
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, field_validator

from backend import database
from backend.auth import ApplicationUser, require_driver

router = APIRouter()
REMOVAL_BLOCKED = "This vehicle has parking or ANPR records and cannot be removed. Its history is preserved."


class VehicleRegistration(BaseModel):
    model_config = ConfigDict(extra="forbid")
    plate_number: str = Field(min_length=1, max_length=32, pattern=r"^[A-Z0-9]+$")

    @field_validator("plate_number", mode="before")
    @classmethod
    def normalise_plate(cls, value):
        return value.strip().upper() if isinstance(value, str) else value


class VehicleSession(BaseModel):
    id: UUID
    vehicle_id: UUID
    zone_id: UUID
    status: Literal["allocated", "occupied"]
    entry_time: AwareDatetime
    parking_confirmed_at: AwareDatetime | None
    exit_time: AwareDatetime | None
    zone_name: str | None = None
    level_name: str | None = None


class VehicleResponse(BaseModel):
    id: UUID
    plate_number: str
    registration_status: str
    active_session: VehicleSession | None = None
    session_information_available: bool = True
    removal_permitted: bool = False
    removal_reason: str | None = None


def vehicle_response(row: dict, user_id: str) -> VehicleResponse:
    if row["user_id"] != user_id:
        raise ValueError("Ownership mismatch")
    sessions = row.get("sessions", [])
    if len(sessions) > 1 or any(s["user_id"] != user_id or s["vehicle_id"] != row["id"] for s in sessions):
        raise ValueError("Invalid session ownership")
    has_records = bool(sessions) or database.vehicle_has_records(row["id"])
    active_session = None
    if sessions:
        session = sessions[0]
        zone = session.get("zone") or {}
        level = zone.get("level") or {}
        active_session = VehicleSession(**session, zone_name=zone.get("name"), level_name=level.get("name"))
    return VehicleResponse(id=row["id"], plate_number=row["plate_number"],
                           registration_status=row["registration_status"],
                           active_session=active_session,
                           removal_permitted=not has_records,
                           removal_reason=REMOVAL_BLOCKED if has_records else None)


@router.delete("/{vehicle_id}")
def remove_vehicle(vehicle_id: UUID, response: Response,
                   driver: Annotated[ApplicationUser, Depends(require_driver)]):
    response.headers["Cache-Control"] = "no-store"
    try:
        row = database.get_owned_vehicle(str(driver.id), str(vehicle_id))
        if row is None or row["user_id"] != str(driver.id) or row["id"] != str(vehicle_id):
            raise HTTPException(404, "Vehicle not found.")
        if database.vehicle_has_records(str(vehicle_id)):
            raise HTTPException(409, REMOVAL_BLOCKED)
        if not database.remove_driver_vehicle(str(driver.id), str(vehicle_id)):
            raise HTTPException(404, "Vehicle not found. Refresh your vehicles.")
        return {"status": "removed", "vehicle_id": vehicle_id}
    except database.VehicleRemovalConflict:
        raise HTTPException(409, REMOVAL_BLOCKED) from None
    except (database.DatabaseError, ValueError, KeyError, TypeError):
        raise HTTPException(503, "Removal could not be verified. Refresh your vehicles before retrying.") from None


@router.get("", response_model=list[VehicleResponse])
def list_vehicles(response: Response, driver: Annotated[ApplicationUser, Depends(require_driver)]):
    response.headers["Cache-Control"] = "no-store"
    try:
        return [vehicle_response(row, str(driver.id)) for row in database.get_driver_vehicles(str(driver.id))]
    except (database.DatabaseError, ValueError, KeyError, TypeError):
        raise HTTPException(503, "Vehicle information is unavailable. Please retry.") from None


@router.post("", response_model=VehicleResponse, status_code=201)
def register_vehicle(request: VehicleRegistration, response: Response,
                     driver: Annotated[ApplicationUser, Depends(require_driver)]):
    response.headers["Cache-Control"] = "no-store"
    try:
        if database.get_vehicle(request.plate_number) is not None:
            raise HTTPException(409, "This plate is already registered.")
        row = database.register_driver_vehicle(str(driver.id), request.plate_number)
        if row["registration_status"] != "pending":
            raise ValueError("Unexpected registration status")
        return vehicle_response(row, str(driver.id))
    except database.DuplicateVehicleError:
        raise HTTPException(409, "This plate is already registered.") from None
    except (database.DatabaseError, ValueError, KeyError, TypeError):
        raise HTTPException(503, "Registration could not be verified. Refresh your vehicles before retrying.") from None
