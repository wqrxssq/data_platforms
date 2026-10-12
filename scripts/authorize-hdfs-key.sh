#!/usr/bin/env bash
# Кладёт публичный ключ hdfs в authorized_keys. Ключ лежит в /tmp/hdfs-cluster.pub.
set -euo pipefail
if [[ ! -s /tmp/hdfs-cluster.pub ]]; then
  echo "missing /tmp/hdfs-cluster.pub" >&2
  exit 1
fi
pubkey=$(tr -d '\r' < /tmp/hdfs-cluster.pub)
install -d -o hdfs -g hdfs -m 700 /home/hdfs/.ssh
auth=/home/hdfs/.ssh/authorized_keys
touch "$auth"
chmod 600 "$auth"
chown hdfs:hdfs "$auth"
grep -qxF "$pubkey" "$auth" || echo "$pubkey" >> "$auth"
cat > /home/hdfs/.ssh/config <<'EOF'
Host team-23-en team-23-nn team-23-00 team-23-01
  User hdfs
  IdentityFile /home/hdfs/.ssh/id_ed25519
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
  BatchMode yes
EOF
chown hdfs:hdfs /home/hdfs/.ssh/config
chmod 600 /home/hdfs/.ssh/config
