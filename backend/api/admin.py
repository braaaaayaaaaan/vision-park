"""Administrator review of driver applications; no account-role management."""

from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import BaseModel, ConfigDict, ValidationError

from backend import database
from backend.auth import ApplicationUser, require_administrator

router = APIRouter(dependencies=[Depends(require_administrator)])
Administrator = Annotated[ApplicationUser, Depends(require_administrator)]


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
