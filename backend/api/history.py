"""Read-only, ownership-scoped completed parking history."""

import base64
from datetime import datetime, timedelta, timezone
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import AwareDatetime, BaseModel, Field, ValidationError

from backend import database
from backend.auth import ApplicationUser, require_driver

router = APIRouter()


class HistoryCursor(BaseModel):
    user_id: UUID
    days: Literal[1, 3, 7]
    vehicle_id: UUID | None
    snapshot: AwareDatetime
    exit_time: AwareDatetime | None
    id: UUID


class HistorySession(BaseModel):
    id: UUID
    vehicle_id: UUID
    plate_number: str
    zone_id: UUID
    zone_name: str | None
    level_id: UUID | None
    level_name: str | None
    entry_time: AwareDatetime
    parking_confirmed_at: AwareDatetime | None
    exit_time: AwareDatetime | None
    duration_seconds: float | None
    status: Literal["completed"]


class HistoryVehicle(BaseModel):
    id: UUID
    plate_number: str


class HistoryResponse(BaseModel):
    sessions: list[HistorySession]
    vehicles: list[HistoryVehicle]
    total_sessions: int = Field(ge=0)
    next_cursor: str | None


def timestamp(value):
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return parsed if parsed.tzinfo and parsed.year >= 1982 else None
    except (ValueError, TypeError):
        return None


@router.get("/history", response_model=HistoryResponse)
def history(response: Response, driver: Annotated[ApplicationUser, Depends(require_driver)],
            days: int = 7, vehicle_id: UUID | None = None,
            limit: Annotated[int, Query(ge=1, le=100)] = 30,
            cursor: Annotated[str | None, Query(max_length=2048)] = None):
    response.headers["Cache-Control"] = "no-store"
    if days not in (1, 3, 7):
        raise HTTPException(422, "Choose 1, 3 or 7 days.")
    position = None
    if cursor:
        try:
            position = HistoryCursor.model_validate_json(base64.urlsafe_b64decode(cursor))
            if (position.user_id, position.days, position.vehicle_id) != (driver.id, days, vehicle_id):
                raise ValueError()
        except (ValueError, ValidationError):
            raise HTTPException(422, "Invalid history cursor. Refresh parking history.") from None
    snapshot = position.snapshot if position else datetime.now(timezone.utc)
    local = snapshot.astimezone(timezone(timedelta(hours=8)))
    midnight = local.replace(hour=0, minute=0, second=0, microsecond=0)
    start = (midnight - timedelta(days=days - 1)).astimezone(timezone.utc)
    end = (midnight + timedelta(days=1)).astimezone(timezone.utc)
    try:
        rows, total = database.get_driver_history(
            str(driver.id), start.isoformat(), end.isoformat(), snapshot.isoformat(),
            str(vehicle_id) if vehicle_id else None, limit + 1,
            position.exit_time.isoformat() if position and position.exit_time else None,
            str(position.id) if position else None,
        )
        vehicles = database.get_history_vehicles(str(driver.id))
        results = []
        for row in rows[:limit]:
            vehicle = row["vehicle"]
            if (row["user_id"] != str(driver.id) or vehicle["user_id"] != str(driver.id)
                    or row["vehicle_id"] != vehicle["id"] or row["status"] != "completed"):
                raise ValueError()
            entry = timestamp(row.get("entry_time"))
            if entry is None:
                # An unusable required timestamp must not silently alter totals.
                raise ValueError()
            exit_time = timestamp(row.get("exit_time"))
            zone = row.get("zone") or {}
            level = zone.get("level") or {}
            results.append(HistorySession(
                id=row["id"], vehicle_id=row["vehicle_id"], plate_number=vehicle["plate_number"],
                zone_id=row["zone_id"], zone_name=zone.get("name"), level_id=level.get("id"),
                level_name=level.get("name"), entry_time=entry,
                parking_confirmed_at=timestamp(row.get("parking_confirmed_at")), exit_time=exit_time,
                duration_seconds=(exit_time - entry).total_seconds() if exit_time and exit_time >= entry else None,
                status="completed",
            ))
        next_cursor = None
        if len(rows) > limit:
            last = results[-1]
            token = HistoryCursor(user_id=driver.id, days=days, vehicle_id=vehicle_id,
                                  snapshot=snapshot, exit_time=last.exit_time, id=last.id)
            next_cursor = base64.urlsafe_b64encode(token.model_dump_json().encode()).decode()
        return HistoryResponse(sessions=results, total_sessions=total, next_cursor=next_cursor,
                               vehicles=[HistoryVehicle(**v) for v in vehicles if v["user_id"] == str(driver.id)])
    except (database.DatabaseError, ValueError, KeyError, TypeError, ValidationError):
        raise HTTPException(503, "Parking history is unavailable. Please retry.") from None
