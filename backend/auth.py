"""Supabase identity verification and separate application permissions."""

import os
from functools import lru_cache
from typing import Annotated
from urllib.parse import urlsplit
from uuid import UUID

import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel
from supabase_auth.types import User

from backend import database

bearer = HTTPBearer(auto_error=False)


def unauthorized() -> HTTPException:
    return HTTPException(401, "Invalid or missing access token.",
                         headers={"WWW-Authenticate": "Bearer"})


def auth_issuer() -> str:
    url = os.getenv("SUPABASE_URL", "").strip().rstrip("/").removesuffix("/rest/v1")
    parsed = urlsplit(url)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username
            or parsed.password or parsed.query or parsed.fragment or parsed.path):
        raise HTTPException(503, "Configure a valid SUPABASE_URL on the backend.")
    return url + "/auth/v1"


@lru_cache(maxsize=4)
def jwks_client(issuer: str) -> jwt.PyJWKClient:
    # Refresh the set every five minutes and on unknown kid (with SDK cooldown).
    # Do not cache individual keys beyond the lifetime of the set.
    return jwt.PyJWKClient(issuer + "/.well-known/jwks.json", lifespan=300,
                           timeout=10, cache_keys=False)


def verify_access_token(token: str) -> UUID:
    issuer = auth_issuer()
    try:
        header = jwt.get_unverified_header(token)
        # ES256 was confirmed at the configured project's public JWKS endpoint.
        # Token headers cannot choose algorithms or remote key locations.
        if header.get("alg") != "ES256" or not isinstance(header.get("kid"), str) or not header["kid"]:
            raise unauthorized()
        key = jwks_client(issuer).get_signing_key_from_jwt(token)
        if key.algorithm_name != "ES256":
            raise unauthorized()
        claims = jwt.decode(token, key.key, algorithms=["ES256"],
                            issuer=issuer, audience="authenticated",
                            options={"require": ["exp", "iat", "iss", "aud", "sub"],
                                     "strict_aud": True})
        return UUID(claims["sub"])
    except jwt.PyJWKClientConnectionError:
        raise HTTPException(503, "Authentication service is unavailable.") from None
    except (jwt.PyJWTError, ValueError, TypeError, KeyError):
        raise unauthorized() from None


def authenticated_auth_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> User:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise unauthorized()
    user_id = verify_access_token(credentials.credentials)
    # Import here because the public client shares auth_issuer with this module.
    from backend.public_auth import get_verified_auth_user
    return get_verified_auth_user(credentials.credentials, user_id)


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
            if tenant and tenant["id"] == str(user.tenant_id):
                user.company_name = tenant["name"]
        return user
    except database.DatabaseError:
        raise HTTPException(503, "Application profile service is unavailable.") from None


def require_approved_active_user(
    user: Annotated[ApplicationUser, Depends(require_application_user)],
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
        tenant = database.get_tenant(str(user.tenant_id))
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
