#!/usr/bin/env bash
# Source in your shell before nogap local-run.sh / npm run dev — no nogap repo edits.
set -uo pipefail

unset -f docker 2>/dev/null || true

_PROXY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_NETWORK="${NOGAP_DOCKER_NETWORK:-new-network}"
_PORT="${NOGAP_LOCAL_FORWARDER_PORT:-3129}"

if ! "${_PROXY_ROOT}/scripts/start-local-forwarder.sh"; then
  echo "Failed to start local forwarder." >&2
  return 1 2>/dev/null || exit 1
fi

_GW="172.17.0.1"
_DOCKER_BIN="$(command -v docker 2>/dev/null || true)"
if [[ -n "${_DOCKER_BIN}" ]]; then
  if ! "${_DOCKER_BIN}" network inspect "${_NETWORK}" >/dev/null 2>&1; then
    "${_DOCKER_BIN}" network create "${_NETWORK}" >/dev/null 2>&1 || true
  fi
  _gw_out="$("${_DOCKER_BIN}" network inspect "${_NETWORK}" -f '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || true)"
  if [[ -n "${_gw_out}" ]]; then
    _GW="${_gw_out}"
  fi
fi

export NOGAP_DOCKER_HTTPS_PROXY="http://${_GW}:${_PORT}"
export NOGAP_DOCKER_NO_PROXY="localhost,127.0.0.1,::1,.local,169.254.169.254,host.docker.internal,*.internal,nogap-auth-service,nogap-chat-service,nogap-questionnaire-service,nogap-unified-service,nogap-router-service,nogap-integrations-service"

export HTTP_PROXY="http://127.0.0.1:${_PORT}"
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

if [[ -z "${_NOGAP_DOCKER_WRAPPED:-}" ]] && command -v docker >/dev/null 2>&1; then
  docker() {
    if [[ "$1" == "run" && -n "${NOGAP_DOCKER_HTTPS_PROXY:-}" ]]; then
      command docker run \
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
      command docker "$@"
    else
      command docker "$@"
    fi
  }
  export -f docker 2>/dev/null || true
  _NOGAP_DOCKER_WRAPPED=1
elif [[ -z "${_NOGAP_DOCKER_WRAPPED:-}" ]]; then
  echo "Note: docker not in PATH — host proxy only." >&2
fi

echo "Host CLI & Apps proxy: ${HTTP_PROXY} (NO_PROXY: ${NO_PROXY})"
echo "Docker AWS egress:     ${NOGAP_DOCKER_HTTPS_PROXY}"
echo "Proxied browser:       ${_PROXY_ROOT}/scripts/chrome-via-proxy.sh http://localhost:3000"
