#!/usr/bin/env bash
# Local Squid on 127.0.0.1:3129 (default) → EC2 Squid with stored credentials (no browser popup).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE="${ROOT}/scripts/workstation-proxy.env.example"
LOCAL="${ROOT}/scripts/workstation-proxy.env"
TEMPLATE="${ROOT}/config/local-forwarder.squid.conf.template"
STATE_DIR="${NOGAP_FORWARDER_STATE:-${HOME}/.nogap-proxy-forwarder}"
SQUID_INSTANCE="${NOGAP_SQUID_INSTANCE:-nogapfwd}"
LISTEN_PORT="${NOGAP_LOCAL_FORWARDER_PORT:-3129}"

# Session exports (e.g. run-nogap-local-proxy.sh) override file.
if [[ -z "${NOGAP_PROXY_PASS:-}" ]]; then
  if [[ -f "$LOCAL" ]]; then
    # shellcheck disable=SC1090
    source "$LOCAL"
  elif [[ -f "$EXAMPLE" ]]; then
    # shellcheck disable=SC1090
    source "$EXAMPLE"
  else
    echo "Missing ${EXAMPLE}" >&2
    exit 1
  fi
fi

if [[ -z "${NOGAP_PROXY_PASS:-}" ]]; then
  echo "Set NOGAP_PROXY_PASS in scripts/workstation-proxy.env" >&2
  exit 1
fi

if ! command -v squid >/dev/null 2>&1; then
  echo "Install: sudo apt-get install -y squid-openssl" >&2
  exit 1
fi
if ! squid -v 2>&1 | grep -qi openssl; then
  echo "Local forwarder needs squid-openssl (TLS parent to EC2)." >&2
  echo "  sudo apt-get install -y squid-openssl" >&2
  exit 1
fi

UPSTREAM_HOST="${NOGAP_PROXY_HOST:-proxy-dev.nogap.ai}"
UPSTREAM_PORT="${NOGAP_PROXY_PORT:-443}"
UPSTREAM_USER="${NOGAP_PROXY_USER:-proxyuser01}"
UPSTREAM_PASS="${NOGAP_PROXY_PASS}"

mkdir -p "${STATE_DIR}" "${STATE_DIR}/cache"
CONF="${STATE_DIR}/squid.conf"
PIDFILE="${STATE_DIR}/squid.pid"

export LOCAL_LISTEN_PORT="${LISTEN_PORT}" STATE_DIR UPSTREAM_HOST UPSTREAM_PORT UPSTREAM_USER UPSTREAM_PASS
envsubst '${LOCAL_LISTEN_PORT} ${STATE_DIR} ${UPSTREAM_HOST} ${UPSTREAM_PORT} ${UPSTREAM_USER} ${UPSTREAM_PASS}' \
  < "$TEMPLATE" > "$CONF"
chmod 600 "$CONF"

_port_listening() {
  ss -tlnH "sport = :${LISTEN_PORT}" 2>/dev/null | grep -q .
}

_configure_docker_proxy() {
  if ! command -v docker >/dev/null 2>&1; then
    return 0
  fi
  mkdir -p "${HOME}/.docker"
  local docker_cfg="${HOME}/.docker/config.json"
  local docker_backup="${HOME}/.docker/config.json.nogap-backup"
  if [[ -f "$docker_cfg" ]] && [[ ! -f "$docker_backup" ]]; then
    # Only backup if not created by nogap
    if ! grep -q "nogap-auth-service" "$docker_cfg" 2>/dev/null; then
      cp "$docker_cfg" "$docker_backup"
    fi
  fi

  local docker_net="${NOGAP_DOCKER_NETWORK:-new-network}"
  local gw="172.17.0.1"
  if ! docker network inspect "${docker_net}" >/dev/null 2>&1; then
    docker network create "${docker_net}" >/dev/null 2>&1 || true
  fi
  local gw_out
  gw_out="$(docker network inspect "${docker_net}" -f '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || true)"
  if [[ -n "${gw_out}" ]]; then
    gw="${gw_out}"
  fi

  cat << EOF > "$docker_cfg"
{
  "proxies": {
    "default": {
      "httpProxy": "http://${gw}:${LISTEN_PORT}",
      "httpsProxy": "http://${gw}:${LISTEN_PORT}",
      "noProxy": "localhost,127.0.0.1,::1,.local,169.254.169.254,172.17.0.1,172.18.0.1,172.16.0.0/12,10.0.0.0/8,192.168.0.0/16,host.docker.internal,*.internal,nogap-auth-service,nogap-chat-service,nogap-questionnaire-service,nogap-unified-service,nogap-router-service,nogap-integrations-service"
    }
  }
}
EOF
}

# Healthy existing instance: reconfigure Squid so ACL and upstream changes take effect
if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null && _port_listening; then
  squid -n "$SQUID_INSTANCE" -f "$CONF" -k reconfigure 2>/dev/null || true
  _configure_docker_proxy
  echo "Local forwarder already running (pid $(cat "$PIDFILE")) on 127.0.0.1:${LISTEN_PORT} (reconfigured)."
  exit 0
fi

# Stale pid and/or port held — clean stop then start
"${ROOT}/scripts/stop-local-forwarder.sh" >/dev/null 2>&1 || true

if _port_listening; then
  echo "Port ${LISTEN_PORT} still in use by another program. Check:" >&2
  ss -tlnp "sport = :${LISTEN_PORT}" 2>/dev/null || true
  echo "Or use: NOGAP_LOCAL_FORWARDER_PORT=3130 ./run-nogap-local-proxy.sh" >&2
  exit 1
fi

if ! _parse_out="$(squid -n "$SQUID_INSTANCE" -f "$CONF" -k parse 2>&1)"; then
  echo "Squid config parse failed (${CONF}):" >&2
  echo "${_parse_out}" | tail -20 >&2
  exit 1
fi
if [[ ! -d "${STATE_DIR}/cache/00" ]]; then
  squid -n "$SQUID_INSTANCE" -f "$CONF" -z 2>/dev/null || true
fi
if ! squid -n "$SQUID_INSTANCE" -f "$CONF" 2>&1; then
  echo "Squid failed to start. See ${STATE_DIR}/cache.log" >&2
  exit 1
fi

# Wait for forwarder port to be listening
for ((i=0; i<30; i++)); do
  if _port_listening; then
    break
  fi
  sleep 0.1
done

if ! _port_listening; then
  echo "Squid started but port ${LISTEN_PORT} is not listening yet. Check ${STATE_DIR}/cache.log" >&2
  exit 1
fi

echo "Local forwarder: http://127.0.0.1:${LISTEN_PORT} → https://${UPSTREAM_HOST}:${UPSTREAM_PORT}"
echo "PAC: file://${ROOT}/config/workstation.pac"

# Configure Docker daemon/client proxy so all containers automatically use EC2 forwarder
_configure_docker_proxy
