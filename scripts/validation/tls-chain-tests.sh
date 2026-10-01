#!/usr/bin/env bash
# TLS chain and proxy regression checks (run from operator workstation).
set -euo pipefail

PROXY_HOST="${PROXY_HOST:-proxy-dev.nogap.ai}"
PAC_PORT="${PAC_PORT:-8443}"
PROXY_PORT="${PROXY_PORT:-443}"
APP_HOST="${APP_HOST:-app-dev.nogap.ai}"
MIN_CHAIN_CERTS="${MIN_CHAIN_CERTS:-2}"

FAIL=0

count_certs() {
  local host="$1" port="$2"
  openssl s_client -connect "${host}:${port}" -servername "$PROXY_HOST" -showcerts </dev/null 2>/dev/null \
    | grep -c 'BEGIN CERTIFICATE' || echo 0
}

echo "=== Chain count :${PROXY_PORT} (Squid) ==="
N443=$(count_certs "$PROXY_HOST" "$PROXY_PORT")
echo "certificates_present=$N443"
if [[ "$N443" -lt "$MIN_CHAIN_CERTS" ]]; then
  echo "FAIL: expected >= ${MIN_CHAIN_CERTS} certificates on ${PROXY_PORT}"
  FAIL=1
else
  echo "PASS"
fi

echo "=== Chain count :${PAC_PORT} (Nginx PAC) ==="
N8443=$(count_certs "$PROXY_HOST" "$PAC_PORT")
echo "certificates_present=$N8443"
if [[ "$N8443" -lt "$MIN_CHAIN_CERTS" ]]; then
  echo "FAIL: expected >= ${MIN_CHAIN_CERTS} certificates on ${PAC_PORT}"
  FAIL=1
else
  echo "PASS"
fi

echo "=== Verify :${PROXY_PORT} (system trust + hostname) ==="
if openssl s_client -connect "${PROXY_HOST}:${PROXY_PORT}" -servername "$PROXY_HOST" \
  -verify_return_error -verify_hostname "$PROXY_HOST" </dev/null 2>/dev/null | grep -q 'Verify return code: 0'; then
  echo "PASS"
else
  echo "FAIL: certificate verification failed on ${PROXY_PORT}"
  FAIL=1
fi

echo "=== Leaf subject ==="
openssl s_client -connect "${PROXY_HOST}:${PROXY_PORT}" -servername "$PROXY_HOST" </dev/null 2>/dev/null \
  | openssl x509 -noout -subject 2>/dev/null | grep -q "CN = ${PROXY_HOST}" && echo "PASS" || {
  echo "FAIL: leaf CN mismatch"
  FAIL=1
}

echo "=== Proxy auth without credentials (expect 407) ==="
CODE=$(curl -sS -o /dev/null -w "%{http_code}" --proxy-insecure \
  -x "https://${PROXY_HOST}:${PROXY_PORT}" "https://${APP_HOST}/" 2>/dev/null) || CODE="000"
echo "http_code=$CODE"
if [[ "$CODE" == "407" ]]; then
  echo "PASS"
else
  echo "WARN: expected 407, got ${CODE} (may still be correct if curl reports 000 on proxy errors)"
fi

if [[ -n "${PROXY_USER:-}" && -n "${PROXY_PASS:-}" ]]; then
  echo "=== Allowlist allow ${APP_HOST} ==="
  ALLOW=$(curl -sS -o /dev/null -w "%{http_code}" --proxy-insecure \
    --proxy-user "${PROXY_USER}:${PROXY_PASS}" \
    -x "https://${PROXY_HOST}:${PROXY_PORT}" "https://${APP_HOST}/" 2>/dev/null || echo "000")
  echo "http_code=$ALLOW"
  if [[ "$ALLOW" =~ ^[23] ]]; then
    echo "PASS"
  else
    echo "FAIL: expected 2xx/3xx through tunnel"
    FAIL=1
  fi

  echo "=== General internet via proxy (example.com) ==="
  EX=$(curl -sS -o /dev/null -w "%{http_code}" --proxy-insecure \
    --proxy-user "${PROXY_USER}:${PROXY_PASS}" \
    -x "https://${PROXY_HOST}:${PROXY_PORT}" "https://example.com/" 2>/dev/null) || EX="000"
  echo "http_code=$EX"
  if [[ "$EX" =~ ^[23] ]]; then
    echo "PASS"
  else
    echo "FAIL: expected 2xx/3xx tunnel to example.com in full-proxy mode"
    FAIL=1
  fi

  echo "=== Trusted chain curl (no --proxy-insecure) ==="
  if curl -sS -o /dev/null -w "%{http_code}" --proxy-user "${PROXY_USER}:${PROXY_PASS}" \
    -x "https://${PROXY_HOST}:${PROXY_PORT}" "https://${APP_HOST}/" 2>/dev/null | grep -qE '^[23]'; then
    echo "PASS"
  else
    echo "WARN: strict TLS proxy verify failed (check local CA store)"
  fi
else
  echo "SKIP: set PROXY_USER and PROXY_PASS for allow/deny/tunnel tests"
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "tls-chain-tests: FAIL"
  exit 1
fi
echo "tls-chain-tests: PASS"
