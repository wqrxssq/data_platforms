#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

if ! as_hdfs "$EDGE" "$HADOOP/bin/hdfs" dfsadmin -safemode get | grep -q 'Safe mode is OFF'; then
  echo 'HDFS недоступен или в safe mode, сначала запустите ДЗ 1' >&2
  exit 1
fi

fetch() {
  local url=$1 file=$2 sha=$3
  if ! echo "$sha  $file" | sha256sum -c --status 2>/dev/null; then
    echo "Скачиваю $url"
    sudo -n curl -fL --retry 5 --retry-delay 2 -o "$file.partial" "$url"
    sudo -n mv "$file.partial" "$file"
  fi
  echo "$sha  $file" | sha256sum -c
}
fetch "$HIVE_URL" "$CACHE/$HIVE_TARBALL" "$HIVE_SHA256"
fetch "$PG_JDBC_URL" "$CACHE/$PG_JDBC" "$PG_JDBC_SHA256"

for node in "${HIVE_NODES[@]}"; do
  echo "Установка Hive на $node"
  stage "$node"
  if [[ $node != "$EDGE" ]] && ! printf '%s  %s\n' \
    "$HIVE_SHA256" "$CACHE/$HIVE_TARBALL" "$PG_JDBC_SHA256" "$CACHE/$PG_JDBC" |
    remote_sh "$node" 'sha256sum -c --status 2>/dev/null'; then
    scp -q "${ssh_opts[@]}" "$CACHE/$HIVE_TARBALL" "$CACHE/$PG_JDBC" "team@$node:/tmp/hm3-stage/"
    remote "$node" sudo -n mv /tmp/hm3-stage/"$HIVE_TARBALL" /tmp/hm3-stage/"$PG_JDBC" "$CACHE/"
  fi
  remote "$node" sudo -n env TARBALL="$CACHE/$HIVE_TARBALL" JDBC_JAR="$CACHE/$PG_JDBC" \
    bash /tmp/hm3-stage/scripts/node/install-hive.sh
done

# Каталоги в HDFS: хранилище таблиц и временные файлы запросов от пользователя hive
as_hdfs "$EDGE" "$HADOOP/bin/hdfs" dfs -mkdir -p /user/hive/warehouse /tmp/hive /tmp/hadoop-yarn/staging
as_hdfs "$EDGE" "$HADOOP/bin/hdfs" dfs -chown -R hive:hive /user/hive
as_hdfs "$EDGE" "$HADOOP/bin/hdfs" dfs -chmod 1777 /tmp /tmp/hive /tmp/hadoop-yarn/staging

echo "PostgreSQL и Metastore на $METASTORE_HOST"
remote "$METASTORE_HOST" sudo -n bash /tmp/hm3-stage/scripts/node/setup-metastore.sh

echo "HiveServer2 на $HS2_HOST"
remote "$HS2_HOST" sudo -n install -m 644 /tmp/hm3-stage/conf/hiveserver2.service /etc/systemd/system/
remote "$HS2_HOST" sudo -n systemctl daemon-reload
remote "$HS2_HOST" sudo -n systemctl enable hiveserver2

# Если Hive уже запущен, перезапускаем с новыми настройками
remote "$METASTORE_HOST" sudo -n systemctl try-restart hive-metastore
remote "$HS2_HOST" sudo -n systemctl try-restart hiveserver2

echo 'Установка завершена, дальше ./scripts/start.sh'
