#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

backup="/var/backups/hadoop-hm2-$(date +%Y%m%d-%H%M%S)"
for node in "${NODES[@]}"; do
  echo "Настройка $node"
  remote "$node" test -x "$HADOOP/bin/yarn"
  remote "$node" sudo -n mkdir -p "$backup"
  for file in yarn-site.xml mapred-site.xml yarn-env.sh mapred-env.sh; do
    remote "$node" sudo -n cp -p "$HADOOP/etc/hadoop/$file" "$backup/$file"
    copy_file "$ROOT/conf/$file" "$node" "$HADOOP/etc/hadoop/$file"
  done
  remote "$node" sudo -n install -d -o hdfs -g hdfs -m 755 \
    /var/lib/hadoop/yarn/local /var/log/hadoop/yarn-containers
done

# Каталоги в HDFS для логов и истории задач
as_hdfs team-23-en "$HADOOP/bin/hdfs" dfs -mkdir -p /tmp/yarn-logs /mr-history/tmp /mr-history/done
as_hdfs team-23-en "$HADOOP/bin/hdfs" dfs -chmod 1777 /tmp/yarn-logs /mr-history/tmp
as_hdfs team-23-en "$HADOOP/bin/hdfs" dfs -chmod 770 /mr-history/done
echo "Настройки сохранены, исходные файлы на каждом узле: $backup"
echo 'Дальше ./scripts/start.sh'
