# Railway — shared test environment

Railway hosts a **shared remote test** backend for Daily Creative. It is not production infrastructure; use [AWS Terraform](../terraform/README.md) for staging/production targets on AWS.

## Prerequisites

- Railway account and CLI (optional)
- Descope **test** project (separate from production)
- AWS S3 bucket for media (see [Media storage](#media-storage))

## Service setup

1. Create a new Railway project and connect this repository.
2. In service **Settings**:
   - **Root Directory:** `/backend` — Railway uses this as the Docker build context (required so `COPY app`, `alembic.ini`, etc. resolve).
   - **Config as Code:** `/railway.toml` — absolute from the repo root; does **not** follow Root Directory. Clear any path pointing at `infra/railway/`.
3. Add the **PostgreSQL** plugin. Railway injects `DATABASE_URL`; convert for SQLAlchemy async if needed:

   ```
   postgresql+asyncpg://USER:PASS@HOST:PORT/DB  # pragma: allowlist secret
   ```

   Use the plugin’s credentials — do not commit them.

4. Configure **Dockerfile deploy** via the repo-root [`railway.toml`](../../railway.toml):

   - `dockerfilePath = "Dockerfile"` (relative to Root Directory `/backend`)
   - Build context is Root Directory (`/backend`), same as local `docker compose` (`context: ./backend`)

5. **Release command** (migrations): `alembic upgrade head` — runs on each deploy before traffic shifts (see `releaseCommand` in `railway.toml`). In the production image Alembic is on `PATH`; for local one-offs always use `uv run` (see below).

6. **Start command:** leave unset in the dashboard — the image runs `scripts/start.sh`, which binds to `$PORT` (Railway) or `8000` (local).

## Environment variables

Map from [`.env.example`](../../.env.example). Set these in Railway **Variables** (secrets marked 🔒):

| Variable | Notes |
|----------|--------|
| `APP_ENV` | `staging` |
| `LOG_LEVEL` | `INFO` |
| `API_PUBLIC_URL` | `https://daily-creative-production.up.railway.app` |
| `RELEASE_VERSION` | semver from release |
| `COMMIT_SHA` | git SHA (CI or manual) |
| `BUILD_TIMESTAMP` | ISO timestamp |
| `DATABASE_URL` | 🔒 From Postgres plugin (`postgresql+asyncpg://...`) |
| `DB_SSL_REQUIRE` | `true` for Railway Postgres (encrypts; does not verify the self-signed chain) |
| `DESCOPE_PROJECT_ID` | `P3GtbG5aJKoUuefcaA8DfyMzA0nK` (test project) |
| `DESCOPE_AUDIENCE` | Optional audience override (defaults to project ID) |
| `MODERATION_OPERATOR_TOKEN` | 🔒 Test-only operator token |
| `STORAGE_ENDPOINT` | `https://s3.REGION.amazonaws.com` |
| `STORAGE_PUBLIC_ENDPOINT` | CloudFront or S3 URL for signed reads |
| `STORAGE_REGION` | e.g. `eu-west-1` |
| `STORAGE_BUCKET` | See media options below |
| `STORAGE_ACCESS_KEY` | 🔒 IAM access key |
| `STORAGE_SECRET_KEY` | 🔒 IAM secret key |
| `STORAGE_USE_SSL` | `true` |
| `METRICS_ENABLED` | `true` |

Optional: `SENTRY_DSN`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `ALERT_WEBHOOK_URL`.

Never paste production Descope, moderation, or storage credentials into Railway test.

## Media storage

Railway does not host object storage. Use AWS S3:

**Option A — dedicated test bucket (recommended)**

- Bucket name e.g. `dailycreative-railway-media`
- Block public access; IAM user with `s3:PutObject`, `GetObject`, `DeleteObject`, `ListBucket` on `users/*` prefix
- Store `STORAGE_ACCESS_KEY` / `STORAGE_SECRET_KEY` in Railway secrets

**Option B — shared staging bucket**

- Reuse the Terraform staging bucket with a **separate** IAM user limited to a prefix or the whole bucket
- Keeps media near AWS staging/production patterns but mixes test data with staging — use only if intentional

Originals must not be exposed via public CDN; if using CloudFront for test, apply the same display/thumbnail-only rules as Terraform.

## Cron / background jobs

Railway does not run the Makefile job targets natively. Options:

1. **Railway cron service** (if available on your plan) — duplicate the backend service with a cron schedule and start command, e.g.:

   ```bash
   uv run python -m app.jobs.upload_cleanup
   ```

2. **GitHub Actions** — scheduled workflow calling Railway run or a one-off `railway run` from CI.

3. **Manual** — from `backend/`: `railway run uv run python -m app.jobs.upload_cleanup` for ad-hoc runs.

### Job commands (from repo `Makefile`)

| Job | Command |
|-----|---------|
| upload_cleanup | `uv run python -m app.jobs.upload_cleanup` |
| sketch_session_cleanup | `uv run python -m app.jobs.sketch_session_cleanup` |
| story_session_cleanup | `uv run python -m app.jobs.story_session_cleanup` |
| idempotency_cleanup | `uv run python -m app.jobs.idempotency_cleanup` |
| deleted_media_cleanup | `uv run python -m app.jobs.deleted_media_cleanup` |
| missing_prompt_check | `uv run python -m app.jobs.missing_prompt_check` |
| account_deletion_finalize | `uv run python -m app.jobs.account_deletion` |

Suggested schedules match Terraform EventBridge defaults (hourly/daily). Add `--dry-run` when testing.

## Deploy checklist

1. Postgres plugin attached; `DATABASE_URL` set with asyncpg driver
2. All required env vars from `.env.example` filled in Railway
3. S3 bucket + IAM keys configured
4. Deploy triggers `alembic upgrade head`
5. Smoke: `curl -fsS $API_PUBLIC_URL/health/live`
6. Seed prompts if needed (from `backend/`): `railway run uv run python -m app.seeds.prompts --days 30`

One-off migrations from your laptop (also from `backend/`):

```bash
railway run uv run alembic upgrade head
```

## Related docs

- [Staging ops](../../docs/ops/staging.md) — Compose vs Railway vs AWS
- [AWS Terraform](../terraform/README.md) — production target
