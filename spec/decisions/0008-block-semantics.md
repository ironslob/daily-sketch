# 0008 — Block Semantics

- Status: Accepted
- Date: 2026-07-19
- Deciders: Engineering

## Context

Phase 11 introduces reciprocal blocking. Product and architecture require private block relationships, feed/detail/profile filtering in both directions, and a blocked/unavailable surface rather than a full profile—without telling the blocked party they have been blocked.

## Decision

- Block relationships are **private**. Public APIs never expose who blocked whom.
- Filtering is **reciprocal**: either direction of a block hides the other user from feed, submission detail, reflections lists, and public profiles (treated as not found / unavailable).
- Server enforcement is authoritative; the iOS client also removes local feed/detail content after a successful block.
- Self-block is rejected with `cannot_block_self`.
- Block and unblock are **idempotent**.
- Existing Likes from blocked users may remain in aggregate counts; blocked authors cannot create new Likes/Reflections across the relationship.

## Consequences

- Profile responses for blocker↔blocked use the same unavailable/404 path as missing accounts to avoid leaking “you are blocked.”
- Moderation operators use separate internal tools; blocking is a user safety control, not a moderation verdict.
