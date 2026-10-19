#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

mkdir -p "$ROOT/evidence"
run="hm3-check-$(date +%Y%m%d-%H%M%S)"
out="$ROOT/evidence/$run"

remote "$METASTORE_HOST" systemctl is-active hive-metastore postgresql
remote "$HS2_HOST" systemctl is-active hiveserver2
remote "$METASTORE_HOST" ss -Hltn sport = :9083
remote "$HS2_HOST" ss -Hltn sport = :10000

stage "$METASTORE_HOST"
echo 'Таблицы hm3 в базе Metastore (PostgreSQL):'
remote "$METASTORE_HOST" sudo -n -u postgres psql -d metastore -tA -F, -f /tmp/hm3-stage/sql/metastore.sql |
  tee "$out-metastore.txt"
grep -Eq '^hm3,sales,[A-Z_]+,[1-9]' "$out-metastore.txt"

# Два клиента на разных узлах одновременно работают через HiveServer2 и общий Metastore
echo "Клиенты: beeline на $EDGE и на $METASTORE_HOST"
beeline "$EDGE" -f "$ROOT/sql/check-sales.hql" >"$out-sales.tsv" 2>"$out-sales.log" &
first=$!
beeline "$METASTORE_HOST" -f /tmp/hm3-stage/sql/check-staging.hql >"$out-staging.tsv" 2>"$out-staging.log" &
second=$!
wait "$first" || { echo "Клиент на $EDGE завершился с ошибкой, лог: $out-sales.log" >&2; exit 1; }
wait "$second" || { echo "Клиент на $METASTORE_HOST завершился с ошибкой, лог: $out-staging.log" >&2; exit 1; }
[[ -s $out-sales.tsv ]] || { echo 'Таблица hm3.sales пуста' >&2; exit 1; }
if ! diff "$out-staging.tsv" "$out-sales.tsv"; then
  echo 'Число строк в партициях не совпадает с исходными данными' >&2
  exit 1
fi
echo 'Строк по партициям (совпадает с исходным CSV):'
cat "$out-sales.tsv"

partitions=$(as_hive "$EDGE" "$HADOOP/bin/hdfs" dfs -ls /user/hive/warehouse/hm3.db/sales | grep -c 'order_date=')
echo "Каталогов партиций в HDFS: $partitions"
as_hdfs "$EDGE" "$HADOOP/bin/hdfs" fsck /user/hive/warehouse/hm3.db/sales >"$out-fsck.txt" 2>&1
grep -q 'is HEALTHY' "$out-fsck.txt"
printf 'Проверка пройдена\nЛоги: %s-*\n' "$out"
