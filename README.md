# Daily Sketch

Native iOS creative journal with a FastAPI backend. Every user receives the same three-word Daily Prompt; guests can sketch before authenticating.

This repository is a monorepo. Phase 2 adds Descope authentication, local user provisioning, and `GET /api/v1/me` on top of the Phase 1 contract and application shell.

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

## Phase 2 — Authentication

- **Contract:** `GET /api/v1/me` returns the current local user (id, username, display name, profile completion, account status, preferences summary). Requires `Authorization: Bearer <Descope JWT>`.
- **Backend:** Verifies Descope JWTs via JWKS (`DESCOPE_JWKS_URL`, defaulting from `DESCOPE_PROJECT_ID`), provisions a local `users` row on first login (idempotent by `descope_subject`), and rejects suspended/deleted accounts.
- **Local mock auth:** When `DESCOPE_PROJECT_ID=replace-me` (the committed placeholder), the iOS app uses `MockAuthService` and the backend accepts matching HS256 local-dev JWTs so guest → sign-in → `GET /me` works without real Descope credentials. Replace placeholders with a development Descope project ID to use Descope Flows.
- **iOS:** Guest launch is unchanged. Profile offers Create Free Account / Sign In. Sessions persist in Keychain. Settings offers Sign Out (does not delete local Drafts — none exist yet in Phase 2).
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
| `make seed` | No-op until prompt/fixture seeding arrives |
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
