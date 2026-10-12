#!/usr/bin/env bash
# Печатает публичный ключ пользователя hdfs. Ключ создаётся на NameNode.
set -euo pipefail
install -d -o hdfs -g hdfs -m 700 /home/hdfs/.ssh
if [[ ! -f /home/hdfs/.ssh/id_ed25519 ]]; then
  sudo -u hdfs -H ssh-keygen -q -t ed25519 -N "" -C "hdfs@team-23-nn" -f /home/hdfs/.ssh/id_ed25519
fi
chown hdfs:hdfs /home/hdfs/.ssh/id_ed25519 /home/hdfs/.ssh/id_ed25519.pub
chmod 600 /home/hdfs/.ssh/id_ed25519
chmod 644 /home/hdfs/.ssh/id_ed25519.pub
cat /home/hdfs/.ssh/id_ed25519.pub
