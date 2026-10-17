"""Isolated, non-persistent Auth clients using only a configured public key."""

import os
from contextlib import contextmanager

import httpx
import jwt
from fastapi import HTTPException
from supabase_auth import SyncGoTrueClient

from backend.auth import auth_issuer


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
