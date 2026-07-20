#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <backup.sql>" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE=(docker compose -f "$ROOT/docker-compose.yml")
BACKUP="$1"

if [[ ! -f "$BACKUP" ]]; then
  echo "Backup file not found: $BACKUP" >&2
  exit 1
fi

"${COMPOSE[@]}" exec -T postgres psql -U "${POSTGRES_USER:-dailysketch}" -d postgres -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${POSTGRES_DB:-dailysketch}' AND pid <> pg_backend_pid();"
"${COMPOSE[@]}" exec -T postgres dropdb -U "${POSTGRES_USER:-dailysketch}" --if-exists "${POSTGRES_DB:-dailysketch}"
"${COMPOSE[@]}" exec -T postgres createdb -U "${POSTGRES_USER:-dailysketch}" "${POSTGRES_DB:-dailysketch}"
cat "$BACKUP" | "${COMPOSE[@]}" exec -T postgres psql -U "${POSTGRES_USER:-dailysketch}" "${POSTGRES_DB:-dailysketch}"
echo "Restore completed from $BACKUP"
