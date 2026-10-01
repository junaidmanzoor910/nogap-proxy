#!/usr/bin/env bash
# End-to-end check: local forwarder → EC2 Squid → internet.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${NOGAP_LOCAL_FORWARDER_PORT:-3129}"
PROXY="http://127.0.0.1:${PORT}"
EXPECTED_EIP="${NOGAP_EXPECTED_EIP:-35.154.197.35}"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK:   $*"; }

command -v curl >/dev/null 2>&1 || fail "curl not installed"
command -v ss >/dev/null 2>&1 || fail "ss not installed"

if ! ss -tlnH "sport = :${PORT}" 2>/dev/null | grep -q .; then
  echo "Forwarder not listening on ${PORT}. Start it:" >&2
  echo "  ${ROOT}/scripts/start-local-forwarder.sh" >&2
  fail "port ${PORT} closed"
fi
ok "forwarder listening on ${PORT}"

ip="$(curl -fsS -m 20 -x "${PROXY}" https://api.ipify.org)" || fail "curl via proxy failed (auth? forwarder? EC2?)"
if [[ "${ip}" != "${EXPECTED_EIP}" ]]; then
  echo "WARN: ipify=${ip} expected EC2 EIP ${EXPECTED_EIP} (may have changed)" >&2
else
  ok "egress IP ${ip} (EC2)"
fi

code="$(curl -fsS -m 20 -o /dev/null -w '%{http_code}' -x "${PROXY}" https://www.google.com/)" || fail "google via proxy failed"
[[ "${code}" == "200" ]] || fail "google HTTP ${code}"
ok "https://www.google.com via proxy (${code})"

echo ""
echo "Local forwarder log (last CONNECT lines):"
tail -3 "${HOME}/.nogap-proxy-forwarder/access.log" 2>/dev/null | grep CONNECT || echo "  (no CONNECT lines yet)"
echo ""
echo "EC2 Squid (SSM on instance) while you browse:"
echo "  sudo tail -f /var/log/squid/access.log | grep --line-buffered CONNECT"
echo ""
echo "Browser: normal Chrome does NOT use this proxy. Use:"
echo "  ${ROOT}/scripts/chrome-via-proxy.sh https://www.google.com"
echo "Then reload EC2 logs — you should see CONNECT www.google.com:443 TCP_TUNNEL/200"
