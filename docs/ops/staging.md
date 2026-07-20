# Staging & deployment environments

Daily Sketch uses three deployment tiers. Pick the right one for the work you are doing.

| Tier | Tooling | Purpose |
|------|---------|---------|
| **Local rehearsal** | Docker Compose (`make staging-up`) | Developer machine; mimics staging settings without cloud cost |
| **Shared test** | [Railway](../../infra/railway/README.md) | Remote API for TestFlight, device matrix, and team integration tests |
| **Production target** | [AWS Terraform](../../infra/terraform/README.md) | Staging and production VPCs on AWS (ECS, RDS, S3, CloudFront) |

```
Local Compose  →  Railway (shared test)  →  AWS Terraform (staging → production)
     ↑                      ↑                           ↑
  laptop              always-on URL               owner-operated
```

## Local rehearsal (Compose)

Reproducible staging rehearsal using Docker Compose on your machine.

```bash
cp .env.example .env
make staging-up
make db-migrate
make seed
make staging-smoke
```

Staging backend listens on **http://localhost:8080**.

### Production-like settings

- `APP_ENV=staging`
- API docs disabled when mimicking production (`APP_ENV=production` in remote deploy)
- Metrics enabled at `/metrics`
- Rate limits and request timeouts active

Compose uses local Postgres and MinIO — no AWS credentials required.

## Shared test (Railway)

Use Railway when you need a **stable HTTPS URL** for iOS Release Staging builds, webhooks, or collaborators who cannot run Compose.

- Postgres: Railway plugin
- Media: AWS S3 (`dailysketch-railway-media` or shared staging bucket via IAM keys in Railway secrets)
- Migrations: `alembic upgrade head` release command on deploy
- Cron jobs: separate Railway cron services or CI — see [infra/railway/README.md](../../infra/railway/README.md)

Keep a **separate Descope test project**, bucket, and secrets from production.

## AWS Terraform (staging & production)

Managed infrastructure for long-lived staging and production:

- `infra/terraform/envs/staging` — pre-production AWS stack (smaller instances, destroy-friendly RDS)
- `infra/terraform/envs/production` — production stack (deletion protection, multi-task ECS, longer retention)

Bootstrap remote state first, then apply with owner-filled `terraform.tfvars` (domains, Descope IDs, image tags — **no secrets in git**).

## Traceability

After any remote deploy, record:

- Backend `RELEASE_VERSION`, `COMMIT_SHA`, Alembic revision from `/health/version`
- OpenAPI contract revision in repository
- Matching iOS Release Staging build number

## Further reading

- [Railway test env setup](../../infra/railway/README.md)
- [AWS Terraform README](../../infra/terraform/README.md)
- [Release process](./release-process.md)
