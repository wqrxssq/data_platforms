#!/usr/bin/env bash
# Запускает HDFS: start-dfs.sh на NameNode от пользователя hdfs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

if [[ "$(hostname -s)" == "$NN" ]]; then
  sudo -n -u hdfs -H /opt/hadoop/sbin/start-dfs.sh </dev/null
else
  ssh_base "${SSH_USER}@${NN}" \
    "sudo -n -u hdfs -H /opt/hadoop/sbin/start-dfs.sh" </dev/null
fi
