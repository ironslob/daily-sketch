# Performance Review — Phase 13

Run:

```bash
make up
make db-migrate
make seed
make perf-profile
```

Results are written to `performance-review.json` in this directory.

## Architecture targets (p95)

| Endpoint | Target |
| --- | --- |
| Current Prompt | < 300 ms |
| Feed first page | < 500 ms |
| Profile history | < 500 ms |
| Like | < 300 ms |
| Reflection create | < 500 ms |
| Submission create | < 700 ms (excl. upload) |
| Image render/fetch | < 500 ms |

## Latest local run (2026-07-20)

| Endpoint | p50 (ms) | p95 (ms) | Target p95 |
| --- | ---: | ---: | ---: |
| Prompt | 2.3 | 6.2 | 300 |
| Feed | 7.8 | 9.5 | 500 |
| Image render | 0 | 0 | 500 |

No new indexes required at measured local load. Image render was 0 ms because the seeded feed had no image URLs to fetch.
