# Operational Runbooks

Condensed from `spec/infrastructure.md` §40.

## Backend unavailable

**Symptoms:** `/health/ready` 503, elevated 5xx.
**Checks:** container logs, database connectivity, storage ping, recent deploy.
**Mitigation:** rollback previous image; scale/restart instances.
**Escalation:** on-call engineer.
**Recovery:** verify smoke tests; monitor metrics 30 minutes.

## Database connection failure

**Checks:** managed DB status, connection pool exhaustion, credentials rotation.
**Mitigation:** reduce traffic, restart app, increase pool only after measurement.

## Backup failure

**Mitigation:** retry backup job; block production migration until backup succeeds.

## Storage failure

**Checks:** bucket policy, credentials, head_bucket/ping.
**Mitigation:** fail readiness; disable uploads if necessary.

## Upload spike / image processing failures

**Checks:** upload error rate, CPU, timeout metrics.
**Mitigation:** tighten rate limits temporarily; investigate corrupt uploads.

## Missing Daily Prompt

**Checks:** `make job-missing-prompt-check`; prompt seed coverage.
**Mitigation:** the job and `GET /api/v1/prompts/today` both call `ensure_published` (deterministic create). Re-run the job; if a draft/withdrawn row blocks the date, publish or remove it; `make seed` for bulk future coverage.

## Migration failure

**Mitigation:** stop deploy; assess forward-fix migration; restore only under incident process.

## Account deletion backlog

**Checks:** pending deletion count; run `make account-deletion-finalize`.

## Moderation incident

**Checks:** report queue via moderation token routes; suspend/remove as needed.

## Credential exposure

**Mitigation:** rotate Descope, DB, storage, moderation tokens; invalidate CI secrets.

## iOS/backend contract mismatch

**Checks:** OpenAPI drift CI; `/health/version` vs iOS build settings.
**Mitigation:** ship compatible client or roll back backend.
