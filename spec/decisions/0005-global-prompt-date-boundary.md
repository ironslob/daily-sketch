# 0005 — Global Prompt Date boundary

- Status: Accepted
- Date: 2026-07-18
- Deciders: Engineering

## Context

Daily Sketch requires one shared three-word Daily Prompt for every user at a given product date. Without a single canonical date boundary, clients in different timezones would observe different “today” prompts, breaking the shared-community interpretation that product.md requires.

## Decision

Version one uses a **global Prompt Date** that rolls over at **00:00 UTC**:

- `prompt_date` is the UTC calendar date;
- `GET /api/v1/prompts/today` resolves against the server UTC clock (`Clock.today()`);
- every client sees the same active Prompt regardless of the user’s local timezone.

Changing this rule requires an ADR update, a product decision, a data-migration review, and updates to all affected specifications.

## Consequences

- Prompt publication, the today endpoint, streak calculation, feed metadata, and notification copy must all use the UTC boundary consistently.
- A user travelling across timezones does not receive a different Prompt than the rest of the community.
- Local reminder times remain user-local preferences and are independent of the Prompt Date boundary.
