#!/usr/bin/env bash
# scripts/start-vpn.sh
# Starts the OpenVPN software client directly on this workstation.
# Uses OpenVPN as software (community open-source CLI), connecting over disguised port 443 TCP.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="${ROOT}/config/client.ovpn"
PID_FILE="/tmp/nogap-openvpn.pid"
LOG_FILE="/tmp/nogap-openvpn.log"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red() { printf '\033[31m%s\033[0m\n' "$*"; }

if ! command -v openvpn >/dev/null 2>&1; then
  red "Error: openvpn binary not found. Install it with: sudo apt-get install -y openvpn"
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  red "Error: Client profile not found at ${CONFIG_FILE}"
  echo "Please fetch it from your EC2 instance first by running: ./scripts/fetch-client-ovpn.sh"
  exit 1
fi

# Check if already running
if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  green "✓ OpenVPN client is already running (PID: $(cat "$PID_FILE"))."
  "${ROOT}/scripts/vpn-status.sh"
  exit 0
fi

# Record current direct public IP before connecting
echo "Checking pre-connection direct IP..."
DIRECT_IP="$(curl -fsS -m 4 https://api.ipify.org 2>/dev/null || echo "unknown")"
echo "Workstation direct IP: ${DIRECT_IP}"

bold "==> Launching OpenVPN client software (connecting over TCP 443 disguised HTTPS)..."
sudo openvpn \
  --config "$CONFIG_FILE" \
  --daemon \
  --writepid "$PID_FILE" \
  --log "$LOG_FILE"

echo "Waiting for tunnel initialization..."
CONNECTED=0
for ((i=0; i<15; i++)); do
  if ip addr show dev tun0 2>/dev/null | grep -q "inet "; then
    CONNECTED=1
    break
  fi
  sleep 1
done

if [[ "$CONNECTED" -eq 1 ]]; then
  VPN_IP="$(ip addr show dev tun0 | grep "inet " | awk '{print $2}')"
  green "✓ OpenVPN tunnel established successfully!"
  echo "Internal VPN IP: ${VPN_IP}"
  
  # Verify public egress IP
  echo "Verifying public egress IP through EC2..."
  EGRESS_IP=""
  for ((t=0; t<5; t++)); do
    EGRESS_IP="$(curl -fsS -m 5 https://api.ipify.org 2>/dev/null || true)"
    if [[ -n "$EGRESS_IP" ]]; then break; fi
    sleep 1
  done

  if [[ -n "$EGRESS_IP" ]]; then
    bold "=========================================================="
    green "✓ ALL WORKSTATION TRAFFIC IS NOW ROUTED THROUGH EC2!"
    echo "  Before (Direct IP):  ${DIRECT_IP}"
    bold "  After  (EC2 Egress): ${EGRESS_IP}"
    echo "  Transport:           TCP 443 (Disguised HTTPS + tls-crypt)"
    bold "=========================================================="
  else
    yellow "Warning: Tunnel interface is UP, but egress IP check timed out."
  fi
else
  red "Error: OpenVPN tunnel failed to come up within 15 seconds."
  echo "Recent log entries from ${LOG_FILE}:"
  tail -n 20 "$LOG_FILE" 2>/dev/null || true
  exit 1
fi
