#!/usr/bin/env bash
# Общие параметры кластера. Файл подключают скрипты на edge-ноде.

NODES=(team-23-en team-23-nn team-23-00 team-23-01)
NN=team-23-nn
DN_NODES=(team-23-en team-23-00 team-23-01)
SSH_USER=team
SSH_KEY="${HOME}/.ssh/team_internal"
HADOOP_VERSION=3.4.3
TARBALL="hadoop-${HADOOP_VERSION}.tar.gz"
TARBALL_CACHE="/var/tmp/${TARBALL}"
SHA_CACHE="/var/tmp/${TARBALL}.sha512"

ssh_base() {
  ssh -i "$SSH_KEY" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=15 \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=40 \
    "$@"
}

scp_to() {
  local host=$1
  local dest=$2
  shift 2
  scp -i "$SSH_KEY" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=15 \
    "$@" "${SSH_USER}@${host}:${dest}"
}

# Скрипт со stdin выполняется от root на узле.
sudo_script() {
  local host=$1
  if [[ "$(hostname -s)" == "$host" ]]; then
    sudo -n bash -s
  else
    ssh_base "${SSH_USER}@${host}" sudo -n bash -s
  fi
}
