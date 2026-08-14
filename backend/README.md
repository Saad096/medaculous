# Medaculous Backend

FastAPI + SQLAlchemy (async) + PostgreSQL.

**For the full setup guide (Docker or not, environment variables, remote-VM deployment,
troubleshooting), see the [root README](../README.md).** This file only covers backend-
specific dev commands (tests, migrations) that don't belong at the top level.

## Local setup

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # then fill in real values — see below
alembic upgrade head
uvicorn app.main:app --reload --port 8000
```

`.env` is gitignored — never commit it. Required before the app will boot:
`DATABASE_URL`, `JWT_SECRET`, `JWT_REFRESH_SECRET` (generate with
`python -c "import secrets; print(secrets.token_urlsafe(64))"`).

For real OTP emails, set `OTP_DEV_MODE=false` plus `AZURE_COMMUNICATION_CONNECTION_STRING`
and `AZURE_COMMUNICATION_SENDER` (Azure Communication Services → Email). With
`OTP_DEV_MODE=true`, codes just print to the server log instead.

## Running tests

```bash
pytest tests/
```

`tests/test_security.py` is pure unit tests (no DB needed). Integration coverage of the
full auth flow (OTP, refresh rotation, reuse detection) has been verified manually against
a real Postgres instance — see `docs/QA_AUDIT_REPORT.md` once Phase 4 lands; promoting that
into an automated `pytest` suite (a test DB + transactional rollback per test) is tracked
there rather than duplicated here.

## Migrations

```bash
alembic revision --autogenerate -m "describe the change"
alembic upgrade head
```

Never hand-edit the schema directly — always go through a migration.

## Running with Docker

The `docker-compose*.yml` files live at the **project root**, not in this folder, since
they orchestrate `backend/` as a build context — run `docker compose` from the project
root, not from here. Postgres itself is never containerized (always a system service —
see the root README's §2a); the compose file only ever containerizes this API. Full
instructions, including remote-VM/firewall guidance, are in the
[root README](../README.md).
