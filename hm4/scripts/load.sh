#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

mkdir -p "$ROOT/evidence"
run="hm4-load-$(date +%Y%m%d-%H%M%S)"
input="$ROOT/evidence/$run.csv"
log="$ROOT/evidence/$run.log"

python3 "$ROOT/scripts/gen_sales.py" > "$input"
echo "Файл $input, строк данных: $(($(wc -l <"$input") - 1))"

staging="/user/hive/staging/sales"
as_hdfs "$HADOOP/bin/hdfs" dfs -rm -r -f -skipTrash "$staging"
as_hdfs "$HADOOP/bin/hdfs" dfs -mkdir -p "$staging"

# заголовок срезаем, имена колонок job задаёт сам
if ! tail -n +2 "$input" | as_hdfs "$HADOOP/bin/hdfs" dfs -put - "$staging/sales.csv" > "$log" 2>&1; then
  echo "Ошибка загрузки, лог: $log" >&2
  tail -40 "$log" >&2
  exit 1
fi

echo "Файлы в HDFS:"
as_hdfs "$HADOOP/bin/hdfs" dfs -ls "$staging"
echo 'Дальше ./scripts/start.sh'
