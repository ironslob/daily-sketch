#!/usr/bin/env bash
# Create the next numbered Alembic revision via autogenerate.
# Usage: new_migration.sh "short_slug" ["Human readable message"]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSIONS="${ROOT}/migrations/versions"
SLUG="${1:-}"
MESSAGE="${2:-}"

if [[ -z "${SLUG}" ]]; then
  echo "Usage: $0 <short_slug> [message]" >&2
  echo "Example: $0 add_prompt_locale \"Add locale column to daily_prompts\"" >&2
  exit 1
fi

if ! echo "${SLUG}" | grep -Eq '^[a-z0-9_]+$'; then
  echo "Slug must be snake_case [a-z0-9_]: ${SLUG}" >&2
  exit 1
fi

# alembic_version.version_num is VARCHAR(32); keep NNNN_slug within that.
max_slug_len=27
if ((${#SLUG} > max_slug_len)); then
  echo "Slug too long (${#SLUG} > ${max_slug_len}); shortens revision id past 32 chars." >&2
  exit 1
fi

if [[ -z "${MESSAGE}" ]]; then
  MESSAGE="${SLUG//_/ }"
fi

next=1
if ls "${VERSIONS}"/[0-9][0-9][0-9][0-9]_*.py >/dev/null 2>&1; then
  highest="$(
    find "${VERSIONS}" -maxdepth 1 -type f -name '[0-9][0-9][0-9][0-9]_*.py' \
      | sed -E 's|.*/([0-9]{4})_.*|\1|' \
      | sort -n \
      | tail -1
  )"
  next=$((10#${highest} + 1))
fi

rev_id="$(printf '%04d_%s' "${next}" "${SLUG}")"
echo "Generating ${rev_id} ..."
cd "${ROOT}"
if command -v uv >/dev/null 2>&1; then
  uv run alembic revision --autogenerate -m "${MESSAGE}" --rev-id "${rev_id}"
else
  alembic revision --autogenerate -m "${MESSAGE}" --rev-id "${rev_id}"
fi
echo "Review ${VERSIONS}/${rev_id}.py before applying (make db-migrate)."
