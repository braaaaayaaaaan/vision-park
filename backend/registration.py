"""Two-step signup: prove identity before creating a pending application row."""

import re
from string import punctuation
from uuid import UUID

from fastapi import HTTPException
from httpx import HTTPError
from pydantic import BaseModel, ConfigDict, Field, SecretStr, ValidationError, field_validator
from supabase_auth.errors import AuthApiError, AuthRetryableError
from supabase_auth.types import User

from backend import database
from backend.auth import verify_access_token
from backend.public_auth import get_verified_auth_user, public_auth_client


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
    def password_strength(cls, value):
        password = value.get_secret_value()
        if not 8 <= len(password) <= 128:
            raise ValueError("Password must contain 8 to 128 characters.")
        if not (re.search(r"[A-Z]", password) and re.search(r"[a-z]", password)
                and re.search(r"[0-9]", password) and any(c in punctuation for c in password)):
            raise ValueError("Include an uppercase letter, lowercase letter, number and special character.")
        return value


SIGNUP_REPLY = {
    "status": "check_email_or_sign_in",
    "message": "If eligible, open your confirmation email to continue. Your saved driver details will be submitted for approval. Existing users can sign in.",
}

# Fixed driver-only callback; never accept an arbitrary redirect from the client.
DRIVER_EMAIL_REDIRECT = "visionpark://auth/confirm"


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


def restore_registration(user: User):
    """Editable onboarding data can request membership, never grant it."""
    try:
        if database.get_auth_profile(user.id) is not None:
            return {"status": "profile_available"}
        onboarding = user.user_metadata.get("visionpark_registration")
        if not isinstance(onboarding, dict):
            return {"status": "completion_required"}
        try:
            request = RegistrationProfile.model_validate({
                "full_name": onboarding.get("full_name"),
                "tenant_id": onboarding.get("requested_tenant_id"),
            })
        except ValidationError:
            return {"status": "completion_required"}
        try:
            return complete_registration(UUID(user.id), request)
        except HTTPException as error:
            if error.status_code == 400:  # Requested company is no longer available.
                return {"status": "completion_required"}
            raise
    except database.DatabaseError:
        raise HTTPException(503, "Registration service is unavailable. Please retry.") from None


def register_driver(request: RegistrationRequest):
    try:
        check_company(request.tenant_id)
        with public_auth_client() as client:
            result = client.sign_up({
                "email": request.email,
                "password": request.password.get_secret_value(),
                "options": {"email_redirect_to": DRIVER_EMAIL_REDIRECT, "data": {"visionpark_registration": {
                    "full_name": request.full_name,
                    "requested_tenant_id": str(request.tenant_id),
                }}},
            })
        # Without a session, signup can return an obfuscated existing-user UUID.
        # Never write a profile based on that unproven UUID or on email lookup.
        if result.session:
            user_id = verify_access_token(result.session.access_token)
            get_verified_auth_user(result.session.access_token, user_id)
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
