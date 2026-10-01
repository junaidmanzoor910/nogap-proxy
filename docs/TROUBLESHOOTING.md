# Troubleshooting

## Chrome: ERR_PROXY_CERTIFICATE_INVALID

**Symptom:** HTTPS proxy `proxy-dev.nogap.ai:443` fails; PAC on 8443 may still work.

**Common cause:** Ubuntu package **`squid`** (GnuTLS) sends only the **leaf** certificate on `https_port`, even when `fullchain.pem` contains intermediates. Browsers need the full Let's Encrypt chain.

**Fix:** Use **`squid-openssl`** (same config paths):

```bash
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y squid-openssl
sudo squid -v 2>&1 | grep -i openssl
sudo systemctl restart squid
```

Confirm chain:

```bash
openssl s_client -connect proxy-dev.nogap.ai:443 -servername proxy-dev.nogap.ai -showcerts </dev/null 2>/dev/null \
  | grep -c 'BEGIN CERTIFICATE'
# Expect >= 2 for Let's Encrypt

openssl s_client -connect proxy-dev.nogap.ai:443 -servername proxy-dev.nogap.ai \
  -verify_return_error -verify_hostname proxy-dev.nogap.ai </dev/null
# Expect verify return code: 0
```

Run [`scripts/validation/tls-chain-tests.sh`](../scripts/validation/tls-chain-tests.sh) from your workstation.

## Squid will not start after user changes

**Symptom:** `basicauthenticator` crashes; `cannot stat /etc/squid/passwords`.

**Fix:** Directory must be traversable by user `proxy`:

```bash
sudo chown root:proxy /etc/squid
sudo chmod 750 /etc/squid
sudo chmod 640 /etc/squid/passwords
sudo systemctl restart squid
```

## Squid error: “The requested URL could not be retrieved”

**Symptom:** Chrome (or PAC) loads `https://app-dev.nogap.ai` (or any HTTPS site) and shows a Squid error page.

**Cause:** Usually **407 Proxy Authentication Required** — credentials missing or wrong.

**Fix:**

1. Use [`scripts/chrome-via-proxy.sh`](../scripts/chrome-via-proxy.sh) (manual `https://proxy-dev.nogap.ai:443`) and enter **proxyuser01** + Squid password when prompted.
2. Confirm on EC2: `sudo grep app-dev /var/log/squid/access.log | tail -3` — look for `TCP_DENIED/407` vs `TCP_TUNNEL/200`.
3. Test with curl:

   ```bash
   cp scripts/workstation-proxy.env.example scripts/workstation-proxy.env
   # set NOGAP_PROXY_PASS
   scripts/with-ec2-proxy curl -sS -o /dev/null -w '%{http_code}\n' https://app-dev.nogap.ai/
   ```

   Expect **200** or **3xx**. Direct `curl https://app-dev.nogap.ai/` should also work (proves origin is up).

**403** on `api-dev.nogap.ai` with auth present: redeploy full Squid template — `sudo scripts/deploy-config.sh` on the instance (old split allowlist).

## Proxy auth works in curl but not Chrome

Use **`--proxy-user user:pass`** with curl (not `-u` alone). In Chrome, use **HTTPS / secure proxy** if PAC `PROXY` fails with TLS Squid — see [CLIENT-SETUP.md](CLIENT-SETUP.md).

## Certificate renewal

After `certbot renew`, the deploy hook must copy **`fullchain.pem`** (not `cert.pem` alone) to `/etc/squid/tls/`. See [CERTBOT-RENEWAL.md](CERTBOT-RENEWAL.md).
