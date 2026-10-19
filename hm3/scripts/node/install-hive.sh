#!/usr/bin/env bash
# Установка Hive на один узел. Запускается от root, конфиги лежат в /tmp/hm3-stage
set -euo pipefail
: "${TARBALL:?}" "${JDBC_JAR:?}"
STAGE=/tmp/hm3-stage
PREFIX=/opt/apache-hive-4.0.0-alpha-2-bin

if ! id hive >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /var/lib/hive --shell /bin/bash --user-group hive
fi
if [[ ! -x $PREFIX/bin/hive ]]; then
  rm -rf "$PREFIX"
  tar -C /opt --no-same-owner -xzf "$TARBALL"
fi
if [[ -e /opt/hive && ! -L /opt/hive ]]; then
  echo '/opt/hive существует и не является ссылкой' >&2
  exit 1
fi
ln -sfn "$PREFIX" /opt/hive

install -m 644 "$JDBC_JAR" "$PREFIX/lib/"
install -m 644 "$STAGE/conf/hive-site.xml" "$STAGE/conf/hive-env.sh" "$PREFIX/conf/"
install -m 644 "$STAGE/conf/hive.sh" /etc/profile.d/hive.sh
install -d -o hive -g hive -m 755 /var/lib/hive /var/log/hive

echo "[hive] $(hostname -s): $(sudo -u hive -H /opt/hive/bin/hive --version 2>/dev/null | grep -m1 '^Hive')"
