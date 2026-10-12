#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/hm2"

cat >"$stage/hm2/proxy.conf" <<'NGINX'
proxy_http_version 1.1;
proxy_set_header Accept-Encoding "";
proxy_set_header X-Forwarded-For $remote_addr;
proxy_read_timeout 60s;
sub_filter_once off;
sub_filter_types application/json application/javascript text/javascript text/plain;
limit_except GET HEAD { deny all; }
NGINX

printf '<!doctype html><html lang="ru"><meta charset="utf-8"><title>team-23</title><h1>Кластер team-23</h1><ul>\n' >"$stage/index.html"
while read -r name host internal_ip internal_port local_port; do
  [[ -n $name && $name != \#* ]] || continue
  # Hadoop добавляет внутренние адреса в ссылки и редиректы
  for address in "$host" "$internal_ip"; do
    printf "sub_filter '%s:%s' 'localhost:%s';\n" "$address" "$internal_port" "$local_port" >>"$stage/hm2/proxy.conf"
    printf 'proxy_redirect http://%s:%s/ http://localhost:%s/;\n' "$address" "$internal_port" "$local_port" >>"$stage/hm2/proxy.conf"
  done
  cat >>"$stage/hm2.conf" <<NGINX
server {
    listen 127.0.0.1:$local_port;
    server_name localhost;
    access_log /var/log/nginx/hm2-access.log;
    error_log /var/log/nginx/hm2-error.log;
    location / {
        proxy_pass http://$host:$internal_port;
        proxy_set_header Host $host:$internal_port;
        include /etc/nginx/hm2/proxy.conf;
    }
}
NGINX
  printf '<li><a href="http://localhost:%s/">%s</a></li>\n' "$local_port" "$name" >>"$stage/index.html"
done <"$ROOT/conf/web-interfaces.tsv"
echo '</ul><p>ДЗ 2 — YARN и веб-интерфейсы</p></html>' >>"$stage/index.html"
cat >>"$stage/hm2.conf" <<NGINX
server {
    listen 127.0.0.1:18080;
    server_name localhost;
    root /var/www/hm2;
    access_log /var/log/nginx/hm2-access.log;
    error_log /var/log/nginx/hm2-error.log;
    location / { limit_except GET HEAD { deny all; } }
}
NGINX

if ! command -v nginx >/dev/null; then
  sudo -n apt-get update
  sudo -n env DEBIAN_FRONTEND=noninteractive apt-get install -y nginx
  # У свежей установки убираем стандартный сайт на порту 80
  sudo -n rm -f /etc/nginx/sites-enabled/default
fi
if [[ -f /etc/nginx/conf.d/hm2.conf ]]; then
  backup="/var/backups/hm2-web-$(date +%Y%m%d-%H%M%S)"
  sudo -n mkdir -p "$backup"
  sudo -n cp -a /etc/nginx/conf.d/hm2.conf /etc/nginx/hm2 "$backup/"
fi
sudo -n install -d -m 755 /etc/nginx/hm2 /var/www/hm2
sudo -n install -m 644 "$stage/hm2/"*.conf /etc/nginx/hm2/
sudo -n install -m 644 "$stage/hm2.conf" /etc/nginx/conf.d/hm2.conf
sudo -n install -m 644 "$stage/index.html" /var/www/hm2/index.html
sudo -n nginx -t
sudo -n systemctl reload nginx
echo 'Интерфейсы слушают только 127.0.0.1 на edge'
echo 'На ноутбуке запустите ./scripts/open-ui.sh, затем откройте http://localhost:18080/'
