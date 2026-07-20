# 0009 — Account Deletion

- Status: Accepted
- Date: 2026-07-19
- Deciders: Engineering

## Context

Users must be able to delete their accounts. Architecture specifies a two-phase approach so public visibility can end immediately while media cleanup and identity-provider teardown remain best-effort and scheduled.

## Decision

1. **`DELETE /api/v1/me`** returns **202** with `status: pending_deletion` (idempotent). Immediately:
   - user status → `pending_deletion` (auth rejects further access for that identity flow per existing status rules);
   - hide public profile and Submissions;
   - soft-delete the author’s Reflections;
   - remove the author’s Likes and decrement counters;
   - retain reports and moderation audit rows minimally.
2. **Finalize job** (`python -m app.jobs.account_deletion` / `make account-deletion-finalize`) is **idempotent** and:
   - best-effort deletes submission and avatar media from storage;
   - best-effort Descope disable/delete seam (no-op without management credentials);
   - marks the user `deleted`.
3. Descope identity deletion is documented as **best-effort**; local/dev may omit management credentials.

## Consequences

- Clients must treat account deletion as non-immediate: explain policy, then sign out and clear local Drafts after a successful 202.
- Operators/schedulers must run the finalize command until Phase 13+ scheduling lands.
- Reversibility after `pending_deletion` is not promised in v1.
