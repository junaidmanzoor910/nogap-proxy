#!/usr/bin/env bash
# Add or update one proxy user. Prefer interactive password entry (not visible in ps).
set -euo pipefail

PASSWD_FILE="/etc/squid/passwords"
SQUID_GROUP="proxy"

usage() {
  echo "Usage: sudo $0 <username>" >&2
  exit 1
}

ensure_password_file() {
  if [[ ! -f "$PASSWD_FILE" ]]; then
    install -d -m 0750 /etc/squid
    install -m 0640 /dev/null "$PASSWD_FILE"
    chown root:"${SQUID_GROUP}" "$PASSWD_FILE" 2>/dev/null || true
  fi
}

[[ $# -eq 1 ]] || usage
USER="$1"
if [[ ! "$USER" =~ ^[a-z][a-z0-9_-]{2,31}$ ]]; then
  echo "Username must be 3-32 chars: lowercase letter, then [a-z0-9_-]." >&2
  exit 1
fi

ensure_password_file

if [[ $(wc -l < "$PASSWD_FILE") -ge 10 ]] && ! grep -q "^${USER}:" "$PASSWD_FILE" 2>/dev/null; then
  echo "Maximum 10 accounts. Revoke an unused account first." >&2
  exit 1
fi

if [[ -n "${PROXY_PASSWORD:-}" ]]; then
  echo "Warning: PROXY_PASSWORD env may be visible in process listings; prefer interactive entry." >&2
  PASS="$PROXY_PASSWORD"
else
  read -r -s -p "Password for ${USER}: " PASS
  echo
  read -r -s -p "Confirm password: " PASS2
  echo
  [[ "$PASS" == "$PASS2" ]] || { echo "Passwords do not match." >&2; exit 1; }
fi

TMP="$(mktemp)"
chmod 600 "$TMP"
grep -v "^${USER}:" "$PASSWD_FILE" > "$TMP" 2>/dev/null || : > "$TMP"
# Write hash line without keeping password on argv longer than necessary.
htpasswd -nbB "$USER" "$PASS" >> "$TMP"
PASS=""
unset PASS PASS2 PROXY_PASSWORD

install -m 0640 -o root -g "${SQUID_GROUP}" "$TMP" "$PASSWD_FILE" 2>/dev/null \
  || install -m 0640 "$TMP" "$PASSWD_FILE"
rm -f "$TMP"

if command -v squid >/dev/null 2>&1; then
  squid -k parse && systemctl reload squid
fi
echo "User ${USER} provisioned."
