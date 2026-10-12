#!/usr/bin/env bash
# Проверяет три живых DataNode, веб-интерфейсы, запись файла и логи.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

JPS=/usr/lib/jvm/java-17-openjdk-amd64/bin/jps
HDFS=/opt/hadoop/bin/hdfs
fail=0

note() {
  echo
  echo "==> $*"
}

jps_on() {
  local host=$1
  if [[ "$(hostname -s)" == "$host" ]]; then
    sudo -n -u hdfs -H "$JPS"
  else
    ssh_base "${SSH_USER}@${host}" sudo -n -u hdfs -H "$JPS"
  fi
}

has_proc() {
  local out=$1 proc=$2
  echo "$out" | awk '{print $2}' | grep -qx "$proc"
}

require_proc() {
  local host=$1 proc=$2 out=$3
  if ! has_proc "$out" "$proc"; then
    echo "${host}: нет процесса ${proc}" >&2
    echo "$out" >&2
    fail=1
  fi
}

forbid_proc() {
  local host=$1 proc=$2 out=$3
  if has_proc "$out" "$proc"; then
    echo "${host}: лишний процесс ${proc}" >&2
    echo "$out" >&2
    fail=1
  fi
}

http_code() {
  curl -sS -L -o /dev/null -w '%{http_code}' --max-time 10 "$1" || echo fail
}

note "Состояние кластера"
report=""
live=""
mode=""
report_err=$(mktemp)
trap 'rm -f "$report_err" "$report_err.out"' EXIT
for _ in $(seq 1 12); do
  if ! sudo -n -u hdfs -H "$HDFS" dfsadmin -report >"$report_err.out" 2>"$report_err"; then
    echo "NameNode не отвечает:" >&2
    cat "$report_err" >&2
    echo "Кластер не запущен. Сначала ./scripts/start.sh" >&2
    exit 1
  fi
  report=$(cat "$report_err.out")
  live=$(echo "$report" | sed -n 's/^Live datanodes (\([0-9]*\)).*/\1/p' | head -1)
  mode=$(sudo -n -u hdfs -H "$HDFS" dfsadmin -safemode get 2>/dev/null | grep -F 'Safe mode is' | head -1 || true)
  echo "live=${live:-0} ${mode:-safemode unknown}"
  if [[ "${live:-0}" == "3" && "$mode" == "Safe mode is OFF"* ]]; then
    break
  fi
  sleep 5
done
rm -f "$report_err" "$report_err.out"
trap - EXIT

if [[ "${live:-0}" != "3" || "$mode" != "Safe mode is OFF"* ]]; then
  echo "Кластер не собрался: нужно 3 DataNode и Safe mode is OFF" >&2
  echo "$report" >&2
  exit 1
fi

dead=$(echo "$report" | sed -n 's/^Dead datanodes (\([0-9]*\)).*/\1/p' | head -1)
dead=${dead:-0}
if [[ "$dead" != "0" ]]; then
  echo "Есть мёртвые DataNode: ${dead}" >&2
  echo "$report" >&2
  fail=1
fi
for host in "${DN_NODES[@]}"; do
  if ! echo "$report" | grep -q "$host"; then
    echo "В отчёте нет ${host}" >&2
    fail=1
  fi
done

note "Процессы jps"
declare -A jps_out
for host in "${NODES[@]}"; do
  jps_out[$host]=$(jps_on "$host")
  echo "--- ${host} ---"
  echo "${jps_out[$host]}"
done
require_proc team-23-nn NameNode "${jps_out[team-23-nn]}"
forbid_proc team-23-nn DataNode "${jps_out[team-23-nn]}"
forbid_proc team-23-nn SecondaryNameNode "${jps_out[team-23-nn]}"
require_proc team-23-en DataNode "${jps_out[team-23-en]}"
require_proc team-23-en SecondaryNameNode "${jps_out[team-23-en]}"
forbid_proc team-23-en NameNode "${jps_out[team-23-en]}"
require_proc team-23-00 DataNode "${jps_out[team-23-00]}"
forbid_proc team-23-00 NameNode "${jps_out[team-23-00]}"
forbid_proc team-23-00 SecondaryNameNode "${jps_out[team-23-00]}"
require_proc team-23-01 DataNode "${jps_out[team-23-01]}"
forbid_proc team-23-01 NameNode "${jps_out[team-23-01]}"
forbid_proc team-23-01 SecondaryNameNode "${jps_out[team-23-01]}"

note "Веб-интерфейсы"
declare -A urls=(
  [NameNode]=http://team-23-nn:9870/
  [SecondaryNameNode]=http://team-23-en:9868/
  [DataNode-en]=http://team-23-en:9864/
  [DataNode-00]=http://team-23-00:9864/
  [DataNode-01]=http://team-23-01:9864/
)
for name in "${!urls[@]}"; do
  code=$(http_code "${urls[$name]}")
  echo "${name} ${urls[$name]} -> ${code}"
  if [[ "$code" != "200" ]]; then
    fail=1
  fi
done

note "Запись и чтение файла с репликацией 3"
sudo -n -u hdfs -H "$HDFS" dfs -mkdir -p /user/hdfs
echo "cluster-check $(date -Is)" | sudo -n -u hdfs -H "$HDFS" dfs -put -f - /user/hdfs/cluster-check.txt
echo "Содержимое:"
sudo -n -u hdfs -H "$HDFS" dfs -cat /user/hdfs/cluster-check.txt

fsck=""
healthy=0
for _ in $(seq 1 12); do
  fsck=$(sudo -n -u hdfs -H "$HDFS" fsck /user/hdfs/cluster-check.txt -files -blocks 2>&1 || true)
  if echo "$fsck" | grep -q 'is HEALTHY' \
    && echo "$fsck" | grep -q 'replication=3' \
    && echo "$fsck" | grep -q 'Under-replicated blocks:[[:space:]]*0' \
    && echo "$fsck" | grep -q 'Number of data-nodes:[[:space:]]*3'; then
    healthy=1
    break
  fi
  sleep 5
done
echo "$fsck"
if [[ "$healthy" -ne 1 ]]; then
  echo "Файл не здоров или репликация не равна 3" >&2
  fail=1
fi

note "Логи"
for host in "${NODES[@]}"; do
  if [[ "$(hostname -s)" == "$host" ]]; then
    raw=$(sudo -n grep -R -E ' ERROR | FATAL ' /var/log/hadoop --include='*.log' --include='*.out' || true)
  else
    raw=$(ssh_base "${SSH_USER}@${host}" \
      "sudo -n grep -R -E ' ERROR | FATAL ' /var/log/hadoop --include='*.log' --include='*.out'" || true)
  fi
  # stop-dfs.sh шлёт SIGTERM, Hadoop пишет это на уровне ERROR.
  errors=$(printf '%s\n' "$raw" | grep -v 'RECEIVED SIGNAL 15: SIGTERM' || true)
  if [[ -n "$errors" ]]; then
    echo "--- ${host} ---"
    echo "$errors"
    fail=1
  else
    echo "${host}: критических записей нет"
  fi
done

echo
if [[ "$fail" -ne 0 ]]; then
  echo "Проверка не пройдена"
  exit 1
fi
echo "Кластер в порядке: 3 DataNode, safe mode выключен, файл реплицирован"
sudo -n -u hdfs -H "$HDFS" dfsadmin -report
