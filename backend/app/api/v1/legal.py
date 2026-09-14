from pathlib import Path

from fastapi import APIRouter, HTTPException, status
from fastapi.responses import FileResponse

router = APIRouter(prefix="/legal", tags=["legal"])

# Checked into git under app/static (unlike PDF_STORAGE_DIR, which holds
# user-uploaded files and is gitignored) — these ship inside the Docker image
# via the existing `COPY app ./app` step, no Dockerfile change needed.
# Deliberately no auth dependency on either route below: a prospective user
# must be able to read these before they have an account at all (the
# registration screen's acceptance checkbox links here).
_LEGAL_DIR = Path(__file__).resolve().parent.parent.parent / "static" / "legal"


def _serve(filename: str, download_name: str) -> FileResponse:
    path = _LEGAL_DIR / filename
    if not path.exists():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"{download_name} is not available yet.")
    return FileResponse(path, media_type="application/pdf", filename=download_name)


@router.get("/terms")
async def get_terms_of_service() -> FileResponse:
    return _serve("terms_of_service.pdf", "Terms of Service.pdf")


@router.get("/privacy")
async def get_privacy_policy() -> FileResponse:
    return _serve("privacy_policy.pdf", "Privacy Policy.pdf")
