#!/usr/bin/env bash
# Установка Hadoop и конфигов на одном узле. Запускается от root.
set -euo pipefail
trap 'echo "[install] failed on $(hostname -s) at line $LINENO" >&2' ERR

: "${TARBALL:?}"
: "${CONF_DIR:?}"
VERSION=3.4.3
PREFIX="/opt/hadoop-${VERSION}"

if [[ ! -x "${PREFIX}/bin/hadoop" ]]; then
  rm -rf "${PREFIX}"
  tar -C /opt -xzf "${TARBALL}"
fi
if [[ -e /opt/hadoop && ! -L /opt/hadoop ]]; then
  echo "/opt/hadoop exists and is not a symlink" >&2
  exit 1
fi
ln -sfn "${PREFIX}" /opt/hadoop

install -d -o hdfs -g hdfs -m 755 \
  /var/lib/hadoop/namenode \
  /var/lib/hadoop/datanode \
  /var/lib/hadoop/namesecondary \
  /var/lib/hadoop/tmp \
  /var/lib/hadoop/pids \
  /var/log/hadoop

cp "${CONF_DIR}/core-site.xml" /opt/hadoop/etc/hadoop/core-site.xml
cp "${CONF_DIR}/hdfs-site.xml" /opt/hadoop/etc/hadoop/hdfs-site.xml
cp "${CONF_DIR}/workers" /opt/hadoop/etc/hadoop/workers
if grep -qx 'localhost' /opt/hadoop/etc/hadoop/workers; then
  echo "workers file still lists localhost" >&2
  exit 1
fi
for worker in team-23-en team-23-00 team-23-01; do
  grep -qx "$worker" /opt/hadoop/etc/hadoop/workers
done
cp "${CONF_DIR}/hadoop.sh" /etc/profile.d/hadoop.sh
chmod 644 \
  /etc/profile.d/hadoop.sh \
  /opt/hadoop/etc/hadoop/core-site.xml \
  /opt/hadoop/etc/hadoop/hdfs-site.xml \
  /opt/hadoop/etc/hadoop/workers

envf=/opt/hadoop/etc/hadoop/hadoop-env.sh
if grep -q '# BEGIN hdfs-cluster' "$envf"; then
  sed -i '/# BEGIN hdfs-cluster/,/# END hdfs-cluster/d' "$envf"
fi
awk '1' "$envf" > "${envf}.tmp"
cat "${CONF_DIR}/hadoop-env.append.sh" >> "${envf}.tmp"
mv "${envf}.tmp" "$envf"

chown -R hdfs:hdfs "${PREFIX}" /var/lib/hadoop /var/log/hadoop

echo "[install] $(hostname -s) version:"
sudo -u hdfs -H /opt/hadoop/bin/hadoop version
