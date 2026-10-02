#!/usr/bin/env bash
# scripts/vpn-status.sh
# Checks status, IP, latency, and throughput of the OpenVPN connection.

set -euo pipefail

PID_FILE="/tmp/nogap-openvpn.pid"
LOG_FILE="/tmp/nogap-openvpn.log"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red() { printf '\033[31m%s\033[0m\n' "$*"; }

bold "=========================================================="
bold "          NoGap OpenVPN Connection Status                 "
bold "=========================================================="

is_running=0
pid="none"
if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  is_running=1
  pid="$(cat "$PID_FILE")"
elif pgrep -f "client.ovpn" >/dev/null 2>&1; then
  is_running=1
  pid="$(pgrep -f "client.ovpn" | head -n1)"
fi

if [[ "$is_running" -eq 1 ]]; then
  green "● Status: CONNECTED (PID: ${pid})"
else
  yellow "○ Status: DISCONNECTED"
fi

# Check tun0 interface
if ip addr show dev tun0 2>/dev/null | grep -q "inet "; then
  vpn_ip="$(ip addr show dev tun0 | grep "inet " | awk '{print $2}')"
  green "✓ Tunnel Interface (tun0): UP (${vpn_ip})"

  # Measure latency to VPN gateway
  latency="$(ping -c 2 -W 2 10.8.0.1 2>/dev/null | tail -1 | awk -F '/' '{print $5}' || echo "N/A")"
  if [[ "$latency" != "N/A" ]]; then
    echo "  Gateway Latency:     ${latency} ms"
  fi

  # Check current public egress IP
  egress_ip="$(curl -fsS -m 4 https://api.ipify.org 2>/dev/null || echo "checking failed")"
  bold "  Public Egress IP:    ${egress_ip}"

  # Interface RX / TX stats
  rx_bytes="$(cat /sys/class/net/tun0/statistics/rx_bytes 2>/dev/null || echo "0")"
  tx_bytes="$(cat /sys/class/net/tun0/statistics/tx_bytes 2>/dev/null || echo "0")"
  rx_mb=$(awk "BEGIN {printf \"%.2f\", ${rx_bytes}/1048576}")
  tx_mb=$(awk "BEGIN {printf \"%.2f\", ${tx_bytes}/1048576}")
  echo "  Data Transferred:    ${tx_mb} MB sent / ${rx_mb} MB received"
else
  yellow "  Tunnel Interface:    DOWN"
  direct_ip="$(curl -fsS -m 4 https://api.ipify.org 2>/dev/null || echo "unknown")"
  echo "  Workstation IP:      ${direct_ip}"
fi

echo "  Disguise Setting:    TCP Port 443 + tls-crypt (Nginx fallback on 8443)"
bold "=========================================================="
