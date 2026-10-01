#!/usr/bin/env bash
# Render templates and reload Squid/Nginx. Requires TLS files at /etc/squid/tls/{fullchain.pem,privkey.pem}.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="/etc/nogap-split-proxy/env"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  PROXY_HOSTNAME="${PROXY_HOSTNAME:-proxy-dev.nogap.ai}"
  ALLOWED_DESTINATION_DOMAIN="${ALLOWED_DESTINATION_DOMAIN:-app-dev.nogap.ai}"
  PAC_HTTPS_PORT="${PAC_HTTPS_PORT:-8443}"
  PROXY_HTTPS_PORT="${PROXY_HTTPS_PORT:-443}"
fi

TLS_DIR="/etc/squid/tls"
for f in fullchain.pem privkey.pem; do
  if [[ ! -f "$TLS_DIR/$f" ]]; then
    echo "Missing $TLS_DIR/$f — issue certificate before deploy-config (see docs/CLOUDFLARE-DNS.md)." >&2
    exit 1
  fi
done
# shellcheck source=lib/validate-fullchain-pem.sh
source "$ROOT/scripts/lib/validate-fullchain-pem.sh"
if [[ -f "/etc/letsencrypt/live/${PROXY_HOSTNAME:-proxy-dev.nogap.ai}/fullchain.pem" ]]; then
  validate_le_fullchain_pem "$TLS_DIR/fullchain.pem" || {
    echo "Refusing deploy: install Let's Encrypt fullchain.pem (not cert.pem alone)." >&2
    exit 1
  }
else
  validate_fullchain_pem "$TLS_DIR/fullchain.pem" 1 || exit 1
fi
chmod 644 "$TLS_DIR/fullchain.pem"
chmod 600 "$TLS_DIR/privkey.pem"

export PROXY_HOSTNAME ALLOWED_DESTINATION_DOMAIN PAC_HTTPS_PORT PROXY_HTTPS_PORT
envsubst '${PROXY_HOSTNAME} ${ALLOWED_DESTINATION_DOMAIN} ${PAC_HTTPS_PORT} ${PROXY_HTTPS_PORT}' \
  < "$ROOT/config/squid.conf.template" > /etc/squid/squid.conf

envsubst '${PROXY_HOSTNAME} ${PAC_HTTPS_PORT}' \
  < "$ROOT/config/nginx-pac.conf" > /etc/nginx/sites-available/pac.conf

install -m 0644 "$ROOT/config/proxy.pac" /var/www/pac/proxy.pac

# Auth helper runs as user "proxy" and must traverse this directory.
chown root:proxy /etc/squid
chmod 750 /etc/squid

if [[ ! -f /etc/squid/passwords ]]; then
  install -m 0640 -o root -g proxy /dev/null /etc/squid/passwords
fi

install -m 0644 "$ROOT/config/logrotate/squid" /etc/logrotate.d/squid-nogap

ln -sf /etc/nginx/sites-available/pac.conf /etc/nginx/sites-enabled/pac.conf
rm -f /etc/nginx/sites-enabled/default

squid -k parse
nginx -t

systemctl enable squid nginx
systemctl restart squid nginx

echo "Squid and Nginx reloaded."
