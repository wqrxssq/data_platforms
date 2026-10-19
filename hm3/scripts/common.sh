#!/usr/bin/env bash

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EDGE=team-23-en
METASTORE_HOST=team-23-nn
HS2_HOST=team-23-en
HIVE_NODES=(team-23-en team-23-nn)
SSH_KEY=${SSH_KEY:-$HOME/.ssh/team_internal}
HADOOP=/opt/hadoop
HIVE=/opt/hive

HIVE_VERSION=4.0.0-alpha-2
HIVE_TARBALL=apache-hive-$HIVE_VERSION-bin.tar.gz
HIVE_URL=https://archive.apache.org/dist/hive/hive-$HIVE_VERSION/$HIVE_TARBALL
HIVE_SHA256=f94c773e7ae3328d780138d9259c584e94d8f2e34715776cdfaaa78bcf3f25e1
PG_JDBC=postgresql-42.7.4.jar
PG_JDBC_URL=https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.4/$PG_JDBC
PG_JDBC_SHA256=188976721ead8e8627eb6d8389d500dccc0c9bebd885268a3047180274a6031e
CACHE=/var/tmp

JDBC_URL="jdbc:hive2://$HS2_HOST:10000/default"

[[ $(hostname -s) == "$EDGE" ]] || { echo "Запускайте скрипт на $EDGE" >&2; exit 1; }

ssh_opts=(-i "$SSH_KEY" -o BatchMode=yes -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=yes -o ConnectTimeout=10)

remote() {
  local node=$1
  shift
  if [[ $node == "$EDGE" ]]; then
    "$@"
  else
    ssh -n "${ssh_opts[@]}" "team@$node" "$@"
  fi
}

# Строка для bash на узле, stdin передаётся команде
remote_sh() {
  local node=$1 command=$2
  if [[ $node == "$EDGE" ]]; then
    bash -c "$command"
  else
    ssh "${ssh_opts[@]}" "team@$node" "$command"
  fi
}

as_hdfs() {
  local node=$1
  shift
  remote "$node" sudo -n -u hdfs -H "$@"
}

as_hive() {
  local node=$1
  shift
  remote "$node" sudo -n -u hive -H "$@"
}

# Копирует конфиги, скрипты узла и SQL в /tmp/hm3-stage
stage() {
  local node=$1
  tar -C "$ROOT" -cf - conf scripts/node sql |
    remote_sh "$node" 'rm -rf /tmp/hm3-stage && mkdir -p /tmp/hm3-stage && tar -C /tmp/hm3-stage -xf -'
}

beeline() {
  local node=$1
  shift
  remote "$node" "$HIVE/bin/beeline" -u "$JDBC_URL" -n hive --silent=true \
    --showHeader=false --outputformat=tsv2 "$@"
}

wait_port() {
  local node=$1 port=$2 name=$3
  for attempt in $(seq 1 60); do
    if remote "$node" ss -Hltn "sport = :$port" | grep -q LISTEN; then
      echo "$name слушает $node:$port"
      return 0
    fi
    sleep 3
  done
  echo "$name не открыл порт $port на $node" >&2
  return 1
}
