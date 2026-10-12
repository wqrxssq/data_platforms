#!/usr/bin/env bash
set -euo pipefail

# Этот скрипт запускается на ноутбуке, остальные — на edge
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SSH_TARGET=${SSH_TARGET:-team@111.88.130.82}
forwards=(-L 127.0.0.1:18080:127.0.0.1:18080)
while read -r name host internal_ip internal_port local_port; do
  [[ -n $name && $name != \#* ]] || continue
  forwards+=(-L "127.0.0.1:$local_port:127.0.0.1:$local_port")
done <"$ROOT/conf/web-interfaces.tsv"

echo 'После подключения откройте http://localhost:18080/'
echo 'Оставьте этот терминал открытым, для отключения нажмите Ctrl+C'
exec ssh -N -T -o ExitOnForwardFailure=yes -o ForwardAgent=no \
  -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
  "${forwards[@]}" "$@" "$SSH_TARGET"
