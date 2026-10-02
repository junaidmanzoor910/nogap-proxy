#!/usr/bin/env bash
# tests/test_openvpn_disguise.sh: Validates OpenVPN configuration, port disguise, and templates.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0

check() {
  local desc="$1"
  shift
  if "$@"; then
    echo "  ✓ ${desc}"
  else
    echo "  ✗ FAIL: ${desc}"
    FAIL=1
  fi
}

echo "== Validating OpenVPN Disguised Architecture =="

# 1. Server Configuration
check "Server config listens on disguised TCP port 443" \
  grep -q "^port 443" "${ROOT}/config/openvpn/server.conf.template"

check "Server config uses TCP protocol" \
  grep -q "^proto tcp-server" "${ROOT}/config/openvpn/server.conf.template"

check "Server config enables tls-crypt control-channel encryption" \
  grep -q "^tls-crypt " "${ROOT}/config/openvpn/server.conf.template"

check "Server config specifies port-share fallback to Nginx on 8443" \
  grep -q "^port-share 127.0.0.1 8443" "${ROOT}/config/openvpn/server.conf.template"

check "Server config pushes full-tunnel default gateway redirection" \
  grep -q 'push "redirect-gateway def1 bypass-dhcp"' "${ROOT}/config/openvpn/server.conf.template"

# 2. Nginx Disguise Site
check "Nginx fallback site listens exclusively on 127.0.0.1:8443 ssl" \
  grep -q "listen 127.0.0.1:8443 ssl" "${ROOT}/config/openvpn/nginx-disguise.conf"

check "Disguise index landing page exists" \
  test -f "${ROOT}/config/openvpn/disguise-index.html"

# 3. Client Configuration
check "Client template targets port 443 TCP" \
  grep -q "remote {{VPN_HOST}} 443" "${ROOT}/config/openvpn/client.conf.template"

check "Client template embeds tls-crypt section" \
  grep -q "<tls-crypt>" "${ROOT}/config/openvpn/client.conf.template"

# 4. Cloud-Init Template
check "Cloud-init enables net.ipv4.ip_forwarding" \
  grep -q "net.ipv4.ip_forward = 1" "${ROOT}/cloud-init/user-data.yaml.tpl"

check "Cloud-init configures iptables MASQUERADE for VPN subnet" \
  grep -q "iptables -t nat -A POSTROUTING -s 10.8.0.0/24" "${ROOT}/cloud-init/user-data.yaml.tpl"

check "Cloud-init provisions OpenVPN package" \
  grep -q -- "- openvpn" "${ROOT}/cloud-init/user-data.yaml.tpl"

# 5. Helper Scripts
check "Bootstrap script is executable" \
  test -x "${ROOT}/scripts/bootstrap-host-openvpn.sh"

check "Client launcher script is executable" \
  test -x "${ROOT}/scripts/start-vpn.sh"

check "Disguise verification script is executable" \
  test -x "${ROOT}/scripts/verify-disguise.sh"

check "Main OpenVPN runner is executable" \
  test -x "${ROOT}/run-nogap-vpn.sh"

if [[ "$FAIL" -eq 0 ]]; then
  echo "PASS: All OpenVPN disguised configuration checks succeeded."
  exit 0
else
  echo "FAIL: One or more OpenVPN checks failed."
  exit 1
fi
