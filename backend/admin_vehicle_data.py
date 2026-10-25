"""Bounded, administrator-only vehicle read projections. No Auth metadata lookups."""
from typing import Literal
from uuid import UUID

from fastapi import HTTPException
from pydantic import AwareDatetime, BaseModel, Field, model_validator

from backend import database

VehicleStatus = Literal['approved', 'pending', 'rejected']


class VehicleCounts(BaseModel):
    approved: int = Field(ge=0)
    pending: int = Field(ge=0)
    rejected: int = Field(ge=0)
    counted: int = Field(ge=0)
    limit: Literal[5]
    limit_reached: bool

    @model_validator(mode='after')
    def consistent(self):
        if self.counted != self.approved + self.pending or self.limit_reached != (self.counted >= self.limit):
            raise ValueError('Inconsistent vehicle counts')
        return self


class DriverIdentity(BaseModel):
    id: UUID
    full_name: str | None
    tenant_id: UUID | None
    company_name: str | None
    approval_status: Literal['approved', 'pending', 'rejected']
    is_active: bool
    vehicle_counts: VehicleCounts


class VehiclePreview(BaseModel):
    id: UUID
    plate_number: str
    registration_status: VehicleStatus


class DriverVehicleOverview(DriverIdentity):
    vehicle_previews: list[VehiclePreview] = Field(max_length=3)


class DriverVehiclePage(BaseModel):
    drivers: list[DriverVehicleOverview]
    total: int = Field(ge=0)
    limit: int = Field(ge=1, le=100)
    offset: int = Field(ge=0, le=1000000)

    @model_validator(mode='after')
    def bounded(self):
        if len(self.drivers) > min(self.limit, max(0, self.total - self.offset)):
            raise ValueError('Invalid driver page')
        if len({driver.id for driver in self.drivers}) != len(self.drivers):
            raise ValueError('Duplicate drivers')
        return self


class DriverDetailIdentity(DriverIdentity):
    # Deliberately unavailable rather than inferred from registration metadata.
    email: None = None


class DriverVehicleRecord(VehiclePreview):
    rejection_reason: str | None = Field(default=None, max_length=500)
    created_at: AwareDatetime | None
    updated_at: AwareDatetime | None


class DriverVehicleDetails(BaseModel):
    driver: DriverDetailIdentity
    vehicles: list[DriverVehicleRecord]
    total: int = Field(ge=0)
    limit: int = Field(ge=1, le=100)
    offset: int = Field(ge=0, le=1000000)

    @model_validator(mode='after')
    def bounded(self):
        if len(self.vehicles) > min(self.limit, max(0, self.total - self.offset)):
            raise ValueError('Invalid vehicle page')
        if len({vehicle.id for vehicle in self.vehicles}) != len(self.vehicles):
            raise ValueError('Duplicate vehicles')
        return self


class VehicleSummaryScope(BaseModel):
    tenant_id: UUID | None
    company_name: str | None


class VehicleSummary(BaseModel):
    scope: VehicleSummaryScope
    registered_vehicles: int = Field(ge=0)
    approved_vehicles: int = Field(ge=0)
    pending_approval: int = Field(ge=0)
    drivers_at_limit: int = Field(ge=0)

    @model_validator(mode='after')
    def consistent(self):
        if self.registered_vehicles < self.approved_vehicles + self.pending_approval:
            raise ValueError('Inconsistent summary')
        if self.drivers_at_limit * 5 > self.approved_vehicles + self.pending_approval:
            raise ValueError('Inconsistent limit summary')
        return self


def normalized_search(value: str) -> str:
    value = value.strip()
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        raise HTTPException(422, 'Use a driver name without control characters.')
    return value


def _payload(result):
    if not isinstance(result, dict):
        raise ValueError('Invalid read response')
    status = result.get('status')
    if status == 'forbidden':
        raise HTTPException(403, 'Administrator access is required.')
    if status == 'unknown_company':
        raise HTTPException(422, 'Select an existing company.')
    if status == 'not_found':
        raise HTTPException(404, 'Driver not found.')
    if status != 'ok' or not isinstance(result.get('data'), dict):
        raise ValueError('Invalid read result')
    return result['data']


def driver_page(admin_id, limit, offset, search, tenant_id, status):
    try:
        page = DriverVehiclePage.model_validate(_payload(database.get_admin_vehicle_drivers(
            admin_id, limit, offset, search, tenant_id, status)))
        if page.limit != limit or page.offset != offset:
            raise ValueError('Page mismatch')
        if tenant_id and any(str(driver.tenant_id) != tenant_id for driver in page.drivers):
            raise ValueError('Company mismatch')
        if status and any(getattr(driver.vehicle_counts, status) < 1 for driver in page.drivers):
            raise ValueError('Status mismatch')
        return page
    except (database.DatabaseError, ValueError, KeyError, TypeError):
        raise HTTPException(503, 'Driver vehicle records are unavailable. Please retry.') from None


def driver_details(admin_id, driver_id, limit, offset, status):
    try:
        details = DriverVehicleDetails.model_validate(_payload(database.get_admin_vehicle_driver_details(
            admin_id, driver_id, limit, offset, status)))
        counts = details.driver.vehicle_counts
        expected = getattr(counts, status) if status else counts.approved + counts.pending + counts.rejected
        if (str(details.driver.id) != driver_id or details.limit != limit or details.offset != offset
                or details.total != expected
                or (status and any(vehicle.registration_status != status for vehicle in details.vehicles))):
            raise ValueError('Driver details mismatch')
        return details
    except (database.DatabaseError, ValueError, KeyError, TypeError):
        raise HTTPException(503, 'Driver details are unavailable. Please retry.') from None


def vehicle_summary(admin_id, tenant_id):
    try:
        result = VehicleSummary.model_validate(_payload(database.get_admin_vehicle_summary(admin_id, tenant_id)))
        if (str(result.scope.tenant_id) if result.scope.tenant_id else None) != tenant_id:
            raise ValueError('Summary company mismatch')
        return result
    except (database.DatabaseError, ValueError, KeyError, TypeError):
        raise HTTPException(503, 'Vehicle summary is unavailable. Please retry.') from None
