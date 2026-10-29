"""Read-only midnight-crossing alerts; no fee, status or capacity mutations."""
from datetime import date, datetime, timedelta, timezone
from typing import Literal

from pydantic import AwareDatetime, BaseModel, Field

from backend import database
from backend.parking.admin_sessions import AdminParkingSession, session_record
from backend.parking.analytics import analytics_period, valid_timestamp
from backend.parking.overview import REPORTING_ZONE, reporting_period


class OvernightAlert(BaseModel):
    session: AdminParkingSession
    driver_name: str | None
    driver_company_name: str | None
    first_midnight: AwareDatetime
    midnights_crossed: int = Field(ge=1)
    seconds_after_midnight: int = Field(ge=0)


class OvernightPage(BaseModel):
    kind: Literal['current', 'past']
    timezone: Literal['Asia/Kuala_Lumpur'] = 'Asia/Kuala_Lumpur'
    generated_at: AwareDatetime
    start_date: date | None
    end_date: date | None
    alerts: list[OvernightAlert]
    total: int = Field(ge=0)
    limit: int
    offset: int


def classify(row, kind, now):
    entry = valid_timestamp(row.get('entry_time'))
    exit_time = valid_timestamp(row.get('exit_time'))
    if entry is None or entry > now:
        return None
    if kind == 'current':
        if row.get('status') not in database.ACTIVE_STATUSES or row.get('exit_time') is not None:
            return None
        end = now
    else:
        if row.get('status') != 'completed' or exit_time is None or exit_time < entry or exit_time > now:
            return None
        end = exit_time
    local_entry = entry.astimezone(REPORTING_ZONE)
    midnight = local_entry.replace(hour=0, minute=0, second=0, microsecond=0) + timedelta(days=1)
    if end < midnight:
        return None
    driver = row.get('user') or {}
    tenant = driver.get('tenant') or {}
    return OvernightAlert(session=session_record(row), driver_name=driver.get('full_name'),
        driver_company_name=tenant.get('name'), first_midnight=midnight,
        midnights_crossed=(end.astimezone(REPORTING_ZONE).date() - local_entry.date()).days,
        seconds_after_midnight=int((end - midnight).total_seconds()))


def read(kind, limit, offset, start_date=None, end_date=None, now=None):
    now = now or datetime.now(timezone.utc)
    if now.tzinfo is None:
        raise ValueError('A timezone-aware reporting time is required.')
    if kind == 'current':
        if start_date is not None or end_date is not None:
            raise ValueError('Date filters apply to past stays only.')
        midnight, _ = reporting_period(now)
        rows = database.get_overnight_candidates(kind, midnight.isoformat(), None)
        start_date = end_date = None
    else:
        if start_date is None and end_date is None:
            end_date = now.astimezone(REPORTING_ZONE).date()
            start_date = end_date - timedelta(days=6)
        start_date, end_date, start, end = analytics_period(start_date, end_date, now)
        rows = database.get_overnight_candidates(kind, start.isoformat(), end.isoformat())
    alerts = [alert for row in rows if (alert := classify(row, kind, now)) is not None
              and (kind == 'current' or start <= alert.session.exit_time < end)]
    if kind == 'current':
        alerts.sort(key=lambda alert: (alert.session.entry_time, str(alert.session.id)))
    else:
        alerts.sort(key=lambda alert: (alert.session.exit_time, str(alert.session.id)), reverse=True)
    return OvernightPage(kind=kind, generated_at=now, start_date=start_date, end_date=end_date,
        alerts=alerts[offset:offset + limit], total=len(alerts), limit=limit, offset=offset)
