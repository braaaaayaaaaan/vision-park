"""Two-step signup: prove identity before creating a pending application row."""

import re
from uuid import UUID

from fastapi import HTTPException
from httpx import HTTPError
from pydantic import BaseModel, ConfigDict, Field, SecretStr, field_validator
from supabase_auth.errors import AuthApiError, AuthRetryableError

from backend import database
from backend.auth import verify_access_token
from backend.public_auth import public_auth_client


class RegistrationProfile(BaseModel):
    model_config = ConfigDict(extra="forbid")
    full_name: str = Field(min_length=1, max_length=150)
    tenant_id: UUID

    @field_validator("full_name")
    @classmethod
    def clean_name(cls, value):
        value = value.strip()
        if not value or any(ord(c) < 32 for c in value):
            raise ValueError("Enter a valid full name.")
        return value


class RegistrationRequest(RegistrationProfile):
    email: str = Field(max_length=254)
    password: SecretStr

    @field_validator("email")
    @classmethod
    def clean_email(cls, value):
        value = value.strip()
        # Conservative email syntax; Supabase remains the delivery validator.
        if not re.fullmatch(r"[^\s@<>]+@[^\s@<>.]+(?:\.[^\s@<>.]+)+", value):
            raise ValueError("Enter a valid email address.")
        return value

    @field_validator("password")
    @classmethod
    def password_length(cls, value):
        if not 12 <= len(value.get_secret_value()) <= 128:
            raise ValueError("Password must contain 12 to 128 characters.")
        return value


SIGNUP_REPLY = {
    "status": "check_email_or_sign_in",
    "message": "If eligible, confirm your email, then sign in and complete registration. Existing users should sign in.",
}


def check_company(tenant_id: UUID):
    tenant = database.get_tenant(str(tenant_id))
    if not tenant or tenant.get("is_active") is not True:
        raise HTTPException(400, "Select an available company.")


def complete_registration(user_id: UUID, request: RegistrationProfile):
    try:
        # Repeated requests never edit, downgrade or reactivate existing users.
        if database.get_auth_profile(str(user_id)) is not None:
            return {"status": "profile_available"}
        check_company(request.tenant_id)
        database.insert_pending_driver(str(user_id), request.full_name, str(request.tenant_id))
        if database.get_auth_profile(str(user_id)) is None:
            raise database.DatabaseError("Profile not visible after insert.")
        return {"status": "profile_available"}
    except database.DatabaseError:
        raise HTTPException(503, "Registration is incomplete. Sign in and retry registration completion.") from None


def register_driver(request: RegistrationRequest):
    try:
        check_company(request.tenant_id)
        with public_auth_client() as client:
            result = client.sign_up({"email": request.email, "password": request.password.get_secret_value()})
        # Without a session, signup can return an obfuscated existing-user UUID.
        # Never write a profile based on that unproven UUID or on email lookup.
        if result.session:
            user_id = verify_access_token(result.session.access_token)
            complete_registration(user_id, request)
        return SIGNUP_REPLY.copy()
    except AuthApiError as error:
        if error.code in {"user_already_exists", "email_exists"}:
            return SIGNUP_REPLY.copy()
        if error.status == 429:
            raise HTTPException(429, "Too many attempts. Try again later.") from None
        if error.status >= 500:
            raise HTTPException(503, "Registration is unavailable. If signup completed, sign in and retry completion.") from None
        raise HTTPException(400, "Unable to register. Check your input and the configured password policy.") from None
    except (AuthRetryableError, HTTPError, database.DatabaseError):
        raise HTTPException(503, "Registration is unavailable. If signup completed, sign in and retry completion.") from None
