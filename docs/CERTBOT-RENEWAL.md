# Certbot DNS-01 (Cloudflare) — issuance, renewal, and secret handling

## Prerequisites

- Grey-cloud DNS `A` record `proxy-dev.nogap.ai` → Elastic IP.
- Scoped Cloudflare API token (DNS edit for this zone/record only).
- `ACME_EMAIL` set for Let’s Encrypt account notices.

## One-time credentials file (never commit)

On the instance (via SSM):

```bash
sudo install -d -m 700 /root/.secrets
sudo install -m 600 /dev/null /root/.secrets/cloudflare.ini
sudo editor /root/.secrets/cloudflare.ini
```

File content (single line, no quotes in token value unless required by certbot):

```ini
# dns_cloudflare_api_token — set per certbot Cloudflare plugin documentation (single line, no quotes in value unless required)
```

Permissions must remain **0600** and owned by **root**. Do not copy into user-data, Terraform, or Git.

## Initial issuance (after deployment approval)

```bash
sudo cp /opt/nogap-split-proxy/scripts/certbot-dns-cloudflare.sh.example /root/certbot-dns-cloudflare.sh
sudo chmod 700 /root/certbot-dns-cloudflare.sh
sudo ACME_EMAIL=you@example.com CLOUDFLARE_CREDENTIALS_FILE=/root/.secrets/cloudflare.ini \
  /root/certbot-dns-cloudflare.sh
```

Avoid passing the token on the command line; use the credentials file only.

## Renewal deploy hook

```bash
sudo install -m 755 /opt/nogap-split-proxy/scripts/renewal-deploy-hook.sh.example \
  /etc/letsencrypt/renewal-hooks/deploy/nogap-split-proxy.sh
```

The hook copies certs to `/etc/squid/tls/` and runs `deploy-config.sh` (reload Squid/Nginx).

## systemd timer (recommended)

Ubuntu’s `certbot` package installs **`certbot.timer`**. Enable it:

```bash
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer
sudo systemctl status certbot.timer
```

Verify twice before relying on it:

```bash
sudo certbot renew --dry-run
```

Renewal runs as **root**, reads `/root/.secrets/cloudflare.ini`, and does **not** need the token in process arguments when using `--dns-cloudflare-credentials`.

## TLS private key protection

- Let’s Encrypt keys live under `/etc/letsencrypt/live/proxy-dev.nogap.ai/` (root-readable).
- Copies in `/etc/squid/tls/` should be **644** cert / **600** key (`deploy-config.sh`).
- Nginx and Squid read keys as root-started services; do not world-read `privkey.pem`.

## Password / token exposure risks

| Action | Risk | Mitigation |
|--------|------|------------|
| `PROXY_PASSWORD` env for `provision-user.sh` | Visible in `ps` briefly | Use interactive prompts |
| `htpasswd` on command line | Password in argv during call | Script unsets `PASS` immediately after |
| `certbot -v` in cron | May log challenges | Use package timer; avoid verbose cron |
| Session Manager transcripts | Operator mistakes | Do not paste tokens/passwords in shared logs |

## Rotation

1. Create new Cloudflare token; update `/root/.secrets/cloudflare.ini`.
2. `sudo certbot renew --force-renewal` (maintenance window).
3. Revoke old Cloudflare token.
