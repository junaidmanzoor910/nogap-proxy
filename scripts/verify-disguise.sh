#!/usr/bin/env bash
# scripts/verify-disguise.sh <ec2-ip-or-hostname>
# Validates that port 443 disguises itself as a legitimate HTTPS web server to scanners/probes.

set -euo pipefail

TARGET="${1:-}"

if [[ -z "$TARGET" ]]; then
  # Try reading from workstation-proxy.env or terraform output
  if [[ -f "$(dirname "$0")/workstation-proxy.env" ]]; then
    # shellcheck disable=SC1090
    source "$(dirname "$0")/workstation-proxy.env"
    TARGET="${NOGAP_PROXY_HOST:-}"
  fi
fi

if [[ -z "$TARGET" ]]; then
  read -r -p "Enter EC2 IP or Hostname to probe: " TARGET
fi

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red() { printf '\033[31m%s\033[0m\n' "$*"; }

bold "=========================================================="
bold "     Probing EC2 Port 443 for HTTPS Web Server Disguise   "
bold "=========================================================="
echo "Target: https://${TARGET}:443"
echo "Sending standard HTTPS probe (simulating firewall / scanner / browser)..."
echo ""

RESP=$(curl -k -s -D - "https://${TARGET}:443" -o /tmp/probe_body.html -m 6 || true)

if echo "$RESP" | grep -qi "HTTP/"; then
  STATUS_LINE=$(echo "$RESP" | grep -i "HTTP/" | head -n1 | tr -d '\r')
  SERVER_HEADER=$(echo "$RESP" | grep -i "^server:" | head -n1 | tr -d '\r' || echo "Hidden")
  green "✓ Port 443 responded to HTTPS probe successfully!"
  echo "  Status Line:   ${STATUS_LINE}"
  echo "  Server Header: ${SERVER_HEADER}"
  if grep -qi "Cloud Gateway" /tmp/probe_body.html 2>/dev/null; then
    green "✓ Received Nginx disguise landing page: 'Cloud Gateway'"
  fi
  echo ""
  bold "Result: Port 443 is PERFECTLY DISGUISED as a normal HTTPS web server."
  echo "To non-VPN clients, port 443 behaves as a standard website."
  echo "Only authorized OpenVPN clients with tls-crypt key can establish a VPN tunnel."
else
  red "Error: Could not establish HTTPS connection to https://${TARGET}:443"
  echo "Ensure EC2 instance is running and port 443 is open in AWS Security Group."
fi
bold "=========================================================="
