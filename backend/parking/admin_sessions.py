"""Read-only administrator session projection; no lifecycle operations."""
from typing import Literal
from uuid import UUID
from pydantic import AwareDatetime, BaseModel, Field
from backend.parking.analytics import AnalyticsLevel, valid_timestamp

SessionStatus = Literal['allocated', 'occupied', 'completed', 'cancelled']


class AdminParkingSession(BaseModel):
    id: UUID
    vehicle_id: UUID | None
    plate_number: str | None
    owner_name: str | None
    tenant_name: str | None
    zone_id: UUID | None
    zone_name: str | None
    level_id: UUID | None
    level_name: str | None
    status: SessionStatus
    entry_time: AwareDatetime | None
    parking_confirmed_at: AwareDatetime | None
    exit_time: AwareDatetime | None
    duration_seconds: float | None = Field(ge=0)


class AdminSessionPage(BaseModel):
    sessions: list[AdminParkingSession]
    total: int = Field(ge=0)
    limit: int
    offset: int
    levels: list[AnalyticsLevel]
    timezone: Literal['Asia/Kuala_Lumpur'] = 'Asia/Kuala_Lumpur'


def session_record(row):
    vehicle = row.get('vehicle') or {}
    owner = vehicle.get('owner') or {}
    tenant = owner.get('tenant') or {}
    zone = row.get('zone') or {}
    entry, exit_time = valid_timestamp(row.get('entry_time')), valid_timestamp(row.get('exit_time'))
    duration = (exit_time - entry).total_seconds() if row['status'] == 'completed' and entry and exit_time and exit_time >= entry else None
    return AdminParkingSession(id=row['id'], vehicle_id=row.get('vehicle_id'), plate_number=vehicle.get('plate_number'),
        owner_name=owner.get('full_name'), tenant_name=tenant.get('name'), zone_id=row.get('zone_id'),
        zone_name=zone.get('name'), level_id=zone.get('level_id'), level_name=(zone.get('level') or {}).get('name'),
        status=row['status'], entry_time=entry, parking_confirmed_at=valid_timestamp(row.get('parking_confirmed_at')),
        exit_time=exit_time, duration_seconds=duration)
