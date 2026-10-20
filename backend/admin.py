"""Administrator registration review and read-only parking reports."""

from typing import Annotated, Literal
from uuid import UUID
from datetime import date, datetime, timezone
import re

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import BaseModel, ConfigDict, ValidationError, Field

from backend import database
from backend.auth import ApplicationUser, require_administrator
from backend.parking.overview import ParkingOverview, aggregate_overview, reporting_period
from backend.parking.analytics import ParkingAnalytics, aggregate_analytics, analytics_period
from backend.parking.admin_sessions import AdminSessionPage, SessionStatus, session_record

router = APIRouter(dependencies=[Depends(require_administrator)])
Administrator = Annotated[ApplicationUser, Depends(require_administrator)]


@router.get('/parking/sessions', response_model=AdminSessionPage)
def parking_sessions(response: Response, limit: Annotated[int, Query(ge=1, le=100)] = 25,
                     offset: Annotated[int, Query(ge=0, le=1000000)] = 0,
                     plate: Annotated[str, Query(max_length=64)] = '', status: SessionStatus | None = None,
                     level_id: UUID | None = None, start_date: date | None = None, end_date: date | None = None):
    response.headers['Cache-Control'] = 'no-store'
    plate = plate.strip().upper()
    if plate and not re.fullmatch(r'[A-Z0-9]{1,32}', plate):
        raise HTTPException(422, 'Use up to 32 letters or digits for number plate search.')
    start = end = None
    if start_date is not None or end_date is not None:
        try:
            _, _, start, end = analytics_period(start_date, end_date, datetime.now(timezone.utc))
        except ValueError as error:
            raise HTTPException(422, str(error)) from None
    try:
        levels = database.get_levels()
        if level_id is not None and not any(row['id'] == str(level_id) for row in levels):
            raise HTTPException(422, 'Select an existing parking level.')
        rows, total = database.get_admin_parking_sessions(limit, offset, plate, status,
            str(level_id) if level_id else None, start.isoformat() if start else None, end.isoformat() if end else None)
        return AdminSessionPage(sessions=[session_record(row) for row in rows], total=total, limit=limit, offset=offset,
            levels=sorted(levels, key=lambda level: (level['level_number'], level['id'])))
    except (database.DatabaseError, ValueError, KeyError, TypeError):
        raise HTTPException(503, 'Parking sessions are unavailable. Please retry.') from None


class VehicleCompany(BaseModel):
    id: UUID
    name: str


class AdminVehicle(BaseModel):
    id: UUID
    plate_number: str
    registration_status: Literal['approved', 'pending', 'rejected']
    owner_id: UUID | None
    owner_name: str | None
    tenant_id: UUID | None
    tenant_name: str | None


class AdminVehiclePage(BaseModel):
    vehicles: list[AdminVehicle]
    total: int = Field(ge=0)
    limit: int
    offset: int
    companies: list[VehicleCompany]


class VehicleDecisionRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')


class VehicleDecisionResponse(BaseModel):
    id: UUID
    plate_number: str
    registration_status: Literal['approved', 'rejected']


def decide_vehicle(admin: ApplicationUser, vehicle_id: UUID, decision: str):
    try:
        result = database.decide_vehicle_registration(str(admin.id), str(vehicle_id), decision)
        errors = {
            'forbidden': (403, 'Administrator access is required.'),
            'not_found': (404, 'Vehicle not found. Refresh the vehicle list.'),
            'conflict': (409, 'This registration has already been processed. Refresh the vehicle list.'),
            'invalid_decision': (400, 'Invalid vehicle registration decision.'),
        }
        if result.get('status') in errors:
            code, message = errors[result['status']]
            raise HTTPException(code, message)
        vehicle = VehicleDecisionResponse.model_validate(result)
        if vehicle.id != vehicle_id or vehicle.registration_status != decision or result.get('status') != decision:
            raise ValueError('Unexpected vehicle decision result')
        return vehicle
    except (database.DatabaseError, ValueError, KeyError, TypeError):
        raise HTTPException(503, 'Vehicle decision could not be confirmed. Refresh the list before retrying. Ensure the vehicle decision RPC is deployed.') from None


@router.post('/vehicles/{vehicle_id}/approve', response_model=VehicleDecisionResponse)
def approve_vehicle(vehicle_id: UUID, admin: Administrator, response: Response,
                    request: VehicleDecisionRequest | None = None):
    response.headers['Cache-Control'] = 'no-store'
    return decide_vehicle(admin, vehicle_id, 'approved')


@router.post('/vehicles/{vehicle_id}/reject', response_model=VehicleDecisionResponse)
def reject_vehicle(vehicle_id: UUID, admin: Administrator, response: Response,
                   request: VehicleDecisionRequest | None = None):
    response.headers['Cache-Control'] = 'no-store'
    return decide_vehicle(admin, vehicle_id, 'rejected')


@router.get('/vehicles', response_model=AdminVehiclePage)
def registered_vehicles(response: Response, limit: Annotated[int, Query(ge=1, le=100)] = 25,
                        offset: Annotated[int, Query(ge=0, le=1000000)] = 0,
                        plate: Annotated[str, Query(max_length=64)] = '',
                        status: Literal['approved', 'pending', 'rejected'] | None = None,
                        tenant_id: UUID | None = None):
    response.headers['Cache-Control'] = 'no-store'
    plate = plate.strip().upper()
    if plate and not re.fullmatch(r'[A-Z0-9]{1,32}', plate):
        raise HTTPException(422, 'Use up to 32 letters or digits for number plate search.')
    try:
        rows, total = database.get_admin_vehicles(limit, offset, plate, status, str(tenant_id) if tenant_id else None)
        vehicles = []
        for row in rows:
            owner = row.get('owner') or {}
            tenant = owner.get('tenant') or {}
            vehicles.append(AdminVehicle(id=row['id'], plate_number=row['plate_number'],
                registration_status=row['registration_status'], owner_id=row.get('user_id'),
                owner_name=owner.get('full_name'), tenant_id=owner.get('tenant_id'), tenant_name=tenant.get('name')))
        return AdminVehiclePage(vehicles=vehicles, total=total, limit=limit, offset=offset,
            companies=sorted(database.get_vehicle_companies(), key=lambda company: (company['name'], company['id'])))
    except (database.DatabaseError, ValueError, KeyError, TypeError):
        raise HTTPException(503, 'Vehicle records are unavailable. Please retry.') from None


@router.get("/parking/analytics", response_model=ParkingAnalytics)
def parking_analytics(response: Response, start_date: date | None = None,
                      end_date: date | None = None, level_id: UUID | None = None):
    response.headers["Cache-Control"] = "no-store"
    now = datetime.now(timezone.utc)
    try:
        first, last, start, end = analytics_period(start_date, end_date, now)
    except ValueError as error:
        raise HTTPException(422, str(error)) from None
    try:
        levels = database.get_levels()
        if level_id is not None and not any(row["id"] == str(level_id) for row in levels):
            raise HTTPException(422, "Select an existing parking level.")
        rows = database.get_analytics_sessions(start.isoformat(), end.isoformat(), str(level_id) if level_id else None)
        return aggregate_analytics(levels, rows, first, last, level_id, now,
            zones=database.get_zones(), tenants=database.get_analytics_tenants())
    except (database.DatabaseError, KeyError, TypeError, ValueError):
        raise HTTPException(503, "Parking analytics are unavailable. Please retry.") from None


@router.get("/parking/overview", response_model=ParkingOverview)
def parking_overview(response: Response):
    response.headers["Cache-Control"] = "no-store"
    now = datetime.now(timezone.utc)
    start, end = reporting_period(now)
    try:
        return aggregate_overview(database.get_levels(), database.get_zones(),
            database.get_overview_sessions(start.isoformat(), end.isoformat()),
            database.get_overview_recent_sessions(now.isoformat()), now)
    except (database.DatabaseError, KeyError, TypeError, ValueError):
        raise HTTPException(503, "Parking overview is unavailable. Please retry.") from None


class RequestedCompany(BaseModel):
    id: UUID
    name: str
    is_active: bool


class PendingRegistration(BaseModel):
    id: UUID
    full_name: str | None
    approval_status: Literal["pending"]
    is_active: bool
    requested_tenant_id: UUID | None
    requested_company: RequestedCompany | None


class ApprovalRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    tenant_id: UUID


class DecisionResponse(BaseModel):
    id: UUID
    approval_status: Literal["approved", "rejected"]
    is_active: bool
    tenant_id: UUID | None


@router.get("/registrations", response_model=list[PendingRegistration])
def registrations(response: Response, limit: Annotated[int, Query(ge=1, le=100)] = 50,
                  offset: Annotated[int, Query(ge=0)] = 0):
    response.headers["Cache-Control"] = "no-store"
    try:
        return database.get_pending_driver_registrations(limit, offset)
    except database.DatabaseError:
        raise HTTPException(503, "Registration service is unavailable.") from None


def decide(admin: ApplicationUser, user_id: UUID, decision: str, tenant_id: UUID | None):
    if admin.id == user_id:
        raise HTTPException(409, "Only pending driver applications can be processed.")
    try:
        result = database.decide_driver_registration(
            str(admin.id), str(user_id), decision, str(tenant_id) if tenant_id else None)
    except database.DatabaseError:
        raise HTTPException(503, "Registration service is unavailable; check the backend RPC deployment.") from None
    errors = {
        "forbidden": (403, "Administrator access is required."),
        "not_found": (404, "Application profile not found."),
        "invalid_application": (409, "Only pending driver applications can be processed."),
        "conflict": (409, "Application already processed or no longer eligible. Refresh the application list."),
        "incomplete_application": (409, "Application profile is incomplete."),
        "invalid_company": (400, "Select a valid, active company."),
        "invalid_decision": (400, "Invalid registration decision."),
    }
    status = result.get("status")
    if status in errors:
        code, message = errors[status]
        raise HTTPException(code, message)
    try:
        profile = DecisionResponse.model_validate(result)
        if (status != decision or profile.id != user_id or profile.approval_status != decision
                or profile.is_active != (decision == "approved") or profile.tenant_id != tenant_id):
            raise ValueError("Unexpected decision result")
        return profile
    except (ValidationError, ValueError):
        raise HTTPException(503, "Registration service returned an invalid response.") from None


@router.post("/registrations/{user_id}/approve", response_model=DecisionResponse)
def approve(user_id: UUID, request: ApprovalRequest, admin: Administrator, response: Response):
    response.headers["Cache-Control"] = "no-store"
    return decide(admin, user_id, "approved", request.tenant_id)


@router.post("/registrations/{user_id}/reject", response_model=DecisionResponse)
def reject(user_id: UUID, admin: Administrator, response: Response):
    response.headers["Cache-Control"] = "no-store"
    return decide(admin, user_id, "rejected", None)
