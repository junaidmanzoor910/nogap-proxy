#!/usr/bin/env bash
# scripts/bootstrap-host-openvpn.sh
# Bootstraps OpenVPN on EC2 in disguised HTTPS mode (TCP port 443 + tls-crypt + port-share)
# Self-contained: creates PKI, server config, Nginx disguise fallback, iptables NAT, and initial client profile.

set -euo pipefail

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red() { printf '\033[31m%s\033[0m\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
  red "Error: This script must be run as root (sudo)."
  exit 1
fi

bold "=========================================================="
bold "   NoGap OpenVPN Deployment - Disguised HTTPS Mode (443)  "
bold "=========================================================="

# 0. Ensure required software packages are installed
bold "==> Installing/verifying OpenVPN, Nginx, and networking packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq openvpn iptables iptables-persistent netfilter-persistent nginx openssl curl jq

# 1. Detect public IP (via IMDSv2 or external echo)
TOKEN=$(curl -sS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true)
PUBLIC_IP=""
if [[ -n "$TOKEN" ]]; then
  PUBLIC_IP=$(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null || true)
fi
if [[ -z "$PUBLIC_IP" ]]; then
  PUBLIC_IP=$(curl -sS https://api.ipify.org 2>/dev/null || echo "127.0.0.1")
fi
green "✓ Detected Public Elastic IP: ${PUBLIC_IP}"

# 2. Detect default egress interface
DEFAULT_IFACE=$(ip route show default | awk '{print $5}' | head -n1)
if [[ -z "$DEFAULT_IFACE" ]]; then
  DEFAULT_IFACE="eth0"
fi
green "✓ Detected Egress Interface: ${DEFAULT_IFACE}"

# 3. Enable IPv4 Forwarding in Kernel
bold "==> Configuring kernel IPv4 forwarding..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null
cat << 'EOF' > /etc/sysctl.d/99-openvpn.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
sysctl --system >/dev/null 2>&1 || true

# 4. Configure iptables NAT (MASQUERADE)
bold "==> Configuring iptables NAT MASQUERADE for 10.8.0.0/24..."
iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -o "$DEFAULT_IFACE" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$DEFAULT_IFACE" -j MASQUERADE

# Persist iptables
if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save >/dev/null 2>&1 || true
elif command -v iptables-save >/dev/null 2>&1; then
  mkdir -p /etc/iptables
  iptables-save > /etc/iptables/rules.v4
fi

# 5. Directories
mkdir -p /etc/openvpn/server /etc/openvpn/client /var/log/openvpn /var/www/disguise /opt/nogap-openvpn
chmod 755 /var/log/openvpn

# 6. Generate Certificates & Keys (Automated OpenSSL PKI)
PKI_DIR="/etc/openvpn/server"
if [[ ! -f "$PKI_DIR/ca.crt" || ! -f "$PKI_DIR/server.crt" ]]; then
  bold "==> Generating CA and Server cryptographic credentials..."
  
  # CA Key & Cert
  openssl req -new -x509 -days 3650 -nodes \
    -newkey rsa:2048 \
    -keyout "$PKI_DIR/ca.key" \
    -out "$PKI_DIR/ca.crt" \
    -subj "/CN=NoGap-OpenVPN-CA"

  # Server Key & CSR
  openssl req -new -nodes \
    -newkey rsa:2048 \
    -keyout "$PKI_DIR/server.key" \
    -out "$PKI_DIR/server.csr" \
    -subj "/CN=server"

  # Sign Server Cert with extendedKeyUsage for server
  cat << 'EOF' > "$PKI_DIR/server-ext.cnf"
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "OpenVPN Server Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
EOF

  openssl x509 -req -days 3650 \
    -in "$PKI_DIR/server.csr" \
    -CA "$PKI_DIR/ca.crt" \
    -CAkey "$PKI_DIR/ca.key" \
    -CAcreateserial \
    -out "$PKI_DIR/server.crt" \
    -extfile "$PKI_DIR/server-ext.cnf"
  
  rm -f "$PKI_DIR/server.csr" "$PKI_DIR/server-ext.cnf"
fi

# Generate DH parameters if not present
if [[ ! -f "$PKI_DIR/dh.pem" ]]; then
  bold "==> Generating DH parameters (2048 bit)..."
  openssl dhparam -out "$PKI_DIR/dh.pem" 2048
fi

# Generate tls-crypt key for control channel encryption
if [[ ! -f "$PKI_DIR/tls-crypt.key" ]]; then
  bold "==> Generating tls-crypt signature obfuscation key..."
  openvpn --genkey secret "$PKI_DIR/tls-crypt.key"
fi

# Generate dummy TLS certificate for Nginx disguise fallback
if [[ ! -f "$PKI_DIR/disguise.crt" ]]; then
  bold "==> Generating SSL certificate for internal Nginx fallback..."
  openssl req -x509 -nodes -days 3650 \
    -newkey rsa:2048 \
    -keyout "$PKI_DIR/disguise.key" \
    -out "$PKI_DIR/disguise.crt" \
    -subj "/CN=gateway.local"
fi

# 7. Configure Nginx Disguise Site (listens on 127.0.0.1:8443)
bold "==> Configuring Nginx disguise fallback on 127.0.0.1:8443..."
cat << 'EOF' > /etc/nginx/sites-available/disguise.conf
server {
    listen 127.0.0.1:8443 ssl default_server;
    server_name _;

    ssl_certificate /etc/openvpn/server/disguise.crt;
    ssl_certificate_key /etc/openvpn/server/disguise.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    root /var/www/disguise;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    server_tokens off;
}
EOF

# Copy benign index.html
if [[ -f "/opt/nogap-split-proxy/config/openvpn/disguise-index.html" ]]; then
  cp "/opt/nogap-split-proxy/config/openvpn/disguise-index.html" /var/www/disguise/index.html
else
  cat << 'EOF' > /var/www/disguise/index.html
<!DOCTYPE html><html><head><title>Cloud Gateway</title></head>
<body style="font-family:sans-serif;text-align:center;padding:50px;background:#0f172a;color:#f8fafc">
<h2>Cloud Gateway</h2><p>Gateway operational &bull; TLS Active</p></body></html>
EOF
fi

# Enable disguise site in Nginx and disable default 80 if needed
ln -sf /etc/nginx/sites-available/disguise.conf /etc/nginx/sites-enabled/disguise.conf
# Remove default site on 80/443 if present
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx || systemctl start nginx

# 8. Write OpenVPN server.conf
bold "==> Writing OpenVPN server configuration..."
cat << 'EOF' > /etc/openvpn/server/server.conf
port 443
proto tcp-server
dev tun0

ca /etc/openvpn/server/ca.crt
cert /etc/openvpn/server/server.crt
key /etc/openvpn/server/server.key
dh /etc/openvpn/server/dh.pem
tls-crypt /etc/openvpn/server/tls-crypt.key

server 10.8.0.0 255.255.255.0
topology subnet
ifconfig-pool-persist /var/log/openvpn/ipp.txt

push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 8.8.8.8"

# Disguise: forward non-VPN HTTPS probes to internal Nginx
port-share 127.0.0.1 8443

cipher AES-256-GCM
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
auth SHA256

keepalive 10 120
persist-key
persist-tun

user nobody
group nogroup

status /var/log/openvpn/openvpn-status.log 10
status-version 2
log-append /var/log/openvpn/openvpn.log
verb 3
mute 10
EOF

# Stop Squid if it was previously running (freeing up port 443)
if systemctl is-active --quiet squid 2>/dev/null; then
  yellow "Stopping existing Squid proxy to free port 443..."
  systemctl stop squid
  systemctl disable squid
fi

# 9. Start & Enable OpenVPN Service
bold "==> Starting OpenVPN server on TCP port 443..."
systemctl enable openvpn-server@server
systemctl restart openvpn-server@server

sleep 2
if systemctl is-active --quiet openvpn-server@server; then
  green "✓ OpenVPN server is active and listening on TCP port 443!"
else
  red "Warning: OpenVPN service failed to start. Logs:"
  journalctl -u openvpn-server@server --no-pager -n 20
fi

# 10. Generate Client Profile (client1)
bold "==> Generating initial client profile (client1)..."
CLIENT_NAME="client1"
CLIENT_KEY="$PKI_DIR/${CLIENT_NAME}.key"
CLIENT_CSR="$PKI_DIR/${CLIENT_NAME}.csr"
CLIENT_CRT="$PKI_DIR/${CLIENT_NAME}.crt"

if [[ ! -f "$CLIENT_CRT" ]]; then
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
fi

# Assemble all-in-one standalone client .ovpn profile
OVPN_OUT="/opt/nogap-openvpn/client.ovpn"
mkdir -p /opt/nogap-openvpn
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

cp "$OVPN_OUT" "/etc/openvpn/client/${CLIENT_NAME}.ovpn"
chmod 600 "$OVPN_OUT" "/etc/openvpn/client/${CLIENT_NAME}.ovpn"

green "=========================================================="
green "✓ OpenVPN Disguised Server Successfully Configured!"
green "  Port: 443 TCP (Looks like standard HTTPS)"
green "  Anti-DPI: tls-crypt enabled"
green "  Probe Fallback: port-share 127.0.0.1:8443 (Nginx)"
green "  Client Profile: ${OVPN_OUT}"
green "=========================================================="
