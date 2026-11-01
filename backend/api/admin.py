"""Administrator registration review, tenant management and parking configuration."""

from typing import Annotated, Literal
from uuid import UUID
from datetime import date, datetime, timezone
import re

from fastapi import APIRouter, Depends, HTTPException, Query, Response, Request
from starlette.concurrency import run_in_threadpool
from pydantic import BaseModel, ConfigDict, ValidationError, Field, field_validator

from backend import database
from backend import tenants
from backend.vehicle_rejection import normalize_rejection_reason
from backend import admin_vehicle_data as vehicle_data
from backend.admin_registration_data import RegistrationSummary, summarize_registrations
from backend.auth import ApplicationUser, require_administrator
from backend.parking.overview import ParkingOverview, aggregate_overview, reporting_period
from backend.parking.analytics import ParkingAnalytics, aggregate_analytics, analytics_period
from backend.parking.admin_sessions import AdminSessionPage, AdminSessionSummary, SessionStatus, session_record
from backend.parking import overnight
from backend.parking import status_reminders
from backend.parking import floor_plans
from backend.parking import calibration
from backend.parking import node_drafts
from backend.parking import edge_drafts
from backend.parking import cross_level_drafts
from backend.parking import levels as parking_levels
from backend.parking import zone_drafts
from backend.parking import zone_entrances
from backend.parking import structure_validation
from backend.parking import publication

router = APIRouter(dependencies=[Depends(require_administrator)])
Administrator = Annotated[ApplicationUser, Depends(require_administrator)]


@router.get('/parking/status-reminders')
def read_status_reminders(response: Response, admin: Administrator,
                          session_ids: Annotated[str, Query(min_length=36, max_length=369)]):
    response.headers['Cache-Control'] = 'private, no-store'
    try:
        ids = [str(UUID(value)) for value in session_ids.split(',')]
        if not 1 <= len(ids) <= 10 or len(set(ids)) != len(ids):
            raise ValueError()
    except ValueError:
        raise HTTPException(422, 'Choose 1–10 distinct parking sessions.') from None
    try:
        return status_reminders.read(str(admin.id), ids)
    except (database.DatabaseError, ValueError, KeyError, TypeError):
        raise HTTPException(503, 'Parking reminders are unavailable. Check reminder storage setup and retry.') from None


@router.post('/parking/status-reminders')
def send_status_reminder(change: status_reminders.SendReminder, response: Response, admin: Administrator):
    response.headers['Cache-Control'] = 'private, no-store'
    try:
        return status_reminders.send(str(admin.id), change)
    except (database.DatabaseError, ValueError, KeyError, TypeError):
        raise HTTPException(503, 'Reminder delivery could not be confirmed. Refresh before retrying the same request.') from None


@router.get('/tenants')
def list_tenants(response: Response, admin: Administrator,
                 search: Annotated[str, Query(max_length=120)] = '',
                 status: Literal['all', 'active', 'inactive'] = 'all',
                 sort: Literal['name_asc', 'name_desc', 'drivers_desc', 'pending_desc'] = 'name_asc',
                 limit: Annotated[int, Query(ge=1, le=100)] = 25,
                 offset: Annotated[int, Query(ge=0, le=1000000)] = 0):
    response.headers['Cache-Control'] = 'private, no-store'
    try:
        return tenants.read(str(admin.id), search=search, status=status, sort=sort, limit=limit, offset=offset)
    except database.DatabaseError:
        raise HTTPException(503, 'Tenant management is unavailable. Check tenant storage setup and retry.') from None


@router.get('/tenants/{tenant_id}')
def tenant_details(tenant_id: UUID, response: Response, admin: Administrator):
    response.headers['Cache-Control'] = 'private, no-store'
    try:
        return tenants.read(str(admin.id), str(tenant_id))
    except database.DatabaseError:
        raise HTTPException(503, 'Company details are unavailable. Please retry.') from None


async def tenant_change(request, response, admin, tenant_id=None):
    response.headers['Cache-Control'] = 'private, no-store'
    if request.headers.get('content-type', '').split(';')[0].lower() != 'application/json':
        raise HTTPException(415, 'Use a JSON company request.')
    body = bytearray()
    async for chunk in request.stream():
        if len(body) + len(chunk) > tenants.MAX_BODY_BYTES:
            raise HTTPException(413, 'Company request exceeds 128 KiB.')
        body.extend(chunk)
    try:
        change = tenants.TenantInput.model_validate_json(body)
    except ValidationError:
        raise HTTPException(422, 'Use a readable company name, valid zones and the current revision.') from None
    if tenant_id is not None and change.id != tenant_id:
        raise HTTPException(422, 'The company identifier does not match.')
    try:
        return await run_in_threadpool(tenants.save, str(admin.id), change, tenant_id is None)
    except database.DatabaseError:
        raise HTTPException(503, 'Company save could not be confirmed. Refresh before retrying.') from None


@router.post('/tenants', status_code=201)
async def create_tenant(request: Request, response: Response, admin: Administrator):
    return await tenant_change(request, response, admin)


@router.put('/tenants/{tenant_id}')
async def update_tenant(tenant_id: UUID, request: Request, response: Response, admin: Administrator):
    return await tenant_change(request, response, admin, tenant_id)


@router.post('/parking/structure/publication/{action}')
async def publication_action(action: Literal['preview','publish'], request: Request, response: Response, admin: Administrator):
    response.headers['Cache-Control']='private, no-store'
    if request.headers.get('content-type','').split(';')[0].lower()!='application/json':
        raise HTTPException(415,'Use a JSON publication request.')
    body=bytearray()
    async for chunk in request.stream():
        if len(body)+len(chunk)>publication.MAX_BODY_BYTES:
            raise HTTPException(413,'Publication request exceeds 64 KiB.')
        body.extend(chunk)
    try:
        change=(publication.PreviewInput if action=='preview' else publication.PublishInput).model_validate_json(body)
    except ValidationError:
        raise HTTPException(422,'Select current levels, explicit tenant permissions and valid preview/confirmation fields.') from None
    try:
        return await run_in_threadpool(publication.preview if action=='preview' else publication.publish,str(admin.id),change)
    except database.DatabaseError:
        raise HTTPException(503,'Publication result could not be confirmed. Refresh preview and review the recorded revision before retrying.') from None


@router.post('/parking/structure/validate')
async def validate_parking_structure(request: Request, response: Response, admin: Administrator):
    response.headers['Cache-Control'] = 'private, no-store'
    if request.headers.get('content-type', '').split(';')[0].lower() != 'application/json':
        raise HTTPException(415, 'Use a JSON validation scope.')
    body = bytearray()
    async for chunk in request.stream():
        if len(body) + len(chunk) > structure_validation.MAX_BODY_BYTES:
            raise HTTPException(413, 'Validation scope exceeds 8 KiB.')
        body.extend(chunk)
    try:
        scope = structure_validation.ValidationScope.model_validate_json(body)
    except ValidationError:
        raise HTTPException(422, 'Select 1–64 distinct parking level UUIDs.') from None
    try:
        return await run_in_threadpool(structure_validation.validate, str(admin.id), scope)
    except database.DatabaseError:
        raise HTTPException(503, 'Draft validation is unavailable. Check validation storage setup and retry.') from None


async def zone_draft_request(request, model):
    if request.headers.get('content-type', '').split(';')[0].lower() != 'application/json':
        raise HTTPException(415, 'Use a JSON draft zone request.')
    body = bytearray()
    async for chunk in request.stream():
        if len(body) + len(chunk) > zone_drafts.MAX_BODY_BYTES:
            raise HTTPException(413, 'Draft zone request exceeds 32 KiB.')
        body.extend(chunk)
    try:
        return model.model_validate_json(body)
    except ValidationError:
        raise HTTPException(422, 'Use readable zone codes/names, valid integer capacities, an intended status and the current edit revision.') from None


@router.get('/parking/levels/{level_id}/floor-plan/node-zone-draft')
def read_node_zone_draft(level_id: UUID, floor_plan_revision: Annotated[int, Query(ge=1, le=2147483646)], response: Response, admin: Administrator):
    response.headers['Cache-Control'] = 'private, no-store'
    try:
        return zone_entrances.read(str(admin.id), str(level_id), floor_plan_revision)
    except database.DatabaseError:
        raise HTTPException(503, 'Draft zone links are unavailable. Check mapping storage setup.') from None


@router.put('/parking/levels/{level_id}/floor-plan/node-zone-draft')
async def save_node_zone_draft(level_id: UUID, request: Request, response: Response, admin: Administrator):
    response.headers['Cache-Control'] = 'private, no-store'
    if request.headers.get('content-type', '').split(';')[0].lower() != 'application/json':
        raise HTTPException(415, 'Use a JSON node and zone-link draft.')
    body = bytearray()
    async for chunk in request.stream():
        if len(body) + len(chunk) > zone_entrances.MAX_BODY_BYTES:
            raise HTTPException(413, 'Node and zone-link draft exceeds 768 KiB.')
        body.extend(chunk)
    try:
        change = zone_entrances.NodeZoneInput.model_validate_json(body)
    except ValidationError:
        raise HTTPException(422, 'Use valid draft nodes, zone links and current edit revisions.') from None
    try:
        return await run_in_threadpool(zone_entrances.save, str(admin.id), str(level_id), change)
    except database.DatabaseError:
        raise HTTPException(503, 'Node and zone-link save could not be confirmed. Reload before retrying.') from None


@router.get('/parking/levels/{level_id}/zone-drafts')
def read_zone_drafts(level_id: UUID, response: Response, admin: Administrator):
    response.headers['Cache-Control'] = 'private, no-store'
    try:
        return zone_drafts.read(str(admin.id), str(level_id))
    except database.DatabaseError:
        raise HTTPException(503, 'Draft zones are unavailable. Check draft zone storage setup.') from None


@router.post('/parking/levels/{level_id}/zone-drafts', status_code=201)
async def create_zone_draft(level_id: UUID, request: Request, response: Response, admin: Administrator):
    response.headers['Cache-Control'] = 'private, no-store'
    change = await zone_draft_request(request, zone_drafts.ZoneInput)
    try:
        return await run_in_threadpool(zone_drafts.mutate, str(admin.id), str(level_id), 'create', change)
    except database.DatabaseError:
        raise HTTPException(503, 'Draft zone creation could not be confirmed. Refresh before retrying.') from None


@router.patch('/parking/levels/{level_id}/zone-drafts/{zone_id}')
async def edit_zone_draft(level_id: UUID, zone_id: UUID, request: Request, response: Response, admin: Administrator):
    response.headers['Cache-Control'] = 'private, no-store'
    change = await zone_draft_request(request, zone_drafts.ZonePatch)
    try:
        return await run_in_threadpool(zone_drafts.mutate, str(admin.id), str(level_id), 'update', change, str(zone_id))
    except database.DatabaseError:
        raise HTTPException(503, 'Draft zone edit could not be confirmed. Refresh before retrying.') from None


@router.delete('/parking/levels/{level_id}/zone-drafts/{zone_id}')
async def delete_zone_draft(level_id: UUID, zone_id: UUID, request: Request, response: Response, admin: Administrator):
    response.headers['Cache-Control'] = 'private, no-store'
    change = await zone_draft_request(request, zone_drafts.ZoneDelete)
    try:
        return await run_in_threadpool(zone_drafts.mutate, str(admin.id), str(level_id), 'delete', change, str(zone_id))
    except database.DatabaseError:
        raise HTTPException(503, 'Draft zone deletion could not be confirmed. Refresh before retrying.') from None


async def level_request(request, model):
    if request.headers.get('content-type', '').split(';')[0].lower() != 'application/json':
        raise HTTPException(415, 'Use a JSON level request.')
    body = bytearray()
    async for chunk in request.stream():
        if len(body) + len(chunk) > parking_levels.MAX_BODY_BYTES:
            raise HTTPException(413, 'Level request exceeds 32 KiB.')
        body.extend(chunk)
    try:
        return model.model_validate_json(body)
    except ValidationError:
        if model is parking_levels.LevelDelete:
            raise HTTPException(422, 'Use the expected metadata revision from the current level record.') from None
        raise HTTPException(422, 'Use integer level numbers, nonempty names of at most 100 characters and an exact edit snapshot.') from None


@router.post('/parking/levels', status_code=201)
async def create_parking_level(request: Request, response: Response, admin: Administrator):
    response.headers['Cache-Control'] = 'private, no-store'
    item = await level_request(request, parking_levels.LevelInput)
    try:
        data = await run_in_threadpool(parking_levels.create, str(admin.id), [item])
        return {'level': data['levels'][0]}
    except database.DatabaseError:
        raise HTTPException(503, 'Level creation could not be confirmed. Refresh before retrying.') from None


@router.post('/parking/levels/bulk', status_code=201)
async def create_multiple_parking_levels(request: Request, response: Response, admin: Administrator):
    response.headers['Cache-Control'] = 'private, no-store'
    batch = await level_request(request, parking_levels.LevelBulk)
    try:
        return await run_in_threadpool(parking_levels.create, str(admin.id), batch.levels)
    except database.DatabaseError:
        raise HTTPException(503, 'Bulk creation could not be confirmed. Refresh before retrying.') from None


@router.patch('/parking/levels/{level_id}')
async def edit_parking_level(level_id: UUID, request: Request, response: Response, admin: Administrator):
    response.headers['Cache-Control'] = 'private, no-store'
    change = await level_request(request, parking_levels.LevelPatch)
    try:
        return await run_in_threadpool(parking_levels.update, str(admin.id), str(level_id), change)
    except database.DatabaseError:
        raise HTTPException(503, 'Level edit could not be confirmed. Refresh before retrying.') from None


@router.delete('/parking/levels/{level_id}')
async def delete_parking_level(level_id: UUID, request: Request, response: Response, admin: Administrator):
    response.headers['Cache-Control'] = 'private, no-store'
    change = await level_request(request, parking_levels.LevelDelete)
    try:
        return await run_in_threadpool(parking_levels.delete, str(admin.id), str(level_id), change)
    except database.DatabaseError:
        raise HTTPException(503, 'Level deletion could not be confirmed. Refresh before retrying.') from None


@router.get('/parking/cross-level-draft-edges')
def read_cross_level_edges(response: Response, admin: Administrator, level_id: UUID | None = None,
                          limit: Annotated[int, Query(ge=1, le=50)] = 10, offset: Annotated[int, Query(ge=0, le=1000000)] = 0):
    response.headers['Cache-Control'] = 'private, no-store'
    try:
        return cross_level_drafts.read(str(admin.id), str(level_id) if level_id else None, limit, offset)
    except database.DatabaseError:
        raise HTTPException(503, 'Cross-level ramps are unavailable. Check ramp draft storage setup.') from None


@router.put('/parking/cross-level-draft-edges')
async def save_cross_level_edges(request: Request, response: Response, admin: Administrator):
    response.headers['Cache-Control'] = 'private, no-store'
    if request.headers.get('content-type', '').split(';')[0].lower() != 'application/json':
        raise HTTPException(415, 'Use a JSON ramp connection batch.')
    body = bytearray()
    async for chunk in request.stream():
        if len(body) + len(chunk) > cross_level_drafts.MAX_BODY_BYTES:
            raise HTTPException(413, 'Ramp connection batch exceeds 32 KiB.')
        body.extend(chunk)
    try:
        batch = cross_level_drafts.RampBatch.model_validate_json(body)
    except ValidationError:
        raise HTTPException(422, 'Use distinct ramp endpoints, valid revisions and confirmed calibrated ramp traces.') from None
    try:
        return await run_in_threadpool(cross_level_drafts.save, str(admin.id), batch)
    except database.DatabaseError:
        raise HTTPException(503, 'Ramp save could not be confirmed. Refresh before retrying.') from None


@router.get('/parking/structure')
def parking_structure(response: Response):
    response.headers['Cache-Control'] = 'private, no-store'
    try:
        return floor_plans.listing()
    except database.DatabaseError:
        raise HTTPException(503, 'Parking structure is unavailable. Check floor-plan setup.') from None


@router.put('/parking/levels/{level_id}/floor-plan')
async def upload_floor_plan(level_id: UUID, request: Request, response: Response,
                            admin: Administrator,
                            expected_revision: Annotated[int, Query(ge=0, le=2147483646)]):
    response.headers['Cache-Control'] = 'private, no-store'
    if request.headers.get('content-type', '').split(';')[0].lower() not in ('image/png', 'image/jpeg'):
        raise HTTPException(415, 'Use a PNG or JPEG image.')
    body = bytearray()
    async for chunk in request.stream():
        if len(body) + len(chunk) > floor_plans.MAX_BYTES:
            raise floor_plans.size_error('floor_plan_upload_too_large')
        body.extend(chunk)
    try:
        return await run_in_threadpool(floor_plans.upload, str(level_id), str(admin.id), expected_revision, bytes(body))
    except database.DatabaseError:
        raise HTTPException(503, 'Floor-plan save is unavailable. Refresh before retrying.') from None


@router.get('/parking/levels/{level_id}/floor-plan/graph-draft')
def read_graph_draft(level_id: UUID, floor_plan_revision: Annotated[int, Query(ge=1, le=2147483646)], response: Response, admin: Administrator):
    response.headers['Cache-Control'] = 'private, no-store'
    try:
        return edge_drafts.read(str(level_id), str(admin.id), floor_plan_revision)
    except database.DatabaseError:
        raise HTTPException(503, 'Connection draft is unavailable. Check edge storage setup.') from None


@router.put('/parking/levels/{level_id}/floor-plan/graph-draft')
async def save_graph_draft(level_id: UUID, request: Request, response: Response, admin: Administrator):
    response.headers['Cache-Control'] = 'private, no-store'
    if request.headers.get('content-type', '').split(';')[0].lower() != 'application/json':
        raise HTTPException(415, 'Use a JSON connection draft.')
    body = bytearray()
    async for chunk in request.stream():
        if len(body) + len(chunk) > edge_drafts.MAX_BODY_BYTES:
            raise HTTPException(413, 'Connection draft exceeds 512 KiB.')
        body.extend(chunk)
    try:
        data = edge_drafts.EdgeInput.model_validate_json(body)
    except ValidationError:
        raise HTTPException(422, 'Use valid revisions and unique UUID connections between distinct nodes. Distances are calculated by the server.') from None
    try:
        return await run_in_threadpool(edge_drafts.save, str(level_id), str(admin.id), data)
    except database.DatabaseError:
        raise HTTPException(503, 'Connection save could not be confirmed. Reload before retrying.') from None


@router.get('/parking/levels/{level_id}/floor-plan/node-draft')
def read_node_draft(level_id: UUID, floor_plan_revision: Annotated[int, Query(ge=1)], response: Response):
    response.headers['Cache-Control'] = 'private, no-store'
    try:
        return node_drafts.read(str(level_id), floor_plan_revision)
    except database.DatabaseError:
        raise HTTPException(503, 'Node draft is unavailable. Check draft storage setup.') from None


@router.put('/parking/levels/{level_id}/floor-plan/node-draft')
async def save_node_draft(level_id: UUID, request: Request, response: Response, admin: Administrator):
    response.headers['Cache-Control'] = 'private, no-store'
    if request.headers.get('content-type', '').split(';')[0] != 'application/json':
        raise HTTPException(415, 'Use a JSON node draft.')
    body = bytearray()
    async for chunk in request.stream():
        if len(body) + len(chunk) > node_drafts.MAX_BODY_BYTES:
            raise HTTPException(413, 'Node draft exceeds 512 KiB.')
        body.extend(chunk)
    try:
        data = node_drafts.DraftInput.model_validate_json(body)
    except ValidationError:
        raise HTTPException(422, 'Invalid draft nodes. Use unique nonblank codes, UUIDs, valid types and finite coordinates.') from None
    try:
        return await run_in_threadpool(node_drafts.save, str(level_id), str(admin.id), data)
    except database.DatabaseError:
        raise HTTPException(503, 'Draft save could not be confirmed. Reload before retrying.') from None


@router.get('/parking/levels/{level_id}/floor-plan/calibration')
def read_calibration(level_id: UUID, floor_plan_revision: Annotated[int, Query(ge=1)], response: Response):
    response.headers['Cache-Control'] = 'private, no-store'
    try:
        return calibration.read(str(level_id), floor_plan_revision)
    except database.DatabaseError:
        raise HTTPException(503, 'Calibration is unavailable. Check calibration setup.') from None


@router.put('/parking/levels/{level_id}/floor-plan/calibration')
def save_calibration(level_id: UUID, measurement: calibration.CalibrationInput, admin: Administrator, response: Response):
    response.headers['Cache-Control'] = 'private, no-store'
    try:
        return calibration.save(str(level_id), str(admin.id), measurement)
    except database.DatabaseError:
        raise HTTPException(503, 'Calibration save could not be confirmed. Refresh before retrying.') from None


@router.get('/parking/levels/{level_id}/floor-plan/image')
def floor_plan_image(level_id: UUID, expected_revision: Annotated[int | None, Query(ge=1)] = None):
    try:
        return Response(floor_plans.image_bytes(str(level_id), expected_revision), media_type='image/png',
                        headers={'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff'})
    except database.DatabaseError:
        raise HTTPException(503, 'Floor plan image is unavailable.') from None


@router.get('/parking/sessions/overnight', response_model=overnight.OvernightPage)
def overnight_sessions(response: Response, kind: Literal['current', 'past'] = 'current',
                       limit: Annotated[int, Query(ge=1, le=100)] = 10,
                       offset: Annotated[int, Query(ge=0, le=1000000)] = 0,
                       start_date: date | None = None, end_date: date | None = None):
    response.headers['Cache-Control'] = 'private, no-store'
    try:
        return overnight.read(kind, limit, offset, start_date, end_date)
    except ValidationError:
        raise HTTPException(503, 'Overnight parking alerts are unavailable. Please retry.') from None
    except ValueError as error:
        raise HTTPException(422, str(error)) from None
    except (database.DatabaseError, KeyError, TypeError):
        raise HTTPException(503, 'Overnight parking alerts are unavailable. Please retry.') from None


@router.get('/parking/sessions', response_model=AdminSessionPage | AdminSessionSummary)
def parking_sessions(response: Response, limit: Annotated[int, Query(ge=1, le=100)] = 25,
                     offset: Annotated[int, Query(ge=0, le=1000000)] = 0,
                     plate: Annotated[str, Query(max_length=64)] = '', status: SessionStatus | None = None,
                     level_id: UUID | None = None, start_date: date | None = None, end_date: date | None = None,
                     summary: bool = False):
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
        levels = database.get_levels() if not summary or level_id is not None else []
        if level_id is not None and not any(row['id'] == str(level_id) for row in levels):
            raise HTTPException(422, 'Select an existing parking level.')
        if summary:
            counts = {}
            for state in ('allocated', 'occupied', 'completed', 'cancelled'):
                _, count = database.get_admin_parking_sessions(1, 0, plate, state,
                    str(level_id) if level_id else None,
                    start.isoformat() if start else None, end.isoformat() if end else None, head=True)
                if type(count) is not int or count < 0:
                    raise ValueError('Invalid session count')
                counts[state] = count
            return AdminSessionSummary(counts=counts)
        rows, total = database.get_admin_parking_sessions(limit, offset, plate, status,
            str(level_id) if level_id else None, start.isoformat() if start else None, end.isoformat() if end else None)
        return AdminSessionPage(sessions=[session_record(row) for row in rows], total=total, limit=limit, offset=offset,
            levels=sorted(levels, key=lambda level: (level['level_number'], level['id'])))
    except (database.DatabaseError, ValueError, KeyError, TypeError):
        raise HTTPException(503, 'Parking sessions are unavailable. Please retry.') from None


class VehicleCompany(BaseModel):
    id: UUID
    name: str


@router.get('/vehicle-drivers', response_model=vehicle_data.DriverVehiclePage)
def vehicle_drivers(response: Response, admin: Administrator,
                    limit: Annotated[int, Query(ge=1, le=100)] = 25,
                    offset: Annotated[int, Query(ge=0, le=1000000)] = 0,
                    search: Annotated[str, Query(max_length=150)] = '',
                    tenant_id: UUID | None = None, status: vehicle_data.VehicleStatus | None = None):
    response.headers['Cache-Control'] = 'no-store'
    return vehicle_data.driver_page(str(admin.id), limit, offset, vehicle_data.normalized_search(search),
                                    str(tenant_id) if tenant_id else None, status)


@router.get('/vehicle-drivers/{driver_id}', response_model=vehicle_data.DriverVehicleDetails)
def vehicle_driver_details(driver_id: UUID, response: Response, admin: Administrator,
                           limit: Annotated[int, Query(ge=1, le=100)] = 25,
                           offset: Annotated[int, Query(ge=0, le=1000000)] = 0,
                           status: vehicle_data.VehicleStatus | None = None):
    response.headers['Cache-Control'] = 'no-store'
    return vehicle_data.driver_details(str(admin.id), str(driver_id), limit, offset, status)


@router.get('/vehicles/summary', response_model=vehicle_data.VehicleSummary)
def registered_vehicle_summary(response: Response, admin: Administrator, tenant_id: UUID | None = None):
    response.headers['Cache-Control'] = 'no-store'
    return vehicle_data.vehicle_summary(str(admin.id), str(tenant_id) if tenant_id else None)


class AdminVehicle(BaseModel):
    id: UUID
    plate_number: str
    registration_status: Literal['approved', 'pending', 'rejected']
    rejection_reason: str | None = Field(default=None, max_length=500)
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


class VehicleRejectionRequest(VehicleDecisionRequest):
    rejection_reason: str = Field(strict=True, min_length=1, max_length=500)

    @field_validator('rejection_reason', mode='before')
    @classmethod
    def valid_reason(cls, value):
        return normalize_rejection_reason(value)


class VehicleDecisionResponse(BaseModel):
    id: UUID
    plate_number: str
    registration_status: Literal['approved', 'rejected']
    rejection_reason: str | None = Field(default=None, max_length=500)


def decide_vehicle(admin: ApplicationUser, vehicle_id: UUID, decision: str, rejection_reason: str | None = None):
    try:
        result = database.decide_vehicle_registration(str(admin.id), str(vehicle_id), decision, rejection_reason)
        errors = {
            'forbidden': (403, 'Administrator access is required.'),
            'not_found': (404, 'Vehicle not found. Refresh the vehicle list.'),
            'conflict': (409, 'This registration has already been processed. Refresh the vehicle list.'),
            'invalid_decision': (400, 'Invalid vehicle registration decision.'),
            'invalid_reason': (422, 'Enter a rejection reason of 500 characters or fewer.'),
        }
        if result.get('status') in errors:
            code, message = errors[result['status']]
            raise HTTPException(code, message)
        vehicle = VehicleDecisionResponse.model_validate(result)
        if vehicle.id != vehicle_id or vehicle.registration_status != decision or result.get('status') != decision:
            raise ValueError('Unexpected vehicle decision result')
        if vehicle.rejection_reason != rejection_reason:
            raise ValueError('Unexpected rejection reason')
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
                   request: VehicleRejectionRequest):
    response.headers['Cache-Control'] = 'no-store'
    return decide_vehicle(admin, vehicle_id, 'rejected', request.rejection_reason)


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
                rejection_reason=row.get('rejection_reason') if row['registration_status'] == 'rejected' else None,
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


class DriverRegistration(BaseModel):
    id: UUID
    full_name: str | None
    approval_status: Literal["pending", "approved", "rejected"]
    is_active: bool
    requested_tenant_id: UUID | None
    requested_company: RequestedCompany | None
    tenant_id: UUID | None = None
    company: RequestedCompany | None = None


class ApprovalRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    tenant_id: UUID


class DecisionResponse(BaseModel):
    id: UUID
    approval_status: Literal["approved", "rejected"]
    is_active: bool
    tenant_id: UUID | None


@router.get('/registrations/summary', response_model=RegistrationSummary)
def registration_summary(response: Response):
    response.headers['Cache-Control'] = 'no-store'
    try:
        return summarize_registrations(database.get_driver_registration_summary_rows(), database.get_vehicle_companies())
    except (database.DatabaseError, ValueError, KeyError, TypeError):
        raise HTTPException(503, 'Registration summary is unavailable. Please retry.') from None


@router.get("/registrations", response_model=list[DriverRegistration])
def registrations(response: Response, limit: Annotated[int, Query(ge=1, le=100)] = 50,
                  offset: Annotated[int, Query(ge=0, le=1000000)] = 0,
                  status: Literal['pending', 'approved', 'rejected', 'all'] = 'pending',
                  tenant_id: UUID | None = None,
                  sort: Literal['name_asc', 'name_desc'] = 'name_asc'):
    response.headers["Cache-Control"] = "no-store"
    try:
        return database.get_driver_registrations(limit, offset, status, str(tenant_id) if tenant_id else None, sort)
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
