# Cloudflare DNS and ACME DNS-01

## Proxy hostname record

| Record | Value | Proxy status |
|--------|-------|----------------|
| `A` `proxy-dev.nogap.ai` | Elastic IP from Terraform output | **DNS only (grey cloud)** |

Do **not** modify `app-dev.nogap.ai`.

## Orange cloud vs grey cloud

Cloudflare’s **proxied (orange)** mode terminates HTTP/S at Cloudflare edges. It is designed for **origin websites**, not arbitrary **HTTPS forward-proxy CONNECT** traffic to third-party hosts. Clients expect to speak the **proxy protocol** directly to your Squid listener on **443**.

**Requirement:** use **DNS-only (grey cloud)** for `proxy-dev.nogap.ai` unless you have a separately verified architecture (not part of this project).

Implications:

- Clients connect to your **Elastic IP** (via DNS resolution of the grey record).
- Cloudflare WAF/CDN features do not apply to proxy traffic.
- Certificate on the instance is from **Let’s Encrypt DNS-01**, not Cloudflare origin cert.

## Cloudflare API token (provisioning — not done in this repo)

Create a **narrow** token:

- Permissions: **Zone → DNS → Edit** for `nogap.ai` only, or single-record custom token if available.
- Optional: restrict client IP to Elastic IP after first deploy.

On the instance (via SSM):

```ini
# /root/.secrets/cloudflare.ini  (chmod 600, root only)
# dns_cloudflare_api_token — paste scoped token as the value on this line (certbot format)
```

**Never** commit this file. Rotate token if exposed.

## Certificate issuance (after approval only)

```bash
sudo install -d -m 700 /root/.secrets
sudo cp certbot-dns-cloudflare.sh.example /root/certbot-dns-cloudflare.sh
# Edit paths; set ACME_EMAIL
sudo CLOUDFLARE_CREDENTIALS_FILE=/root/.secrets/cloudflare.ini ACME_EMAIL=you@example.com bash /root/certbot-dns-cloudflare.sh
```

Install renewal hook:

```bash
sudo install -m 755 scripts/renewal-deploy-hook.sh.example /etc/letsencrypt/renewal-hooks/deploy/nogap-split-proxy.sh
```

Test renewal and enable `certbot.timer`: see [CERTBOT-RENEWAL.md](CERTBOT-RENEWAL.md).

```bash
sudo certbot renew --dry-run
```

## Terraform state sensitivity

State files record resource IDs and **user_data** contents. They must not contain API tokens. Use encrypted remote state (S3 + KMS) for teams; restrict bucket IAM.
