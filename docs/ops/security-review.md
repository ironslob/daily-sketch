# Security Review — Phase 13

**Date:** 2026-07-20 (updated during V1 post-implementation audit)
**Scope:** Backend + iOS release readiness per `spec/implementation.md` §18.2

| Control | Status | Evidence |
| --- | --- | --- |
| Descope configuration | Pass (local placeholders) / Owner gate (staging/prod) | `Settings.validate_remote_environment` rejects any `replace-me` substring in staging/production |
| JWT validation | Pass | `app/auth/jwt.py`; optional auth soft-fails to anonymous for public reads |
| Storage policy | Pass | Private bucket, signed PUT/GET only, no credentials in iOS |
| Signed URL expiry | Pass | Create + `POST .../refresh-signed-upload`; expiry settings validated ≥60s |
| Image validation | Pass | MIME allowlist, max bytes, decode/dimensions in `app/media/processing.py` |
| Public media / EXIF | Pass (derivatives) | Originals retained **verbatim** privately; display/thumbnail derivatives are EXIF-stripped and are the only URLs returned in feed/detail/profile payloads |
| Secrets | Pass | `.env.example` placeholders only; `detect-secrets` in CI |
| Moderation access | Pass | `X-Moderation-Token` compared with `secrets.compare_digest`; rate limited |
| Account deletion | Pass | Two-phase deletion + finalize job via shared `job_main` (dry-run supported); uploads marked `deleted_at` |
| Log redaction | Pass | `app/core/redaction.py` + JSON formatter integration |
| Rate limits | Pass | In-process middleware; `429 rate_limited` documented in OpenAPI |

## Residual risks

- Owner must supply real Descope, storage, and moderation credentials before staging/production deploy.
- Physical-device and TestFlight distribution require Apple signing setup.
- Original objects may still contain EXIF/GPS if present in the client upload. They are never exposed via public API URLs; operators with direct storage access can still read them. Destroy originals on account deletion finalize / deleted-media cleanup.

## Verdict

No known critical issues in repository-controlled scope. Remote environment boot fails fast when secrets remain at development placeholders.
