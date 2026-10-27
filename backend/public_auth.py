"""Isolated, non-persistent Auth clients using only a configured public key."""

import os
from contextlib import contextmanager
from time import perf_counter
from uuid import UUID

import httpx
import jwt
from fastapi import HTTPException
from pydantic import ValidationError
from supabase_auth import SyncGoTrueClient
from supabase_auth.errors import AuthApiError, AuthRetryableError
from supabase_auth.types import User

from backend.auth import auth_issuer, unauthorized, auth_diagnostic


def public_key() -> str:
    key = os.getenv("SUPABASE_PUBLISHABLE_KEY", "").strip() or os.getenv("SUPABASE_ANON_KEY", "").strip()
    valid = key.startswith("sb_publishable_")
    if not valid:
        try:
            # Classification only, never identity verification. Supabase validates
            # this configured API key. Reject accidental service-role credentials.
            valid = jwt.decode(key, options={"verify_signature": False}).get("role") == "anon"
        except jwt.PyJWTError:
            valid = False
    if not valid:
        raise HTTPException(503, "Configure SUPABASE_PUBLISHABLE_KEY or SUPABASE_ANON_KEY with a public key.")
    return key


@contextmanager
def public_auth_client():
    key = public_key()
    with httpx.Client(timeout=15, follow_redirects=False) as transport:
        client = SyncGoTrueClient(url=auth_issuer(), headers={"apikey": key},
                                  auto_refresh_token=False, persist_session=False,
                                  http_client=transport)
        try:
            yield client
        finally:
            client.close()


def get_verified_auth_user(token: str, expected_user_id: UUID) -> User:
    """Read confirmation from Auth, never from editable metadata/JWT hints."""
    started_at = perf_counter()
    request_started_at = started_at
    auth_diagnostic("supabase_user_verification", "reached")
    try:
        with public_auth_client() as client:
            request_started_at = perf_counter()
            auth_diagnostic("supabase_user_request", "started")
            response = client.get_user(jwt=token)
            auth_diagnostic("supabase_user_response", "received", upstream_status=200, started_at=request_started_at)
    except AuthApiError as error:
        auth_diagnostic("supabase_user_request", "upstream_rejected", "AuthApiError", error.status, started_at=request_started_at)
        if error.status in (401, 403):
            raise unauthorized() from None
        raise HTTPException(503, "Authentication service is unavailable.") from None
    except (AuthRetryableError, httpx.HTTPError, ValidationError) as error:
        upstream_status = None
        if isinstance(error, ValidationError):
            category, exception_class = "invalid_upstream_response", "ValidationError"
        elif isinstance(error, AuthRetryableError):
            category, exception_class = "upstream_retryable", "AuthRetryableError"
            upstream_status = error.status
        elif isinstance(error, httpx.TimeoutException):
            category, exception_class = "timeout", "TimeoutException"
        else:
            category, exception_class = "transport_unavailable", "HTTPError"
        auth_diagnostic("supabase_user_request", category, exception_class, upstream_status, started_at=request_started_at)
        raise HTTPException(503, "Authentication service is unavailable.") from None
    except HTTPException:
        auth_diagnostic("supabase_user_setup", "configuration_rejected", "HTTPException", started_at=started_at)
        raise
    if response is None or response.user is None:
        auth_diagnostic("supabase_user_response", "missing_user", started_at=started_at)
        raise unauthorized()
    user = response.user
    if user.id != str(expected_user_id):
        auth_diagnostic("supabase_user_response", "identity_mismatch", started_at=started_at)
        raise unauthorized()
    if user.is_anonymous or not user.email or not user.email.strip() or not user.email_confirmed_at:
        auth_diagnostic("supabase_user_response", "confirmed_email_required", started_at=started_at)
        raise HTTPException(403, "Confirm your email before continuing.")
    auth_diagnostic("supabase_user_verification", "succeeded", started_at=started_at)
    return user
