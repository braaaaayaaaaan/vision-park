"""Isolated, non-persistent Auth clients using only a configured public key."""

import os
import atexit
import logging
from threading import Lock
from contextlib import contextmanager
from time import perf_counter
from uuid import UUID

import httpx
import jwt
from fastapi import HTTPException
from pydantic import ValidationError
from supabase_auth import SyncGoTrueClient
from supabase_auth.types import User

from backend.auth import auth_issuer, unauthorized, auth_diagnostic


_transport = None
_transport_lock = Lock()


def verification_transport():
    """Pool stateless GET /user connections, never sessions or authorization."""
    global _transport
    with _transport_lock:
        if _transport is None:
            _transport = httpx.Client(timeout=15, follow_redirects=False,
                                      limits=httpx.Limits(max_connections=40, max_keepalive_connections=20))
        return _transport


def close_verification_transport():
    global _transport
    with _transport_lock:
        if _transport is not None:
            _transport.close()
            _transport = None


atexit.register(close_verification_transport)


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
        request_started_at = perf_counter()
        auth_diagnostic("supabase_user_request", "started")
        response = verification_transport().get(auth_issuer() + '/user',
            headers={'apikey': public_key(), 'Authorization': f'Bearer {token}'})
        if response.status_code in (401, 403):
            raise unauthorized()
        if not response.is_success:
            logging.getLogger('uvicorn.error').warning(
                'auth_user_request_failed category=upstream_rejected status=%s', response.status_code)
            raise HTTPException(503, 'Authentication service is unavailable.')
        user = User.model_validate(response.json())
        auth_diagnostic("supabase_user_response", "received", upstream_status=200, started_at=request_started_at)
    except (httpx.HTTPError, ValidationError, ValueError) as error:
        upstream_status = None
        if isinstance(error, (ValidationError, ValueError)):
            category, exception_class = "invalid_upstream_response", "ValidationError"
        elif isinstance(error, httpx.TimeoutException):
            category, exception_class = "timeout", "TimeoutException"
        else:
            category, exception_class = "transport_unavailable", "HTTPError"
        auth_diagnostic("supabase_user_request", category, exception_class, upstream_status, started_at=request_started_at)
        logging.getLogger('uvicorn.error').warning('auth_user_request_failed category=%s', category)
        raise HTTPException(503, "Authentication service is unavailable.") from None
    except HTTPException:
        auth_diagnostic("supabase_user_setup", "configuration_rejected", "HTTPException", started_at=started_at)
        raise
    if user.id != str(expected_user_id):
        auth_diagnostic("supabase_user_response", "identity_mismatch", started_at=started_at)
        raise unauthorized()
    if user.is_anonymous or not user.email or not user.email.strip() or not user.email_confirmed_at:
        auth_diagnostic("supabase_user_response", "confirmed_email_required", started_at=started_at)
        raise HTTPException(403, "Confirm your email before continuing.")
    auth_diagnostic("supabase_user_verification", "succeeded", started_at=started_at)
    return user
