#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

mkdir -p "$ROOT/evidence"
run="hm4-start-$(date +%Y%m%d-%H%M%S)"
log="$ROOT/evidence/$run.log"

# spark-submit работает от пользователя hdfs, а домашняя папка team ему не видна,
# поэтому кладём job в /tmp и запускаем оттуда
cp "$ROOT/spark/job.py" /tmp/hm4-job.py
chmod 644 /tmp/hm4-job.py

echo "Запуск Spark на YARN"
if ! as_hdfs "$SPARK/bin/spark-submit" --master yarn --deploy-mode client /tmp/hm4-job.py > "$log" 2>&1; then
  echo "Ошибка Spark, лог: $log" >&2
  tail -40 "$log" >&2
  exit 1
fi

# приложение должно быть видно в YARN и завершиться успешно
app=$(grep -oE 'application_[0-9]+_[0-9]+' "$log" | head -1 || true)
[[ -n $app ]] || { echo 'В логе нет ID приложения YARN' >&2; exit 1; }
as_hdfs "$HADOOP/bin/yarn" application -status "$app" > "$ROOT/evidence/$run-yarn.txt" 2>&1 || true
if ! grep 'Final-State' "$ROOT/evidence/$run-yarn.txt" | grep -q SUCCEEDED; then
  echo "Приложение $app не завершилось со статусом SUCCEEDED" >&2
  cat "$ROOT/evidence/$run-yarn.txt" >&2
  exit 1
fi
echo "Приложение YARN: $app, статус SUCCEEDED"

echo "Регистрация таблицы в Hive"
hive_log="$ROOT/evidence/$run-hive.log"
if ! "$HIVE/bin/beeline" -u "$JDBC_URL" -n hive -f "$ROOT/sql/create.hql" > "$hive_log" 2>&1; then
  echo "Ошибка регистрации, лог: $hive_log" >&2
  tail -40 "$hive_log" >&2
  exit 1
fi

echo 'Дальше ./scripts/check.sh'
