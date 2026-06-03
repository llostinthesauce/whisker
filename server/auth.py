import secrets
from typing import Optional


class AuthError(Exception):
    """Raised when an API request does not include the configured bearer token."""


def require_bearer(authorization: Optional[str], expected_token: str) -> None:
    header = (authorization or "").strip()
    prefix = "Bearer "
    if not header.startswith(prefix):
        raise AuthError("missing bearer token")

    supplied = header[len(prefix) :].strip()
    if not supplied or not secrets.compare_digest(supplied, expected_token):
        raise AuthError("invalid bearer token")
