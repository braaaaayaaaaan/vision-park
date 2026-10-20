"""Session-derived occupancy and assignment breakdowns; no capacity percentages."""
from bisect import bisect_right
from collections import Counter
from datetime import timedelta
from typing import Literal
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, Field
from backend.parking.overview import COUNTED_STATUSES, timestamp


class OccupancyPoint(BaseModel):
    timestamp: AwareDatetime
    occupied: int = Field(ge=0)


class HistoricalOccupancy(BaseModel):
    checkpoint: Literal["hour_start", "day_end_or_refresh"]
    points: list[OccupancyPoint]


class ZoneDemand(BaseModel):
    id: UUID
    name: str
    assignments: int = Field(ge=0)


class LevelDemand(BaseModel):
    id: UUID
    name: str
    level_number: int
    assignments: int = Field(ge=0)
    zones: list[ZoneDemand]


class ParkingDemand(BaseModel):
    levels: list[LevelDemand]
    unmapped_assignments: int = Field(ge=0)


class TenantCount(BaseModel):
    id: UUID
    name: str
    sessions: int = Field(ge=0)


class TenantActivity(BaseModel):
    association: Literal["session_user_current_tenant"] = "session_user_current_tenant"
    tenants: list[TenantCount]
    unattributed_sessions: int = Field(ge=0)


def safe_time(value):
    try:
        return timestamp(value)
    except (ValueError, TypeError, OverflowError):
        return None


def aggregate_utilisation(levels, zones, tenants, sessions, start, end, level_id, now):
    selected = str(level_id) if level_id is not None else None
    level_map = {row["id"]: row for row in levels if selected is None or row["id"] == selected}
    zone_map = {row["id"]: row for row in zones if row["level_id"] in level_map}
    tenant_map = {row["id"]: row for row in tenants}
    assignments, company_counts = Counter(), Counter()
    unmapped = unattributed = 0
    begins, ends = [], []
    for row in sessions:
        if row["status"] not in COUNTED_STATUSES:
            continue
        if selected is not None and (row.get("zone") or {}).get("level_id") != selected:
            continue
        entry = safe_time(row.get("entry_time"))
        if entry is not None and start <= entry < end and entry <= now:
            zone_id = row.get("zone_id")
            if zone_id in zone_map:
                assignments[zone_id] += 1
            else:
                unmapped += 1
            tenant_id = (row.get("user") or {}).get("tenant_id")
            if tenant_id in tenant_map:
                company_counts[tenant_id] += 1
            else:
                unattributed += 1

        confirmed = safe_time(row.get("parking_confirmed_at"))
        exit_time = safe_time(row.get("exit_time"))
        # Do not infer confirmations or transitions from allocation/current status alone.
        if entry is None or confirmed is None or not entry <= confirmed <= now:
            continue
        if row["status"] == "occupied" and row.get("exit_time") is None:
            begins.append(confirmed)
        elif row["status"] == "completed" and exit_time is not None and confirmed <= exit_time <= now:
            begins.append(confirmed)
            ends.append(exit_time)
    begins.sort()
    ends.sort()
    single = end - start == timedelta(days=1)
    checkpoints = []
    cursor = start
    while cursor < end and cursor <= now:
        point = cursor if single else min(cursor + timedelta(days=1) - timedelta(microseconds=1), now)
        checkpoints.append(OccupancyPoint(timestamp=point, occupied=bisect_right(begins, point) - bisect_right(ends, point)))
        cursor += timedelta(hours=1) if single else timedelta(days=1)
    demand = []
    for key, level in sorted(level_map.items(), key=lambda item: (item[1]["level_number"], item[0])):
        local = sorted((zone for zone in zone_map.values() if zone["level_id"] == key), key=lambda row: (row["name"], row["id"]))
        items = [ZoneDemand(id=zone["id"], name=zone["name"], assignments=assignments[zone["id"]]) for zone in local]
        demand.append(LevelDemand(id=key, name=level["name"], level_number=level["level_number"],
            assignments=sum(item.assignments for item in items), zones=items))
    companies = [TenantCount(id=key, name=tenant["name"], sessions=company_counts[key]) for key, tenant in tenant_map.items()]
    companies.sort(key=lambda item: (-item.sessions, item.name, str(item.id)))
    return dict(historical_occupancy=HistoricalOccupancy(checkpoint="hour_start" if single else "day_end_or_refresh", points=checkpoints),
        parking_demand=ParkingDemand(levels=demand, unmapped_assignments=unmapped),
        tenant_activity=TenantActivity(tenants=companies, unattributed_sessions=unattributed))
