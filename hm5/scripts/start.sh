#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
[[ $(hostname -s) == team-23-en ]] || { echo 'Запускайте на team-23-en' >&2; exit 1; }
export PREFECT_HOME="$ROOT/.prefect"
unset PREFECT_API_URL
export PREFECT_SERVER_ALLOW_EPHEMERAL_MODE=true
export PREFECT_SERVER_ANALYTICS_ENABLED=false
exec "$ROOT/.venv/bin/python" "$ROOT/flow.py" "$@"
