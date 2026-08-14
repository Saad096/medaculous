# Open Questions

Things that are genuinely undecidable without the project owner. Everything not blocked by one of these keeps moving in the meantime.

## Credentials / accounts (blocking Phase 2 build-out, not Phase 1 scaffolding)
- [x] PostgreSQL connection string — local Postgres (`medaculous` db, localhost:5432) has been the working dev DB all session, set in `backend/.env`'s `DATABASE_URL`. A separate *production* Postgres (managed/hosted) is still undecided, but that's a deployment-target decision, not a credential gap blocking build-out.
- [ ] Apple Developer account details + Sign in with Apple key (Team ID, Key ID, private key file, Service ID for the Android/web redirect flow).
- [ ] Google OAuth client IDs for Android, iOS, and Web separately.
- [x] Azure AI Search resource endpoint + key — provided 2026-08-13. Index schema designed and built (see note below), not something that needed to come from the project owner.
- [x] Anthropic API key (`ANTHROPIC_API_KEY`) — provided, confirmed set in `backend/.env` 2026-08-13.
- [ ] CI provider for iOS builds, since the dev machine is Ubuntu (Codemagic / GitHub Actions macOS runner / Xcode Cloud).

**Google/Apple sign-in code is fully built and verified (2026-08-13)** — backend
(`/auth/google`, `/auth/apple`) verifies real tokens server-side; frontend
(`OAuthService`, wired into `AuthRepository`) retrieves native ID/identity
tokens and posts them. Verified live on Android that tapping either button
today shows a friendly "coming soon" message (not a raw error or crash) since
no client IDs are set. Once real values land in `.env` (`GOOGLE_CLIENT_ID*`,
`APPLE_*`) and are passed via `--dart-define` at build time (`GOOGLE_CLIENT_ID`,
`GOOGLE_CLIENT_ID_IOS`, `APPLE_SERVICE_ID`, `APPLE_REDIRECT_URI` — see
`frontend/lib/core/config/env.dart`), sign-in should work with no further code
changes on Android. iOS additionally needs native config this session couldn't
add or verify (no Xcode/macOS on this dev machine): a `CFBundleURLSchemes`
entry in `Info.plist` for the Google redirect, and the Sign In with Apple
capability + entitlement wired into the Xcode project.

## Branding
- [x] **RESOLVED (owner decision, 2026-08-13): keep using the inferred tokens.** Vector logo file (only a 1024×1024 PNG and a GIF exist today — `public/logo.png`, `Medaculous logo GIF.gif`). No formal color palette, font license, or style guide exists; `docs/DISCOVERY_REPORT.md` §3's best-effort extracted/inferred tokens (Tailwind blue-600, `#2563eb`, as the primary color) stay as-is — no real brand assets or a different color were provided, and I can't invent a logo/palette on the owner's behalf. Revisit if real brand assets ever land.
- [x] The animated logo GIF's full motion sequence — not pursued further; no splash-screen animation work is planned until real branding assets exist (see above).
- [x] PWA manifest icons/theme colors in the current app are placeholder (blue-square-cross, white theme) and mismatched with the real logo — confirmed safe to disregard, not replicate.

## Data & compliance
- [x] **RESOLVED (owner decision, 2026-08-13): apply defensive best-practices only — no compliance certification claimed.** Whether Ward Companion patient data, symptom-checker inputs, or uploaded PDFs legally count as regulated health/PII data (HIPAA/GDPR-adjacent) remains a legal determination outside engineering scope — this is **not** claimed or certified here. What was built regardless, since it's sound practice either way: Ward Companion's `/wipe` does a genuine hard-delete (not soft-delete) of shift/patient/task data; `app/workers/otp_cleanup.py` and `token_pruning.py` already exist to purge expired OTPs and dead refresh tokens (real gap flagged: neither is wired to a scheduler yet — needs cron/systemd once a deployment target is chosen); deletions propagate to the Azure Search index too. Encryption-at-rest is left as an infra/hosting-layer setting (Postgres/Blob disk encryption) for whenever a production host is chosen. Full writeup: `docs/SECURITY_CHECKLIST.md` → "Data retention & compliance."

## Product/scope decisions discovered during Phase 0
- [x] **Subscription/trial model — RESOLVED (owner decision, 2026-08-13): built trial-tracking scaffolding only, no payment integration.** Pricing tiers and a payment provider (Stripe/RevenueCat/App Store & Play Store IAP) are still not decided and remain out of scope. What's built: `TRIAL_DURATION_DAYS` (backend `config.py`, 3 days), computed `trial_expires_at`/`is_trial_active` on `UserOut` (derived from `created_at`, no extra column), surfaced in the Flutter app as a non-blocking "N days left" banner on Home (`AppUser.isTrialActive`/`trialDaysLeft`). Nothing is enforced/gated yet — this is status-only scaffolding a real paywall can build on once pricing/provider is chosen.
- [x] **Knowledge Hub sync** — RESOLVED (user decision, 2026-08-12): full sync — PDF files themselves, plus folders/bookmarks/annotations, all server-synced. Storage: local disk on the FastAPI server for now (`backend/data/pdfs/<user_id>/<pdf_id>.pdf`, served via an authenticated streaming endpoint), not S3/Blob — a swap-in-place migration later if/when scale requires it, since nothing else needs to know where the bytes live. Scope cuts made building this (not blocking, just noting for follow-up):
  - **Annotation types**: MVP ports highlights (colored rects over a page region) and text notes only. The legacy's Konva-based freehand pen/shapes/stickers/image-annotation tools are cut, mirroring the same freehand-drawing cut already made for Notes — the PDF's own "annotation tools are clunky/broken" complaint was about exactly those tools, so cutting them rather than porting broken behavior seems like the right call, but flag if freehand markup on PDFs specifically is a hard requirement.
  - **Full-text PDF content search — BUILT (2026-08-13)**: once `AZURE_SEARCH_ENDPOINT`/`AZURE_SEARCH_KEY` were provided, built the real index (`backend/app/services/search.py`) and wired it into Knowledge Hub (`GET /knowledge-hub/search`, indexed on upload/deleted on delete) — search now finds matches *inside* PDF content, with the frontend jumping straight to the matching page. Same index also powers RAG context retrieval for Medaculous AI chat (notes + PDFs + past conversations, per-user filtered) and Notes search. See `docs/SECURITY_CHECKLIST.md` for the schema/design writeup. No embedding provider is configured (Anthropic doesn't offer one; no Azure OpenAI resource was provisioned), so this is BM25 full-text + Azure's semantic reranker, not vector similarity — real relevance improvement (confirmed live: a query for "blood pressure treatment" correctly surfaced a note about "hypertension") without needing an embeddings pipeline. Swapping in vector search later is additive, not a rewrite, if an embedding provider is chosen.
  - **Outline/TOC navigation**: deferred — this was already a *new* fix request (not preserve-as-is), so it's being tracked as a genuine follow-up rather than a silent scope cut.
- [x] **Exam Planner scheduling engine location** — RESOLVED (user decision, 2026-08-12): server-side, Python/FastAPI — `examPlannerEngine.ts`'s algorithms (schedule generation, adaptive catch-up, spaced-repetition intervals, streak update, readiness-score formula) ported to Python, matching the architecture of every other synced feature. Scope cuts made building this (not blocking, tracked for follow-up):
  - **Weekly/monthly calendar views**: MVP ships the daily agenda view only (the core "what do I study today" loop) plus the dashboard/stats view. Weekly/monthly are visualization variants of the same `/exam-planner/schedule` data — additive UI work, not a data-model gap.
  - **Custom Syllabus Editor UI**: the backend CRUD for specialties/topics exists (so nothing is blocked), but the add/edit/delete editor screen itself isn't built this pass — users get the default blueprint seeded per exam.
  - **Topic notes/checklists** (`TopicUserMeta.notes`/`checklists`): the data model and API exist, but no dedicated notes/checklist screen yet.
  - **Pomodoro-style focus timer**: pure client-side UI with no backend dependency — straightforward to add later, deferred for this pass.
  - **Search modal**: deferred.
- [x] **Calculator source & approach** — RESOLVED (user decision, 2026-08-13): WebView approach confirmed, but pointed at [ClinCalc](https://clincalc.com/) instead of MDCalc — free, no login/paywall, no anti-embedding clause in its disclaimer/ToS, and it ships its own official mobile apps (so mobile clinical use is clearly an intended use case, unlike MDCalc which the original PDF spec assumed without checking licensing). Covers cardiology, critical care, infectious disease, nephrology, and pharmacokinetics calculators. The old codebase's dead `CalculatorDashboard.tsx`/`CalculatorDetail.tsx` scaffolding for native calculators remains unused — WebView, not native reimplementation, is the confirmed approach.
- [x] **AI model swapability — RESOLVED (owner decision, 2026-08-13): admin-configurable server-side string, not a user-facing picker.** Already fully implemented before this decision was even made: `backend/app/services/llm.py`'s `_TIER_TO_MODEL` dict maps tiers to `settings.ANTHROPIC_MODEL_HAIKU/SONNET/OPUS` env vars — swapping models is an `.env` edit, no code change, no redeploy of app logic. Confirmed via grep no model string is hardcoded anywhere else in the backend.
- [ ] State-management preference: no existing Flutter/Dart precedent in this codebase (it's a pure React web app), so no signal to defer to — Riverpod (master spec's default) will be used unless the owner has a different preference.

## UX decisions discovered during QA (Phase 4, Patrol E2E testing)
- [x] **Back button on Home exits the app immediately** — RESOLVED (2026-08-13): implemented the common Android "press back again to exit" pattern (`PopScope` + `SystemNavigator.pop()`, 2-second window) rather than leaving it as an instant, confirmation-less exit. Low-risk enough of a UX call (standard platform convention, not a product/business decision) to just implement rather than block on — verified live on-device: single back shows a snackbar and stays open, double-back-within-2s exits cleanly.

## Already covered by existing docs (not re-listed here)
- `security_spec.md` (repo root) documents a Firestore-era threat model ("Dirty Dozen" payloads) for the orphaned Firebase backend. Its *data-ownership invariants* (strict per-user ownership, no cross-user access, feedback reports write-only) are still valid principles for the new Postgres/FastAPI design and will be carried forward; the Firestore-specific rule syntax itself does not port.
