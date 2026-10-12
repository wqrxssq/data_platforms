#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

as_hdfs team-23-nn "$HADOOP/bin/yarn" --daemon start resourcemanager
for node in "${WORKERS[@]}"; do
  as_hdfs "$node" "$HADOOP/bin/yarn" --daemon start nodemanager
done
as_hdfs team-23-en "$HADOOP/bin/mapred" --daemon start historyserver
echo 'YARN и JobHistory запущены, дальше ./scripts/check.sh'
