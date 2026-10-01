# Step-by-step: local NoGap + egress via EC2 (no nogap repo changes)

## One command (recommended)

```bash
cd ~/Documents/proxy
chmod +x run-nogap-local-proxy.sh
./run-nogap-local-proxy.sh
```

Prompts for Squid username/password, **automatically** enables EC2 egress (forwarder + Docker wrapper), you start each backend (`local-run.sh`) and frontend yourself, then opens proxied Chrome when you type `yes`. Drops you into bash with `docker` proxy still active.

---

## Manual steps (same behavior)

Use this when:

- Backends run in **Docker** (`./local-run-all.sh`)
- Frontend runs with **`npm run dev`** (`frontend-service/scripts/dev-local.sh`)
- **AWS** and other **public HTTPS** from backends should exit via **EC2 Elastic IP**
- **`localhost`** APIs (`localhost:4000`, Docker service names) stay **direct**

You only change/setup the **`proxy`** repo on the laptop. **Do not edit nogap-services.**

---

## Prerequisites

| Item | Notes |
|------|--------|
| EC2 proxy running | Squid on `proxy-dev.nogap.ai:443` |
| Squid user + password | e.g. `proxyuser01` from `provision-user.sh` on EC2 |
| AWS CLI / SSM access | To tail logs (optional) |
| Laptop software | `bash`, `curl`, `docker`, `squid`, Chrome |
| Paths | Adjust `~/Documents/proxy` and `~/nogap-services` if yours differ |

---

## Part 1 — EC2 (one-time or after proxy config changes)

### 1.1 SSM into the instance

```bash
aws ssm start-session --profile dev --region us-east-1 --target <instance-id>
```

### 1.2 Deploy Squid + PAC

```bash
sudo /opt/nogap-split-proxy/scripts/deploy-config.sh
```

### 1.3 Confirm OpenSSL Squid (TLS chain)

```bash
sudo squid -v 2>&1 | grep -i openssl
```

If missing:

```bash
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y squid-openssl
sudo systemctl restart squid
```

### 1.4 Squid password

Create or reset a user:

```bash
sudo /opt/nogap-split-proxy/scripts/provision-user.sh proxyuser01
```

Save the password securely for the laptop.

### 1.5 Note Elastic IP

On your machine:

```bash
cd ~/Documents/proxy/terraform
terraform output elastic_ip
```

---

## Part 2 — Laptop one-time setup

### 2.1 Install packages

```bash
sudo apt-get update
sudo apt-get install -y squid curl
```

### 2.2 Proxy credentials file

```bash
cd ~/Documents/proxy
cp scripts/workstation-proxy.env.example scripts/workstation-proxy.env
chmod 600 scripts/workstation-proxy.env
```

Edit `scripts/workstation-proxy.env`:

```bash
NOGAP_PROXY_USER=proxyuser01
NOGAP_PROXY_PASS='your-squid-password'
```

### 2.3 Make scripts executable

```bash
chmod +x scripts/start-local-forwarder.sh \
         scripts/stop-local-forwarder.sh \
         scripts/start-workstation-egress.sh \
         scripts/enable-nogap-ec2-egress.sh \
         scripts/chrome-via-proxy.sh \
         scripts/with-ec2-proxy
```

---

## Part 3 — Every local NoGap session (order matters)

### 3.1 Run the interactive helper (starts forwarder only)

```bash
cd ~/Documents/proxy
./run-nogap-local-proxy.sh
```

Follow prompts. It does **not** start nogap for you.

### 3.2 Terminal A — backends (your `local-run.sh` per service)

Use the **same shell** left open by `./run-nogap-local-proxy.sh` (proxy already enabled):

```bash
cd ~/nogap-services/auth-service && ./local-run.sh
cd ~/nogap-services/router-service && ./local-run.sh
# …each service you need
```

> Re-run `./local-run.sh` in that shell if you had containers up before this session.

### 3.3 Terminal B — frontend

```bash
cd ~/nogap-services/frontend-service
./scripts/dev-local.sh
```

App: **http://localhost:3000**

### 3.4 Chrome

When `./run-nogap-local-proxy.sh` asks, type **yes** — or run:

```bash
~/Documents/proxy/scripts/chrome-via-proxy.sh http://localhost:3000
```

---

## Part 4 — Verify

### 4.1 CLI (host)

In a shell with `source scripts/enable-nogap-ec2-egress.sh`:

```bash
curl -sS https://api.ipify.org && echo
```

**Pass:** IP = Elastic IP from Part 1.5.

### 4.2 EC2 Squid logs

On EC2:

```bash
sudo tail -f /var/log/squid/access.log
```

While using the app (login, load data):

| You should see | Meaning |
|----------------|--------|
| `CONNECT ...amazonaws.com:443` + `proxyuser01` + `TCP_TUNNEL/200` | Backend AWS via EC2 |
| `CONNECT api-dev.nogap.ai` / `auth-dev.nogap.ai` | Browser public APIs via EC2 |
| **No** `CONNECT localhost` | Expected — local APIs direct |

Filter:

```bash
sudo tail -f /var/log/squid/access.log | grep -E 'amazonaws|nogap\.ai|TCP_TUNNEL/200'
```

### 4.3 Service health

```bash
cd ~/nogap-services
./local-run-all.sh status
curl -sS http://localhost:4000/health
curl -sS http://localhost:3000/api/health
```

---

## Part 5 — When you are done

### 5.1 Stop nogap

```bash
cd ~/nogap-services
./local-run-all.sh stop
```

Stop frontend: `Ctrl+C` in the `npm run dev` terminal.

### 5.2 Stop local forwarder

```bash
cd ~/Documents/proxy
./scripts/stop-local-forwarder.sh
```

Close the test Chrome profile window.

---

## Quick reference (copy-paste session)

```bash
# Once per session
cd ~/Documents/proxy && ./run-nogap-local-proxy.sh

# Terminal A — backends (shell from run-nogap-local-proxy.sh)
cd ~/nogap-services/<service> && ./local-run.sh

# Terminal B — frontend
cd ~/nogap-services/frontend-service && ./scripts/dev-local.sh
```

---

## What goes where (summary)

| Traffic | Via EC2? |
|---------|----------|
| Docker → AWS (Secrets Manager, S3, …) | **Yes**, if 3.1 → 3.3 order |
| Docker → `nogap-*-service:400x` | **No** |
| Browser → `http://localhost:4000` | **No** (default `env.local`) |
| Proxied Chrome → `auth-dev`, `google`, `app-dev`, `api-dev` | **Yes** |
| Normal Chrome | **No** |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| No `amazonaws` in Squid log | `source enable-nogap-ec2-egress.sh` then re-run each `./local-run.sh` |
| `407` in logs | Wrong `NOGAP_PROXY_PASS` in `workstation-proxy.env` |
| Forwarder won’t start | `sudo apt-get install -y squid`; check password in env file |
| `docker: command not found` in subshell | Use **bash**; run `source` in same shell as `local-run-all.sh` |
| Chrome “URL could not be retrieved” | Run `source enable-nogap-ec2-egress.sh` first; use `chrome-via-proxy.sh` |
| Frontend can’t reach APIs | Backends not up — `./local-run-all.sh status` |
| `403` on some hosts in Squid | On EC2: `sudo /opt/nogap-split-proxy/scripts/deploy-config.sh` |

---

## Related docs

- [LOCALHOST-DEV-EGRESS.md](LOCALHOST-DEV-EGRESS.md) — concepts and forwarder
- [CLIENT-SETUP.md](CLIENT-SETUP.md) — PAC / manual proxy
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — Squid TLS and auth errors
