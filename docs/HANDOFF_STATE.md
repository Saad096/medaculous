# HANDOFF_STATE — Medaculous (Cursor session, resumed from Claude Code)

Last updated: 2026-08-13 (late-night pass — full UI/UX audit implemented + one
end-to-end QA cycle on device; see §2b). Read together with `docs/DISCOVERY_REPORT.md`
(Phase 0 contract), `docs/OPEN_QUESTIONS.md` (decisions log), and
`docs/SECURITY_CHECKLIST.md` (security posture). There is **no git repo** in this
workspace — these docs are the only session-to-session state.

## 1. What is built and verified working

All 11 features + auth exist end-to-end (Flutter `frontend/` + FastAPI `backend/`),
built against local Postgres (`medaculous` @ localhost:5432) and Anthropic (tiered
Haiku/Sonnet/Opus via `backend/.env`, model IDs env-swappable — PDF fix "model must
be updatable" is done):

- **Auth**: register/login/OTP/forgot-reset, JWT access+refresh (separate secrets),
  Google/Apple OAuth verified server-side (graceful "coming soon" until client IDs
  land), 3-day trial status scaffolding (non-blocking banner). Test account
  `talk2saadalam@gmail.com` is logged in on the attached device (a895001e) — reuse it.
- **Systems**: Postgres-backed disease library (15 systems, ~430 diseases, 16
  sections) + per-disease user notes/images (PDF fix "needs a backend, rich text" done).
- **Symptoms**: AI differential diagnosis (`POST /symptoms/check`, JSON-constrained).
- **Symptom-Based Drug Recommendations**: recommendations + interaction checker +
  substitution finder + favourites (`/pharmacy/*`).
- **Formulary**: curated DB + AI enhance/generate-and-cache monographs.
- **Notes**: rich text (flutter_quill), folders, images, search, trash, server-synced.
- **Medaculous AI**: streaming chat (Ward/ER/Exam/Auto), disclaimer banner,
  library/save, RAG context from user's notes/PDFs/past chats via Azure AI Search.
- **Calculator**: in-app WebView → ClinCalc (owner-approved swap from MDCalc).
- **Knowledge Hub**: PDF upload/folders/viewer, highlights + text-note annotations,
  full-text search (Azure, BM25 + semantic reranker), server-stored PDFs.
- **Ward Companion**: shifts/patients/tasks/handover + hard-delete wipe.
- **Exam Planner**: 16 exams, Python port of the scheduling engine, daily agenda +
  dashboard, focus timer widget.
- **OSCE Prep**: 29 stations/7 categories, step checklists, 10-min timer, favourites.
- **Security**: cross-user authz regression tests (`backend/tests/`), hashed
  OTP/refresh tokens, per-user search-index trimming — see SECURITY_CHECKLIST.md.

Tooling notes for this machine: Flutter SDK lives at
`~/snap/flutter/common/flutter/bin` (the bare `flutter` on PATH is a broken snap
alias — prepend that dir to PATH). Backend venv: `backend/.venv`. Device
`a895001e` (Xiaomi 23129RAA4G, Android 13) attached and authorized.

## 2. Where the previous session stopped

Phase 4 (QA/security hardening): last completed items (all 2026-08-13) were the
authz audit + tests, Azure Search integration (RAG + Knowledge Hub search), OAuth
verification, exam-planner catalog auth fix, double-back-to-exit UX, and the
security/data-retention writeups. No half-done code was found — the tree is clean
and consistent with the docs.

### 2a. This session's completed work (2026-08-13 evening)

1. **Bottom nav → 5 tabs, done.** Removed `AppNavTab.ai` from
   `frontend/lib/core/widgets/app_bottom_nav.dart`; the bar now shows exactly
   Home, Diseases, Symptoms, Formulary, Notes.
2. **Medaculous AI made globally reachable — done, via an app-bar action icon,
   not a FAB.** `frontend/lib/core/widgets/ai_fab.dart` (class still named
   `AiFab` for now) renders a small purple→indigo gradient icon button
   (`Icons.auto_awesome_rounded`, 44×44 touch target, tooltip "Medaculous AI")
   that pushes `/ai-chat`. It's wired into the `AppBar.actions` (or, on Home,
   the custom header row) of all 5 top-level screens: `home_screen.dart`,
   `systems_list_screen.dart`, `symptom_checker_screen.dart`,
   `formulary_list_screen.dart`, `notes_list_screen.dart`.
   - **Why not a `floatingActionButton`** (tried first, reverted): a FAB is a
     fixed-position overlay on top of the scrollable body. On every one of
     these 5 screens the body is a full-bleed `GridView`/`ListView` that
     already overflows its viewport, so at rest (scroll offset 0) whatever
     row/card happens to land at the bottom-right corner sits *directly under*
     the FAB — verified on-device, it covered the "Medaculous AI" home
     feature-card's description text. Tried reserving trailing scroll
     padding (doesn't move what's visible at offset 0 — padding is only
     reachable by scrolling past real content) and shrinking the viewport via
     an outer `Padding` (fixes the overlay but instead *clips* the boundary
     row — for the Home feature cards specifically, whose `Column` uses a
     `Spacer()` to bottom-align the title/description, any clip from the
     bottom deletes the text entirely, leaving only the icon). Neither is
     salvageable without hand-tuning pixel offsets per screen/device, so the
     FAB approach was abandoned. An app-bar action sits in a distinct region
     Scaffold always reserves — it structurally cannot overlap body content,
     at any scroll position or screen size. Screenshots taken on the attached
     device (a895001e) confirm no overlap on any of the 5 screens.
   - Notes screen keeps its own screen-specific "Add note" `FloatingActionButton`
     unchanged; the AI icon lives in that screen's `AppBar.actions` instead of
     being stacked with it.
   - Chat screen (`chat_screen.dart`) no longer has a `bottomNavigationBar`; it's
     a pushed screen with the default back arrow, "Library" moved to `actions`.
   - **Follow-up polish idea (not done):** rename the `AiFab` class/file to
     something like `AiAction`/`ai_action_button.dart` now that it's not a FAB —
     purely cosmetic, left as-is to minimize churn this session.
3. **Expert-grade system prompts — done.** Rewrote all backend LLM system
   prompts to consultant-level clinical quality (structured, guideline-anchored,
   explicit about uncertainty/red flags, mobile-markdown-friendly):
   `backend/app/api/v1/ai.py` (Ward/ER/Exam/Auto personas + shared
   `_CLINICAL_CORE`), `backend/app/api/v1/symptoms.py`, `backend/app/api/v1/
   pharmacy.py` (pharmacist/interaction/substitute), `backend/app/api/v1/
   formulary.py` (generate). Verified live on-device: asked "first line
   treatment for atrial fibrillation" in the Auto chat mode and got a properly
   structured scenario table (unstable → cardioversion, stable → rate control,
   CHA₂DS₂-VASc/HAS-BLED called out by name) plus a clarifying follow-up
   question — matches the "expert" bar the owner asked for.
4. **Verification — done.** `flutter analyze`: 0 errors (25 pre-existing
   `info`-level lints in untouched code, same count before/after). `dart
   format` run on all touched files. Backend: `pytest` → 15 passed (only
   benign `aiohttp` "unclosed connector" cleanup noise in logs, not failures).
   Rebuilt the debug APK and manually verified all 5 tab screens + the AI chat
   screen on the attached device (`a895001e`, already logged in as
   `talk2saadalam@gmail.com`).

### 2b. UI/UX audit pass (2026-08-13 late night) — implemented + QA'd

Owner asked for a professional UI/UX audit, fixes end-to-end first, then one QA
cycle (not fix-test-fix). All items below are shipped, rebuilt, and verified on
device `a895001e` in both themes:

1. **AI access moved again: app-bar icon → global gradient FAB** managed by a
   new `frontend/lib/core/widgets/nav_shell.dart`. `NavShell` wraps all 5
   top-level screens and auto-hides BOTH the bottom nav and the FAB(s) on
   scroll-down, restoring them on scroll-up / tap / at rest near the top (the
   owner's "reading mode" request). This also resolves the old FAB-overlap
   problem documented in §2a: the FAB gets out of the way instead of covering
   content. On Notes, `NavShell` stacks a mini AI FAB above the screen's own
   "add note" FAB.
2. **Bottom nav restyled**: rounded top corners, soft shadow, animated
   pill-shaped active indicator.
3. **Home feature cards**: larger (64 px box / 32 px icon) centered icons,
   centered titles/descriptions, matching the disease-tile look. Search bar is
   pill-shaped (as are Formulary, Knowledge Hub, and OSCE search fields).
4. **Systems view toggle**: icon/list toggle is now a full-width segmented
   control instead of two small corner buttons.
5. **Splash redesigned**: navy→purple gradient, glowing pulsing logo, tagline,
   progress spinner; plus the NATIVE Android launch screen is branded (navy +
   logo via `launch_background.xml` + `values/colors.xml`) so cold starts never
   flash white.
6. **Auth screens branded**: new `auth_header.dart` (logo, wordmark, "AI powered
   medical reference" tagline, clinician banner) on login/register/forgot.
7. **Dark theme sweep**: fixed remaining fixed-white/light surfaces — OSCE
   station header/sections, focus timer, symptom-checker patient-info card,
   medication reference boxes, pharmacy "Patient Risk Filters" card, PDF viewer
   page bar. AI chat bubbles keep a fixed light surface with an explicit dark
   markdown stylesheet, readable in both themes.
8. **AI output quality**: all backend prompts now carry absolute writing-style
   rules (no em/en dashes as punctuation, no arrows, no emojis, natural
   complete sentences, bold headings + one-idea bullets). Verified live in
   chat, symptom checker, pharmacy, and formulary output.
9. **Robustness fixes found during QA**:
   - `backend/app/services/llm.py` `_parse_json_response`: strips fences,
     trims stray prose, and falls back to `json.loads(strict=False)` — the
     model regularly emits literal newlines inside long string values, which
     strict parsing rejected and surfaced as 502 "unexpected response".
   - Symptom checker: prompt now asks for the 5–8 most relevant differentials
     (was "ALL possible", which overflowed the token cap and truncated the
     JSON); `max_tokens` raised to 8192. Formulary generate also 8192.
   - Chat stream: generation counter + 90 s stream timeout + broad exception
     handling so a dropped connection can no longer leave the input disabled.
   - Non-streaming AI endpoints: client `receiveTimeout` raised to 150–180 s
     (backend retries once on invalid JSON, which can double latency).
10. **QA cycle run** (fresh build, `adb install -r`): splash → home → symptom
    check (dark) → formulary AI profile generation (dapagliflozin, dark) →
    pharmacy recommendation (dark) → theme switch in Settings → home/chat
    stream/notes (light). `flutter analyze` 0 warnings/errors (25 pre-existing
    infos), `flutter test` passes, backend `pytest` 15 passed.

## 3. Prioritized next tasks

1. **[PDF fix, Notes #1] Pinch-to-zoom on note image previews** — confirmed still
   missing (no `InteractiveViewer` anywhere in `frontend/lib`).
2. **[PDF fix, Knowledge Hub #3] Outline/TOC navigation** — explicitly deferred
   earlier, still open.
3. ~~Cosmetic: rename `AiFab`~~ — moot, it is a FAB again (see §2b item 1).
4. Deferred scope-cut follow-ups (OPEN_QUESTIONS.md): Exam Planner weekly/monthly
   views, syllabus editor UI, topic notes/checklists screen, search modal; wiring
   `otp_cleanup`/`token_pruning` workers to a scheduler (needs deployment target).

## 4. UI mismatches vs screenshots/branding

- Screenshot `1. Homescreen.png` shows a 6-item nav bar (Home, Diseases, Symptoms,
  Formulary, Notes, AI) — **resolved this session**: bar is now 5 positions, AI
  is reachable via a gradient icon in each top-level screen's app bar (see §2a).
- Branding: owner confirmed (2026-08-13) the inferred tokens (blue-600 primary,
  Inter/Space Grotesk) stay — no separate branding doc exists in the workspace
  beyond logo PNG/GIF; theme is centralized in `frontend/lib/core/theme/`.

## 5. Open questions (unchanged, see OPEN_QUESTIONS.md)

Google/Apple OAuth client IDs, Apple dev account, iOS CI (no macOS here),
production Postgres/hosting, payment provider for the trial→subscription flow.
