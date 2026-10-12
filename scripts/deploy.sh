#!/usr/bin/env bash
# Полное развёртывание HDFS с edge-ноды team-23-en.
set -euo pipefail
trap 'echo "deploy failed at line $LINENO" >&2' ERR

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

if [[ "$(hostname -s)" != "team-23-en" ]]; then
  echo "Запускайте deploy.sh на team-23-en" >&2
  exit 1
fi
if [[ ! -f "$SSH_KEY" ]]; then
  echo "Нет SSH-ключа ${SSH_KEY}" >&2
  exit 1
fi

mkdir -p /tmp/hdfs-deploy
exec 9>/tmp/hdfs-deploy/deploy.lock
flock -n 9 || { echo "deploy.sh уже запущен" >&2; exit 1; }

step() {
  echo
  echo "==> $*"
}

run_parallel() {
  local label=$1
  shift
  local host pid
  local -a pids=()
  local failed=0
  for host in "$@"; do
    "$label" "$host" >"/tmp/hdfs-deploy/${host}.${label}.log" 2>&1 &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
      failed=1
    fi
  done
  if [[ "$failed" -ne 0 ]]; then
    echo "${label} failed. Logs:" >&2
    cat /tmp/hdfs-deploy/*."${label}".log >&2
    exit 1
  fi
}

bootstrap_host() {
  local host=$1
  echo "[bootstrap] ${host}"
  sudo_script "$host" < "$ROOT/scripts/bootstrap-node.sh"
}

stage_conf() {
  local host=$1
  local stage="/tmp/hdfs-conf-stage-${host}"
  rm -rf "$stage"
  mkdir -p "$stage"
  cp "$ROOT/conf/core-site.xml" \
     "$ROOT/conf/hdfs-site.xml" \
     "$ROOT/conf/workers" \
     "$ROOT/conf/hadoop-env.append.sh" \
     "$ROOT/conf/hadoop.sh" \
     "$stage/"
  if [[ "$(hostname -s)" == "$host" ]]; then
    rm -rf /tmp/hdfs-conf
    mkdir -p /tmp/hdfs-conf
    cp "$stage"/* /tmp/hdfs-conf/
  else
    ssh_base "${SSH_USER}@${host}" 'rm -rf /tmp/hdfs-conf && mkdir -p /tmp/hdfs-conf'
    scp_to "$host" "/tmp/hdfs-conf/" "$stage"/*
  fi
  rm -rf "$stage"
}

install_host() {
  local host=$1
  echo "[install] ${host}"
  stage_conf "$host"
  if [[ "$(hostname -s)" == "$host" ]]; then
    sudo -n env TARBALL="$TARBALL_CACHE" CONF_DIR=/tmp/hdfs-conf bash -s \
      < "$ROOT/scripts/install-node.sh"
  else
    scp_to "$host" "/tmp/${TARBALL}" "$TARBALL_CACHE"
    ssh_base "${SSH_USER}@${host}" \
      "sudo -n env TARBALL=/tmp/${TARBALL} CONF_DIR=/tmp/hdfs-conf bash -s" \
      < "$ROOT/scripts/install-node.sh"
  fi
}

sha512_matches() {
  local expected actual
  [[ -f "$TARBALL_CACHE" && -f "$SHA_CACHE" ]] || return 1
  expected=$(grep -oiE '[0-9a-f]{128}' "$SHA_CACHE" | head -1)
  actual=$(sha512sum "$TARBALL_CACHE" | awk '{print $1}')
  [[ -n "$expected" && "$expected" == "$actual" ]]
}

download_tarball() {
  local sha_url="https://downloads.apache.org/hadoop/common/hadoop-${HADOOP_VERSION}/${TARBALL}.sha512"
  local -a urls=(
    "https://dlcdn.apache.org/hadoop/common/hadoop-${HADOOP_VERSION}/${TARBALL}"
    "https://downloads.apache.org/hadoop/common/hadoop-${HADOOP_VERSION}/${TARBALL}"
    "https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION}/${TARBALL}"
  )
  local url
  echo "Скачиваю контрольную сумму"
  curl -fL --retry 5 --retry-delay 2 -o "$SHA_CACHE" "$sha_url"
  for url in "${urls[@]}"; do
    echo "Скачиваю ${url}"
    if curl -fL --retry 3 --retry-delay 2 -o "${TARBALL_CACHE}.partial" "$url"; then
      mv "${TARBALL_CACHE}.partial" "$TARBALL_CACHE"
      return 0
    fi
    rm -f "${TARBALL_CACHE}.partial"
  done
  echo "Не удалось скачать ${TARBALL}" >&2
  return 1
}

ensure_tarball() {
  if sha512_matches; then
    echo "Архив уже есть, SHA-512 ok"
    return
  fi
  rm -f "$TARBALL_CACHE" "${TARBALL_CACHE}.partial" "$SHA_CACHE"
  download_tarball
  if ! sha512_matches; then
    echo "SHA-512 не совпала" >&2
    exit 1
  fi
  echo "SHA-512 ok"
}

step "Дистрибутив Hadoop ${HADOOP_VERSION}"
ensure_tarball

step "Java, пользователь hdfs и /etc/hosts"
run_parallel bootstrap_host "${NODES[@]}"
for host in "${NODES[@]}"; do
  grep '\[bootstrap\].*ok' "/tmp/hdfs-deploy/${host}.bootstrap_host.log"
done

step "Установка Hadoop и конфигурации"
run_parallel install_host "${NODES[@]}"
for host in "${NODES[@]}"; do
  grep -E 'Hadoop [0-9]' "/tmp/hdfs-deploy/${host}.install_host.log" | tail -1
done

step "SSH для пользователя hdfs с NameNode"
pubkey=$(sudo_script "$NN" < "$ROOT/scripts/print-hdfs-pubkey.sh")
if [[ "$pubkey" != ssh-ed25519\ * ]]; then
  echo "Некорректный публичный ключ: ${pubkey}" >&2
  exit 1
fi
printf '%s\n' "$pubkey" > /tmp/hdfs-cluster.pub
for host in "${NODES[@]}"; do
  if [[ "$(hostname -s)" != "$host" ]]; then
    scp_to "$host" /tmp/hdfs-cluster.pub /tmp/hdfs-cluster.pub
  fi
  sudo_script "$host" < "$ROOT/scripts/authorize-hdfs-key.sh"
done
sudo_script "$NN" < "$ROOT/scripts/trust-hosts.sh"
sudo_script "$NN" <<'EOF'
set -euo pipefail
for h in team-23-en team-23-nn team-23-00 team-23-01; do
  got=$(sudo -u hdfs -H ssh -n "$h" hostname -s)
  echo "hdfs@team-23-nn -> ${h} = ${got}"
  [[ "$got" == "$h" ]]
done
EOF

step "Роли NameNode и Secondary NameNode"
sudo_script "$NN" <<'EOF'
set -euo pipefail
nn=$(sudo -u hdfs -H /opt/hadoop/bin/hdfs getconf -namenodes)
snn=$(sudo -u hdfs -H /opt/hadoop/bin/hdfs getconf -secondarynamenodes)
echo "namenodes: ${nn}"
echo "secondary namenodes: ${snn}"
echo "$nn" | grep -q 'team-23-nn'
echo "$snn" | grep -q 'team-23-en'
if echo "$snn" | grep -q '0.0.0.0'; then
  echo "Secondary NameNode остался на 0.0.0.0" >&2
  exit 1
fi
EOF

step "Форматирование NameNode, если каталог ещё пустой"
sudo_script "$NN" <<'EOF'
set -euo pipefail
if [[ -f /var/lib/hadoop/namenode/current/VERSION ]]; then
  echo "[format] NameNode уже отформатирован"
  exit 0
fi
if [[ -n "$(ls -A /var/lib/hadoop/namenode 2>/dev/null || true)" ]]; then
  echo "Каталог NameNode не пуст и не содержит VERSION" >&2
  exit 1
fi
sudo -u hdfs -H /opt/hadoop/bin/hdfs namenode -format -nonInteractive
EOF

step "Запуск HDFS"
"$ROOT/scripts/start.sh"

step "Проверка кластера"
"$ROOT/scripts/verify.sh"
