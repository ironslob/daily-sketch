#!/bin/sh
# Production start: bind to Railway's PORT when set, else 8000 for local Docker.
set -eu
exec uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-8000}"
