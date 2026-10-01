#!/usr/bin/env bash
# Create up to 10 proxy users with random passwords. Credentials written root-only on the instance.
set -euo pipefail

PASSWD_FILE="/etc/squid/passwords"
SQUID_GROUP="proxy"
CREDFILE="${CREDFILE:-/root/nogap-proxy-initial-users.txt}"
PREFIX="${USER_PREFIX:-proxyuser}"

if [[ $(id -u) -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

install -d -m 0750 /etc/squid
install -m 0600 /dev/null "$CREDFILE"
install -m 0640 -o root -g "${SQUID_GROUP}" /dev/null "$PASSWD_FILE"

for i in $(seq 1 10); do
  u="${PREFIX}$(printf '%02d' "$i")"
  p="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 24)"
  htpasswd -bB "$PASSWD_FILE" "$u" "$p"
  printf '%s %s\n' "$u" "$p" >> "$CREDFILE"
done
chmod 600 "$CREDFILE"

if command -v squid >/dev/null 2>&1; then
  squid -k parse && systemctl reload squid
fi

echo "Provisioned 10 users (${PREFIX}01..${PREFIX}10)."
echo "Credentials: ${CREDFILE} (mode 600). Retrieve only via SSM; do not log or commit."
