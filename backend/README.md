# Daily Sketch backend

FastAPI application for Daily Sketch. See the repository root README for local setup.

## Phase 4 — Daily Prompt and empty feed

- **Endpoints:** `GET /api/v1/prompts/today`, `GET /api/v1/prompts/{prompt_id}`, `GET /api/v1/feed/recent` (all unauthenticated).
- **Service rules:** Only `published` prompts are returned. Missing today/id → `404 prompt_not_found`. Feed returns `{ "items": [], "next_cursor": null }` until Submissions exist.
- **Clock:** `PromptService` uses injectable `Clock.today()` (UTC calendar date).
- **Seed:** `make seed` / `python -m app.seeds.prompts` upserts deterministic three-word prompts (validated non-empty, unique within a prompt).

## Phase 2 — Authentication and user provisioning

- **JWT verification:** Descope session JWTs are verified with PyJWT `PyJWKClient` (JWKS caching/rotation), checking signature, issuer, audience, expiry, and `sub`.
- **Local mock:** When `DESCOPE_PROJECT_ID=replace-me`, the backend uses `LocalDevTokenVerifier` (HS256) so the iOS mock auth path can call `GET /api/v1/me` without a real Descope project.
- **Provisioning:** First authenticated request creates a `users` row keyed by immutable `descope_subject` (`status=incomplete`). Repeated logins resolve the same user. Suspended accounts return `403 account_suspended`; deleted/pending-deletion return `403 account_unavailable`.
- **Endpoint:** `GET /api/v1/me` returns public-safe current-user fields plus a preferences summary (Phase 2 defaults; persisted preferences arrive in Phase 3).

## Phase 1 foundations

- **Settings:** Typed configuration via `app.core.settings` (`APP_ENV`, database, storage, Descope placeholders, `RELEASE_VERSION`, `COMMIT_SHA`, `REQUEST_TIMEOUT_SECONDS`, `PROMPT_DATE_TIMEZONE=UTC`).
- **Request ID:** `RequestIDMiddleware` reads or generates `X-Request-ID` and returns it on every response.
- **Errors:** Domain `AppError` and framework exceptions render the shared OpenAPI `Error` envelope.
- **Logging:** Structured JSON logs include request ID, route, method, status, latency, environment, and release version.
- **Clock:** Injectable `Clock` / `SystemClock` (UTC) for Prompt Date and later domain timing.
- **Storage:** `StorageAdapter` protocol with a Phase 1 `NotConfiguredStorageAdapter` stub. Signed uploads arrive in Phase 7.
- **Routing:** Health probes at `/health/*`. Versioned feature mount at `/api/v1`.

## Useful commands

```bash
make backend-install
make backend-run
make backend-test
make backend-lint
make backend-typecheck
make db-migrate
make seed
```
