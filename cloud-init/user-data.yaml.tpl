#cloud-config
package_update: true
package_upgrade: true

packages:
  - openvpn
  - easy-rsa
  - iptables-persistent
  - netfilter-persistent
  - nginx
  - amazon-ssm-agent
  - jq
  - curl
  - openssl

write_files:
  - path: /etc/sysctl.d/99-openvpn.conf
    permissions: "0644"
    content: |
      net.ipv4.ip_forward = 1
      net.ipv6.conf.all.disable_ipv6 = 1
      net.ipv6.conf.default.disable_ipv6 = 1

  - path: /etc/nginx/sites-available/disguise.conf
    permissions: "0644"
    content: |
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

  - path: /var/www/disguise/index.html
    permissions: "0644"
    content: |
      <!DOCTYPE html>
      <html lang="en">
      <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Secure Cloud Service</title>
          <style>
              body { font-family: system-ui, sans-serif; background: #0f172a; color: #e2e8f0; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; }
              .box { text-align: center; padding: 2.5rem; background: #1e293b; border-radius: 12px; box-shadow: 0 10px 25px rgba(0,0,0,0.5); max-width: 480px; width: 90%; border: 1px solid #334155; }
              h1 { font-size: 1.5rem; margin: 0 0 0.5rem 0; color: #f8fafc; }
              p { font-size: 0.95rem; color: #94a3b8; line-height: 1.5; margin: 0; }
              .badge { display: inline-block; margin-top: 1.5rem; padding: 0.25rem 0.75rem; border-radius: 9999px; background: rgba(56, 189, 248, 0.1); color: #38bdf8; font-size: 0.8rem; }
          </style>
      </head>
      <body>
          <div class="box">
              <h1>Cloud Gateway</h1>
              <p>This edge gateway is active and operating normally. Authorized services may connect via standard secure protocols.</p>
              <div class="badge">TLS Active &bull; Gateway Operational</div>
          </div>
      </body>
      </html>

runcmd:
  # 1. Start Amazon SSM Agent
  - systemctl enable amazon-ssm-agent
  - systemctl start amazon-ssm-agent || true

  # 2. Kernel IP Forwarding
  - sysctl --system

  # 3. iptables NAT MASQUERADE for VPN pool 10.8.0.0/24
  - |
    DEFAULT_IFACE=$(ip route show default | awk '{print $5}' | head -n1)
    [ -z "$DEFAULT_IFACE" ] && DEFAULT_IFACE="eth0"
    iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$DEFAULT_IFACE" -j MASQUERADE
    netfilter-persistent save || true

  # 4. Create directories
  - mkdir -p /etc/openvpn/server /etc/openvpn/client /var/log/openvpn /var/www/disguise /opt/nogap-openvpn
  - chmod 755 /var/log/openvpn

  # 5. Cryptography & PKI generation
  - |
    PKI="/etc/openvpn/server"
    # CA
    openssl req -new -x509 -days 3650 -nodes -newkey rsa:2048 -keyout "$PKI/ca.key" -out "$PKI/ca.crt" -subj "/CN=NoGap-OpenVPN-CA"
    # Server cert
    openssl req -new -nodes -newkey rsa:2048 -keyout "$PKI/server.key" -out "$PKI/server.csr" -subj "/CN=server"
    cat << 'EOF' > "$PKI/server-ext.cnf"
    basicConstraints = CA:FALSE
    nsCertType = server
    nsComment = "OpenVPN Server Certificate"
    subjectKeyIdentifier = hash
    authorityKeyIdentifier = keyid,issuer
    keyUsage = critical, digitalSignature, keyEncipherment
    extendedKeyUsage = serverAuth
    EOF
    openssl x509 -req -days 3650 -in "$PKI/server.csr" -CA "$PKI/ca.crt" -CAkey "$PKI/ca.key" -CAcreateserial -out "$PKI/server.crt" -extfile "$PKI/server-ext.cnf"
    rm -f "$PKI/server.csr" "$PKI/server-ext.cnf"
    # DH parameters & tls-crypt key
    openssl dhparam -out "$PKI/dh.pem" 2048
    openvpn --genkey secret "$PKI/tls-crypt.key"
    # Nginx SSL cert
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout "$PKI/disguise.key" -out "$PKI/disguise.crt" -subj "/CN=gateway.local"

  # 6. Configure and start Nginx disguise fallback
  - ln -sf /etc/nginx/sites-available/disguise.conf /etc/nginx/sites-enabled/disguise.conf
  - rm -f /etc/nginx/sites-enabled/default
  - systemctl restart nginx

  # 7. Write OpenVPN server config (Disguised TCP 443 + tls-crypt + port-share)
  - |
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

    # Forward non-VPN probes on 443 to internal Nginx (Port Disguise)
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

  # 8. Start OpenVPN Service
  - systemctl enable openvpn-server@server
  - systemctl restart openvpn-server@server

  # 9. Generate Initial Client Profile (client1)
  - |
    PKI="/etc/openvpn/server"
    TOKEN=$(curl -sS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true)
    PUB_IP=$(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null || curl -sS https://api.ipify.org 2>/dev/null || echo "127.0.0.1")

    openssl req -new -nodes -newkey rsa:2048 -keyout "$PKI/client1.key" -out "$PKI/client1.csr" -subj "/CN=client1"
    cat << 'EOF' > "$PKI/client1-ext.cnf"
    basicConstraints = CA:FALSE
    nsCertType = client
    nsComment = "OpenVPN Client Certificate"
    subjectKeyIdentifier = hash
    authorityKeyIdentifier = keyid,issuer
    keyUsage = critical, digitalSignature
    extendedKeyUsage = clientAuth
    EOF
    openssl x509 -req -days 3650 -in "$PKI/client1.csr" -CA "$PKI/ca.crt" -CAkey "$PKI/ca.key" -CAcreateserial -out "$PKI/client1.crt" -extfile "$PKI/client1-ext.cnf"
    rm -f "$PKI/client1.csr" "$PKI/client1-ext.cnf"

    cat << EOF > /opt/nogap-openvpn/client.ovpn
    client
    dev tun
    proto tcp
    remote $${PUB_IP} 443
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
    $(cat "$PKI/ca.crt")
    </ca>

    <cert>
    $(cat "$PKI/client1.crt")
    </cert>

    <key>
    $(cat "$PKI/client1.key")
    </key>

    <tls-crypt>
    $(cat "$PKI/tls-crypt.key")
    </tls-crypt>
    EOF
    chmod 600 /opt/nogap-openvpn/client.ovpn
    cp /opt/nogap-openvpn/client.ovpn /etc/openvpn/client/client1.ovpn
