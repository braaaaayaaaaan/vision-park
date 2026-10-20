"""Read-only operational snapshot; no allocation or capacity mutations."""
from collections import Counter
from datetime import date, datetime, timedelta, timezone
from typing import Literal
from uuid import UUID
from zoneinfo import ZoneInfo

from pydantic import AwareDatetime, BaseModel, Field

REPORTING_ZONE = ZoneInfo("Asia/Kuala_Lumpur")
COUNTED_STATUSES = ("allocated", "occupied", "completed")


class CapacityStats(BaseModel):
    usable_capacity: int = Field(ge=0)
    occupied: int = Field(ge=0)
    reserved: int = Field(ge=0)
    available: int = Field(ge=0)
    occupancy_percentage: float | None


class LevelStats(CapacityStats):
    id: UUID
    name: str
    level_number: int


class HourlyMovement(BaseModel):
    hour: int = Field(ge=0, le=23)
    entries: int = Field(ge=0)
    exits: int = Field(ge=0)


class RecentSession(BaseModel):
    id: UUID
    plate_number: str | None
    level_name: str | None
    zone_name: str | None
    status: Literal["allocated", "occupied", "completed"]
    entry_time: AwareDatetime
    exit_time: AwareDatetime | None


class ParkingOverview(BaseModel):
    reporting_date: date
    timezone: Literal["Asia/Kuala_Lumpur"] = "Asia/Kuala_Lumpur"
    period_start: AwareDatetime
    period_end: AwareDatetime
    generated_at: AwareDatetime
    totals: CapacityStats
    today_entries: int = Field(ge=0)
    today_exits: int = Field(ge=0)
    hourly: list[HourlyMovement]
    levels: list[LevelStats]
    recent_sessions: list[RecentSession]


def reporting_period(now):
    if now.tzinfo is None:
        raise ValueError("A timezone-aware snapshot is required")
    local = now.astimezone(REPORTING_ZONE)
    start = local.replace(hour=0, minute=0, second=0, microsecond=0)
    return start.astimezone(timezone.utc), (start + timedelta(days=1)).astimezone(timezone.utc)


def timestamp(value):
    if value is None:
        return None
    result = datetime.fromisoformat(str(value).replace("Z", "+00:00")) if not isinstance(value, datetime) else value
    if result.tzinfo is None:
        raise ValueError("Missing timestamp timezone")
    return result


def percentage(occupied, capacity):
    return round(100 * occupied / capacity, 2) if capacity else None


def aggregate_overview(levels, zones, sessions, recent, now):
    start, end = reporting_period(now)
    active_levels = {row["id"]: row for row in levels if row["is_active"]}
    included_zones = {row["id"]: row for row in zones
                      if row["operational_status"] == "open" and row["level_id"] in active_levels}
    counts = Counter()
    hourly = [HourlyMovement(hour=hour, entries=0, exits=0) for hour in range(24)]
    for row in sessions:
        if row["status"] not in COUNTED_STATUSES:
            continue
        if row["status"] in ("allocated", "occupied"):
            counts[(row["zone_id"], row["status"])] += 1
        for field, bucket in (("entry_time", "entries"), ("exit_time", "exits")):
            value = timestamp(row.get(field))
            if value is not None and start <= value < end and value <= now:
                hour = value.astimezone(REPORTING_ZONE).hour
                setattr(hourly[hour], bucket, getattr(hourly[hour], bucket) + 1)

    by_level = {key: dict(usable_capacity=0, occupied=0, reserved=0, available=0)
                for key in active_levels}
    for zone in included_zones.values():
        capacity = max(0, zone["total_capacity"] - zone["unavailable_capacity"])
        occupied = counts[(zone["id"], "occupied")]
        reserved = counts[(zone["id"], "allocated")]
        target = by_level[zone["level_id"]]
        for key, value in dict(usable_capacity=capacity, occupied=occupied, reserved=reserved,
                               available=max(0, capacity - occupied - reserved)).items():
            target[key] += value
    results = []
    for level_id, values in by_level.items():
        level = active_levels[level_id]
        results.append(LevelStats(id=level_id, name=level["name"], level_number=level["level_number"],
                                  **values, occupancy_percentage=percentage(values["occupied"], values["usable_capacity"])))
    results.sort(key=lambda level: (level.level_number, str(level.id)))
    totals = {key: sum(values[key] for values in by_level.values())
              for key in ("usable_capacity", "occupied", "reserved", "available")}
    recent_results = []
    for row in recent:
        if row["status"] not in COUNTED_STATUSES:
            continue
        zone = row.get("zone") or {}
        level = zone.get("level") or {}
        vehicle = row.get("vehicle") or {}
        recent_results.append(RecentSession(id=row["id"], plate_number=vehicle.get("plate_number"),
            level_name=level.get("name"), zone_name=zone.get("name"), status=row["status"],
            entry_time=row["entry_time"], exit_time=row.get("exit_time")))
    return ParkingOverview(reporting_date=now.astimezone(REPORTING_ZONE).date(), period_start=start,
        period_end=end, generated_at=now, totals=CapacityStats(**totals,
            occupancy_percentage=percentage(totals["occupied"], totals["usable_capacity"])),
        today_entries=sum(hour.entries for hour in hourly), today_exits=sum(hour.exits for hour in hourly),
        hourly=hourly, levels=results, recent_sessions=recent_results)
