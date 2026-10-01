# Client configuration (PAC + authenticated proxy)

## PAC URL

```
https://proxy-dev.nogap.ai:8443/proxy.pac
```

PAC sends **almost all hosts** to `HTTPS proxy-dev.nogap.ai:443` (TLS forward proxy). **localhost**, **127.0.0.1**, and **\*.local** stay **DIRECT** (destination only — see [LOCALHOST-DEV-EGRESS.md](LOCALHOST-DEV-EGRESS.md)).

For **all applications** on the machine (not only the browser), use **system** HTTPS proxy below or [`scripts/with-ec2-proxy`](../scripts/with-ec2-proxy) (see [LOCALHOST-DEV-EGRESS.md](LOCALHOST-DEV-EGRESS.md)).

### `PROXY` vs `HTTPS` in PAC (TLS `https_port` on Squid)

Squid speaks **TLS first** on port **443** (HTTPS forward proxy). PAC keyword **`PROXY host:443`** means “use the HTTP proxy protocol on that port,” which is **not** the same as **`HTTPS host:443`** (“secure proxy” / TLS-to-proxy).

| Client | `PROXY proxy-dev.nogap.ai:443` in PAC | Notes |
|--------|----------------------------------------|-------|
| **Firefox** (desktop) | Often works with TLS `https_port` when auth + CONNECT are configured | Validate in your release; use manual **HTTPS proxy** if PAC fails |
| **Chrome / Edge** (desktop) | **Inconsistent** with TLS-only `https_port` when PAC uses `PROXY` | Prefer manual **Secure / HTTPS proxy** `proxy-dev.nogap.ai:443` or test `HTTPS proxy-dev.nogap.ai:443` in PAC on a staging profile |
| **Safari** (macOS) | Uses system PAC; TLS proxy support **not guaranteed** | Test before relying on PAC-only rollout |
| **Android Chrome** | PAC support **limited**; `PROXY` vs `HTTPS` untested here | Treat mobile as **unverified** until device-tested |
| **iOS Safari** | PAC often **MDM-only**; no universal guarantee | Same as above |

**Not verified in CI:** real browser interoperability is **environment-specific**. Do not assume `PROXY` and `HTTPS` PAC entries are interchangeable. Record results in [VALIDATION.md](VALIDATION.md).

If the browser fails to connect, set manual proxy to **HTTPS** `proxy-dev.nogap.ai:443` with your proxy credentials. This design does **not** claim traffic is indistinguishable from ordinary site HTTPS.

**Server-side Squid ACLs remain authoritative** if PAC is edited.

## Limitations (all platforms)

- **Not all traffic** uses the PAC (system apps, many mobile apps, background services).
- **DNS over HTTPS (DoH)** in the browser can change resolution behavior; routing is still by hostname in PAC for browsers that honor PAC.
- **QUIC/HTTP3** may bypass proxy for some sites; test with flags/disabled QUIC if needed.
- **Non-HTTPS** (plain HTTP on port 80) is not tunneled unless the client uses the proxy for HTTP as well.
- **WebSockets** over HTTPS generally work via CONNECT.
- **CONNECT** ACLs enforce hostname and port **443** only; **encrypted paths** inside the tunnel are **not** inspected (no TLS interception).

## Windows 10/11

1. **Settings → Network & Internet → Proxy → Use setup script** → PAC URL.
2. Or **Internet Options → Connections → LAN settings → Automatic configuration**.
3. Browser: Chrome/Edge use system proxy by default; Firefox → Settings → Network → Automatic proxy configuration URL.

Authentication: first HTTPS request via proxy should prompt for username/password (or use OS/browser credential store).

## macOS

**System Settings → Network → (interface) → Details → Proxies → Automatic Proxy Configuration** → PAC URL.

Safari uses system proxy. Chrome uses system proxy; Firefox separate.

## Linux (desktop) — Lubuntu / LXQt / GNOME

### All machine traffic (recommended for “everything via proxy”)

1. **Preferences → Network Connections** (or **Settings → Network** → gear icon on your connection).
2. **Proxy** tab → **Manual**.
3. Set **HTTPS proxy** (secure): host `proxy-dev.nogap.ai`, port **443**.
4. Leave HTTP proxy empty unless you know you need it.
5. Apply, then **restart browsers** and any apps that cache proxy settings.

Chrome on Linux usually follows **system** proxy when “Use system proxy settings” is enabled.

### PAC (browser-oriented)

- **Automatic configuration URL:** `https://proxy-dev.nogap.ai:8443/proxy.pac`
- Or: `google-chrome --proxy-pac-url="https://proxy-dev.nogap.ai:8443/proxy.pac"`

PAC does **not** affect all apps (CLI, many Electron apps, etc.). Use **manual HTTPS proxy** for widest coverage.

### Firefox

- Settings → Network → **Automatic** PAC URL, or **Manual** HTTPS proxy `proxy-dev.nogap.ai` port **443**.

## Android

PAC support is **limited** and varies by OS version and manufacturer.

- Some versions: Wi‑Fi → Modify → Advanced → **Proxy: Automatic (PAC)**.
- Many apps **ignore** Wi‑Fi proxy; only some browsers honor it.
- Expect to test **Chrome for Android** explicitly; native apps may not use proxy.

## iOS / iPadOS

- **Supervised/MDM** is the reliable way to push PAC globally.
- Unsupervised: Wi‑Fi HTTP Proxy **Manual** (host/port) per network; **no full PAC** on all apps.
- Third-party browsers may not honor PAC like desktop Safari.

## Credential distribution

1. Operator runs `provision-user.sh` on instance (interactive password).
2. Deliver username/password via your org’s **secure channel** (password manager, encrypted email — policy your choice).
3. Revoke with `revoke-user.sh` and `systemctl reload squid`.

Never embed credentials in the PAC file.
