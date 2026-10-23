#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

remote "$HS2_HOST" sudo -n systemctl stop hiveserver2
remote "$METASTORE_HOST" sudo -n systemctl stop hive-metastore
echo 'HiveServer2 и Metastore остановлены, PostgreSQL, HDFS и YARN продолжают работать'
