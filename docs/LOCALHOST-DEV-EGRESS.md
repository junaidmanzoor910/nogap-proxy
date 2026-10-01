# Workstation egress: all public sites + local-process outbound via EC2

## Goals

| Goal | How |
|------|-----|
| **All websites** (`app-dev.nogap.ai`, Google, …) via EC2 | Browser PAC → local forwarder → EC2 Squid |
| **Local outbound** (curl, Node, `npm`, etc. on the laptop) via EC2 | `HTTP_PROXY=http://127.0.0.1:3129` + same forwarder |
| **Local inbound** (`http://localhost:3000`, `localhost:4000`) unchanged | PAC + `NO_PROXY` keep **destination** localhost **DIRECT** |

You do **not** need to change your application repo. Docker containers only use EC2 if you pass proxy env into `docker run` (see below).

## One-time setup (each laptop)

```bash
cd proxy
cp scripts/workstation-proxy.env.example scripts/workstation-proxy.env
chmod 600 scripts/workstation-proxy.env
# NOGAP_PROXY_USER, NOGAP_PROXY_PASS (Squid creds from EC2)

sudo apt-get install -y squid   # local forwarder only
chmod +x scripts/*.sh
```

On **EC2** (once): `sudo /opt/nogap-split-proxy/scripts/deploy-config.sh`

## Daily use (one command)

```bash
./scripts/start-workstation-egress.sh
```

Then in **that same terminal** (or a child shell that inherited env):

```bash
curl -sS https://api.ipify.org    # should show Elastic IP
./scripts/chrome-via-proxy.sh https://app-dev.nogap.ai
```

Or start Chrome automatically:

```bash
NOGAP_START_CHROME=1 ./scripts/start-workstation-egress.sh
```

**No proxy password popup** in Chrome — auth is on the local forwarder.

## What still stays DIRECT

- Browser or app calling **`http://localhost:*`** / **`127.0.0.1`**
- Hostnames ending in **`.local`**

## Nogap local — no nogap file edits

Use **`./run-nogap-local-proxy.sh`** (credentials + forwarder + Chrome prompt). You start each **`local-run.sh`** and **`dev-local.sh`** yourself. See [NOGAP-LOCAL-EC2-EGRESS.md](NOGAP-LOCAL-EC2-EGRESS.md).

## Verify on EC2

```bash
sudo tail -f /var/log/squid/access.log | grep --line-buffered -v ' 127\.0\.0\.1 '
```

## Stop forwarder

```bash
./scripts/stop-local-forwarder.sh
```
