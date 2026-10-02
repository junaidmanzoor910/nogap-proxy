#!/usr/bin/env bash
# run-nogap-vpn.sh: All-in-one control script for NoGap Disguised OpenVPN.
# Uses OpenVPN as software on EC2 with TCP port 443 + tls-crypt + port-share.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="${ROOT}/scripts"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red() { printf '\033[31m%s\033[0m\n' "$*"; }
cyan() { printf '\033[36m%s\033[0m\n' "$*"; }

action="${1:-}"

if [[ -z "$action" ]]; then
  echo ""
  bold "=========================================================="
  bold "      NoGap OpenVPN Control Center (Disguised HTTPS)      "
  bold "=========================================================="
  echo "1) Start OpenVPN (Route all traffic through EC2)"
  echo "2) Stop OpenVPN (Restore direct workstation routing)"
  echo "3) Check Status & Egress IP"
  echo "4) Fetch Client Profile from EC2 via SSM"
  echo "5) Verify Port 443 Disguise (Probe HTTPS web server)"
  echo "6) Launch Web Dashboard UI"
  echo "q) Exit"
  echo ""
  read -r -p "Select option [1-6, q]: " choice
  case "$choice" in
    1) action="start" ;;
    2) action="stop" ;;
    3) action="status" ;;
    4) action="fetch" ;;
    5) action="probe" ;;
    6) action="ui" ;;
    q|Q) exit 0 ;;
    *) echo "Invalid option." ; exit 1 ;;
  esac
fi

case "$action" in
  start|up|connect)
    "${SCRIPTS}/start-vpn.sh"
    ;;
  stop|down|disconnect)
    "${SCRIPTS}/stop-vpn.sh"
    ;;
  status|info)
    "${SCRIPTS}/vpn-status.sh"
    ;;
  fetch|download)
    "${SCRIPTS}/fetch-client-ovpn.sh"
    ;;
  probe|verify)
    "${SCRIPTS}/verify-disguise.sh" "${2:-}"
    ;;
  ui)
    "${ROOT}/run-ui.sh"
    ;;
  *)
    echo "Usage: $0 {start|stop|status|fetch|probe|ui}" >&2
    exit 1
    ;;
esac
