"""Supabase identity verification and separate application permissions."""

import os
import logging
from datetime import datetime, timezone
from functools import lru_cache
from time import perf_counter
from typing import Annotated
from urllib.parse import urlsplit
from uuid import UUID

import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, PrivateAttr
from supabase_auth.types import User

from backend import database

bearer = HTTPBearer(auto_error=False)


def auth_diagnostic(stage: str, category: str, exception_class: str = "none", upstream_status=None, *, started_at=None):
    """Local opt-in only. Callers pass fixed labels, never exception messages."""
    if (os.getenv("VISIONPARK_ENV", "").strip().lower() != "development"
            or os.getenv("AUTH_DIAGNOSTICS", "").strip().lower() != "true"):
        return
    status = upstream_status if type(upstream_status) is int and 100 <= upstream_status <= 599 else "unknown"
    elapsed_ms = round(max(0, (perf_counter() - started_at) * 1000), 2) if started_at is not None else "unknown"
    # Use Uvicorn's configured console logger; no global logging configuration.
    logging.getLogger("uvicorn.error").info(
        "auth_diagnostic stage=%s category=%s exception=%s upstream_status=%s elapsed_ms=%s at=%s",
        stage, category, exception_class, status, elapsed_ms, datetime.now(timezone.utc).isoformat())


def jwt_rejection_diagnostic(stage: str, error: Exception, started_at):
    # Log only a known base exception class, including for custom subclasses.
    categories = (
        (jwt.ExpiredSignatureError, "expired_token"),
        (jwt.ImmatureSignatureError, "token_not_yet_valid"),
        (jwt.InvalidSignatureError, "invalid_signature"),
        (jwt.InvalidIssuerError, "issuer_mismatch"),
        (jwt.InvalidAudienceError, "audience_mismatch"),
        (jwt.InvalidAlgorithmError, "algorithm_mismatch"),
        (jwt.MissingRequiredClaimError, "missing_required_claim"),
        (jwt.PyJWKClientError, "key_lookup_failed"),
        (jwt.DecodeError, "malformed_token"),
        (jwt.PyJWTError, "other_jwt_validation_failure"),
        (ValueError, "invalid_token_structure"),
        (TypeError, "invalid_token_structure"),
        (KeyError, "invalid_token_structure"),
    )
    for error_type, category in categories:
        if isinstance(error, error_type):
            auth_diagnostic(stage, category, error_type.__name__, started_at=started_at)
            return


def unauthorized() -> HTTPException:
    return HTTPException(401, "Invalid or missing access token.",
                         headers={"WWW-Authenticate": "Bearer"})


def auth_issuer() -> str:
    url = os.getenv("SUPABASE_URL", "").strip().rstrip("/").removesuffix("/rest/v1")
    parsed = urlsplit(url)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username
            or parsed.password or parsed.query or parsed.fragment or parsed.path):
        auth_diagnostic("jwt_configuration", "invalid_supabase_url")
        raise HTTPException(503, "Configure a valid SUPABASE_URL on the backend.")
    return url + "/auth/v1"


@lru_cache(maxsize=4)
def jwks_client(issuer: str) -> jwt.PyJWKClient:
    # Refresh the set every five minutes and on unknown kid (with SDK cooldown).
    # Do not cache individual keys beyond the lifetime of the set.
    return jwt.PyJWKClient(issuer + "/.well-known/jwks.json", lifespan=300,
                           timeout=10, cache_keys=False)


def verify_access_claims(token: str) -> dict:
    started_at = perf_counter()
    issuer = auth_issuer()
    stage = "jwt_header"
    stage_started_at = started_at
    try:
        header = jwt.get_unverified_header(token)
        # ES256 was confirmed at the configured project's public JWKS endpoint.
        # Token headers cannot choose algorithms or remote key locations.
        if header.get("alg") != "ES256" or not isinstance(header.get("kid"), str) or not header["kid"]:
            auth_diagnostic(stage, "algorithm_mismatch" if header.get("alg") != "ES256" else "missing_or_invalid_kid", started_at=stage_started_at)
            raise unauthorized()
        stage = "jwt_key_lookup"
        stage_started_at = perf_counter()
        key = jwks_client(issuer).get_signing_key_from_jwt(token)
        if key.algorithm_name != "ES256":
            auth_diagnostic(stage, "key_algorithm_mismatch", started_at=stage_started_at)
            raise unauthorized()
        auth_diagnostic(stage, "succeeded", started_at=stage_started_at)
        stage = "jwt_signature_and_claims"
        stage_started_at = perf_counter()
        claims = jwt.decode(token, key.key, algorithms=["ES256"],
                            issuer=issuer, audience="authenticated",
                            options={"require": ["exp", "iat", "iss", "aud", "sub"],
                                     "strict_aud": True})
        stage = "jwt_subject"
        stage_started_at = perf_counter()
        UUID(claims["sub"])
        auth_diagnostic("jwt_validation", "succeeded", started_at=started_at)
        return claims
    except jwt.PyJWKClientConnectionError:
        auth_diagnostic(stage, "key_service_unavailable", "PyJWKClientConnectionError", started_at=stage_started_at)
        raise HTTPException(503, "Authentication service is unavailable.") from None
    except (jwt.PyJWTError, ValueError, TypeError, KeyError) as error:
        jwt_rejection_diagnostic(stage, error, stage_started_at)
        raise unauthorized() from None


def verify_access_token(token: str) -> UUID:
    """Bootstrap/registration compatibility; never interprets a decoded hint."""
    return UUID(verify_access_claims(token)["sub"])


def authenticated_claims(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> dict:
    if credentials is None or credentials.scheme.lower() != "bearer":
        auth_diagnostic("bearer", "missing_or_invalid_credentials")
        raise unauthorized()
    return verify_access_claims(credentials.credentials)


def authenticated_auth_user(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(bearer)],
    claims: Annotated[dict, Depends(authenticated_claims)],
) -> User:
    # Import here because the public client shares auth_issuer with this module.
    from backend.public_auth import get_verified_auth_user
    return get_verified_auth_user(credentials.credentials, UUID(claims["sub"]))


def has_verified_totp(user: User) -> bool:
    return any(factor.factor_type == "totp" and factor.status == "verified"
               for factor in (user.factors or []))


def is_mfa_verified(claims: dict, user: User) -> bool:
    # Both sources are verified server-side. A stored UI flag or editable user
    # metadata is never evidence of MFA. Removing the last TOTP closes access.
    return claims.get("aal") == "aal2" and has_verified_totp(user)


def require_mfa(
    claims: Annotated[dict, Depends(authenticated_claims)],
    user: Annotated[User, Depends(authenticated_auth_user)],
) -> None:
    if not is_mfa_verified(claims, user):
        raise HTTPException(403, detail={"code": "mfa_required",
                            "message": "Complete authenticator verification to continue."},
                            headers={"Cache-Control": "private, no-store",
                                     "X-VisionPark-Auth": "mfa-required"})


def authenticated_user_id(
    user: Annotated[User, Depends(authenticated_auth_user)],
) -> UUID:
    return UUID(user.id)


class ApplicationUser(BaseModel):
    id: UUID
    full_name: str | None
    role: str
    approval_status: str
    is_active: bool
    tenant_id: UUID | None
    company_name: str | None = None
    # Request-local only; never serialized or reused across requests.
    _tenant: dict | None = PrivateAttr(default=None)
    _tenant_loaded: bool = PrivateAttr(default=False)


def require_application_user(
    user_id: Annotated[UUID, Depends(authenticated_user_id)],
) -> ApplicationUser:
    try:
        row = database.get_auth_profile(str(user_id))
        if row is None:
            raise HTTPException(403, "Application profile is unavailable.")
        user = ApplicationUser.model_validate(row)
        if user.id != user_id:
            raise HTTPException(403, "Application profile is unavailable.")
        user.company_name = None
        if user.tenant_id:
            tenant = database.get_tenant(str(user.tenant_id))
            user._tenant, user._tenant_loaded = tenant, True
            if tenant and tenant["id"] == str(user.tenant_id):
                user.company_name = tenant["name"]
        return user
    except database.DatabaseError:
        raise HTTPException(503, "Application profile service is unavailable.") from None


def require_approved_active_user(
    user: Annotated[ApplicationUser, Depends(require_application_user)],
    _mfa: Annotated[None, Depends(require_mfa)],
) -> ApplicationUser:
    if user.approval_status != "approved" or not user.is_active:
        raise HTTPException(403, "An approved, active account is required.")
    return user


def require_driver(
    user: Annotated[ApplicationUser, Depends(require_approved_active_user)],
) -> ApplicationUser:
    if user.role != "driver" or user.tenant_id is None:
        raise HTTPException(403, "A driver with a verified active company is required.")
    try:
        tenant = user._tenant if user._tenant_loaded else database.get_tenant(str(user.tenant_id))
    except database.DatabaseError:
        raise HTTPException(503, "Company service is unavailable.") from None
    if not tenant or tenant["id"] != str(user.tenant_id) or tenant["is_active"] is not True:
        raise HTTPException(403, "A driver with a verified active company is required.")
    return user


def require_administrator(
    user: Annotated[ApplicationUser, Depends(require_approved_active_user)],
) -> ApplicationUser:
    if user.role != "admin":
        raise HTTPException(403, "Administrator access is required.")
    return user
