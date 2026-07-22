# Scheduled Jobs

Provider cron examples (UTC):

| Job | Schedule | Command |
| --- | --- | --- |
| Account deletion finalize | `0 * * * *` | `python -m app.jobs.account_deletion` |
| Upload cleanup | `15 * * * *` | `python -m app.jobs.upload_cleanup` |
| Sketch session cleanup | `30 * * * *` | `python -m app.jobs.sketch_session_cleanup` |
| Story session cleanup | `35 * * * *` | `python -m app.jobs.story_session_cleanup` |
| Idempotency cleanup | `45 * * * *` | `python -m app.jobs.idempotency_cleanup` |
| Deleted media cleanup | `0 3 * * *` | `python -m app.jobs.deleted_media_cleanup` |
| Missing prompt check | `0 12 * * *` | `python -m app.jobs.missing_prompt_check` (ensures today + tomorrow) |

Dry-run locally:

```bash
make jobs-dry-run
```

Jobs are idempotent and safe under duplicate execution.
