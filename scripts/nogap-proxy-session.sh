#!/usr/bin/env bash
# After local forwarder is up: host/Docker proxy env, NoGap hints, optional Chrome, interactive bash.
set -uo pipefail

# Inherited exported docker() from an old session breaks setup (unset _NOGAP_REAL_DOCKER + set -u).
unset -f docker 2>/dev/null || true
unset _NOGAP_DOCKER_WRAPPED 2>/dev/null || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHROME_SCRIPT="${ROOT}/scripts/chrome-via-proxy.sh"
FORWARDER_PORT="${NOGAP_LOCAL_FORWARDER_PORT:-3129}"
DOCKER_NETWORK="${NOGAP_DOCKER_NETWORK:-new-network}"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
step() { printf '\n\033[36m==>\033[0m %s\n' "$*"; }

export HTTP_PROXY="http://127.0.0.1:${FORWARDER_PORT}"
export HTTPS_PROXY="${HTTP_PROXY}"
export ALL_PROXY="${HTTP_PROXY}"
export http_proxy="${HTTP_PROXY}"
export https_proxy="${HTTPS_PROXY}"
export all_proxy="${HTTP_PROXY}"
export NO_PROXY="localhost,127.0.0.1,::1,.local,169.254.169.254,host.docker.internal,*.internal"
export no_proxy="${NO_PROXY}"

# AWS SDK Connection Pooling and Optimization (Boto3 / Python / Node)
export AWS_MAX_POOL_CONNECTIONS=50
export AWS_METADATA_SERVICE_TIMEOUT=1
export AWS_METADATA_SERVICE_NUM_ATTEMPTS=1
export AWS_NODEJS_CONNECTION_REUSE_ENABLED=1

# Enable Node.js native fetch proxy support (Node 20+)
if command -v node >/dev/null 2>&1 && node --help 2>&1 | grep -q -- '--use-env-proxy'; then
  case "${NODE_OPTIONS:-}" in
    *--use-env-proxy*) ;;
    *) export NODE_OPTIONS="--use-env-proxy ${NODE_OPTIONS:-}" ;;
  esac
fi

_GW="172.17.0.1"
_DOCKER_BIN="$(command -v docker 2>/dev/null || true)"
if [[ -n "${_DOCKER_BIN}" ]]; then
  "${_DOCKER_BIN}" network inspect "${DOCKER_NETWORK}" >/dev/null 2>&1 || "${_DOCKER_BIN}" network create "${DOCKER_NETWORK}" >/dev/null 2>&1 || true
  _gw_out="$("${_DOCKER_BIN}" network inspect "${DOCKER_NETWORK}" -f '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || true)"
  if [[ -n "${_gw_out}" ]]; then
    _GW="${_gw_out}"
  fi
  if [[ -z "${_NOGAP_DOCKER_WRAPPED:-}" ]]; then
    _NOGAP_REAL_DOCKER="${_DOCKER_BIN}"
    docker() {
      if [[ "$1" == "run" && -n "${NOGAP_DOCKER_HTTPS_PROXY:-}" ]]; then
        "${_NOGAP_REAL_DOCKER}" run \
          -e "HTTP_PROXY=${NOGAP_DOCKER_HTTPS_PROXY}" \
          -e "HTTPS_PROXY=${NOGAP_DOCKER_HTTPS_PROXY}" \
          -e "ALL_PROXY=${NOGAP_DOCKER_HTTPS_PROXY}" \
          -e "http_proxy=${NOGAP_DOCKER_HTTPS_PROXY}" \
          -e "https_proxy=${NOGAP_DOCKER_HTTPS_PROXY}" \
          -e "all_proxy=${NOGAP_DOCKER_HTTPS_PROXY}" \
          -e "NO_PROXY=${NOGAP_DOCKER_NO_PROXY}" \
          -e "no_proxy=${NOGAP_DOCKER_NO_PROXY}" \
          -e "AWS_MAX_POOL_CONNECTIONS=50" \
          -e "AWS_METADATA_SERVICE_TIMEOUT=1" \
          -e "AWS_METADATA_SERVICE_NUM_ATTEMPTS=1" \
          -e "AWS_NODEJS_CONNECTION_REUSE_ENABLED=1" \
          "${@:2}"
      elif [[ "$1" == "compose" && -n "${NOGAP_DOCKER_HTTPS_PROXY:-}" ]]; then
        HTTP_PROXY="${NOGAP_DOCKER_HTTPS_PROXY}" \
        HTTPS_PROXY="${NOGAP_DOCKER_HTTPS_PROXY}" \
        ALL_PROXY="${NOGAP_DOCKER_HTTPS_PROXY}" \
        http_proxy="${NOGAP_DOCKER_HTTPS_PROXY}" \
        https_proxy="${NOGAP_DOCKER_HTTPS_PROXY}" \
        all_proxy="${NOGAP_DOCKER_HTTPS_PROXY}" \
        NO_PROXY="${NOGAP_DOCKER_NO_PROXY}" \
        no_proxy="${NOGAP_DOCKER_NO_PROXY}" \
        AWS_MAX_POOL_CONNECTIONS=50 \
        AWS_METADATA_SERVICE_TIMEOUT=1 \
        AWS_METADATA_SERVICE_NUM_ATTEMPTS=1 \
        AWS_NODEJS_CONNECTION_REUSE_ENABLED=1 \
        "${_NOGAP_REAL_DOCKER}" "$@"
      else
        "${_NOGAP_REAL_DOCKER}" "$@"
      fi
    }
    export -f docker 2>/dev/null || echo "Note: docker() wrapper not exported — source ${ROOT}/scripts/enable-nogap-ec2-egress.sh" >&2
    _NOGAP_DOCKER_WRAPPED=1
  fi
else
  echo "Note: docker not in PATH — host proxy only; start Docker for container AWS egress." >&2
fi

export NOGAP_DOCKER_HTTPS_PROXY="http://${_GW}:${FORWARDER_PORT}"
export NOGAP_DOCKER_NO_PROXY="localhost,127.0.0.1,::1,.local,169.254.169.254,host.docker.internal,*.internal,nogap-auth-service,nogap-chat-service,nogap-questionnaire-service,nogap-unified-service,nogap-router-service,nogap-integrations-service"

echo "Host CLI & Apps proxy: ${HTTP_PROXY} (NO_PROXY: ${NO_PROXY})"
echo "Docker AWS egress:     ${NOGAP_DOCKER_HTTPS_PROXY}"
echo "Verify chain:          ${ROOT}/scripts/verify-proxy-chain.sh"

# If a specific command was passed to the session, execute it directly
if [[ $# -gt 0 ]]; then
  exec "$@"
fi

step "Start NoGap yourself"
bold "This shell — each backend:"
echo "  cd <nogap-services>/<service> && ./local-run.sh"
echo ""
bold "Another terminal — frontend only:"
echo "  cd <nogap-services>/frontend-service && ./scripts/dev-local.sh"
echo ""
echo "  UI: http://localhost:3000"
echo ""

step "Chrome (localhost UI + public HTTPS via EC2)"
read -r -p "Type yes when backends and frontend are up [yes/manual/skip]: " _ready

if [[ "${_ready,,}" == "yes" || "${_ready,,}" == "y" ]]; then
  chmod +x "${CHROME_SCRIPT}" 2>/dev/null || true
  NOGAP_CHROME_PROXY_MODE="${NOGAP_CHROME_PROXY_MODE:-local-manual}" \
    "${CHROME_SCRIPT}" "http://localhost:3000" &
  echo "Chrome started (proxied profile)."
elif [[ "${_ready,,}" == "manual" || "${_ready,,}" == "m" ]]; then
  bold "Manual Chrome:"
  echo "  ${CHROME_SCRIPT} http://localhost:3000"
  echo ""
  echo "  google-chrome --user-data-dir=\"\$HOME/.chrome-nogap-proxy\" \\"
  echo "    --proxy-server=\"http://127.0.0.1:${FORWARDER_PORT}\" \\"
  echo "    --proxy-bypass-list=\"<-loopback>;localhost;127.0.0.1;::1;<local>;*.local\" \\"
  echo "    http://localhost:3000"
fi

echo ""
bold "This shell keeps Docker & Host → EC2 proxy enabled. All AWS/external traffic routes through EC2."
bold "All localhost/127.0.0.1 services remain DIRECT and local."
echo "Stop forwarder when done: ${ROOT}/scripts/stop-local-forwarder.sh"
echo ""

exec bash -i
