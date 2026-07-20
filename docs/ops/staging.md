# Staging Deployment

Reproducible staging rehearsal using Docker Compose.

## Start staging profile

```bash
cp .env.example .env
make staging-up
make db-migrate
make seed
make staging-smoke
```

Staging backend listens on **http://localhost:8080**.

## Production-like settings

- `APP_ENV=staging`
- API docs disabled when mimicking production (`APP_ENV=production` in remote deploy)
- Metrics enabled at `/metrics`
- Rate limits and request timeouts active

## Remote staging (owner)

Replace Compose with managed PostgreSQL, private object storage, TLS termination, and protected deploy approvals. Keep environment isolation: separate Descope project, bucket, secrets, and hostname from production.

## Traceability

After deploy, record:

- Backend `RELEASE_VERSION`, `COMMIT_SHA`, Alembic revision from `/health/version`
- OpenAPI contract revision in repository
- Matching iOS Release Staging build number
