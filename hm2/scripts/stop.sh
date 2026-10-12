#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

for node in "${WORKERS[@]}"; do
  as_hdfs "$node" "$HADOOP/bin/yarn" --daemon stop nodemanager
done
as_hdfs team-23-nn "$HADOOP/bin/yarn" --daemon stop resourcemanager
as_hdfs team-23-en "$HADOOP/bin/mapred" --daemon stop historyserver
echo 'YARN и JobHistory остановлены, HDFS продолжает работать'
