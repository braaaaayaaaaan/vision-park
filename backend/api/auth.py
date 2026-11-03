"""Registration and read-only access to the caller's application profile."""

from typing import Annotated

from uuid import UUID

from fastapi import APIRouter, Depends, Response, HTTPException
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.routing import APIRoute
from pydantic import BaseModel
from supabase_auth.types import User

from backend.auth import (ApplicationUser, require_application_user, authenticated_user_id,
                          authenticated_auth_user, authenticated_claims, is_mfa_verified)
from backend import database
from backend.registration import RegistrationRequest, RegistrationProfile, register_driver, complete_registration, restore_registration


class SafeAuthRoute(APIRoute):
    def get_route_handler(self):
        handler = super().get_route_handler()

        async def safe_handler(request):
            try:
                response = await handler(request)
            except RequestValidationError:
                # FastAPI's default errors echo input values, including passwords
                # and arbitrary extra fields. Do not expose any submitted values.
                response = JSONResponse(status_code=422, content={"detail": "Invalid registration input. Check required fields and formats."})
            response.headers["Cache-Control"] = "no-store"
            return response
        return safe_handler


router = APIRouter(route_class=SafeAuthRoute)


class Company(BaseModel):
    id: UUID
    name: str


@router.get("/companies", response_model=list[Company])
def companies():
    try:
        return database.get_registration_companies()
    except database.DatabaseError:
        raise HTTPException(503, "Company service is unavailable.") from None


@router.post("/register", status_code=202)
def register(request: RegistrationRequest):
    return register_driver(request)


@router.post("/register/complete")
def complete(request: RegistrationProfile, user_id: Annotated[UUID, Depends(authenticated_user_id)]):
    return complete_registration(user_id, request)


@router.post("/register/restore")
def restore(user: Annotated[User, Depends(authenticated_auth_user)]):
    return restore_registration(user)


class AuthenticationProfile(ApplicationUser):
    aal: str
    mfa_verified: bool
    totp_factors: list[dict]


@router.get("/me", response_model=AuthenticationProfile)
def me(response: Response, user: Annotated[ApplicationUser, Depends(require_application_user)],
       claims: Annotated[dict, Depends(authenticated_claims)],
       auth_user: Annotated[User, Depends(authenticated_auth_user)]):
    response.headers["Cache-Control"] = "no-store"
    return AuthenticationProfile(**user.model_dump(),
        aal="aal2" if claims.get("aal") == "aal2" else "aal1",
        mfa_verified=is_mfa_verified(claims, auth_user),
        totp_factors=[{"id": factor.id, "status": factor.status,
                       "friendly_name": factor.friendly_name}
                      for factor in (auth_user.factors or []) if factor.factor_type == "totp"])
