"""Driver session reads and token-protected development parking mutations."""

import os
from secrets import compare_digest
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response, Security
from fastapi.security import APIKeyHeader
from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, ValidationError, field_validator

from backend import database
from backend.auth import ApplicationUser, require_driver
from backend.parking.navigation import AssignedRouteResponse, assigned_route
from backend.parking.navigation_floor_plans import published_image_bytes
from backend.database import DatabaseError
from backend.parking.allocation import AllocationError, allocate_parking
from backend.parking.sessions import ClosureResult, ConfirmationResult, SessionError, close_parking, confirm_parking

router = APIRouter()
allocation_key = APIKeyHeader(name="X-Allocation-Token", auto_error=False)


@router.get("/sessions/{session_id}/route", response_model=AssignedRouteResponse)
def session_route(session_id: UUID, response: Response,
                  driver: Annotated[ApplicationUser, Depends(require_driver)]):
    response.headers["Cache-Control"] = "no-store"
    return assigned_route(str(driver.id), str(session_id))


@router.get('/sessions/{session_id}/route/levels/{level_id}/floor-plan')
def session_floor_plan(session_id: UUID, level_id: UUID,
                       publication_revision: Annotated[int, Query(gt=0)],
                       floor_plan_revision: Annotated[int, Query(gt=0)],
                       driver: Annotated[ApplicationUser, Depends(require_driver)]):
    # Recheck ownership, allocation, route membership and publication on every
    # image request. Never grant access merely because a driver knows a level ID.
    route = assigned_route(str(driver.id), str(session_id))
    descriptor = next((level.floor_plan for level in route.levels if str(level.id) == str(level_id)), None)
    if descriptor is None:
        raise HTTPException(404, 'A verified published floor plan is unavailable for this route.')
    if descriptor.publication_revision != publication_revision or descriptor.revision != floor_plan_revision:
        raise HTTPException(409, 'The published map changed. Refresh navigation.')
    try:
        image = published_image_bytes(str(level_id), descriptor)
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(503, 'The verified floor plan is unavailable. Refresh and retry.') from None
    return Response(image, media_type='image/png', headers={
        'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff'})


class ActiveSessionResponse(BaseModel):
    id: UUID
    vehicle_id: UUID
    plate_number: str
    registration_status: str
    status: Literal["allocated", "occupied"]
    zone_id: UUID
    zone_code: str
    zone_name: str
    level_id: UUID
    level_name: str
    level_number: int
    entry_time: AwareDatetime
    parking_confirmed_at: AwareDatetime | None
    exit_time: AwareDatetime | None


class ActiveSessionsResponse(BaseModel):
    sessions: list[ActiveSessionResponse]


class ZoneAvailabilityResponse(BaseModel):
    id: UUID
    name: str
    level_id: UUID
    level_name: str
    operational_status: Literal["open"]
    total_capacity: int = Field(ge=0)
    unavailable_capacity: int = Field(ge=0)
    allocated_sessions: int = Field(ge=0)
    occupied_sessions: int = Field(ge=0)
    total_spaces: int = Field(ge=0)
    available_spaces: int = Field(ge=0)
    occupancy: float | None


class LevelAvailabilityResponse(BaseModel):
    id: UUID
    name: str
    level_number: int
    total_spaces: int
    available_spaces: int
    occupancy: float | None
    zones: list[ZoneAvailabilityResponse]


class ParkingAvailabilityResponse(BaseModel):
    available_spaces: int
    accessible_zone_count: int
    levels: list[LevelAvailabilityResponse]


@router.get("/availability", response_model=ParkingAvailabilityResponse)
def parking_availability(response: Response, driver: Annotated[ApplicationUser, Depends(require_driver)]):
    """Read-only capacity snapshot of open authorised zones on active levels."""
    response.headers["Cache-Control"] = "no-store"
    try:
        allowed = {row["zone_id"] for row in database.get_permissions(str(driver.tenant_id))
                   if row["tenant_id"] == str(driver.tenant_id)}
        if not allowed:
            return ParkingAvailabilityResponse(available_spaces=0, accessible_zone_count=0, levels=[])
        levels = {row["id"]: row for row in database.get_levels() if row["is_active"]}
        grouped = {}
        for zone in database.get_zones():
            if (zone["id"] not in allowed or zone["operational_status"] != "open"
                    or zone["level_id"] not in levels):
                continue
            level = levels[zone["level_id"]]
            allocated = database.count_active_sessions(zone["id"], status="allocated")
            occupied = database.count_active_sessions(zone["id"], status="occupied")
            # Same capacity model as rank_zones/reserve_parking_zone. This read
            # never reserves capacity; counts may change immediately afterwards.
            usable = max(0, zone["total_capacity"] - zone["unavailable_capacity"])
            available = max(0, usable - allocated - occupied)
            item = ZoneAvailabilityResponse(
                id=zone["id"], name=zone["name"], level_id=level["id"], level_name=level["name"],
                operational_status="open", total_capacity=zone["total_capacity"],
                unavailable_capacity=zone["unavailable_capacity"], allocated_sessions=allocated,
                occupied_sessions=occupied, total_spaces=usable, available_spaces=available,
                occupancy=(1 - available / usable) if usable else None,
            )
            grouped.setdefault(level["id"], []).append(item)
        results = []
        for level_id, zones in grouped.items():
            level = levels[level_id]
            total = sum(zone.total_spaces for zone in zones)
            available = sum(zone.available_spaces for zone in zones)
            results.append(LevelAvailabilityResponse(
                id=level_id, name=level["name"], level_number=level["level_number"],
                total_spaces=total, available_spaces=available,
                occupancy=(1 - available / total) if total else None,
                zones=sorted(zones, key=lambda zone: (zone.name, str(zone.id))),
            ))
        results.sort(key=lambda level: (level.level_number, str(level.id)))
        return ParkingAvailabilityResponse(
            available_spaces=sum(level.available_spaces for level in results),
            accessible_zone_count=sum(len(level.zones) for level in results), levels=results,
        )
    except (DatabaseError, KeyError, TypeError, ValueError):
        raise HTTPException(503, "Parking availability is unavailable. Please try again.") from None


@router.get("/sessions/active", response_model=ActiveSessionsResponse)
def active_sessions(response: Response, driver: Annotated[ApplicationUser, Depends(require_driver)]):
    """All of this driver's active vehicle sessions; an empty list means none."""
    response.headers["Cache-Control"] = "no-store"
    try:
        sessions = []
        for row in database.get_driver_active_sessions(str(driver.id)):
            vehicle, zone = row["vehicle"], row["zone"]
            level = zone["level"]
            # Fail closed if data violates the query's ownership/relationship contract.
            if (row["user_id"] != str(driver.id) or vehicle["user_id"] != str(driver.id)
                    or row["vehicle_id"] != vehicle["id"] or row["zone_id"] != zone["id"]
                    or zone["level_id"] != level["id"]):
                raise ValueError("Invalid session relationship")
            sessions.append(ActiveSessionResponse(
                id=row["id"], vehicle_id=vehicle["id"], plate_number=vehicle["plate_number"],
                registration_status=vehicle["registration_status"], status=row["status"],
                zone_id=zone["id"], zone_code=zone["code"], zone_name=zone["name"],
                level_id=level["id"], level_name=level["name"], level_number=level["level_number"],
                entry_time=row["entry_time"], parking_confirmed_at=row["parking_confirmed_at"],
                exit_time=row["exit_time"],
            ))
        sessions.sort(key=lambda session: (session.entry_time, str(session.id)), reverse=True)
        return ActiveSessionsResponse(sessions=sessions)
    except (DatabaseError, KeyError, TypeError, ValueError, ValidationError):
        raise HTTPException(503, "Active parking sessions are unavailable. Please try again.") from None


def require_allocation_access(token: Annotated[str | None, Security(allocation_key)]):
    if os.getenv("PARKING_ALLOCATION_ENABLED", "").lower() != "true":
        raise HTTPException(404, "Development allocation endpoint is disabled.")
    expected = os.getenv("PARKING_ALLOCATION_TOKEN", "")
    if not expected:
        raise HTTPException(503, "Configure a separate PARKING_ALLOCATION_TOKEN on the backend.")
    if token is None or not compare_digest(token.encode(), expected.encode()):
        raise HTTPException(403, "Invalid allocation token.")


class AllocationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    plate_number: str = Field(min_length=1, max_length=32, pattern=r"^[A-Z0-9]+$")
    entrance_node_id: UUID

    @field_validator("plate_number", mode="before")
    @classmethod
    def normalise_plate(cls, value):
        # Reject punctuation/internal spaces instead of silently changing identity.
        return value.strip().upper() if isinstance(value, str) else value


class AllocationResponse(BaseModel):
    plate_number: str
    zone_id: UUID
    zone_name: str
    level_id: UUID
    level_name: str
    level_number: int
    distance_meters: float = Field(ge=0, allow_inf_nan=False)
    route_node_ids: list[UUID] = Field(min_length=1)
    parking_session_id: UUID
    status: Literal["allocated"]


@router.post("/allocate", response_model=AllocationResponse, status_code=201,
             dependencies=[Depends(require_allocation_access)])
def allocate(request: AllocationRequest):
    """Creates a real session when enabled and the reservation RPC is installed."""
    try:
        return allocate_parking(request.plate_number, str(request.entrance_node_id))
    except AllocationError as error:
        raise HTTPException(error.status_code, {"code": error.code, "message": str(error)}) from None
    except DatabaseError as error:
        raise HTTPException(503, {"code": "database_unavailable", "message": str(error)}) from None


class ConfirmationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    vehicle_id: UUID


@router.post("/driver/sessions/{session_id}/confirm", response_model=ConfirmationResult)
def driver_confirm(session_id: UUID, response: Response,
                   driver: Annotated[ApplicationUser, Depends(require_driver)]):
    """Authorise the exact session/vehicle pair, then reuse the transactional RPC."""
    response.headers["Cache-Control"] = "no-store"
    try:
        row = database.get_driver_session(str(driver.id), str(session_id))
        if (row is None or row["id"] != str(session_id) or row["user_id"] != str(driver.id)
                or row["vehicle"]["user_id"] != str(driver.id)
                or row["vehicle"]["id"] != row["vehicle_id"]):
            raise HTTPException(404, "Parking session not found.")
        if row["status"] not in ("allocated", "occupied") or row["exit_time"] is not None:
            raise HTTPException(409, "Only an active allocated session can be confirmed.")
        if ((row["status"] == "allocated" and row["parking_confirmed_at"] is not None)
                or (row["status"] == "occupied" and row["parking_confirmed_at"] is None)):
            raise HTTPException(409, "The session has inconsistent confirmation timestamps.")
        # Occupied is an idempotent retry, not another transition. The RPC locks
        # and rechecks state, including an exit that races this preflight read.
        result = confirm_parking(str(session_id), row["vehicle_id"])
        if str(result["zone_id"]) != row["zone_id"]:
            raise DatabaseError("Confirmation assignment mismatch.")
        return result
    except SessionError as error:
        raise HTTPException(error.status_code, {"code": error.code, "message": str(error)}) from None
    except (DatabaseError, KeyError, TypeError, ValueError):
        raise HTTPException(503, "Parking confirmation could not be verified. Refresh the session before retrying.") from None


@router.post("/sessions/{session_id}/confirm", response_model=ConfirmationResult,
             dependencies=[Depends(require_allocation_access)])
def confirm(session_id: UUID, request: ConfirmationRequest):
    """Development-only confirmation; repeats return the original confirmation."""
    try:
        return confirm_parking(str(session_id), str(request.vehicle_id))
    except SessionError as error:
        raise HTTPException(error.status_code, {"code": error.code, "message": str(error)}) from None
    except DatabaseError as error:
        raise HTTPException(503, {"code": "database_unavailable", "message": str(error)}) from None


class ClosureRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    vehicle_id: UUID


@router.post("/sessions/{session_id}/close", response_model=ClosureResult,
             dependencies=[Depends(require_allocation_access)])
def close(session_id: UUID, request: ClosureRequest):
    """Development-only session closure; safe to repeat after completion."""
    try:
        return close_parking(str(session_id), str(request.vehicle_id))
    except SessionError as error:
        raise HTTPException(error.status_code, {"code": error.code, "message": str(error)}) from None
    except DatabaseError as error:
        raise HTTPException(503, {"code": "database_unavailable", "message": str(error)}) from None
