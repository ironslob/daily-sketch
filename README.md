# Daily Sketch

Native iOS creative journal with a FastAPI backend. Every user receives the same three-word Daily Prompt; guests can sketch before authenticating.

This repository is a monorepo. Phase 4 delivers today’s Daily Prompt and the Home experience on top of Phase 3 profile/preferences.

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

## Phase 4 — Daily Prompt and Home experience

- **Contract (public; guest + authenticated):**
  - `GET /api/v1/prompts/today` — published Daily Prompt for the current UTC Prompt Date.
  - `GET /api/v1/prompts/{prompt_id}` — published Daily Prompt by ID.
  - `GET /api/v1/feed/recent` — cursor-paginated recent feed (empty until Submissions exist in Phase 7/8).
- **Database:** `daily_prompts` table (migration `0004_daily_prompts`) with `prompt_status` enum (`draft|published|withdrawn`). One prompt per `prompt_date`.
- **Prompt Date:** Global boundary at **00:00 UTC** (see `spec/decisions/0005-global-prompt-date-boundary.md`). All clients see the same current Prompt.
- **Seed:** `make seed` runs `python -m app.seeds.prompts --days 30` to deterministically upsert today plus 30 future published prompts from `backend/app/data/prompt_words.txt`.
- **iOS Home:** Three-word `PromptGroup`, Start Sketch (placeholder until Phase 5 timer flow), and Community Sketches with independent prompt/feed loading, empty, and error/retry states. Feed failure never blocks the prompt or Start Sketch.
- **Out of Phase 4:** Timer Selection / Sketch Sessions (Phase 5), SubmissionCard image feed / infinite scroll (Phase 8).

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
- **iOS:** Guest launch is unchanged. Profile offers Create Free Account / Sign In. Sessions persist in Keychain. Settings offers Sign Out (does not delete local Drafts — none exist yet).
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
