#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

mkdir -p "$ROOT/evidence"
run="hm2-$(date +%Y%m%d-%H%M%S)-$$"
path="/user/hdfs/$run"
log="$ROOT/evidence/$run.log"

ready=0
for attempt in $(seq 1 30); do
  if curl -fsS --max-time 5 http://team-23-nn:8088/ws/v1/cluster/nodes | python3 -c '
import json, sys
nodes = json.load(sys.stdin).get("nodes") or {}
active = {n["nodeHostName"] for n in nodes.get("node", []) if n["state"] == "RUNNING" and n.get("healthReport", "") == ""}
sys.exit(active != {"team-23-en", "team-23-00", "team-23-01"})
'; then
    ready=1
    break
  fi
  sleep 2
done
[[ $ready == 1 ]] || { echo 'Три NodeManager не готовы' >&2; exit 1; }
echo 'NodeManager: 3 RUNNING'
as_hdfs team-23-en "$HADOOP/bin/yarn" node -list

as_hdfs team-23-en "$HADOOP/bin/hdfs" dfs -mkdir -p "$path/input"
printf 'hadoop yarn hadoop\n' | sudo -n -u hdfs -H "$HADOOP/bin/hdfs" dfs -put - "$path/input/text.txt"
if ! timeout 180 sudo -n -u hdfs -H "$HADOOP/bin/hadoop" jar \
  "$HADOOP/share/hadoop/mapreduce/hadoop-mapreduce-examples-3.4.3.jar" \
  wordcount "$path/input" "$path/output" >"$log" 2>&1; then
  echo "Задача не завершилась, лог: $log" >&2
  tail -40 "$log" >&2
  exit 1
fi

app=$(grep -oE 'application_[0-9]+_[0-9]+' "$log" | sed -n '1p')
[[ -n $app ]] || { echo 'В логе нет ID приложения YARN' >&2; exit 1; }
curl -fsS --max-time 10 "http://team-23-nn:8088/ws/v1/cluster/apps/$app" | python3 -c '
import json, sys
app = json.load(sys.stdin)["app"]
print(app["id"], app["state"], app["finalStatus"])
assert app["state"] == "FINISHED" and app["finalStatus"] == "SUCCEEDED"
'
result=$(as_hdfs team-23-en "$HADOOP/bin/hdfs" dfs -cat "$path/output/part-r-00000")
[[ $result == $'hadoop\t2\nyarn\t1' ]] || { echo "Неожиданный результат: $result" >&2; exit 1; }
printf '%s\n' "$result"

job=${app/application_/job_}
history=0
for attempt in $(seq 1 30); do
  if curl -fsS --max-time 5 "http://team-23-en:19888/ws/v1/history/mapreduce/jobs/$job" | python3 -c '
import json, sys
job = json.load(sys.stdin)["job"]
assert job["state"] == "SUCCEEDED"
print("JobHistory:", job["id"], job["state"])
'; then history=1; break; fi
  sleep 2
done
[[ $history == 1 ]] || { echo 'Задача не появилась в JobHistory' >&2; exit 1; }

report=$(as_hdfs team-23-en "$HADOOP/bin/hdfs" dfsadmin -report)
grep -q 'Live datanodes (3)' <<<"$report"
! grep -Eq 'Dead datanodes \([1-9]' <<<"$report"
grep -Eq 'Missing blocks: 0$' <<<"$report"
grep -Eq 'Blocks with corrupt replicas: 0$' <<<"$report"
as_hdfs team-23-en "$HADOOP/bin/hdfs" fsck "$path" -files -blocks | tee "$ROOT/evidence/$run-fsck.txt"
grep -q 'is HEALTHY' "$ROOT/evidence/$run-fsck.txt"
printf 'Проверка пройдена\nПриложение: %s\nДанные: %s\nЛог: %s\n' "$app" "$path" "$log"
