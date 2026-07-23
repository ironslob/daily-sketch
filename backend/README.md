# Daily Sketch backend

FastAPI application for Daily Sketch. See the repository root README for local setup.

## Phase 4 — Daily Prompt and empty feed

- **Endpoints:** `GET /api/v1/prompts/today`, `GET /api/v1/prompts/{prompt_id}`, `GET /api/v1/feed/recent` (all unauthenticated).
- **Service rules:** Only `published` prompts are returned. `GET /prompts/today` ensures a published row for the UTC Prompt Date (deterministic on-demand create under a transaction-scoped advisory lock). Existing draft/withdrawn rows are not overwritten (`404 prompt_not_found`). Missing id → `404 prompt_not_found`. Feed returns `{ "items": [], "next_cursor": null }` until Submissions exist.
- **Clock:** `PromptService` uses injectable `Clock.today()` (UTC calendar date).
- **Jobs:** `missing_prompt_check` ensures published prompts for today and tomorrow via the same helper (dry-run checks only).
- **Seed:** `make seed` / `uv run python -m app.seeds.prompts` upserts deterministic three-word prompts for bulk future coverage (same generator as on-demand). `uv run python -m app.seeds.safety` seeds sample block relationships and open reports for local testing.

## Phase 11 — Safety

- **Public:** reports, blocked-users, block/unblock, `DELETE /me` → `pending_deletion`.
- **Internal:** `/internal/moderation/*` with `X-Moderation-Token` / `MODERATION_OPERATOR_TOKEN`.
- **Finalize:** `make account-deletion-finalize`.
- **ADRs:** `0008-block-semantics`, `0009-account-deletion`.

## Phase 2 — Authentication and user provisioning

- **JWT verification:** Descope session JWTs are verified with the official `descope` Python SDK (`DescopeClient.validate_session`), including JWKS caching/rotation, issuer, audience, expiry, and `sub`/`userId`.
- **Local mock:** When `DESCOPE_PROJECT_ID=replace-me`, the backend uses `LocalDevTokenVerifier` (HS256) so the iOS mock auth path can call `GET /api/v1/me` without a real Descope project.
- **Provisioning:** First authenticated request creates a `users` row keyed by immutable `descope_subject` (`status=incomplete`). Repeated logins resolve the same user. Suspended accounts return `403 account_suspended`; deleted/pending-deletion return `403 account_unavailable`.
- **Endpoint:** `GET /api/v1/me` returns public-safe current-user fields plus a preferences summary (Phase 2 defaults; persisted preferences arrive in Phase 3).

## Phase 1 foundations

- **Settings:** Typed configuration via `app.core.settings` (`APP_ENV`, database, storage, Descope project ID, `RELEASE_VERSION`, `COMMIT_SHA`, `REQUEST_TIMEOUT_SECONDS`, `PROMPT_DATE_TIMEZONE=UTC`).
- **Request ID:** `RequestIDMiddleware` reads or generates `X-Request-ID` and returns it on every response.
- **Errors:** Domain `AppError` and framework exceptions render the shared OpenAPI `Error` envelope.
- **Logging:** Structured JSON logs include request ID, route, method, status, latency, environment, and release version.
- **Clock:** Injectable `Clock` / `SystemClock` (UTC) for Prompt Date and later domain timing.
- **Storage:** `StorageAdapter` protocol implemented by `MinioStorageAdapter` (S3-compatible). Direct signed uploads, derivative generation, and signed reads are live.
- **Routing:** Health probes at `/health/*`. Versioned feature mount at `/api/v1`.

## Useful commands

```bash
make up                 # Postgres + MinIO + hot-reload API (migrate-on-start)
make seed
make backend-shell
make backend-test
make backend-lint
make backend-typecheck
make db-migrate
make db-revision m=add_foo   # autogenerate next Alembic revision from models
make db-check                # fail if models drift from applied schema
make logs
make down
```

### Schema migrations

1. Change SQLAlchemy models under `app/models/` (indexes and constraints belong on the models).
2. Generate a revision: `make db-revision m=short_slug` (optional `msg="Human message"`).
3. Review the generated file under `migrations/versions/`, then apply with `make db-migrate`.
4. Keep revision ids ≤32 characters (`NNNN_` + slug) — Postgres `alembic_version.version_num` is `VARCHAR(32)`.

Do not hand-write routine DDL; use autogenerate and only edit the revision when Alembic needs a nudge (data backfills, enum renames, deferred FKs).

Optional host venv (CI and OpenAPI validate without Compose):

```bash
make backend-install
make backend-run
```
