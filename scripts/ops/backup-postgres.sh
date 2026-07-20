#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE=(docker compose -f "$ROOT/docker-compose.yml")
BACKUP_DIR="${BACKUP_DIR:-$ROOT/.backups}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$BACKUP_DIR/postgres-$STAMP.sql"

mkdir -p "$BACKUP_DIR"
"${COMPOSE[@]}" exec -T postgres pg_dump -U "${POSTGRES_USER:-dailysketch}" "${POSTGRES_DB:-dailysketch}" >"$OUT"
echo "Backup written to $OUT"
