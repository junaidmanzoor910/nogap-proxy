#!/usr/bin/env bash
# scripts/generate-client-ovpn.sh <client-name>
# Generates a new self-contained OpenVPN client profile with embedded credentials.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (sudo)." >&2
  exit 1
fi

CLIENT_NAME="${1:-}"
if [[ -z "$CLIENT_NAME" ]]; then
  echo "Usage: $0 <client-name>" >&2
  exit 1
fi

PKI_DIR="/etc/openvpn/server"
OUT_DIR="/opt/nogap-openvpn"
mkdir -p "$OUT_DIR"

if [[ ! -f "$PKI_DIR/ca.crt" || ! -f "$PKI_DIR/ca.key" ]]; then
  echo "Error: CA certificates not found in $PKI_DIR. Run bootstrap-host-openvpn.sh first." >&2
  exit 1
fi

# Detect public IP
TOKEN=$(curl -sS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true)
PUBLIC_IP=""
if [[ -n "$TOKEN" ]]; then
  PUBLIC_IP=$(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null || true)
fi
if [[ -z "$PUBLIC_IP" ]]; then
  PUBLIC_IP=$(curl -sS https://api.ipify.org 2>/dev/null || echo "127.0.0.1")
fi

CLIENT_KEY="$PKI_DIR/${CLIENT_NAME}.key"
CLIENT_CSR="$PKI_DIR/${CLIENT_NAME}.csr"
CLIENT_CRT="$PKI_DIR/${CLIENT_NAME}.crt"
OVPN_OUT="$OUT_DIR/${CLIENT_NAME}.ovpn"

echo "==> Generating credentials for client '${CLIENT_NAME}'..."
openssl req -new -nodes \
  -newkey rsa:2048 \
  -keyout "$CLIENT_KEY" \
  -out "$CLIENT_CSR" \
  -subj "/CN=${CLIENT_NAME}"

cat << 'EOF' > "$PKI_DIR/client-ext.cnf"
basicConstraints = CA:FALSE
nsCertType = client
nsComment = "OpenVPN Client Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature
extendedKeyUsage = clientAuth
EOF

openssl x509 -req -days 3650 \
  -in "$CLIENT_CSR" \
  -CA "$PKI_DIR/ca.crt" \
  -CAkey "$PKI_DIR/ca.key" \
  -CAcreateserial \
  -out "$CLIENT_CRT" \
  -extfile "$PKI_DIR/client-ext.cnf"

rm -f "$CLIENT_CSR" "$PKI_DIR/client-ext.cnf"

cat << EOF > "$OVPN_OUT"
client
dev tun
proto tcp
remote ${PUBLIC_IP} 443
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
verb 3
mute 10

<ca>
$(cat "$PKI_DIR/ca.crt")
</ca>

<cert>
$(cat "$CLIENT_CRT")
</cert>

<key>
$(cat "$CLIENT_KEY")
</key>

<tls-crypt>
$(cat "$PKI_DIR/tls-crypt.key")
</tls-crypt>
EOF

chmod 600 "$OVPN_OUT"
echo "✓ Client profile created successfully: ${OVPN_OUT}"
