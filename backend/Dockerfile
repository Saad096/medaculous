# --- builder: compile wheels, no build tools in the runtime layer ---
FROM python:3.12-slim AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends gcc libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt

# --- runtime: small final image ---
FROM python:3.12-slim AS runtime

WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends libpq5 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /wheels /wheels
COPY requirements.txt .
RUN pip install --no-cache-dir --no-index --find-links=/wheels -r requirements.txt \
    && rm -rf /wheels

COPY app ./app
COPY alembic ./alembic
COPY alembic.ini .

# data/ holds uploaded PDFs and avatars (see PDF_STORAGE_DIR / AVATAR_STORAGE_DIR
# in config.py) — created and chowned here so appuser can write to it. Without
# this, appuser inherits /app as root-owned read-only and every upload 500s on
# the very first mkdir() (found via a live "upload fails" report, 2026-08-14).
RUN adduser --disabled-password --no-create-home appuser \
    && mkdir -p /app/data/pdfs /app/data/avatars \
    && chown -R appuser:appuser /app/data
USER appuser

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
