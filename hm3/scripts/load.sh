#!/usr/bin/env bash
# ./scripts/load.sh [файл.csv] — без аргумента генерирует тестовые продажи
set -euo pipefail
source "$(dirname "$0")/common.sh"

mkdir -p "$ROOT/evidence"
run="hm3-load-$(date +%Y%m%d-%H%M%S)"
log="$ROOT/evidence/$run.log"
staging=/user/hive/staging/sales
header='order_id,order_date,customer_id,region,product,quantity,price'

input=${1:-}
if [[ -z $input ]]; then
  input="$ROOT/evidence/$run.csv"
  python3 "$ROOT/scripts/gen_sales.py" >"$input"
fi
[[ $(head -1 "$input") == "$header" ]] || { echo "Ожидается заголовок $header" >&2; exit 1; }
echo "Файл $input, строк данных: $(($(wc -l <"$input") - 1))"

as_hive "$EDGE" "$HADOOP/bin/hdfs" dfs -rm -r -f -skipTrash "$staging"
as_hive "$EDGE" "$HADOOP/bin/hdfs" dfs -mkdir -p "$staging"
# Заголовок отрезается здесь: skip.header.line.count в этой версии Hive не работает при чтении через MapReduce
tail -n +2 "$input" | sudo -n -u hive -H "$HADOOP/bin/hdfs" dfs -put - "$staging/sales.csv"

if ! beeline "$EDGE" --hivevar staging_dir="$staging" -f "$ROOT/sql/load.hql" >"$log" 2>&1; then
  echo "Загрузка не удалась, лог: $log" >&2
  tail -40 "$log" >&2
  exit 1
fi
echo 'Партиции hm3.sales:'
grep '^order_date=' "$log"
echo "Лог: $log"
echo 'Дальше ./scripts/check.sh'
