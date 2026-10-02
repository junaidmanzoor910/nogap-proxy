#!/usr/bin/env bash
# scripts/stop-vpn.sh
# Stops the OpenVPN software client and restores normal workstation routing.

set -euo pipefail

PID_FILE="/tmp/nogap-openvpn.pid"
LOG_FILE="/tmp/nogap-openvpn.log"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }

bold "==> Stopping OpenVPN client..."

stopped=0
if [[ -f "$PID_FILE" ]]; then
  PID=$(cat "$PID_FILE")
  if kill -0 "$PID" 2>/dev/null; then
    sudo kill "$PID" 2>/dev/null || true
    for ((i=0; i<10; i++)); do
      if ! kill -0 "$PID" 2>/dev/null; then
        break
      fi
      sleep 1
    done
    stopped=1
  fi
  rm -f "$PID_FILE"
fi

# Fallback: kill any lingering openvpn process using client.ovpn
if pgrep -f "client.ovpn" >/dev/null 2>&1; then
  sudo pkill -f "client.ovpn" 2>/dev/null || true
  stopped=1
fi

sleep 1

# Check current restored direct IP
RESTORED_IP="$(curl -fsS -m 4 https://api.ipify.org 2>/dev/null || echo "unknown")"

if [[ "$stopped" -eq 1 ]]; then
  green "✓ OpenVPN client terminated cleanly."
  echo "Default routing restored. Public IP: ${RESTORED_IP}"
else
  yellow "OpenVPN client was not running."
  echo "Current Public IP: ${RESTORED_IP}"
fi
