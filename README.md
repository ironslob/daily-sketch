# Daily Sketch

Native iOS creative journal with a FastAPI backend. Every user receives the same three-word Daily Prompt; guests can sketch before authenticating.

This repository is a monorepo. Phase 12 delivers local reminders, recovery hardening, accessibility polish, privacy-conscious analytics, and offline-aware Home behaviour on top of Phase 11’s safety features.

## Prerequisites

- Python 3.14
- [uv](https://github.com/astral-sh/uv)
- Docker and Docker Compose
- Xcode 16+ with an iOS 18 simulator
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Node.js / npx (OpenAPI Swift client generation)
- Make

## Quick start

```bash
cp .env.example .env
make backend-install
make up
curl http://localhost:8000/health/live
curl http://localhost:8000/health/ready
make db-migrate
make seed
```

Generate and open the iOS project:

```bash
make ios-generate
open ios/DailySketch.xcodeproj
```

Or build from the CLI:

```bash
make ios-build
```

## Repository layout

| Path | Purpose |
| --- | --- |
| `api/openapi/` | OpenAPI contract (source of truth) |
| `api/generated/` | Generated Swift client — do not edit by hand |
| `backend/` | FastAPI application, Alembic migrations, tests |
| `ios/` | SwiftUI app (`DailySketch`) |
| `spec/` | Product, design, architecture, implementation, infrastructure |

## Phase 12 — Notifications, Recovery, Accessibility, and Polish

- **Local daily reminders:** `Core/Notifications/` schedules iOS local notifications from saved preferences (`notifications_enabled`, `notification_time_local`, timezone). Permission is requested when enabling reminders in Settings or Profile Completion; denied permission exposes an Open Settings shortcut. Tapping a reminder opens Home.
- **Recovery hardening:** Pending upload/submission resume (reuse completed `uploadId` when safe), signed-upload expiry retry, auth-expiry during publish routes back to the auth checkpoint, and offline-aware Home with disk-cached prompt/feed snapshots.
- **Accessibility and polish:** Timer `accessibilityValue`, Reduce Motion for skeleton shimmer, appearance preference wired to app `preferredColorScheme`, offline indicator, and Settings reminder time picker aligned with Stitch.
- **Product analytics:** Scrubbed local funnel events via `AnalyticsClient` (OSLog + in-memory buffer for tests). No third-party sink or sensitive payloads.
- **Tests:** Reminder schedule/reschedule, notification navigation, offline cache, auth expiry during upload, upload resume, analytics scrubbing, VoiceOver/large-type UI smoke tests.
- **Out of Phase 12:** APNs push, Activity inbox UI, analytics warehouse, Phase 13 release hardening.

## Phase 11 — Safety, Blocking, Reporting, and Account Deletion

- **Contract (public):**
  - `POST /api/v1/reports` — create a report (`submission` / `reflection` / `profile`); confirmation-only response (no moderation internals).
  - `GET /api/v1/me/blocked-users` — list users you block.
  - `PUT` / `DELETE /api/v1/users/{user_id}/block` — idempotent block/unblock.
  - `DELETE /api/v1/me` — request deletion → `202` / `pending_deletion` (optional `Idempotency-Key`).
- **Internal (not in public OpenAPI):** `/internal/moderation/*` guarded by `X-Moderation-Token` matching `MODERATION_OPERATOR_TOKEN` — list/inspect reports, hide/remove/restore content, suspend/restore users.
- **Backend:** Migration `0010_blocks_reports` (`user_blocks`, `reports`, `moderation_actions`). Reciprocal block filtering on feed, detail, reflections, and profiles. Finalize pending deletions with `make account-deletion-finalize` (`python -m app.jobs.account_deletion`). Seeds include sample blocks/reports via the safety seed.
- **iOS:** Report sheet (private copy + Block User offer), block confirmation, Blocked Users, Delete Account confirmation, Settings Safety section; guest report/block resume auth; content disappears after block.
- **ADRs:** `spec/decisions/0008-block-semantics.md`, `0009-account-deletion.md`.
- **Out of Phase 11:** Full HTTP rate-limit middleware (Phase 13); activity inbox UI; public deep links.

## Phase 10 — Public Profiles, Streaks, and Native Sharing

- **Contract:**
  - `GET /api/v1/users/{username}` — public profile with `avatar_url`, `submission_count`, `current_streak`, and `is_self` (optional auth). Incomplete/suspended/deleted profiles → `404`.
  - `GET /api/v1/users/{username}/submissions` — reverse-chronological cursor page reusing `RecentFeed` / `FeedItem`.
  - `PATCH /api/v1/me` accepts optional `avatar_upload_id`; `CurrentUser` includes `avatar_url`. Avatar consumption errors: `upload_not_found`, `upload_not_ready`, `upload_already_consumed`, `avatar_upload_invalid`.
  - `POST /api/v1/uploads` accepts `purpose: avatar` (processed like submission images).
- **Backend:** Migration `0009_avatar_upload_fk` adds FK + index on `users.avatar_upload_id`. Streak = consecutive UTC Prompt Dates with ≥1 published Submission ending today or yesterday (multiple per day count once). Avatar display URLs populate profile, me, feed, detail, and reflection authors.
- **iOS:** Own + other Profile screens with journal gallery cards, pagination, empty states, Edit Profile (username/bio + Change Photo avatar flow), settings gear on own profile. Submission Detail uses the system share sheet with a downloaded image + prompt/attribution/branding text — never a signed storage URL.
- **Out of Phase 10:** Reporting, blocking, account deletion (Phase 11); activity inbox UI; public deep-link infrastructure.

## Phase 9 — Likes and Reflections

- **Contract:**
  - `PUT /api/v1/submissions/{submission_id}/like` / `DELETE .../like` — authenticated Like/Unlike; returns `LikeState` (`liked`, `like_count`). Idempotent; self-Like allowed.
  - `GET /api/v1/submissions/{submission_id}/reflections` — guest-readable, oldest→newest cursor page (`ReflectionList`).
  - `POST /api/v1/submissions/{submission_id}/reflections` — authenticated + complete profile + `Idempotency-Key`; body max length from `REFLECTION_MAX_LENGTH` (default 500).
  - `DELETE /api/v1/reflections/{reflection_id}` — author-only soft-delete (`204`).
- **Backend:** Migration `0008_likes_reflections_activity` (`submission_likes`, `reflections`, `activity_events`). Conflict-safe counter updates; activity events for non-self actions only. Feed/detail `viewer_has_liked` is real (batch lookup on feed).
- **iOS:** Optimistic Like on feed cards and detail (rollback on failure); Reflection thread + composer on detail; guest writes present the auth sheet and resume on success.
- **Out of Phase 9:** Activity inbox UI (later); reporting/blocking (Phase 11). Public profiles, streaks, and native share landed in Phase 10.
## Phase 8 — Community Feed and Submission Detail

- **Contract (guests + optional auth):**
  - `GET /api/v1/feed/recent` — reverse-chronological cursor-paginated feed (`published_at DESC, id DESC`) with full `FeedItem` projections (image URLs, user/prompt summaries, timer metadata, caption preview, Like/Reflection counts, `viewer_has_liked`, `is_owner`).
  - `GET /api/v1/submissions/{submission_id}` — community detail; excludes soft-deleted/hidden/removed content and suspended/deleted authors.
- **Backend:** Keyset cursor pagination (`invalid_cursor` → 422), single joined query (no N+1), published + active-author filtering, Phase 11 block-filter seam. Counts come from denormalised columns; Like state is Phase 9.
- **iOS:** Home renders `SubmissionCard` list with pull-to-refresh and infinite scroll; artwork opens Detail; owner opens public Profile. Detail shows owner row, prompt chips, date/timer, caption, social row, and owner delete with confirmation. Shared `URLCache` backs image loading.
- **Out of Phase 8:** Real Likes/Reflections (Phase 9), full public profiles/streaks/native share (Phase 10), reporting/blocking (Phase 11).

## Phase 7 — Direct Upload and Submission Publication

- **Contract (authenticated unless noted):**
  - `POST /api/v1/uploads` — create a pending upload slot with a signed `PUT` URL (`Idempotency-Key` optional).
  - `GET /api/v1/uploads/{upload_id}` — fetch owned upload status.
  - `POST /api/v1/uploads/{upload_id}/complete` — verify object, process image, mark `ready`.
  - `POST /api/v1/submissions` — atomically publish (`Idempotency-Key` required semantics + 7-day TTL).
  - `GET /api/v1/submissions/{submission_id}` — public detail with optional auth (`is_owner` / `viewer_has_liked`).
  - `DELETE /api/v1/submissions/{submission_id}` — owner soft-delete (`204`; subsequent `GET` → `404`).
- **Storage:** MinIO/S3 via boto3 (`MinioStorageAdapter`). Server uses `STORAGE_ENDPOINT`; signed URLs handed to clients use `STORAGE_PUBLIC_ENDPOINT` when set (e.g. `http://localhost:9000`).
- **Image processing:** Synchronous Pillow on complete — decode/validate, strip EXIF, normalise orientation, write display + thumbnail derivatives (see `spec/decisions/0006-s3-direct-uploads.md`, `0007-synchronous-image-processing.md`).
- **Database:** `uploads` + `submissions` (migration `0007_uploads_submissions`) with counters, unique session/upload FKs, and feed-oriented indexes.
- **iOS:** Review → create upload → signed PUT (progress) → complete → create submission; Draft deleted only after confirmed publication; local `PublishedSubmissionStore` drives Home “You sketched today” / View My Sketch / Create Another; minimal Submission Detail fetches `GET /submissions/{id}`. Profile-incomplete publishing routes to profile completion. Duplicate-safe retry reuses a persisted Idempotency-Key on the Draft.
- **Tests:** Backend contract/integration tests use an in-memory fake storage adapter (CI does not require live MinIO for the default suite). Optional MinIO adapter tests run with `STORAGE_TEST=1`.
- **Out of Phase 7:** Community feed cards/pagination, likes, reflections, full social Submission Detail, avatars, notifications, queues/Redis.

## Phase 6 — Camera, Local Drafts, and Review Submission

- **Local only (at delivery):** Camera capture, Drafts, and Review UI. Server upload and Submission publication arrive in Phase 7 (above).
- **Capture:** After Finish / Take Photo, a focused “Add your sketch” screen offers **Take Photo** (native camera) and **Choose from Library** (`PhotosUI`). Camera permission denial still allows library selection and deep-links to Settings.
- **Review Submission:** Mandatory **Ready to share?** screen with image preview, prompt + timer metadata, optional caption (280 chars), **Replace/Retake**, **Submit to Community**, and **Save to Drafts**.
- **Drafts:** Metadata in Application Support JSON (`DraftStore`); JPEG files under `Application Support/DailySketch/Drafts/` with complete file protection (`DraftImageStore`). Never UserDefaults for image bytes. Retention purge defaults to 30 days on Home load.
- **Guest checkpoint:** **Save Your Creativity** preserves the Draft through Create Account / Sign In and returns to Review; **Continue Later** saves and returns Home.
- **Home recovery:** Draft card (**Ready when you are**) with Continue / Discard.
- **Permissions:** `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` in `Info.plist`.

## Phase 5 — Sketch Sessions and Timer Flow

- **Contract (authenticated):**
  - `POST /api/v1/sketch-sessions` — start a session (`201`). Optional `Idempotency-Key` header for safe retries.
  - `GET /api/v1/sketch-sessions/{session_id}` — fetch an owned session (`session_not_found` for missing/non-owner).
  - `POST /api/v1/sketch-sessions/{session_id}/events` — record lifecycle events (`paused`, `resumed`, `timer_completed`, `finished_early`, `photo_step_reached`, `abandoned`, …).
  - `POST /api/v1/sketch-sessions/{session_id}/abandon` — abandon (idempotent when already abandoned).
- **Database:** `sketch_sessions` + `sketch_session_events` (migration `0005_sketch_sessions`); `idempotency_keys` (migration `0006_idempotency_keys`). Reuses existing `timer_mode` enum; durations `{60,180,300,600}`.
- **iOS Timer Flow:** Timer Selection sheet (1/3/5/10 min + No timer, Remember off by default). Remembered choice bypasses the sheet (guest via UserDefaults; authenticated via preferences). Active Sketch supports countdown, pause/resume, finish, cancel confirmation, and recovers after interruption. Guests keep sessions local-only. Authenticated session-create/event failures continue the timer locally and mark sync pending.
- **Photo step:** Finish / Take Photo continues into Phase 6 capture → Review Submission.

## Phase 4 — Daily Prompt and Home experience

- **Contract (public; guest + authenticated):**
  - `GET /api/v1/prompts/today` — published Daily Prompt for the current UTC Prompt Date.
  - `GET /api/v1/prompts/{prompt_id}` — published Daily Prompt by ID.
  - `GET /api/v1/feed/recent` — cursor-paginated recent feed (empty until Submissions exist in Phase 7/8).
- **Database:** `daily_prompts` table (migration `0004_daily_prompts`) with `prompt_status` enum (`draft|published|withdrawn`). One prompt per `prompt_date`.
- **Prompt Date:** Global boundary at **00:00 UTC** (see `spec/decisions/0005-global-prompt-date-boundary.md`). All clients see the same current Prompt.
- **Seed:** `make seed` runs `python -m app.seeds.prompts --days 30` to deterministically upsert today plus 30 future published prompts from `backend/app/data/prompt_words.txt`.
- **iOS Home:** Three-word `PromptGroup`, Start Sketch → Phase 5 timer/session flow, and Community Sketches with independent prompt/feed loading, empty, and error/retry states. Feed failure never blocks the prompt or Start Sketch.
- **Out of Phase 4:** SubmissionCard image feed / infinite scroll (Phase 8).

## Phase 3 — Profile completion and preferences

- **Contract:**
  - `PATCH /api/v1/me` — update username, display name, and optional bio; completing username + display name marks the profile complete.
  - `GET /api/v1/me/preferences` / `PATCH /api/v1/me/preferences` — server-backed reminder, timer, timezone, and appearance preferences.
  - `GET /api/v1/users/{username}` — public-safe profile projection (no auth required).
- **Database:** `user_preferences` table (migration `0003_user_preferences`) with `timer_mode` and `appearance` enums. Username uniqueness remains case-insensitive via `users.username_normalized`.
- **Username rules (Phase 3 assumption):** `^[A-Za-z0-9_]{3,30}$`, reserved names rejected, availability resolved on save (`409 username_taken`).
- **iOS:** Profile completion onboarding after first sign-in; Settings includes profile summary, reminder, timer preference, appearance, and Sign Out. Incomplete profiles are routed to completion before publish-gated actions.
- **Out of Phase 3:** avatar upload, live username-availability endpoint, submission/streak counts on public profiles, local notification scheduling.

## Phase 2 — Authentication

- **Contract:** `GET /api/v1/me` returns the current local user (id, username, display name, profile completion, account status, preferences summary). Requires `Authorization: Bearer <Descope JWT>`.
- **Backend:** Verifies Descope JWTs via JWKS (`DESCOPE_JWKS_URL`, defaulting from `DESCOPE_PROJECT_ID`), provisions a local `users` row on first login (idempotent by `descope_subject`), and rejects suspended/deleted accounts.
- **Local mock auth:** When `DESCOPE_PROJECT_ID=replace-me` (the committed placeholder), the iOS app uses `MockAuthService` and the backend accepts matching HS256 local-dev JWTs so guest → sign-in → `GET /me` works without real Descope credentials. Replace placeholders with a development Descope project ID to use Descope Flows.
- **iOS:** Guest launch is unchanged. Profile offers Create Free Account / Sign In. Sessions persist in Keychain. Settings offers Sign Out (local Drafts are preserved).
- **Secrets:** Never commit real Descope management secrets. Project ID is public configuration only.

## Phase 1 conventions

- **API prefix:** Feature routes use `/api/v1`. Health probes stay at `/health/live` and `/health/ready`.
- **Auth scheme:** `bearerAuth` (Descope JWT) is defined in the contract and applied to authenticated feature endpoints.
- **Errors:** Responses use the shared `Error` envelope (`error.code`, `error.message`, `error.details`, `error.request_id`).
- **Pagination:** List endpoints use the shared `CursorPage` shape (`items`, `next_cursor`).
- **Request ID:** Every response includes `X-Request-ID`. Clients may supply one; otherwise the server generates a UUID. The same value appears in error bodies.
- **Backend foundations:** Structured JSON logging, injectable UTC clock, and a storage adapter interface (implementation in Phase 7).
- **iOS shell:** Two tabs (Home, Profile), settings route from Profile, semantic design tokens, and reusable buttons / loading / empty / error components.

## Make targets

| Target | Description |
| --- | --- |
| `make up` / `down` / `logs` | Local Docker Compose services |
| `make backend-install` | Create Python 3.14 venv and install deps |
| `make backend-run` | Run API with reload on `:8000` |
| `make backend-test` / `lint` / `typecheck` | Backend quality gates |
| `make db-migrate` / `db-reset` | Alembic migrate (reset destroys local volume) |
| `make seed` | Seed today + future Daily Prompts |
| `make api-validate` | Validate OpenAPI |
| `make api-generate-ios` | Regenerate Swift client |
| `make api-check-generated` | Fail if generated client is stale |
| `make repo-checks` | Spec presence, migration names, large-file policy |
| `make docker-build` | Build backend image |
| `make ios-generate` / `ios-build` / `ios-test` | XcodeGen + simulator |
| `make clean-local` | Remove Compose volumes and local caches |

## Local services

Docker Compose provides:

- PostgreSQL 18 on `localhost:5432`
- MinIO on `localhost:9000` (console `:9001`)
- Backend API on `localhost:8000`

Credentials are local placeholders only — see `.env.example`. Never commit real Descope, database, or storage secrets.

## iOS configuration

- Display name: **Daily Sketch**
- Module: `DailySketch`
- Minimum iOS: **18.0**
- Bundle ID placeholder: `com.example.dailysketch.dev`
- Apple Team ID is not committed; set `DEVELOPMENT_TEAM` locally when needed
- Debug builds use `API_BASE_URL=http://localhost:8000`, `APP_ENVIRONMENT=local`, and `DESCOPE_PROJECT_ID=replace-me`

## OpenAPI workflow

```bash
make api-validate
make api-generate-ios
make api-check-generated
```

CI fails when generated clients drift from `api/openapi/openapi.yaml`.

## Specs

Authoritative documents live in `spec/`. Architectural decisions are recorded under `spec/decisions/`.
