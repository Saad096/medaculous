# Medaculous

An AI-powered medical reference and clinical workflow app for medical students and
clinicians: a **Flutter mobile app** (iOS + Android) backed by a **FastAPI + PostgreSQL**
API, with **Anthropic Claude** as the AI provider throughout (chat, symptom checking, drug
recommendations, formulary auto-fill). This guide is written so someone with no prior
familiarity with this codebase can get both halves running, point the app at a real
server, push the code to GitHub, and debug the common ways any of that goes wrong.

---

## 1. What's in this app

**Platform:** native mobile (Android + iOS) via Flutter, talking to a self-hosted FastAPI
backend over a plain REST/JSON API (+ one streaming endpoint for chat). No web frontend —
the legacy React/Firebase prototype this replaced is archived, not shipped.

**Core features** (each has its own backend router + Flutter screen):

| Feature | What it does |
|---|---|
| **Medaculous AI** | Streaming chat with 4 modes (Ward / ER / Exam / Auto), persistent conversation history, save-to-Notes, cross-conversation context via Azure AI Search |
| **Systems & Diseases** | Browsable body-system → disease hierarchy with structured detail pages |
| **Symptom Checker** | AI differential diagnosis ranked by likelihood, always surfacing can't-miss diagnoses |
| **Drug Recommendations** | AI pharmacist: tiered recommendations, drug-drug interaction checking, substitute finder, favorites |
| **Formulary** | Curated drug database with lazy AI-fill (generates missing fields once, then caches for every future viewer) and AI-backed search-or-create for drugs not yet in the database |
| **Knowledge Hub** | Upload/store/search personal PDFs, nested folders, native in-app viewer, bookmarks, highlight/note annotations, full-text content search, and (new) extracted title/author/content-preview metadata shown per document |
| **Ward Companion** | Shift tracking, patient list, task management with priorities |
| **Exam Planner** | Setup wizard, adaptive study scheduling, Pomodoro session timer, streaks/stats |
| **OSCE Preparation** | Station checklists with an accurate (background-safe) exam timer |
| **Notes** | Rich-text notes with images, folders, and per-disease attachment |
| **Calculator** | In-app medical calculators (WebView) |

**Account & platform features:**
- Email/password auth with real OTP email verification, plus Google/Apple sign-in (both
  fully implemented server-side; the buttons show "coming soon" until real OAuth client
  IDs are configured — see §6).
- 3-day free trial, then a pricing/paywall flow (Monthly/Annual plans, full checkout UI).
  Payment processing itself is intentionally not live yet — see §6's Stripe note.
- Per-user AI usage limits (50 AI messages / rolling 30 days by default, overridable per
  user) enforced server-side on every AI-backed endpoint.
- An **admin role** (seeded for `talk2saadalam@gmail.com`) with an in-app dashboard:
  total users, AI usage stats, signups chart, per-user limit overrides, and account
  deletion.
- Dark mode, profile photo upload, Terms/Privacy acceptance at signup.

---

## 2. Repository layout

```
Medaculous v1 ZIP/
├── backend/                    FastAPI + PostgreSQL API (Python)
│   ├── app/
│   │   ├── api/v1/             One router file per feature (auth, ai, admin, symptoms,
│   │   │                       pharmacy, formulary, knowledge_hub, ward, exam_planner,
│   │   │                       osce, notes, diseases) — all mounted in api/v1/router.py
│   │   ├── models/             SQLAlchemy ORM models (one file per feature area)
│   │   ├── schemas/            Pydantic request/response schemas
│   │   ├── services/           Cross-cutting logic: llm.py (Anthropic), search.py (Azure
│   │   │                       AI Search), email.py, google_oauth.py, apple_oauth.py
│   │   ├── core/                config.py (all env vars), security.py (JWT/password hashing)
│   │   └── db/                  session.py (async SQLAlchemy engine), base.py
│   ├── alembic/versions/        One migration file per schema change, applied in order
│   ├── data/                    Uploaded PDFs/avatars land here at runtime (gitignored)
│   ├── .env.example             Template — copy to .env and fill in (see §5)
│   └── Dockerfile
├── frontend/                    Flutter app (iOS + Android)
│   ├── lib/
│   │   ├── core/                 Shared: theme, router (app_router.dart), reusable widgets,
│   │   │                        network client, secure token storage
│   │   └── features/             One directory per feature, each split into
│   │                            domain/ (models) · data/ (API client) ·
│   │                            presentation/ (providers + screens/widgets)
│   ├── assets/                   Logo, app icon source, fonts
│   └── android/, ios/            Native platform projects
├── docs/                        Design/discovery notes from the original build (reference only)
├── screenshots/                 Client-supplied reference screenshots (gitignored — see §3)
├── docker-compose.yml           Backend in Docker, connecting out to system Postgres
└── docker-compose.dev.yml       Overlay: live-reload for docker-compose.yml
```

**Postgres always runs as a system service — never inside a container**, whether the
backend itself runs bare-metal or in Docker. There is one real Postgres install, one real
database, used the same way either way; `docker-compose.yml` only ever containerizes the
backend, and connects out to that already-running system Postgres via `DATABASE_URL` in
`backend/.env`.

---

## 3. What's tracked in git (and what isn't)

A few large, non-code reference files the client originally supplied
(`*.pdf`, `*.gif`, `*.docx`, `screenshots/`) are excluded via `.gitignore` — they're
one-off deliverables, not source, and would otherwise bloat every clone forever. They stay
on disk locally; they just don't get committed. Everything else — all backend and frontend
source, Alembic migrations, Docker config, and `docs/` — is tracked normally.

Also gitignored, for the usual reasons: `backend/.env` (real secrets — only
`.env.example` is committed), `backend/.venv/`, `backend/data/` (user-uploaded files),
Flutter's `build/`/`.dart_tool/`, Android's `key.properties`/`*.jks` (a real release
signing key — see `frontend/README.md`), and standard editor/OS noise.

---

## 4. Prerequisites

- **PostgreSQL, installed as a system service** — required either way (Docker or not);
  see the install steps in **§6a** below if you don't have it yet.
- [Docker](https://docs.docker.com/get-docker/) + Docker Compose (bundled with Docker
  Desktop; on Linux servers, `docker compose` is a plugin — confirm with `docker compose
  version`) — only needed for the Docker path.
- [Flutter SDK](https://docs.flutter.dev/get-started/install) — needed either way, to run
  the mobile app.
- An Android device/emulator or iOS device/simulator to actually run the app on.
- [Git](https://git-scm.com/downloads) — to version and push this code (see §7).

---

## 5. Environment variables (`backend/.env`)

Copied from `backend/.env.example`, which has a comment above every line explaining what
it's for — read that file alongside this list. The short version of what's required
before the app will even boot, versus what can stay blank until you have it:

**Must be set to boot at all:**
- `DATABASE_URL` — see §6a below; same value whether you run the backend via Docker or
  the plain virtualenv path.
- `JWT_SECRET`, `JWT_REFRESH_SECRET` — any long random string works. Generate one with:
  ```bash
  python3 -c "import secrets; print(secrets.token_urlsafe(64))"
  ```
  Run it twice — these two must be **different** values.

**Safe to leave blank for local testing** (the app handles absence gracefully — features
just report "not configured" instead of crashing):
- `AZURE_COMMUNICATION_CONNECTION_STRING` / `AZURE_COMMUNICATION_SENDER` — real OTP
  emails. Leave `OTP_DEV_MODE=true` (the `.env.example` default) and OTP codes print to
  the backend's terminal/logs instead of being emailed — good enough to log in during
  development.
- `GOOGLE_CLIENT_ID*`, `APPLE_*` — Google/Apple sign-in. The email/password flow works
  fully without these; the social sign-in buttons show a "coming soon" message until
  these are filled in.
- `ANTHROPIC_API_KEY` — needed for Medaculous AI, symptom checker, drug recommendations,
  and formulary AI-fill to actually return AI responses (those features will error
  without it, but the rest of the app works).
- `AZURE_SEARCH_ENDPOINT` / `AZURE_SEARCH_KEY` — powers cross-conversation AI context and
  PDF content search. Optional; those two specific search-quality features degrade
  gracefully without it.
- `STRIPE_SECRET_KEY` / `STRIPE_PUBLISHABLE_KEY` — real payment processing. Leave blank
  for now: the checkout screen is fully built (plan selection, card-details form) but the
  final "Pay" action shows a "secure checkout is almost ready" message instead of
  charging anything until these are filled in **and** a backend charge/webhook endpoint
  is built on top of them (not yet done — see the note in `checkout_screen.dart`).

**Must match your real deployment once you have one:**
- `APP_BASE_URL` — this backend's own public URL (`http://localhost:8000` for local dev;
  `http://<vm-ip>:8000` or `https://your-domain.com` in production — see §8).
- `CORS_ORIGINS` — comma-separated list of origins allowed to call the API. Not usually
  relevant for the mobile app itself (mobile apps aren't subject to browser CORS), but
  matters if you ever add a web admin panel.
- `ADMIN_EMAIL` — which account gets admin dashboard access (defaults to
  `talk2saadalam@gmail.com`). The admin flag is set on that user by a data migration at
  first `alembic upgrade head`; changing this setting later does **not** retroactively
  flip anyone's `is_admin` — grant/revoke that via the admin dashboard itself, or a
  one-off `UPDATE users SET is_admin = true WHERE email = '...';`.

---

## 6a. Install PostgreSQL as a system service (do this once, either path)

**Ubuntu/Debian:**
```bash
sudo apt update && sudo apt install -y postgresql
sudo systemctl enable --now postgresql   # starts now, and on every future boot
sudo -u postgres psql -c "CREATE USER saad WITH PASSWORD '123' CREATEDB;"
sudo -u postgres psql -c "CREATE DATABASE medaculous OWNER saad;"
```
**macOS:** `brew install postgresql@16 && brew services start postgresql@16`, then the
same two `psql` commands via `psql postgres`.

(Use whatever username/password/database name you like — just make sure
`DATABASE_URL` in `backend/.env`, set up next, matches whatever you picked here.)

---

## 6. Start the backend (Docker — recommended)

```bash
cd "Medaculous v1 ZIP"
cp backend/.env.example backend/.env
```

Open `backend/.env` and set `DATABASE_URL` to the Postgres you just created, e.g.
`postgresql+asyncpg://saad:123@localhost:5432/medaculous` — then fill in the rest of the
real values; see **§5 Environment variables** above for what each one does and which ones
you can safely leave blank for now.

Then, from the project root (where `docker-compose.yml` lives):

```bash
docker compose up --build
```

This builds and starts **only the backend** in a container — Postgres is never
containerized, the backend connects straight out to the system Postgres you set up in
§6a. On startup it automatically runs any pending database migrations — creating the
schema the first time, and a harmless no-op every time after — then starts the API on
`http://localhost:8000`. Leave this running in its terminal (or add `-d` to run it in
the background: `docker compose up --build -d`).

Uploaded PDFs and avatars are written to a named Docker volume (`backend_data`, mounted
at `/app/data`) so they survive `docker compose up --build` recreating the container —
only `docker compose down -v` (which explicitly deletes volumes) or removing the volume
by hand wipes them.

> **Why `docker-compose.yml` overrides `DATABASE_URL`'s host to
> `host.docker.internal` instead of using `.env`'s `localhost` verbatim:** the word
> "localhost" inside a container never means "the real machine" — it means the
> container itself. There is no way around this while keeping a literal `localhost` in
> the connection string used *inside* Docker specifically; `host.docker.internal` is
> the one hostname Docker resolves to your real machine on every platform (Desktop and
> native Linux Engine alike, via the `extra_hosts` entry already in the compose file).
> The override only replaces the host — it reuses the same user/password/db name from
> `.env`. **If you change those in `.env`, update the matching line in
> `docker-compose.yml` to match.** Running without Docker (§6b) has no such issue —
> `localhost` there really is the machine, so `.env` is used completely unmodified.

**Port already in use?** If you also have the backend running outside Docker (§6b) on the
same machine, both can't bind port 8000 at once — stop one first (`Ctrl+C` on the
`uvicorn` process, or `docker compose down` for the container).

Check it worked:

```bash
curl http://localhost:8000/docs
```

A `200` response (or opening that URL in a browser and seeing the Swagger UI) means the
backend is up.

**Rebuilding after you (or I) change backend code:**

```bash
docker compose up --build          # rebuilds only the layers that changed — fast, uses cache
docker compose build --no-cache    # forces a full rebuild from scratch — use if something
docker compose up                  # seems stale/wrong after a normal rebuild, or after
                                    # editing requirements.txt/Dockerfile itself
```

On the *same* VM/machine, always prefer the cached rebuild (`up --build`) — it only
reinstalls Python packages when `requirements.txt` actually changed, so it's normally a
few seconds. Reach for `--no-cache` only when you suspect the cache itself is wrong
(rare), not as a routine step.

**Live-reload while developing** (restarts the API automatically when you edit backend
code, instead of needing `docker compose up --build` every time):

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build
```

**Stopping:**

```bash
docker compose down
```

There's no database volume to worry about here — Postgres lives outside Docker
entirely (§6a), so stopping/removing this container never touches your data. It *does*
still have the `backend_data` volume (uploaded files) — add `-v` to also wipe that.

**Optional: a database admin UI** (pgAdmin, at `http://localhost:5050`, also connects to
the system Postgres via the same host networking as the backend):

```bash
docker compose --profile tools up -d pgadmin
```

---

## 6b. Start the backend (without Docker)

Use this if you'd rather not install Docker, or you're on a machine where it's not
available. Same Postgres either way (§6a) — this path just runs the API itself in a
plain virtualenv instead of a container.

```bash
cd "Medaculous v1 ZIP/backend"
python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env
```

Edit `.env`: set `DATABASE_URL` to match whatever you created in §6a (e.g.
`postgresql+asyncpg://saad:123@localhost:5432/medaculous`), plus the other values in
**§5** above. Then:

```bash
alembic upgrade head        # creates all tables — do this once, and again after any
                             # future migration is added
uvicorn app.main:app --reload --port 8000
```

Same check as the Docker path: `curl http://localhost:8000/docs` should return `200`.

---

## 6c. Run the Flutter app

```bash
cd "Medaculous v1 ZIP/frontend"
flutter pub get
```

The app never hardcodes where the backend lives — you tell it at build/run time with
`--dart-define=API_BASE_URL=...`. Pick the line that matches how you're running it:

```bash
# Android emulator (10.0.2.2 is the emulator's alias for your host machine's localhost)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1

# Physical Android device over USB, backend running on the same computer:
adb reverse tcp:8000 tcp:8000
flutter run --dart-define=API_BASE_URL=http://localhost:8000/api/v1

# Any device, backend on a remote server by IP address:
flutter run --dart-define=API_BASE_URL=http://203.0.113.10:8000/api/v1

# Any device, backend behind a real domain (recommended for production — also
# required if you want https:// instead of a bare IP):
flutter run --dart-define=API_BASE_URL=https://api.medaculous.com/api/v1
```

If you find yourself repeating a long `--dart-define` line, put it in a JSON file instead:

```json
// frontend/config/prod.json
{ "API_BASE_URL": "https://api.medaculous.com/api/v1" }
```
```bash
flutter run --dart-define-from-file=config/prod.json
```

**For running on a real connected phone (not an emulator), building an installable APK,
signing a real release, and publishing to the Play Store or Apple App Store, see
[`frontend/README.md`](frontend/README.md)** — that's the full walkthrough, this section
only covers where the backend URL comes from.

---

## 7. Version control: pushing this code to GitHub

This project isn't in git yet. To start tracking it and push to your own GitHub:

```bash
cd "Medaculous v1 ZIP"
git init
git add .
git commit -m "Initial commit"
```

Then create an empty repository on GitHub (no README/license/gitignore — this project
already has its own) at **github.com/new**, and connect it:

```bash
git remote add origin git@github.com:<your-username>/medaculous.git
git branch -M main
git push -u origin main
```

(Use the `https://github.com/<you>/medaculous.git` form instead if you push over HTTPS
rather than SSH — GitHub will prompt for a personal access token as the password the
first time.)

If you have the [GitHub CLI](https://cli.github.com/) installed and logged in
(`gh auth login`), the create-and-push step collapses to one command run from inside the
repo after `git init`/`git add`/`git commit` above:

```bash
gh repo create medaculous --private --source=. --remote=origin --push
```

**Day-to-day from here:** normal git — `git add`, `git commit`, `git push`. Nothing about
this project's structure requires anything unusual (no submodules, no LFS). Double-check
`git status` before your first commit and confirm `backend/.env` does **not** appear in
the list (it's gitignored, but worth a glance — that file holds real secrets).

---

## 8. Deploying the backend to a remote VM

1. Get the code onto the VM — now that it's a git repo (§7), the simplest path is
   `git clone` your GitHub repo directly on the VM (or `scp`/`rsync` if you'd rather not
   involve GitHub). Then follow **§6** (Docker, recommended) or **§6b** (no Docker) above,
   on the VM itself.
2. Set `APP_BASE_URL` in `backend/.env` to the VM's real address (its IP or a domain
   pointed at it), not `localhost`.
3. **Open the port.** This trips people up more than anything else here — the backend
   can be running perfectly and still be unreachable from your phone because nothing
   let port 8000 through:
   - **Cloud provider firewall** (this is the one people forget): AWS Security Groups,
     GCP Firewall Rules, Azure Network Security Groups, or your VPS provider's firewall
     panel — add an inbound rule allowing TCP port 8000 (or 443 if you put a reverse
     proxy in front, see below) from your IP or `0.0.0.0/0`.
   - **The VM's own firewall**, if it has one active:
     ```bash
     sudo ufw allow 8000/tcp     # Ubuntu/Debian with ufw
     ```
   - Confirm the app is actually listening on all interfaces, not just the VM's internal
     loopback — it already is by default here (`--host 0.0.0.0` in both the Docker CMD
     and the bare `uvicorn` command above), but double-check if you ever change that.
4. For production, prefer a real domain + HTTPS over a bare IP: point a domain's DNS at
   the VM, put a reverse proxy (nginx, Caddy) in front of port 8000 to terminate TLS, and
   use `https://your-domain.com/api/v1` as the mobile app's `API_BASE_URL`. Sending
   passwords/tokens over plain `http://` to a public IP is fine for a quick test, not for
   anything real.
5. Install Postgres on the VM the same way as §6a and run `docker compose up --build -d`
   (same command as local dev — there's only one `docker-compose.yml`, and it always
   connects out to system Postgres, never a container, so nothing changes between local
   and production here). Migrations still run automatically on startup — nothing extra
   to run by hand once the Postgres system service itself is up.
6. Rebuild the Flutter app pointed at the VM's real address before installing it on any
   device meant to use the deployed backend — see §6c. A dev build pointed at
   `localhost`/`10.0.2.2` will never reach a remote VM; that's a build-time flag, not
   something that auto-detects the server.

---

## 9. Troubleshooting

**"`docker compose up` can't connect to Postgres / connection refused on 5432"** →
confirm Postgres is actually running (`sudo systemctl status postgresql`) and reachable
at `host.docker.internal:5432` from a container — `docker run --rm alpine sh -c "apk add
-q curl && nc -zv host.docker.internal 5432"` should print "open". If that fails, the
issue is Postgres itself (not listening, or bound only to a socket/interface that
doesn't include the host gateway) rather than anything in this compose file. Also
double check `docker-compose.yml`'s `DATABASE_URL` line matches the user/password/db
you actually created in §6a — see the callout in §6 for why that line exists instead of
reusing `.env`'s value verbatim.

**"`curl http://localhost:8000/docs` works on the VM itself, but not from my phone/laptop"**
→ Almost always the cloud firewall / security group from §8 step 3, not the app.
Test from *outside* the VM with `curl http://<vm-ip>:8000/docs` (from your own laptop,
not SSH'd into the VM) — if that hangs/times out, it's the firewall; if it returns a
response but the phone still can't reach it, check the phone is actually online and not
on a network that blocks that port.

**"Connection refused" from the app** → the backend isn't running, or `API_BASE_URL`
points at the wrong host/port. Re-check the `flutter run`/`flutter build` command you
used actually included the right `--dart-define=API_BASE_URL=...`.

**"`docker compose up` fails / the backend container keeps restarting"** → run
`docker compose logs backend` to see the actual error. There's no `db` service to check
here (Postgres is never containerized — see §6a) — a restart loop is almost always
either Postgres unreachable (see the first entry above) or a bad value in `.env`. If it
looks like a stale image is the problem: `docker compose build --no-cache && docker
compose up`.

**"Uploads (PDF, avatar) return an error / files disappear after a rebuild"** → if you're
running an older checkout, confirm the Docker image actually has the `data/` ownership
fix (`backend/Dockerfile` should `chown` `/app/data` to `appuser` before dropping root),
and that `docker-compose.yml` mounts the `backend_data` named volume at `/app/data` —
without that volume, uploaded files live only in the container's writable layer and are
lost on the next `docker compose up --build`.

**"It worked before, now it doesn't, after I changed something"** → try the non-cached
rebuild (`docker compose build --no-cache && docker compose up`) — rules out a stale
Docker layer cache before you go looking for a real bug.

**"OTP email never arrives"** → check `OTP_DEV_MODE` in `.env`. If `true`, there is no
real email — the code is printed in the backend's logs/terminal instead
(`docker compose logs backend` if running via Docker). Set it to `false` and fill in the
`AZURE_COMMUNICATION_*` values once you have a real email provider configured.

**"Google/Apple sign-in shows 'coming soon'"** → expected until `GOOGLE_CLIENT_ID*` /
`APPLE_*` are filled in in `.env` — this is intentional, not a bug (see §5).

**"Checkout's final Pay button shows 'coming soon' instead of charging a card"** →
also intentional — no `STRIPE_SECRET_KEY` is configured yet, and no card details entered
in that screen are ever transmitted anywhere (see §5).

**"AI features (Medaculous AI, symptom checker, drug recommendations, formulary AI-fill)
return an error"** → `ANTHROPIC_API_KEY` is missing/invalid in `.env`.

**"AI features return a 429 / 'usage limit reached'"** → expected once a user hits their
AI message quota (50 per rolling 30 days by default). Raise or clear it for a specific
user from the in-app Admin Dashboard (Settings → Admin, only visible to the account set
as `ADMIN_EMAIL`), or directly: `UPDATE users SET ai_monthly_limit = 1000 WHERE email =
'...';`.

**Flutter build acting strange after a `git pull`** → clear Flutter's local caches and
retry:
```bash
cd frontend
flutter clean
flutter pub get
```

**App launcher icon still shows the default Flutter icon after `flutter build`** →
regenerate it: `cd frontend && dart run flutter_launcher_icons` (reads
`assets/icon/app_icon.png`, configured in `pubspec.yaml`'s `flutter_launcher_icons:`
block). Android sometimes caches the old icon briefly after an in-place `adb install -r`
— a launcher refresh or device restart clears it.
