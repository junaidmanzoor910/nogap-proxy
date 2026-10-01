#!/usr/bin/env bash
# Prove squid-openssl sends multiple certs from a multi-PEM fullchain (Ubuntu 24.04).
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  echo "SKIP: docker not available"
  exit 0
fi

echo "== squid-openssl TLS chain handshake test =="

docker run --rm ubuntu:24.04 bash -ec '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq squid-openssl openssl ca-certificates >/dev/null

WORKDIR=/tmp/squidchain
mkdir -p "$WORKDIR" /etc/squid/tls /var/log/squid
cd "$WORKDIR"

# Fake CA + leaf (not publicly trusted; tests chain *count* only).
openssl genrsa -out ca.key 2048 2>/dev/null
openssl req -x509 -new -key ca.key -subj "/CN=TestChainCA" -days 1 -out ca.pem 2>/dev/null
openssl genrsa -out leaf.key 2048 2>/dev/null
openssl req -new -key leaf.key -subj "/CN=proxy-dev.nogap.ai" -out leaf.csr 2>/dev/null
openssl x509 -req -in leaf.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 1 -out leaf.pem 2>/dev/null
cat leaf.pem ca.pem > /etc/squid/tls/fullchain.pem
cp leaf.key /etc/squid/tls/privkey.pem
chmod 644 /etc/squid/tls/fullchain.pem
chmod 600 /etc/squid/tls/privkey.pem
touch /etc/squid/passwords
chown root:proxy /etc/squid
chmod 750 /etc/squid

grep -q openssl <<< "$(squid -v 2>&1)" || { echo "FAIL: not squid-openssl build"; exit 1; }

cat > /etc/squid/squid.conf <<EOF
https_port 14443 tls-cert=/etc/squid/tls/fullchain.pem tls-key=/etc/squid/tls/privkey.pem
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwords
auth_param basic children 1
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all
cache deny all
EOF

squid -k parse
squid -N -d 1 &
sleep 2

COUNT=$(openssl s_client -connect 127.0.0.1:14443 -servername proxy-dev.nogap.ai -showcerts </dev/null 2>/dev/null | grep -c "BEGIN CERTIFICATE" || echo 0)
kill $(cat /run/squid.pid 2>/dev/null) 2>/dev/null || pkill squid || true

if [[ "$COUNT" -lt 2 ]]; then
  echo "FAIL: squid-openssl presented $COUNT certificate(s), expected >= 2"
  exit 1
fi
echo "PASS: squid-openssl presented $COUNT certificate(s)"
'
