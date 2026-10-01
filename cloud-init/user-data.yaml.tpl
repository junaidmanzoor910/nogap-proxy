#cloud-config
package_update: true
package_upgrade: true

packages:
  - squid-openssl
  - nginx
  - certbot
  - python3-certbot-dns-cloudflare
  - amazon-ssm-agent
  - jq
  - apache2-utils

write_files:
  - path: /etc/nogap-split-proxy/env
    permissions: "0644"
    content: |
      PROXY_HOSTNAME=${proxy_hostname}
      ALLOWED_DESTINATION_DOMAIN=${allowed_destination_domain}
      PAC_HTTPS_PORT=${pac_https_port}
      PROXY_HTTPS_PORT=${proxy_https_port}
      REPO_CONFIG_ROOT=/opt/nogap-split-proxy/config

runcmd:
  - mkdir -p /opt/nogap-split-proxy /etc/squid/tls /var/www/pac
  - systemctl enable amazon-ssm-agent
  - systemctl start amazon-ssm-agent || true
  - sysctl -w net.ipv6.conf.all.disable_ipv6=1
  - sysctl -w net.ipv6.conf.default.disable_ipv6=1
  - |
    grep -q nogap-ipv6 /etc/sysctl.d/99-nogap-split-proxy.conf 2>/dev/null || {
      echo '# nogap-ipv6' >> /etc/sysctl.d/99-nogap-split-proxy.conf
      echo 'net.ipv6.conf.all.disable_ipv6=1' >> /etc/sysctl.d/99-nogap-split-proxy.conf
      echo 'net.ipv6.conf.default.disable_ipv6=1' >> /etc/sysctl.d/99-nogap-split-proxy.conf
    }
  - echo "Bootstrap complete. Sync config from repo via SSM and run scripts/deploy-config.sh after TLS material exists."
