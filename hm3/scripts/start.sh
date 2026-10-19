#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

remote "$METASTORE_HOST" sudo -n systemctl start hive-metastore
wait_port "$METASTORE_HOST" 9083 Metastore
remote "$HS2_HOST" sudo -n systemctl start hiveserver2
wait_port "$HS2_HOST" 10000 HiveServer2
echo 'Hive запущен, дальше ./scripts/load.sh'
