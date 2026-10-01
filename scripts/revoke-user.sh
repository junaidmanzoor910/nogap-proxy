#!/usr/bin/env bash
set -euo pipefail

PASSWD_FILE="/etc/squid/passwords"
SQUID_GROUP="proxy"

[[ $# -eq 1 ]] || { echo "Usage: sudo $0 <username>" >&2; exit 1; }
USER="$1"

[[ -f "$PASSWD_FILE" ]] || { echo "No password file." >&2; exit 1; }
grep -q "^${USER}:" "$PASSWD_FILE" || { echo "User not found." >&2; exit 1; }

TMP="$(mktemp)"
chmod 600 "$TMP"
grep -v "^${USER}:" "$PASSWD_FILE" > "$TMP"
install -m 0640 -o root -g "${SQUID_GROUP}" "$TMP" "$PASSWD_FILE" 2>/dev/null \
  || install -m 0640 "$TMP" "$PASSWD_FILE"
rm -f "$TMP"

if command -v squid >/dev/null 2>&1; then
  squid -k parse && systemctl reload squid
fi
echo "User ${USER} revoked."
