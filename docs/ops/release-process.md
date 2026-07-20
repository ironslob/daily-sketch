# Release Process

Condensed from `spec/infrastructure.md` §38.

1. Merge reviewed code; CI green.
2. Build immutable backend container image.
3. Validate OpenAPI compatibility (`make api-validate`, `make api-check-generated`).
4. Deploy to staging; run migrations as dedicated step.
5. Run smoke/E2E checklist (`docs/release/e2e-checklist.md`).
6. Archive Release Staging iOS build.
7. Verify backup/recovery readiness (`docs/ops/backup-restore.md`).
8. Approve production release.
9. Run production migration; deploy same image tested in staging.
10. Verify health/metrics; monitor errors.
11. Release/phased iOS production build.
12. Record release notes and traceability matrix below.

## Traceability matrix

| Artifact | Source |
| --- | --- |
| iOS build | Xcode `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` |
| Backend release | `RELEASE_VERSION`, `COMMIT_SHA`, `BUILD_TIMESTAMP` |
| API contract | `api/openapi/openapi.yaml` git revision |
| Database schema | Alembic head from `/health/version` |

## TestFlight readiness (in-repo)

- Release Staging/Production xcconfigs present
- Privacy Manifest included
- Archive runbook: `docs/release/testflight-upload.md`
- Live App Store Connect upload requires owner Apple credentials
