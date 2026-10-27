"""Run locally with python -m backend.auth_smoke; never pass credentials as args."""

import getpass
import logging
import sys

import httpx

from backend.public_auth import public_auth_client, public_key


def main() -> int:
    # Keep third-party debug logging from exposing request headers/bodies.
    logging.disable(logging.CRITICAL)
    try:
        public_key()  # Fail before prompting if no public key is configured.
        if not sys.stdin.isatty():
            print("Run this smoke test in an interactive local terminal.")
            return 1
        email = getpass.getpass("Approved administrator email (hidden): ")
        password = getpass.getpass("Password (hidden): ")
        with public_auth_client() as client:
            result = client.sign_in_with_password({"email": email, "password": password})
            password = None
            if not result.session or not result.user:
                raise ValueError("No session")
            # Fixed loopback destination; no redirects that could leak the token.
            response = httpx.get("http://127.0.0.1:8000/auth/me", timeout=15,
                                 follow_redirects=False,
                                 headers={"Authorization": "Bearer " + result.session.access_token})
            response.raise_for_status()
            profile = response.json()
            if (profile.get("id") != result.user.id or profile.get("role") != "admin"
                    or profile.get("approval_status") != "approved" or profile.get("is_active") is not True):
                raise ValueError("Unexpected profile")
        print("PASS: /auth/me matches the signed-in approved, active administrator.")
        return 0
    except Exception:
        print("Smoke test not completed. Check the public key configuration, local API, credentials and administrator status. No credentials or tokens were printed.")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
