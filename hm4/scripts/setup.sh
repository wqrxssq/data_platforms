#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

CACHE=/var/tmp
TARBALL="spark-3.5.9-bin-hadoop3.tgz"
URL="https://archive.apache.org/dist/spark/spark-3.5.9/${TARBALL}"

if [ ! -f "$CACHE/$TARBALL" ]; then
  echo "Скачиваю Spark 3.5.9"
  sudo curl -fL --retry 5 --retry-delay 2 -o "$CACHE/${TARBALL}.partial" "$URL"
  sudo mv "$CACHE/${TARBALL}.partial" "$CACHE/$TARBALL"
fi

if [ ! -x /opt/spark/bin/spark-submit ]; then
  echo "Распаковка Spark"
  sudo tar -xzf "$CACHE/$TARBALL" -C /opt
  sudo ln -sfn /opt/spark-3.5.9-bin-hadoop3 /opt/spark
fi

echo "Конфигурация Spark"
sudo cp "$ROOT/conf/spark-defaults.conf" /opt/spark/conf/
sudo cp "$ROOT/conf/spark-env.sh" /opt/spark/conf/

echo "Версия Spark:"
sudo -u hdfs /opt/spark/bin/spark-submit --version 2>&1 | grep -m1 version

echo "Архив библиотек в HDFS"
if ! as_hdfs "$HADOOP/bin/hdfs" dfs -test -e /apps/spark/spark-3.5.9-jars.zip; then
  sudo /usr/lib/jvm/java-17-openjdk-amd64/bin/jar -cfM /tmp/spark-3.5.9-jars.zip -C /opt/spark/jars .
  as_hdfs "$HADOOP/bin/hdfs" dfs -mkdir -p /apps/spark
  as_hdfs "$HADOOP/bin/hdfs" dfs -put -f /tmp/spark-3.5.9-jars.zip /apps/spark/spark-3.5.9-jars.zip
  sudo rm -f /tmp/spark-3.5.9-jars.zip
fi

echo 'Установка завершена, дальше ./scripts/load.sh'
