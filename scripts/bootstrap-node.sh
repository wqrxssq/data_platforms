#!/usr/bin/env bash
# Подготовка одного узла: Java 17, пользователь hdfs, каталоги, /etc/hosts.
set -euo pipefail
trap 'echo "[bootstrap] failed on $(hostname -s) at line $LINENO" >&2' ERR

export DEBIAN_FRONTEND=noninteractive

retry() {
  local attempt=0
  until "$@"; do
    attempt=$((attempt + 1))
    if [[ "$attempt" -ge 5 ]]; then
      echo "[bootstrap] giving up: $*" >&2
      return 1
    fi
    echo "[bootstrap] retry ${attempt}: $*" >&2
    sleep 10
  done
}

echo "[bootstrap] $(hostname -s) packages"
retry apt-get update -qq
retry apt-get install -y openjdk-17-jdk-headless ca-certificates curl tar

if [[ ! -x /usr/lib/jvm/java-17-openjdk-amd64/bin/java ]]; then
  echo "[bootstrap] unexpected JAVA_HOME layout: $(readlink -f "$(command -v java)")" >&2
  exit 1
fi

if ! id hdfs >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash --user-group hdfs
fi
install -d -o hdfs -g hdfs -m 700 /home/hdfs/.ssh
install -d -o hdfs -g hdfs -m 755 \
  /var/lib/hadoop/namenode \
  /var/lib/hadoop/datanode \
  /var/lib/hadoop/namesecondary \
  /var/lib/hadoop/tmp \
  /var/lib/hadoop/pids \
  /var/log/hadoop

ensure_host() {
  local ip=$1 name=$2
  if ! awk -v ip="$ip" -v name="$name" '
    $1 == ip { for (i = 2; i <= NF; i++) if ($i == name) found = 1 }
    END { exit !found }
  ' /etc/hosts; then
    echo "${ip} ${name}" >> /etc/hosts
  fi
}

ensure_host 10.23.0.10 team-23-en
ensure_host 10.23.0.11 team-23-nn
ensure_host 10.23.0.12 team-23-00
ensure_host 10.23.0.13 team-23-01

short=$(hostname -s)
ip=$(awk -v n="$short" '$1 ~ /^10\./ { for (i = 2; i <= NF; i++) if ($i == n) { print $1; exit } }' /etc/hosts)
if [[ -z "$ip" ]]; then
  echo "[bootstrap] no address for ${short} in /etc/hosts" >&2
  exit 1
fi
fqdn=$(awk -v n="$short" '$1 == "127.0.1.1" { for (i = 2; i <= NF; i++) if (index($i, ".") > 0) { print $i; exit } }' /etc/hosts)
if [[ -z "$fqdn" ]]; then
  fqdn=$(awk -v ip="$ip" '$1 == ip { for (i = 2; i <= NF; i++) if (index($i, ".") > 0) { print $i; exit } }' /etc/hosts)
fi

tmp=$(mktemp)
awk -v short="$short" -v fqdn="$fqdn" -v ip="$ip" '
  $1 == "127.0.1.1" {
    out = $1
    for (i = 2; i <= NF; i++) if ($i != short && $i != fqdn) out = out " " $i
    print out
    next
  }
  $1 == ip {
    if (fqdn != "") print ip " " short " " fqdn
    else print ip " " short
    next
  }
  { print }
' /etc/hosts > "$tmp"
cat "$tmp" > /etc/hosts
rm -f "$tmp"

declare -A expected=(
  [team-23-en]=10.23.0.10
  [team-23-nn]=10.23.0.11
  [team-23-00]=10.23.0.12
  [team-23-01]=10.23.0.13
)
for name in "${!expected[@]}"; do
  got=$(getent ahostsv4 "$name" | awk '{print $1; exit}')
  if [[ "$got" != "${expected[$name]}" ]]; then
    echo "[bootstrap] ${name} resolves to ${got:-nothing}, expected ${expected[$name]}" >&2
    exit 1
  fi
done

check_dir=$(mktemp -d)
cat > "${check_dir}/HostCheck.java" <<'EOF'
import java.net.InetAddress;
public class HostCheck {
  public static void main(String[] args) throws Exception {
    System.out.println(InetAddress.getLocalHost().getHostAddress());
  }
}
EOF
javac "${check_dir}/HostCheck.java"
java_ip=$(timeout 20 java -cp "$check_dir" HostCheck)
rm -rf "$check_dir"
echo "[bootstrap] $(hostname -s) java InetAddress.getLocalHost -> ${java_ip}"
if [[ "$java_ip" == 127.* ]]; then
  echo "[bootstrap] hostname resolves to loopback" >&2
  exit 1
fi

echo "[bootstrap] $(hostname -s) ok"
