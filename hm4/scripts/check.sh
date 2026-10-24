#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

mkdir -p "$ROOT/evidence"
run="hm4-check-$(date +%Y%m%d-%H%M%S)"
out="$ROOT/evidence/$run"

echo "Партиции в HDFS"
as_hdfs "$HADOOP/bin/hdfs" dfs -ls -R /user/hive/warehouse/hm4.db/sales_agg > "$out-hdfs.txt"
grep -q 'order_date=' "$out-hdfs.txt" || { echo 'Партиций в HDFS нет' >&2; exit 1; }
# ls -R печатает по две строки на каждый раздел: сам каталог order_date=...
# и файл part-*.parquet внутри него; каталоги в выводе ls начинаются с d
echo "Строк с order_date=: $(grep -c 'order_date=' "$out-hdfs.txt") (каталог + файл на каждый раздел)"
echo "Каталогов-разделов:  $(grep -c '^d.*order_date=' "$out-hdfs.txt") (должно совпасть с SHOW PARTITIONS)"

echo "Чтение стандартным клиентом Hive"
if ! "$HIVE/bin/beeline" -u "$JDBC_URL" -n hive -e "
SHOW PARTITIONS hm4.sales_agg;
SELECT * FROM hm4.sales_agg ORDER BY order_date, region LIMIT 10;
SELECT SUM(orders_count) AS orders, ROUND(SUM(total_revenue), 2) AS revenue FROM hm4.sales_agg;
" > "$out-beeline.txt" 2>&1; then
  echo "Ошибка чтения, лог: $out-beeline.txt" >&2
  tail -40 "$out-beeline.txt" >&2
  exit 1
fi

[[ -s "$out-beeline.txt" ]] || { echo 'Hive не вернул данные' >&2; exit 1; }
grep -q 'order_date=' "$out-beeline.txt" || { echo 'Через Hive партиции не видны' >&2; exit 1; }
cat "$out-beeline.txt"

echo "Проверка пройдена, логи: $out-*"
