"""Historical session analytics, with additive occupancy and demand sections."""
from datetime import date, datetime, time, timedelta, timezone
from typing import Literal
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, Field
from backend.parking.overview import REPORTING_ZONE, COUNTED_STATUSES, HourlyMovement, timestamp
from backend.parking.utilisation import HistoricalOccupancy, ParkingDemand, TenantActivity, aggregate_utilisation

MAX_REPORTING_DAYS = 90
BUCKETS = [("Under 1 Hour", 3600), ("1–3 Hours", 10800), ("3–6 Hours", 21600),
           ("6–9 Hours", 32400), ("9+ Hours", None)]


class PeakHour(BaseModel):
    hour: int = Field(ge=0, le=23)
    count: int = Field(gt=0)


class AnalyticsSummary(BaseModel):
    total_entries: int = Field(ge=0)
    total_exits: int = Field(ge=0)
    average_duration_seconds: float | None
    peak_entry_hour: PeakHour | None
    peak_exit_hour: PeakHour | None


class MovementPeriod(BaseModel):
    period: str
    entries: int = Field(ge=0)
    exits: int = Field(ge=0)


class DurationBucket(BaseModel):
    label: str
    count: int = Field(ge=0)


class Durations(BaseModel):
    valid_completed_sessions: int = Field(ge=0)
    distribution: list[DurationBucket]


class AnalyticsLevel(BaseModel):
    id: UUID
    name: str
    level_number: int
    is_active: bool


class ParkingAnalytics(BaseModel):
    start_date: date
    end_date: date
    timezone: Literal["Asia/Kuala_Lumpur"] = "Asia/Kuala_Lumpur"
    period_start: AwareDatetime
    period_end: AwareDatetime
    generated_at: AwareDatetime
    level_id: UUID | None
    levels: list[AnalyticsLevel]
    summary: AnalyticsSummary
    granularity: Literal["hour", "day"]
    movements: list[MovementPeriod]
    hourly_pattern: list[HourlyMovement]
    durations: Durations
    historical_occupancy: HistoricalOccupancy
    parking_demand: ParkingDemand
    tenant_activity: TenantActivity


def analytics_period(start_date, end_date, now):
    today = now.astimezone(REPORTING_ZONE).date()
    if start_date is None and end_date is None:
        start_date, end_date = today - timedelta(days=6), today
    if start_date is None or end_date is None:
        raise ValueError("Provide both start_date and end_date.")
    if start_date < date(1982, 1, 1):
        raise ValueError("Reporting dates must be on or after 1982-01-01.")
    if start_date > end_date or (end_date - start_date).days >= MAX_REPORTING_DAYS:
        raise ValueError("Choose an ordered date range of at most 90 days.")
    if end_date > today:
        raise ValueError("The reporting end date cannot be in the future.")
    start = datetime.combine(start_date, time.min, REPORTING_ZONE).astimezone(timezone.utc)
    end = datetime.combine(end_date + timedelta(days=1), time.min, REPORTING_ZONE).astimezone(timezone.utc)
    return start_date, end_date, start, end


def valid_timestamp(value):
    try:
        return timestamp(value)
    except (ValueError, TypeError, OverflowError):
        return None


def aggregate_analytics(levels, sessions, start_date, end_date, level_id, now, zones=None, tenants=None):
    start_date, end_date, start, end = analytics_period(start_date, end_date, now)
    days = (end_date - start_date).days + 1
    hourly = [HourlyMovement(hour=hour, entries=0, exits=0) for hour in range(24)]
    daily = {str(start_date + timedelta(days=index)): {"entries": 0, "exits": 0} for index in range(days)}
    durations = []
    distribution = [DurationBucket(label=label, count=0) for label, _ in BUCKETS]
    for row in sessions:
        if row["status"] not in COUNTED_STATUSES:
            continue
        if level_id is not None and (row.get("zone") or {}).get("level_id") != str(level_id):
            continue
        entry, exit_time = valid_timestamp(row.get("entry_time")), valid_timestamp(row.get("exit_time"))
        for value, kind in ((entry, "entries"), (exit_time, "exits")):
            if value is not None and start <= value < end and value <= now:
                local = value.astimezone(REPORTING_ZONE)
                daily[str(local.date())][kind] += 1
                setattr(hourly[local.hour], kind, getattr(hourly[local.hour], kind) + 1)
        if row["status"] == "completed" and entry is not None and exit_time is not None and entry <= exit_time <= now and start <= exit_time < end:
            seconds = (exit_time - entry).total_seconds()
            durations.append(seconds)
            for index, (_, upper) in enumerate(BUCKETS):
                if upper is None or seconds < upper:
                    distribution[index].count += 1
                    break

    def peak(kind):
        # max keeps the first (earliest) hour on a tie.
        item = max(hourly, key=lambda hour: getattr(hour, kind))
        return PeakHour(hour=item.hour, count=getattr(item, kind)) if getattr(item, kind) else None

    movements = ([MovementPeriod(period=f"{item.hour:02d}:00", entries=item.entries, exits=item.exits) for item in hourly]
                 if days == 1 else [MovementPeriod(period=day, **values) for day, values in daily.items()])
    options = sorted([AnalyticsLevel(**level) for level in levels], key=lambda level: (level.level_number, str(level.id)))
    return ParkingAnalytics(start_date=start_date, end_date=end_date, period_start=start, period_end=end,
        generated_at=now, level_id=level_id, levels=options, granularity="hour" if days == 1 else "day",
        summary=AnalyticsSummary(total_entries=sum(item.entries for item in hourly), total_exits=sum(item.exits for item in hourly),
            average_duration_seconds=round(sum(durations) / len(durations), 2) if durations else None,
            peak_entry_hour=peak("entries"), peak_exit_hour=peak("exits")), movements=movements, hourly_pattern=hourly,
        durations=Durations(valid_completed_sessions=len(durations), distribution=distribution),
        **aggregate_utilisation(levels, zones or [], tenants or [], sessions, start, end, level_id, now))
