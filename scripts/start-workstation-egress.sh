#!/usr/bin/env bash
# One command: local forwarder + env for CLI + Chrome (all public HTTPS via EC2).
# Localhost destinations stay DIRECT (workstation.pac + NO_PROXY).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${ROOT}/scripts/start-local-forwarder.sh"

export HTTP_PROXY="http://127.0.0.1:${NOGAP_LOCAL_FORWARDER_PORT:-3129}"
export HTTPS_PROXY="${HTTP_PROXY}"
export http_proxy="${HTTP_PROXY}"
export https_proxy="${HTTP_PROXY}"
export NO_PROXY="localhost,127.0.0.1,::1,.local"
export no_proxy="${NO_PROXY}"

PAC_FILE="${ROOT}/config/workstation.pac"
PAC_URL="file://${PAC_FILE}"

echo ""
echo "=== Workstation egress via EC2 ==="
echo "CLI proxy:  ${HTTP_PROXY}"
echo "NO_PROXY:   ${NO_PROXY}"
echo "PAC:        ${PAC_URL}"
echo ""
echo "Test: curl -sS https://api.ipify.org"
echo "Open Chrome (example):"
echo "  ${ROOT}/scripts/chrome-via-proxy.sh"
echo ""

if [[ "${NOGAP_START_CHROME:-0}" == "1" ]]; then
  export NOGAP_CHROME_PROXY_MODE=local
  export NOGAP_PAC_FILE="$PAC_FILE"
  exec "${ROOT}/scripts/chrome-via-proxy.sh" "${@:-https://app-dev.nogap.ai}"
fi

if [[ $# -gt 0 ]]; then
  exec "$@"
fi
