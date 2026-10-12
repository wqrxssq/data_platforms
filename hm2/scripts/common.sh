#!/usr/bin/env bash

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
NODES=(team-23-en team-23-nn team-23-00 team-23-01)
WORKERS=(team-23-en team-23-00 team-23-01)
SSH_KEY=${SSH_KEY:-$HOME/.ssh/team_internal}
HADOOP=/opt/hadoop

[[ $(hostname -s) == team-23-en ]] || { echo 'Запускайте скрипт на team-23-en' >&2; exit 1; }

remote() {
  local node=$1
  shift
  if [[ $node == team-23-en ]]; then
    "$@"
  else
    ssh -n -i "$SSH_KEY" -o BatchMode=yes -o IdentitiesOnly=yes \
      -o StrictHostKeyChecking=yes -o ConnectTimeout=10 "team@$node" "$@"
  fi
}

as_hdfs() {
  local node=$1
  shift
  remote "$node" sudo -n -u hdfs -H "$@"
}

copy_file() {
  local source=$1 node=$2 target=$3
  if [[ $node == team-23-en ]]; then
    sudo -n install -o hdfs -g hdfs -m 644 "$source" "$target"
  else
    cat "$source" | ssh -i "$SSH_KEY" -o BatchMode=yes -o IdentitiesOnly=yes \
      -o StrictHostKeyChecking=yes -o ConnectTimeout=10 "team@$node" \
      "sudo -n -u hdfs tee '$target' >/dev/null"
  fi
}
