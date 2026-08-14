from dataclasses import dataclass

from fastapi import HTTPException, status
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token

from app.core.config import settings


@dataclass
class GoogleProfile:
    sub: str
    email: str
    email_verified: bool
    name: str | None


_google_request = google_requests.Request()

# Any of these client IDs (web/Android/iOS) may appear as the token's audience,
# since each platform mints tokens against its own OAuth client registration.
def _accepted_client_ids() -> list[str]:
    return [
        cid
        for cid in (settings.GOOGLE_CLIENT_ID, settings.GOOGLE_CLIENT_ID_ANDROID, settings.GOOGLE_CLIENT_ID_IOS)
        if cid
    ]


def verify_google_id_token(token: str) -> GoogleProfile:
    """
    Verifies the ID token against Google's public keys server-side — never trust a
    client-asserted email. Raises 401 on any verification failure.
    """
    accepted = _accepted_client_ids()
    if not accepted:
        raise HTTPException(status_code=status.HTTP_501_NOT_IMPLEMENTED, detail="Google sign-in is not configured.")

    try:
        payload = id_token.verify_oauth2_token(token, _google_request)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid Google token.") from exc

    if payload.get("aud") not in accepted:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token was not issued for this app.")

    if payload.get("iss") not in ("accounts.google.com", "https://accounts.google.com"):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token issuer.")

    return GoogleProfile(
        sub=payload["sub"],
        email=payload["email"],
        email_verified=bool(payload.get("email_verified", False)),
        name=payload.get("name"),
    )
