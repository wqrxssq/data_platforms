#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
[[ $(hostname -s) == team-23-en ]] || { echo 'Запускайте на team-23-en' >&2; exit 1; }
[[ -x /opt/spark/bin/spark-submit ]] || { echo 'Сначала нужна установка из ДЗ 4' >&2; exit 1; }
if ! python3 -c 'import ensurepip' 2>/dev/null; then
  sudo -n apt-get update
  sudo -n env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get install -y python3-venv
fi
python3 -m venv "$ROOT/.venv"
"$ROOT/.venv/bin/python" -m pip install -r "$ROOT/requirements.txt"
echo 'Дальше ./scripts/start.sh'
