# DNS + Let’s Encrypt (post-deploy)

Current Elastic IP (verify in `terraform output`): use **`terraform output elastic_ip`**.

## 1. Cloudflare DNS (grey cloud)

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| A | `proxy-dev` | `<elastic_ip>` | **DNS only** (grey) |

Confirm:

```bash
dig +short proxy-dev.nogap.ai A
```

## 2. Cloudflare API token (instance only)

Via SSM session on the instance:

```bash
sudo install -d -m 700 /root/.secrets
sudo nano /root/.secrets/cloudflare.ini   # mode 600 after save
```

Contents (one line, scoped DNS edit token for `nogap.ai`):

```ini
# dns_cloudflare_api_token — set per certbot Cloudflare plugin documentation
```

```bash
sudo chmod 600 /root/.secrets/cloudflare.ini
```

## 3. Issue certificate

```bash
sudo cp /opt/nogap-split-proxy/scripts/certbot-dns-cloudflare.sh.example /root/certbot-dns-cloudflare.sh
sudo chmod 700 /root/certbot-dns-cloudflare.sh
sudo install -m 755 /opt/nogap-split-proxy/scripts/renewal-deploy-hook.sh.example \
  /etc/letsencrypt/renewal-hooks/deploy/nogap-split-proxy.sh
sudo ACME_EMAIL=you@example.com CLOUDFLARE_CREDENTIALS_FILE=/root/.secrets/cloudflare.ini \
  /root/certbot-dns-cloudflare.sh
sudo systemctl enable --now certbot.timer
sudo certbot renew --dry-run
```

## 4. Retrieve proxy user passwords

```bash
sudo cat /root/nogap-proxy-initial-users.txt
```

Distribute via your secure channel; delete or shred the file after distribution if policy requires.
