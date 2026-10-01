#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${NOGAP_FORWARDER_STATE:-${HOME}/.nogap-proxy-forwarder}"
SQUID_INSTANCE="${NOGAP_SQUID_INSTANCE:-nogapfwd}"
LISTEN_PORT="${NOGAP_LOCAL_FORWARDER_PORT:-3129}"
PIDFILE="${STATE_DIR}/squid.pid"
CONF="${STATE_DIR}/squid.conf"

if [[ -f "$CONF" ]]; then
  squid -n "$SQUID_INSTANCE" -f "$CONF" -k shutdown 2>/dev/null || true
fi

if [[ -f "$PIDFILE" ]]; then
  kill "$(cat "$PIDFILE")" 2>/dev/null || true
  rm -f "$PIDFILE"
fi

# Orphan listeners from this forwarder (e.g. after kill -9)
if command -v lsof >/dev/null 2>&1; then
  while read -r pid; do
    [[ -z "$pid" ]] && continue
    args="$(ps -p "$pid" -o args= 2>/dev/null || true)"
    if [[ "$args" == *"${STATE_DIR}"* ]] || [[ "$args" == *"${SQUID_INSTANCE}"* ]] || [[ "$args" == *"squid"* ]]; then
      kill "$pid" 2>/dev/null || true
    fi
  done < <(lsof -t -i ":${LISTEN_PORT}" -sTCP:LISTEN 2>/dev/null || true)
fi

# Restore Docker config if modified by forwarder
DOCKER_CFG="${HOME}/.docker/config.json"
DOCKER_BACKUP="${HOME}/.docker/config.json.nogap-backup"
if [[ -f "$DOCKER_BACKUP" ]]; then
  mv "$DOCKER_BACKUP" "$DOCKER_CFG"
elif [[ -f "$DOCKER_CFG" ]]; then
  if grep -q "nogap-auth-service" "$DOCKER_CFG" 2>/dev/null; then
    rm -f "$DOCKER_CFG"
  fi
fi

sleep 1
echo "Stopped local forwarder (if it was running)."
