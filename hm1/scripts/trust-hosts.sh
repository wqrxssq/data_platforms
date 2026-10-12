#!/usr/bin/env bash
# known_hosts для пользователя hdfs на NameNode, откуда start-dfs.sh ходит по SSH.
set -euo pipefail
hosts=(team-23-en team-23-nn team-23-00 team-23-01)
install -d -o hdfs -g hdfs -m 700 /home/hdfs/.ssh
tmp=$(mktemp)
sudo -u hdfs -H ssh-keyscan -T 5 -t ed25519,rsa "${hosts[@]}" > "$tmp"
for h in "${hosts[@]}"; do
  if ! grep -q "$h" "$tmp"; then
    echo "ssh-keyscan missed ${h}" >&2
    cat "$tmp" >&2
    exit 1
  fi
done
install -o hdfs -g hdfs -m 644 "$tmp" /home/hdfs/.ssh/known_hosts
rm -f "$tmp"
