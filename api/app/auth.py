import hashlib
import os
import secrets
from datetime import datetime, timedelta, timezone

import jwt

ALGORITHM = "HS256"


def secret() -> str:
    return os.environ.get("JWT_SECRET", "dev-only-change-me")


def hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), 200_000).hex()
    return f"{salt}${digest}"


def verify_password(password: str, stored: str) -> bool:
    try:
        salt, digest = stored.split("$", 1)
    except ValueError:
        return False
    check = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), 200_000).hex()
    return secrets.compare_digest(check, digest)


def make_token(user_id: str) -> str:
    payload = {
        "sub": user_id,
        "exp": datetime.now(timezone.utc) + timedelta(days=30),
    }
    return jwt.encode(payload, secret(), algorithm=ALGORITHM)


def decode_token(token: str) -> str:
    payload = jwt.decode(token, secret(), algorithms=[ALGORITHM])
    return str(payload["sub"])
