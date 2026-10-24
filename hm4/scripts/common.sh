#!/usr/bin/env bash

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EDGE=team-23-en

HADOOP=/opt/hadoop
SPARK=/opt/spark
HIVE=/opt/hive

JDBC_URL="jdbc:hive2://${EDGE}:10000/default"

[[ $(hostname -s) == $EDGE ]] || { echo "Запускайте скрипт на $EDGE" >&2; exit 1; }

as_hdfs() {
  sudo -u hdfs -H "$@"
}
