"""Isolated, non-persistent Auth clients using only a configured public key."""

import os
from contextlib import contextmanager
from uuid import UUID

import httpx
import jwt
from fastapi import HTTPException
from pydantic import ValidationError
from supabase_auth import SyncGoTrueClient
from supabase_auth.errors import AuthApiError, AuthRetryableError
from supabase_auth.types import User

from backend.auth import auth_issuer, unauthorized


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
    try:
        with public_auth_client() as client:
            response = client.get_user(jwt=token)
    except AuthApiError as error:
        if error.status in (401, 403):
            raise unauthorized() from None
        raise HTTPException(503, "Authentication service is unavailable.") from None
    except (AuthRetryableError, httpx.HTTPError, ValidationError):
        raise HTTPException(503, "Authentication service is unavailable.") from None
    if response is None or response.user is None:
        raise unauthorized()
    user = response.user
    if user.id != str(expected_user_id):
        raise unauthorized()
    if user.is_anonymous or not user.email or not user.email.strip() or not user.email_confirmed_at:
        raise HTTPException(403, "Confirm your email before continuing.")
    return user
