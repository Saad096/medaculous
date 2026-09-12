import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.router import api_router
from app.core.config import settings

logging.basicConfig(level=logging.INFO if settings.is_prod else logging.DEBUG)

# Bumped by hand alongside every backend change meant to ship — not read from
# git, so it works the same whether the code got there via `git pull` or a
# plain file copy. Purely a deploy-verification signal: after pushing a
# change and rebuilding on a VM, `curl http://<vm>:<port>/health` showing
# this exact string (not a previous one) confirms the fresh code is what's
# actually running, without needing shell/git access on the VM itself.
_BUILD_TAG = "2026-09-13.1-pharmacy-parsing-retry"

app = FastAPI(title="Medaculous API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "env": settings.ENV, "build": _BUILD_TAG}
