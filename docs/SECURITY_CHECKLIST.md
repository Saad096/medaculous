# Security Checklist — Postgres/FastAPI/Flutter stack

This supersedes `security_spec.md` (repo root) for the new system — that doc is the
legacy Firestore "Dirty Dozen" threat model and is reference-only (see
`docs/DISCOVERY_REPORT.md`). This checklist covers the actual FastAPI backend and
Flutter client built this project. Status reflects what's been verified as of
2026-08-13.

## Authentication

- [x] Passwords hashed with bcrypt via `passlib` (`app/core/security.py`), never stored or logged in plaintext.
- [x] Access and refresh tokens use **separate JWT secrets** (`JWT_SECRET` / `JWT_REFRESH_SECRET`) — a leaked access token can't be replayed as a refresh token. Verified in `tests/test_security.py`.
- [x] Access tokens are short-lived (15 min default); refresh tokens are longer-lived (30 days) and stored server-side as a **hash**, not the raw token (`test_refresh_token_hash_is_deterministic_and_one_way`).
- [x] Expired access tokens are rejected with a distinct `401 Token expired` (vs a generic invalid-credentials 401) so the client knows to silently refresh rather than force a full re-login (`app/api/deps.py`).
- [x] Logout invalidates by refresh-token hash, not by requiring a valid (possibly already-expired) access token — so logout works even mid-session-expiry.
- [x] OTP codes: rate-limited per-email and per-IP (`OTP_MAX_REQUESTS_PER_EMAIL_PER_HOUR`, `OTP_MAX_REQUESTS_PER_IP_PER_HOUR`), resend cooldown, max verify attempts per code, and stored hashed not plaintext (`test_otp_hash_matches_only_the_original_code`).
- [x] Login brute-force protection: account lockout after `LOGIN_MAX_FAILED_ATTEMPTS` failed attempts within `LOGIN_LOCKOUT_WINDOW_MINUTES`.
- [x] `TEST_MODE_OTP_BACKDOOR` (exposes OTP codes via a debug endpoint for Patrol E2E automation) defaults to `False` and is documented as never-set-in-shared-envs in `config.py`.
- [x] Google/Apple OAuth: backend verifies real ID/identity tokens against Google's JWKS / Apple's public keys server-side (`app/services/google_oauth.py`, `apple_oauth.py`) rather than trusting client-asserted identity — correctly returns `501` (not a crash) when client IDs are unconfigured.

## Authorization (per-user ownership)

Every endpoint that touches user-owned data is gated behind `Depends(get_current_user)`,
and ownership is checked at the query/row level (not just "is authenticated") — the
`_get_owned_*` helper pattern used in `pharmacy.py`, `knowledge_hub.py`, `ward.py`,
`osce.py`, `formulary.py` returns `404` (not `403`) for another user's resource, so a
client can't distinguish "doesn't exist" from "exists but isn't yours."

- [x] **Audited every router** (`ai, auth, diseases, exam_planner, formulary, knowledge_hub, notes, osce, pharmacy, symptoms, ward`) for missing `get_current_user` — one gap found and fixed: `GET /exam-planner/exams` was serving public catalog data without auth, inconsistent with every other catalog-style endpoint (e.g. `GET /formulary/tree`, which does require auth despite being shared data). Fixed 2026-08-13.
- [x] `auth.py`'s pre-session routes (register/login/refresh/OTP/oauth) are correctly ungated — they can't require a session before one exists. `logout` correctly authenticates via refresh-token hash instead of access token. `/me` is the one session-gated route in that router.
- [x] **Automated regression coverage**: `backend/tests/test_authz_cross_user.py` — 8 tests, real Postgres-backed (not mocked), covering Notes, Knowledge Hub folders, Ward Companion patients, OSCE favorites/progress, Exam Planner setup, and Pharmacy favorites. Each creates a resource as user A and asserts user B gets `404`/is excluded from list views/can't mutate it, plus a blanket "every listed endpoint requires auth" sweep. Run with:
  ```
  cd backend && PYTHONPATH=. ./.venv/bin/python -m pytest tests/test_authz_cross_user.py -v
  ```

## Azure AI Search (added 2026-08-13)

- [x] **Single shared index, per-user security trimming** — `AZURE_SEARCH_INDEX` (`medaculous-knowledge`) holds every user's indexed notes/PDF-chunks/chat-messages together, with a filterable `user_id` field enforced on *every* query in `app/services/search.py`. Verified live: a query as one user returned zero hits for content indexed under a different user_id.
- [x] **Deletion propagates to the index** — deleting a note, PDF, or conversation calls `delete_by_source()`, removing its chunks from Azure Search too (confirmed live: post-delete searches return empty). One accepted exception: deleting a *note* does not retroactively scrub mentions of it from *already-indexed chat history* — a past AI conversation that discussed the note's content remains its own independently-owned, still-user-scoped record. Deleting the conversation itself removes that copy.
- [x] **No secrets/PII cross the trust boundary that shouldn't** — `AZURE_SEARCH_KEY` stays server-side only (used by the backend's `SearchClient`, never sent to the app). This is a shared Azure resource also hosting unrelated indexes for other projects on the same account — confirmed via `list_indexes()` that only the `medaculous-knowledge` index was touched; nothing else on the resource was read, written, or modified.
- [ ] Not yet built: an admin/support tool to bulk-purge a user's search-index entries independent of deleting their source rows (e.g. for a future "right to be forgotten" flow) — today, deleting the underlying note/PDF/conversation is the only path that cleans the index.

## File storage (Knowledge Hub PDFs)

- [x] **Path traversal**: `pdf_id` and `user_id` are both typed `uuid.UUID` on the FastAPI route/dependency — a malformed value (e.g. `../../etc/passwd`) fails UUID parsing and gets a `422` before ever reaching `_pdf_path()`. Combined with the DB ownership check in `_get_owned_pdf()` running before any filesystem access, there's no path-traversal vector here. Verified by code inspection, not just assumption.
- [x] PDFs are stored per-user (`data/pdfs/<user_id>/<pdf_id>.pdf`) and served through an authenticated `FileResponse` endpoint — never as static files, never with a guessable/public URL.
- [x] Upload size capped (`PDF_MAX_UPLOAD_MB`).

## Secrets

- [x] No provider API keys (Anthropic, Google, Apple, Azure) are ever sent to the client — the legacy app's `GET /api/config` key-leak bug (see `DISCOVERY_REPORT.md`) is explicitly called out in `config.py` as the failure mode being avoided, and the new backend proxies all LLM calls server-side. That legacy leak itself was fixed (dead code deleted) 2026-08-13 — see task #5.
- [x] `.env` is gitignored; `.env.example`-style documentation lives in `config.py`'s field defaults/comments rather than a committed real `.env`.
- [ ] Real credentials (Google OAuth client IDs, Apple Sign-In keys, Azure AI Search, production Postgres URL) are still placeholders pending the project owner — tracked in `OPEN_QUESTIONS.md`. Not a code defect; code paths handle absence gracefully (501/disabled rather than crashing).

## Transport / CORS

- [x] CORS origins are configurable via `CORS_ORIGINS` env var, not wildcarded in code.
- [ ] Not yet verified: production CORS origin list, HTTPS enforcement/HSTS at the reverse-proxy layer (out of scope until a real deployment target is chosen).

## Data retention & compliance (added 2026-08-13)

**Not a compliance certification.** Whether Ward Companion patient data, symptom-checker
inputs, or uploaded PDFs legally count as PHI/PII under HIPAA/GDPR is a determination
the project owner needs to make (possibly with legal counsel) — see `OPEN_QUESTIONS.md`.
What follows is the defensive engineering posture applied regardless of that answer,
since it's good practice either way and costs nothing to have in place now.

- [x] **Ward Companion hard-deletes, doesn't soft-delete**: `DELETE /ward/wipe` (`app/api/v1/ward.py`) permanently removes the shift, every patient, and every task — the most identifiable/sensitive data category in the app doesn't linger in a trash table the way Notes/Knowledge Hub do. Confirmed via code inspection: no `is_deleted` flag on `WardPatient`/`WardTask`, just a real `DELETE`.
- [x] **Expired-credential cleanup workers exist** (`app/workers/otp_cleanup.py`, `app/workers/token_pruning.py`) — purge expired OTP codes and dead (revoked/expired) refresh tokens respectively. **Gap found**: neither is wired to run on any schedule (no cron, no apscheduler job despite it being in `requirements.txt` unused) — they're callable scripts (`python -m app.workers.otp_cleanup`) that nothing currently invokes. This needs a real scheduler once a deployment target is chosen; tracked here rather than silently assumed to be running.
- [x] **Deletion propagates to the search index** (see Azure AI Search section above) — deleted notes/PDFs don't linger as retrievable AI-chat context either.
- [ ] **Encryption at rest** is an infrastructure-layer setting (Postgres disk encryption, Azure Blob/Storage encryption), not application code — needs to be enabled on whatever hosting is chosen for Postgres and PDF storage. Not verified against the current local dev Postgres (irrelevant for a dev machine) or any production target (none chosen yet).
- [ ] `audit_log` has no retention/purge policy — left unbounded intentionally for now, since audit trails are typically something compliance regimes want *retained longer*, not purged; a retention period (if any) should come from the same legal/compliance determination above, not be guessed at here.
- [ ] No formal data processing agreement / privacy policy content reviewed — outside engineering scope.

## Not yet built (tracked, not blocking)

- [ ] Rate limiting on general API endpoints beyond OTP/login (e.g. per-IP throttling on AI-generation endpoints, which are the most expensive to abuse).
- [ ] Structured audit logging for sensitive actions (PDF deletion, ward-data wipe, account deletion) — `audit_log` table exists in the schema but isn't yet written to from these endpoints.
- [ ] Dependency vulnerability scanning (`pip-audit` / `npm audit` / `flutter pub outdated` for known CVEs) as a CI step — no CI pipeline exists yet.
