from dataclasses import dataclass

import jwt
from fastapi import HTTPException, status
from jwt import PyJWKClient

from app.core.config import settings

APPLE_ISSUER = "https://appleid.apple.com"
APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"

_jwk_client = PyJWKClient(APPLE_JWKS_URL)


@dataclass
class AppleProfile:
    sub: str
    # Apple gives a private-relay address if the user chose "Hide My Email"; treat
    # it like any other email for account purposes — it's still a valid deliverable
    # inbox that forwards to the user.
    email: str | None
    email_verified: bool


def verify_apple_identity_token(identity_token: str) -> AppleProfile:
    """
    Verifies Apple's identity token server-side against Apple's published JWKS.
    Note: Apple omits `email` on every login after the first — the caller must have
    persisted it from the first successful sign-in (see User.apple_sub linking).
    """
    if not settings.APPLE_CLIENT_ID:
        raise HTTPException(status_code=status.HTTP_501_NOT_IMPLEMENTED, detail="Sign in with Apple is not configured.")

    try:
        signing_key = _jwk_client.get_signing_key_from_jwt(identity_token)
        payload = jwt.decode(
            identity_token,
            signing_key.key,
            algorithms=["RS256"],
            audience=settings.APPLE_CLIENT_ID,
            issuer=APPLE_ISSUER,
        )
    except jwt.PyJWTError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid Apple identity token.") from exc

    email_verified_claim = payload.get("email_verified")
    email_verified = email_verified_claim in (True, "true")

    return AppleProfile(
        sub=payload["sub"],
        email=payload.get("email"),
        email_verified=email_verified,
    )
