#!/usr/bin/env bash
# PostgreSQL, схема и служба Metastore. Запускается от root на узле Metastore
set -euo pipefail
STAGE=/tmp/hm3-stage
CONF=/opt/hive/conf
PASSWORD_FILE=/etc/hive/metastore-db.password
cd /

if ! systemctl cat postgresql.service >/dev/null 2>&1; then
  echo 'Установка PostgreSQL'
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq postgresql >/dev/null
fi
systemctl enable --now postgresql
# Ubuntu по умолчанию слушает только localhost, Metastore стоит на этом же узле

install -d -o root -g hive -m 750 /etc/hive
if [[ ! -s $PASSWORD_FILE ]]; then
  (umask 077; openssl rand -hex 24 >"$PASSWORD_FILE")
fi
chown root:hive "$PASSWORD_FILE"
chmod 640 "$PASSWORD_FILE"
password=$(<"$PASSWORD_FILE")

sudo -u postgres psql -q -v ON_ERROR_STOP=1 -v pw="$password" <<'SQL'
SELECT 'CREATE ROLE hive LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'hive')\gexec
ALTER ROLE hive WITH LOGIN PASSWORD :'pw';
SELECT 'CREATE DATABASE metastore OWNER hive' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'metastore')\gexec
SQL

sed "s/@DB_PASSWORD@/$password/" "$STAGE/conf/hivemetastore-site.xml" >"$CONF/hivemetastore-site.xml.tmp"
chown root:hive "$CONF/hivemetastore-site.xml.tmp"
chmod 640 "$CONF/hivemetastore-site.xml.tmp"
mv "$CONF/hivemetastore-site.xml.tmp" "$CONF/hivemetastore-site.xml"

initialized=$(sudo -u postgres psql -d metastore -tAc "SELECT to_regclass('public.\"VERSION\"') IS NOT NULL")
if [[ $initialized == t ]]; then
  echo 'Схема Metastore уже создана'
else
  echo 'Создание схемы Metastore, лог: /var/log/hive/schematool.log'
  sudo -u hive -H /opt/hive/bin/schematool -dbType postgres -initSchema >/var/log/hive/schematool.log 2>&1
fi
sudo -u hive -H /opt/hive/bin/schematool -dbType postgres -info 2>/dev/null | grep -i 'schema version'

install -m 644 "$STAGE/conf/hive-metastore.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable hive-metastore
