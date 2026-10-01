import os

import jwt
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token
from jwt import PyJWKClient

APPLE_KEYS = PyJWKClient("https://appleid.apple.com/auth/keys")


class OAuthError(Exception):
    def __init__(self, message: str, status: int = 401):
        super().__init__(message)
        self.message = message
        self.status = status


def _ids(name: str, fallback: str = "") -> list[str]:
    raw = os.environ.get(name, fallback)
    return [part.strip() for part in raw.split(",") if part.strip()]


def verify_google_id_token(token: str) -> dict:
    audiences = _ids("GOOGLE_CLIENT_IDS")
    if not audiences:
        raise OAuthError("GOOGLE_CLIENT_IDS is not set on the server", 500)
    try:
        payload = id_token.verify_oauth2_token(token, google_requests.Request(), audience=None)
    except Exception as exc:
        raise OAuthError("Invalid Google token") from exc
    if payload.get("aud") not in audiences:
        raise OAuthError("Invalid Google token")
    email = (payload.get("email") or "").lower()
    subject = payload.get("sub")
    if not subject or not email:
        raise OAuthError("Invalid Google token")
    name = payload.get("name") or email.split("@")[0]
    return {"google_id": subject, "email": email, "name": name}


def verify_apple_id_token(token: str) -> dict:
    audiences = _ids("APPLE_CLIENT_IDS", "lk.alphabet.takings")
    try:
        signing_key = APPLE_KEYS.get_signing_key_from_jwt(token)
        payload = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            audience=audiences,
            issuer="https://appleid.apple.com",
        )
    except Exception as exc:
        raise OAuthError("Invalid Apple token") from exc
    subject = payload.get("sub")
    if not subject:
        raise OAuthError("Invalid Apple token")
    email = (payload.get("email") or f"{subject}@privaterelay.appleid.com").lower()
    name = email.split("@")[0] if payload.get("email") else "Apple User"
    return {"apple_id": subject, "email": email, "name": name}
