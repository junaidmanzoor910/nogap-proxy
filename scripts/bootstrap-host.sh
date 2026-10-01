#!/usr/bin/env bash
# Run on the instance (via SSM) after cloning/syncing this repository to /opt/nogap-split-proxy.
set -euo pipefail

ENV_FILE="/etc/nogap-split-proxy/env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE — run cloud-init first or create env file." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  squid-openssl nginx certbot python3-certbot-dns-cloudflare amazon-ssm-agent apache2-utils jq

systemctl enable amazon-ssm-agent
systemctl restart amazon-ssm-agent

mkdir -p /etc/squid/tls /var/www/pac /etc/squid/ssl 2>/dev/null || true
chmod 750 /etc/squid
chmod 700 /etc/squid/tls

echo "Host packages installed. Next: place TLS certs, deploy-config.sh, provision users."
