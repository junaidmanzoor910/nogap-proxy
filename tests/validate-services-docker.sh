#!/usr/bin/env bash
# Render configs and run nginx -t / squid -k parse on Ubuntu 24.04 (same major package as EC2).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v docker >/dev/null 2>&1; then
  echo "SKIP: docker not available for containerized nginx/squid validation"
  exit 0
fi

echo "== Containerized Squid/Nginx validation (Ubuntu 24.04) =="

docker run --rm -v "${ROOT}:/work" ubuntu:24.04 bash -ec '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq squid-openssl nginx gettext-base openssl ca-certificates >/dev/null
grep -q openssl <<< "$(squid -v 2>&1)" || { echo "FAIL: expected squid-openssl package"; exit 1; }

mkdir -p /etc/squid/tls /var/www/pac /var/log/squid
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout /etc/squid/tls/privkey.pem -out /etc/squid/tls/fullchain.pem \
  -subj /CN=proxy-dev.nogap.ai -days 1 2>/dev/null
chmod 644 /etc/squid/tls/fullchain.pem
chmod 600 /etc/squid/tls/privkey.pem
touch /etc/squid/passwords

export PROXY_HOSTNAME=proxy-dev.nogap.ai
export ALLOWED_DESTINATION_DOMAIN=app-dev.nogap.ai
export PAC_HTTPS_PORT=8443
export PROXY_HTTPS_PORT=443

envsubst "\${PROXY_HOSTNAME} \${ALLOWED_DESTINATION_DOMAIN} \${PAC_HTTPS_PORT} \${PROXY_HTTPS_PORT}" \
  < /work/config/squid.conf.template > /etc/squid/squid.conf

envsubst "\${PROXY_HOSTNAME} \${PAC_HTTPS_PORT}" \
  < /work/config/nginx-pac.conf > /etc/nginx/conf.d/pac.conf
cp /work/config/proxy.pac /var/www/pac/proxy.pac

cat > /etc/nginx/nginx.conf <<NGX
user www-data;
worker_processes 1;
events { worker_connections 1024; }
http { include /etc/nginx/conf.d/*.conf; }
NGX

echo "-- squid version --"
squid -v | head -1

echo "-- squid -k parse --"
if ! squid -k parse 2>&1; then
  echo "FAIL: squid -k parse"
  exit 1
fi

echo "-- nginx -t --"
if ! nginx -t 2>&1; then
  echo "FAIL: nginx -t"
  exit 1
fi

echo "PASS: squid and nginx configuration valid on Ubuntu 24.04"
'
