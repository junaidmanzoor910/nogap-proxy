#!/usr/bin/env bash
# Chrome profile that sends external HTTPS via EC2 Squid (localhost stays DIRECT via PAC).
set -euo pipefail
PROXY_HOST="${NOGAP_PROXY_HOST:-proxy-dev.nogap.ai}"
PROXY_PORT="${NOGAP_PROXY_PORT:-443}"
LOCAL_PORT="${NOGAP_LOCAL_FORWARDER_PORT:-3129}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAC_URL="${NOGAP_PAC_URL:-https://${PROXY_HOST}:8443/proxy.pac}"
WORKSTATION_PAC="${NOGAP_PAC_FILE:-file://${ROOT}/config/workstation.pac}"
PROFILE="${NOGAP_CHROME_PROFILE:-$HOME/.chrome-nogap-proxy}"
# local-manual = reliable on Linux (file:// PAC is often ignored by Chrome).
MODE="${NOGAP_CHROME_PROXY_MODE:-local-manual}"

for bin in google-chrome google-chrome-stable chromium chromium-browser; do
  if command -v "$bin" >/dev/null 2>&1; then
    CHROME="$bin"
    break
  fi
done
if [[ -z "${CHROME:-}" ]]; then
  echo "No Chrome/Chromium binary found." >&2
  exit 1
fi

ARGS=(--user-data-dir="$PROFILE" --new-window)

case "$MODE" in
  local-manual)
    ARGS+=(--proxy-server="http://127.0.0.1:${LOCAL_PORT}")
    ARGS+=(--proxy-bypass-list="<-loopback>;localhost;127.0.0.1;::1;<local>;*.local")
    ;;
  local)
    # Local forwarder holds EC2 credentials; Chrome needs no proxy auth dialog.
    ARGS+=(--proxy-pac-url="$WORKSTATION_PAC")
    ;;
  pac)
    ARGS+=(--proxy-pac-url="$PAC_URL")
    ;;
  manual)
    ARGS+=(--proxy-server="https://${PROXY_HOST}:${PROXY_PORT}")
    ;;
  *)
    ARGS+=(--proxy-server="http://127.0.0.1:${LOCAL_PORT}")
    ARGS+=(--proxy-bypass-list="<-loopback>;localhost;127.0.0.1;::1;<local>;*.local")
    ;;
esac

if [[ $# -gt 0 ]]; then
  ARGS+=("$@")
else
  ARGS+=("about:blank")
fi

echo "Chrome: ${CHROME} (mode=${MODE}, profile=${PROFILE})"
if [[ "$MODE" == "manual" || "$MODE" == "pac" ]]; then
  echo "Enter Squid credentials when prompted (${NOGAP_PROXY_USER:-proxyuser01})."
else
  echo "Using local forwarder 127.0.0.1:${LOCAL_PORT} (run scripts/start-local-forwarder.sh if not started)."
fi
exec "$CHROME" "${ARGS[@]}"
