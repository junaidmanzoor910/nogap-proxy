#!/usr/bin/env bash
# Squid creds → forwarder + EC2 egress → you start nogap → optional Chrome → bash with docker proxy.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${ROOT}/scripts/workstation-proxy.env"
CHROME_SCRIPT="${ROOT}/scripts/chrome-via-proxy.sh"
FORWARDER_PORT="${NOGAP_LOCAL_FORWARDER_PORT:-3129}"
DOCKER_NETWORK="${NOGAP_DOCKER_NETWORK:-new-network}"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
step() { printf '\n\033[36m==>\033[0m %s\n' "$*"; }

if ! command -v squid >/dev/null 2>&1; then
  echo "Install: sudo apt-get install -y squid-openssl curl" >&2
  exit 1
fi
if ! squid -v 2>&1 | grep -qi openssl; then
  echo "Install squid-openssl (required for TLS to EC2): sudo apt-get install -y squid-openssl" >&2
  exit 1
fi

step "Squid credentials (EC2 proxy-dev.nogap.ai)"
_use_existing=0
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  if [[ -n "${NOGAP_PROXY_USER:-}" && -n "${NOGAP_PROXY_PASS:-}" ]]; then
    if [[ ! -t 0 || $# -gt 0 ]]; then
      _use_existing=1
    else
      read -r -p "Use saved credentials for '${NOGAP_PROXY_USER}'? [Y/n]: " _reuse
      if [[ "${_reuse,,}" != "n" && "${_reuse,,}" != "no" ]]; then
        _use_existing=1
      fi
    fi
  fi
fi

if [[ "$_use_existing" -eq 0 ]]; then
  read -r -p "Squid username [proxyuser01]: " _user
  _user="${_user:-proxyuser01}"
  read -r -s -p "Squid password: " _pass
  echo ""
  if [[ -z "${_pass}" ]]; then
    echo "Password cannot be empty." >&2
    exit 1
  fi

  {
    echo "NOGAP_PROXY_HOST=${NOGAP_PROXY_HOST:-proxy-dev.nogap.ai}"
    echo "NOGAP_PROXY_PORT=${NOGAP_PROXY_PORT:-443}"
    echo "NOGAP_PROXY_USER=${_user}"
    printf 'NOGAP_PROXY_PASS=%q\n' "${_pass}"
  } > "$ENV_FILE"
  chmod 600 "$ENV_FILE"

  read -r -p "Keep credentials in scripts/workstation-proxy.env for next time? [Y/n]: " _save
  if [[ "${_save,,}" == "n" || "${_save,,}" == "no" ]]; then
    _CLEANUP_ENV=1
  fi
  unset _user _pass _save
fi

step "Starting proxy (forwarder + Docker/host egress to EC2)"
"${ROOT}/scripts/stop-local-forwarder.sh" 2>/dev/null || true
if ! "${ROOT}/scripts/start-local-forwarder.sh"; then
  echo "Failed to start local forwarder." >&2
  exit 1
fi

if [[ "${_CLEANUP_ENV:-0}" -eq 1 ]]; then
  rm -f "$ENV_FILE"
fi

echo ""
step "Verifying proxy egress via EC2..."
_egress_ip=""
for ((t=0; t<5; t++)); do
  _egress_ip="$(curl -fsS -m 6 -x "http://127.0.0.1:${FORWARDER_PORT}" https://api.ipify.org 2>/dev/null || true)"
  if [[ -n "${_egress_ip}" ]]; then
    break
  fi
  sleep 1
done
if [[ -n "${_egress_ip}" ]]; then
  bold "✓ Forwarder verified: egress is via EC2 (${_egress_ip})"
else
  echo "WARN: Egress check via local forwarder timed out. Check EC2 credentials or upstream host." >&2
fi

# If script is sourced, apply environment to the current shell
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  # shellcheck source=scripts/enable-nogap-ec2-egress.sh
  source "${ROOT}/scripts/enable-nogap-ec2-egress.sh"
  return 0 2>/dev/null || exit 0
fi

if [[ "${1:-}" == "--ui" || "${1:-}" == "ui" ]]; then
  echo ""
  exec "${ROOT}/run-ui.sh"
fi

echo ""
echo "==> Forwarder OK — loading proxy session (host CLI + Docker)..."
unset -f docker 2>/dev/null || true
unset _NOGAP_DOCKER_WRAPPED 2>/dev/null || true
exec bash "${ROOT}/scripts/nogap-proxy-session.sh" "$@"
