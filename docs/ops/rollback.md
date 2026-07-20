# Production Rollback

Per `spec/infrastructure.md` §39.

## Default responses

1. **Application failure:** deploy previous immutable backend image; keep database schema compatible.
2. **Bad migration:** roll forward with corrective Alembic migration — do not downgrade by default.
3. **Severe data incident:** restore database under incident process only.

## Steps

1. Stop traffic increase / pause iOS phased release if needed.
2. Redeploy last known-good backend image tag recorded in release metadata.
3. Verify `/health/live`, `/health/ready`, `/health/version`.
4. Confirm error rate and latency metrics normalize.
5. Document incident timeline and follow-up migration if schema changed.

## iOS rollback

- Halt TestFlight phased release or submit hotfix build linked to compatible API contract revision.
- Never point production iOS builds at non-production API hosts.

## Not default

- Database point-in-time restore for routine application bugs.
- Force-push or destructive schema rollback while supported clients remain in the field.
