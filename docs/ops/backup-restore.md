# Backup and Restore

## Local backup

```bash
make up
make backup-postgres
```

Backups are written to `.backups/postgres-<timestamp>.sql`.

## Local restore drill

```bash
make backup-postgres
make restore-postgres BACKUP=.backups/postgres-<timestamp>.sql
make db-migrate
curl http://localhost:8000/health/ready
```

Record drill results in release notes before production migration.

## Drill log

- **2026-07-20:** `make backup-postgres` → `.backups/postgres-20260720T081637Z.sql`; `make restore-postgres BACKUP=...` succeeded; `/health/ready` returned ok after backend restart.

## Production guidance

- Use managed PostgreSQL automated daily backups with point-in-time recovery where available.
- Restore into an isolated environment before trusting a backup.
- After restore, avoid destructive cleanup jobs until storage/database consistency is verified.
