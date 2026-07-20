#!/usr/bin/env bash
# Repository checks: required specs present, migration naming, large-file policy.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

echo "== Spec presence =="
for path in \
  spec/product.md \
  spec/design.md \
  spec/architecture.md \
  spec/implementation.md \
  spec/infrastructure.md
do
  if [[ ! -f "${path}" ]]; then
    echo "Missing required spec: ${path}" >&2
    exit 1
  fi
  echo "ok ${path}"
done

echo "== Alembic migration naming/ordering =="
previous=""
found=0
# shellcheck disable=SC2012
for path in $(find backend/migrations/versions -maxdepth 1 -type f -name '*.py' | LC_ALL=C sort); do
  found=1
  base="$(basename "${path}")"
  if ! echo "${base}" | grep -Eq '^[0-9]{4}_[a-z0-9_]+\.py$'; then
    echo "Invalid migration filename (expected NNNN_name.py): ${base}" >&2
    exit 1
  fi
  if [[ -n "${previous}" && "${base}" < "${previous}" ]]; then
    echo "Migrations are not sorted: ${previous} before ${base}" >&2
    exit 1
  fi
  previous="${base}"
  echo "ok ${base}"
done

if [[ "${found}" -eq 0 ]]; then
  echo "No Alembic migrations found." >&2
  exit 1
fi

echo "== Large file policy =="
max_bytes=$((1024 * 1024)) # 1 MiB
allowed_large="spec/stitch_daily_sketch_journal.zip"

find . -type f \
  -not -path './.git/*' \
  -not -path './backend/.venv/*' \
  -not -path './backend/.mypy_cache/*' \
  -not -path './backend/.ruff_cache/*' \
  -not -path './backend/.pytest_cache/*' \
  -not -path './node_modules/*' \
  -not -path './ios/DerivedData/*' \
  -not -path './ios/*.xcodeproj/*' \
  -not -path '*/.terraform/*' \
  -print0 |
while IFS= read -r -d '' file; do
  size="$(wc -c < "${file}" | tr -d ' ')"
  if [[ "${size}" -le "${max_bytes}" ]]; then
    continue
  fi
  rel="${file#./}"
  if [[ "${rel}" == "${allowed_large}" ]]; then
    echo "allowed large file ${rel} (${size} bytes)"
    continue
  fi
  echo "Prohibited large file (${size} bytes): ${rel}" >&2
  exit 1
done

echo "Repository checks passed."
