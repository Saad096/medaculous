# Medaculous — Phase 0 Discovery Report

Source codebase: repo root (`/home/saad-alam/Documents/assignments/projects/medaculous/Medaculous v1 ZIP/`) — a Google AI Studio "remix" build. React 19 + Vite 6 + TypeScript, Tailwind v4 (CSS-based theme), Firebase SDK present but unmounted, Google Gemini (`gemini-3.5-flash`) as the only LLM in use today. `metadata.json` internally names it `"Remix 4 : Without Signin and backend"` — this is the previous engineer's own label confirming auth/backend were deliberately stripped from what was otherwise a more complete app, with the stripped code left in the tree rather than deleted.

This report is the Phase 0 contract for everything that follows (Flutter frontend, FastAPI backend). Nothing in Phase 1/2 should contradict it without updating this file.

---

## 1. Business Logic Inventory (11 features + Settings)

Cross-referenced against `Medaculous 11 features with Fixes recquired.pdf` (product owner's own feature/fix list) and direct code reading. Each entry: **purpose**, **current implementation**, **fixes required per the PDF**, **migration note**.

### Settings / App Shell
- **Current**: Dark-mode toggle, personal Gemini API key entry (paste/test/save/remove, `localStorage`), client-side RPM usage bar (display-only, not enforced), feedback mailto link. Onboarding/disclaimer flow is hardcoded to "already seen" — effectively disabled.
- **Fixes required (PDF)**: Add email/Google sign-in at startup enabling cross-platform sync of Notes, Exam Planner, Knowledge Hub, subscription; **3-day trial**. Remove manual API-key UI; manage keys server-side with fallback keys.
- **Migration note**: The exact auth UX (login/register/reset, Google sign-in) already exists fully built in `SyncSettings.tsx` + `AuthContext.tsx`, just never mounted (see §3). Treat as reference implementation for the new backend-driven auth, not a template to reuse client-side (it talks to Firebase; the new client will talk to FastAPI).

### 1. Systems (disease reference library)
- **Purpose**: 15 body systems → ~430 diseases, each with 16 fixed content sections (Definition, Classification, Signs/Symptoms, Anatomy, Pathophysiology, Approach, Investigations, Diagnosis, Differentials, Patient Advice, Management, Prescribing Info, Calculators, Evidence, Complications, Notes) plus per-disease user Notes (text + image attachments).
- **Current implementation**: Content lives as **430 hardcoded TypeScript modules directly inside `src/components/`** (`Record<string,string>` of markdown per section), routed through a manual lazy-import map in `DiseaseDetail.tsx`. This is the single largest content-migration payload.
- **Fixes required (PDF)**: Needs a backend so content can be created/edited per-topic (currently requires a code change + redeploy to edit any disease). Needs rich-text formatting support (bold/bullets) in that content.
- **Migration note**: Port to Postgres `diseases` / `disease_sections` tables, admin-editable. Per-disease user notes/images (`localStorage["disease_notes_<name>"]`, `disease_images_<name>`) map directly to a `user_disease_notes` table once auth exists.

### 2. Symptoms (AI symptom checker)
- **Purpose**: Enter symptom(s) + age/sex → ranked differential diagnosis with rationale, next steps, investigations, red flags.
- **Current implementation**: Single Gemini call, `responseSchema`-constrained JSON (`SymptomsDiagnoser.tsx`).
- **Fixes required (PDF)**: None — preserve as-is.
- **Migration note**: Prompt/schema ports directly to `services/llm.py`; no client-side business logic to preserve beyond the prompt itself.

### 3. Symptom-Based Drug Recommendations
- **Purpose**: AI "clinical pharmacist" — symptom + risk-factor form (country, age, weight, pregnancy/breastfeeding, allergies, renal/hepatic impairment) → tiered OTC/symptomatic recommendations; plus a drug-interaction checker and therapeutic-substitution finder; favorites list.
- **Current implementation**: `SymptomBasedRecommendations.tsx` tries a server endpoint first (`/api/symptom-recommendations` etc. in the legacy `server.ts`), falling back to an inlined duplicate Gemini call when no server is reachable. **The server.ts versions are the canonical prompts/schemas** — this dual-path pattern is the strongest signal for what to port.
- **Fixes required (PDF)**: None — preserve as-is.
- **Migration note**: Port the three `server.ts` endpoints (`/api/symptom-recommendations`, `/api/check-interactions`, `/api/find-substitutes`) verbatim in intent to FastAPI routes; drop the client-side Gemini fallback entirely (mobile app should always go through the backend).

### 4. Formulary
- **Purpose**: ~100 curated drugs, organized System → Class → Drug, with a 12-section drug detail view (MOA, dosing, contraindications, interactions, pregnancy/lactation, monitoring, PK, AI clinical notes). Unknown/searched drugs trigger AI-generated monograph creation, which is cached and becomes part of the permanent formulary.
- **Current implementation**: Static `formularyData.ts` + client-side Gemini generation cached to `localStorage`; a background hook (`useFormularySync.ts`) pre-warms the entire formulary via Gemini on every client, one drug at a time — fragile and quota-wasteful at scale.
- **Fixes required (PDF)**: None on feature scope, but the "generate once, cache forever" pattern needs a real backend design.
- **Migration note**: Move generation to a server-side batch job writing to Postgres `drug_profiles` once, shared by all users, instead of every client re-generating. `cleanClassName()` (~50-entry pharma-class normalization table) ports directly.

### 5. Notes
- **Purpose**: Rich-text notes (iOS-Notes-like) with folders, images, freehand drawing, search, trash/restore, pin, manual reorder, JSON export/import, cross-device sync.
- **Current implementation**: `Notes.tsx` (2564 lines, largest file in the app) — TipTap-based editor, fully local (`localStorage`), plus an orphaned Firestore sync path and a separate abandoned LAN-WebSocket pairing sync (`server.ts /api/sync-ws`) — three sync mechanisms, none reaching a real always-on cloud backend today.
- **Fixes required (PDF)**: Image preview needs pinch-to-zoom (currently missing). Sync reliability needs verification once real accounts exist.
- **Migration note**: `Note`/`Folder`/`Attachment` types port directly to Postgres tables. Drop the LAN-WebSocket sync entirely (doesn't translate to mobile-only, no shared LAN server) in favor of real cloud sync via the FastAPI backend.

### 6. Medaculous AI (chat assistant)
- **Purpose**: Streaming medical chat with 3 modes (Ward/ER/Exam) plus auto-detect, save-to-library, AI-mistake disclaimer on every response.
- **Current implementation**: `MedaculousAI.tsx`, `gemini-3.5-flash` hardcoded, full conversation history replayed every turn.
- **Fixes required (PDF)**: Model must be swappable/upgradeable, not hardcoded.
- **Migration note**: This is exactly what `services/llm.py`'s model-tier wrapper (§4.5 of the master spec) is for — route "Medaculous AI" chat through the Sonnet-tier default, keep mode system prompts, keep the disclaimer footer as a non-negotiable UI element.

### 7. Calculator
- **Purpose**: Access to validated medical calculators without leaving the app.
- **Current implementation**: A single `<iframe src="mdcalc.com">` (`CalculatorEmbed.tsx`). A nicer searchable picker (`CalculatorDashboard.tsx`/`CalculatorDetail.tsx`) and calculator catalogs exist in the codebase but are **fully built and never wired in** — dead code. **No native calculation logic exists anywhere in the codebase** — every "calculator" is a link-out object, not a formula.
- **Fixes required (PDF)**: None — explicitly confirmed as just an in-app WebView.
- **Migration note**: Low complexity — a Flutter WebView pointed at MDCalc satisfies the spec as written. Flag to product owner: if in-app native calculators (BMI, CHA2DS2-VASc, CURB-65, etc.) are ever wanted, they need to be built from scratch — nothing to port.

### 8. Knowledge Hub
- **Purpose**: Personal PDF library (user-uploaded guidelines/textbooks) with folders, search, viewer, annotations, bookmarks.
- **Current implementation**: `KnowledgeHub.tsx` + `PdfViewer.tsx`, IndexedDB-backed (`idb`), `pdfjs-dist` (worker loaded from a CDN, a network dependency to flag), Konva-based annotation layer (`PdfDrawingLayer.tsx`) plus a separate freehand canvas tool (`DrawingCanvas.tsx`) shared with Notes.
- **Fixes required (PDF)**: Rendering is blurry — needs sharper output. Annotation tools are clunky/broken — needs a real working implementation. Add outline/TOC navigation for PDFs with embedded outlines.
- **Migration note**: This is the single biggest offline-only gap today (never syncs to any cloud store). Decide (→ OPEN_QUESTIONS) whether Knowledge Hub becomes server-synced in the mobile app or stays device-local; either way the annotation/rendering engine needs re-selection for Flutter (native PDF renderer, not pdf.js).

### 9. Ward Companion
- **Purpose**: Ward-round workspace — patient list, task checklist, one-tap handover summary, "delete all shift data" for confidentiality.
- **Current implementation**: `WardCompanion.tsx` (2027 lines) — pure local CRUD, zero network calls, PDF export via `jspdf`. `localStorage["wc_shift"]`, `wc_patients`, `wc_tasks`.
- **Fixes required (PDF)**: None.
- **Migration note**: Cleanest migration target — direct 1:1 mapping to `Shift`/`Patient`/`Task` Postgres tables. Confidentiality requirement (explicit shift-data purge) should carry into the new data-retention design (§5 of master spec).

### 10. Exam Planner
- **Purpose**: Personalized study-schedule generator across 16 postgraduate exams (PLAB, MRCP, USMLE, FCPS, AMC, MCCQE, DHA, HAAD, SMLE, Prometric, custom) — wizard setup, daily/weekly/monthly views, spaced-repetition revision scheduling, readiness score, streaks, Pomodoro-style focus, syllabus editor.
- **Current implementation**: `ExamPlanner/` (11 files, ~4600 lines) + a genuine scheduling algorithm in `examPlannerEngine.ts` (427 lines, pure functions: schedule generation, adaptive catch-up, spaced-repetition intervals, readiness-score formula). Fully local (`localStorage` blob), no AI, no auth.
- **Fixes required (PDF)**: None.
- **Migration note**: The scheduling engine is real, non-trivial business logic — port its algorithms (not just data shape) to Python for the backend, or re-implement in Dart if scheduling should run client-side; either is defensible, flag as open question if the owner has a preference. Data model normalizes cleanly to Postgres (Exam, UserExamSetup, Topic, ScheduledSession, TopicUserMeta, Streak).

### 11. OSCE Preparation
- **Purpose**: Step-by-step clinical exam practice checklists across 29 stations/7 categories, with a 10-minute practice timer, bookmarking/filtering.
- **Current implementation**: `OscePrep/` (3 files, ~857 lines), fully local (`localStorage`), no AI, no auth.
- **Fixes required (PDF)**: None.
- **Migration note**: Clean, self-contained migration target — `OsceStation`/`OsceSection`/`OsceStep` port directly to Postgres; per-user progress/favorites become user-scoped tables once auth exists.

---

## 2. Current Architecture Snapshot

### Data model (today)
All *user-generated* content design already exists as a working Firestore schema (unused in the shipped app, but real and pointed at a live Firebase project `gothic-helper-wn50x`):
```
/users/{userId}                              -> { uid, email, lastSync? }
/users/{userId}/notes/{noteId}                -> Note
/users/{userId}/folders/{folderId}            -> Folder
/users/{userId}/diseaseNotes/{diseaseName}    -> per-disease free-text notes
/users/{userId}/drugProfiles/{drugId}         -> AI-generated drug monographs (opaque JSON string)
/users/{userId}/customDrugs/{drugId}          -> user-added drugs (opaque JSON string)
/users/{userId}/diseaseImages/{diseaseName}   -> base64/URL image arrays (opaque JSON string)
/feedback_reports/{reportId}                  -> create-only, unreadable by users
```
Reference/static content (diseases, formulary, OSCE stations, exam syllabi) ships as bundled TS files, never touches Firestore. Recommendation: normalize the opaque-JSON-string fields into real Postgres columns rather than reproducing the Firestore blob pattern.

### Auth (today)
A **complete, functional Firebase email/password + Google-OAuth flow exists** (`AuthContext.tsx`, `SyncSettings.tsx`, `syncService.ts`) but is **never mounted** — `main.tsx` only wraps the app in `NotesProvider`, not `AuthProvider`. This is exactly why the product owner's PDF says "no sign-in" even though real auth code is sitting in the tree. Treat this as reference material for the new auth's *shape* (what fields, what flows), not as code to reuse (new client talks to FastAPI/JWT, not Firebase).

### Server (today)
`server.ts` (repo root) is a real Express app, not just a static file server — it hosts the three canonical AI endpoints (§1.3) and a WebSocket LAN-pairing sync. It previously also exposed `GET /api/config`, which **returned the server's own Gemini API key in plaintext to any client that called it**, with zero legitimate callers anywhere in the frontend (confirmed via a full repo search — the app's actual "bring your own key" settings feature stores the user's own key in `localStorage` and never touches this route). **FIXED (task #5, 2026-08-13): the dead `/api/config` route was deleted outright** rather than gated behind auth, since nothing needs it and removing it eliminates the exposure entirely. This is a security bug to be aware of and explicitly not repeat — the new FastAPI backend must proxy all LLM calls server-side and never expose provider keys to any client.

### Sync/offline (today)
Three separate, non-overlapping mechanisms: (1) orphaned Firestore cloud sync, (2) an abandoned LAN WebSocket peer-pairing relay (won't translate to mobile), (3) IndexedDB for the Knowledge Hub PDF library (fully local, never syncs anywhere). The mobile rebuild should consolidate all of this into one cloud-sync path through the new backend.

### No shared component library
`src/components/ui/` contains only a Framer Motion animation-wrapper file — every screen hand-rolls its own Tailwind styling. There is no Button/Card/Input/Dialog design system to port; the Flutter `lib/core/theme/` will be authored from scratch, informed by the extracted tokens below.

---

## 3. Extracted Design Tokens

**Confidently explicit** (found directly in code, safe to adopt as-is):
- **Fonts**: Inter (body/UI), Space Grotesk (headings/display).
- **Type scale**: informal but consistent micro-scale at 10/11/12/13/14/15/16/17px — matches iOS Human Interface Guidelines sizing (17px body, 11px caption).
- **Radius**: skewed large/soft — cards/panels `xl`/`2xl` (12–16px), modals/hero `3xl` (24px), small controls `lg`/`md`. No sharp corners anywhere.
- **Motion**: consistent "soft scale + fade" idiom, never slide-based. Global button press: 200ms ease, scale-to-0.95 on tap (applied via a repo-root codemod, `apply-animations.cjs`, to nearly every button in the app — confirms this was intended as a universal interaction, not per-component). Page transitions: spring (`stiffness:300, damping:25`) scale+fade, direction-aware. Modals: 0.2s scale+fade. Lists: staggered children, 0.05s stagger.
- **Icons**: `lucide-react` exclusively (thin/rounded line-icon style, matches the soft-radius aesthetic).
- **Dark mode**: manual toggle (not system-based), persisted, `.dark` class + Tailwind `dark:` variants used 896 times — dark mode is a first-class citizen, not an afterthought.
- **Logo** (`public/logo.png`, canonical brand mark): dark navy background; stylized "M" in a purple→magenta gradient with a white medical-cross notch; a light-purple neural-network/brain motif above the M; wordmark "medaculous" + tagline "AI POWERED MEDICAL REFERENCE" below.

**Inferred, not formally declared** (reasonable defaults, flag to product owner if a real brand color exists):
- **Primary color**: Tailwind blue-600 (`#2563eb`) / blue-500 (`#3b82f6`) — most-used accent for active nav/links/primary actions, but never declared as a theme token; it's just Tailwind's stock default used most often.
- **"AI feature" accent family**: purple/indigo/pink/emerald — evidenced by the logo's gradient, the AI-chat "thinking" orb gradient (`purple→blue→emerald`), and a `sparkle-glow` CSS keyframe cycling the same three hues, but never formalized as tokens.
- **Semantic colors** (convention only, not enforced anywhere): emerald = success, red = danger, amber = warning.

**Inconsistency found, do not replicate**: The PWA manifest icons (`pwa-192x192.svg`/`pwa-512x512.svg`) are a generic blue-square-with-white-cross placeholder that does not match the actual brand mark, and the manifest's `theme_color`/`background_color` are white — also mismatched with the dark-navy/purple logo. Use `logo.png`'s actual palette for the Flutter app icon and splash screen, not these placeholders.

**Cannot fully verify**: the animated `Medaculous logo GIF.gif`'s full motion sequence — only its first frame could be inspected. Composition matches the static logo with a possibly more saturated gradient and a subtle glow; likely the intended animated splash, but the actual animation curve is unconfirmed → flag as open question if pixel-perfect splash replication matters.

---

## 4. Screen Gap List (what must be newly built, not migrated)

None of the following exist in the current app in any reachable form — all are net-new for the Flutter rebuild, per the master spec's §3.2 minimum screen inventory:

- Splash (branded, animated logo reveal)
- Onboarding carousel (2–3 slides, skippable) — the existing `OnboardingTutorial.tsx` only teaches users to paste a Gemini key; not reusable content
- Login / Register / OTP verification / Forgot-Reset password — UI shape can reference the orphaned `SyncSettings.tsx`, but must be rebuilt against the new JWT/OTP backend, not Firebase
- Continue with Google / Continue with Apple (Apple Sign-In has zero precedent in this codebase)
- Biometric unlock
- Account-locked / session-expired states
- Global network-offline banner, generic error screen, empty-state illustrations, loading skeletons as a *shared* system (today every screen improvises its own empty/error/loading text inline, inconsistently)
- A real Settings screen showing environment (dev/prod) indicator

---

## 5. Assumptions Made During Discovery

1. Assumed the orphaned Firebase Auth/Firestore code is *reference material only* — none of it will be reused verbatim since the new backend is FastAPI/PostgreSQL/JWT, not Firebase. If the owner intends to keep Firebase for anything (e.g., push notifications, analytics), that needs to be stated explicitly.
2. Assumed the 430 per-disease `*_DATA.ts` files represent the complete, currently-correct clinical content set to migrate as-is (content accuracy itself was not clinically reviewed — out of scope for this engineering discovery).
3. Assumed "Calculator" stays a WebView-to-MDCalc per the PDF's explicit "no fix needed," not a request for native calculators, despite `CalculatorDashboard.tsx`/`CalculatorDetail.tsx` existing as unused scaffolding for a native picker.
4. Assumed Knowledge Hub's sync status (local-only today) is a gap to close, not an intentional design choice — flagged in OPEN_QUESTIONS.md rather than decided unilaterally.
5. Assumed the LAN-WebSocket sync mechanism in `server.ts` is dead-end legacy (doesn't work on a mobile-only architecture) and will not be ported.

See `docs/OPEN_QUESTIONS.md` for everything that genuinely needs the product owner's input before it can be finalized.
