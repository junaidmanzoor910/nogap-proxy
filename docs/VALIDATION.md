# Validation and test matrix

## Local tests (no AWS)

Run from repository root:

```bash
./tests/run-local-tests.sh
```

Covers PAC label-boundary logic, Squid ACL template ordering, and secret-pattern scan.

## Post-deployment automated script

```bash
export PROXY_USER=proxyuser01   # example
export PROXY_PASS=...           # from secure distribution only
./scripts/validation/tls-chain-tests.sh
INSTANCE_ID=i-xxxxxxxx ./scripts/validation/post-deploy-tests.sh
```

`tls-chain-tests.sh` checks certificate **chain count** on 443/8443, **openssl verify**, proxy **407** without auth, and allow/deny when credentials are set. Use **`--proxy-user`** for HTTPS proxy auth.

Set `PROXY_USER` / `PROXY_PASS` only in your shell; do not log them.

## Manual tests

| ID | Test | Expected | Performed locally |
|----|------|----------|-------------------|
| T1 | TLS 443 chain count | ≥ 2 PEM blocks; verify code 0 | `tls-chain-tests.sh` |
| T2 | TLS 8443 PAC chain | ≥ 2 PEM blocks | `tls-chain-tests.sh` |
| T3 | PAC fetch | 200, `FindProxyForURL` present | No |
| T4 | Proxy no auth | 407 / denied | No |
| T5 | Proxy auth + `app-dev.nogap.ai` | Tunnel succeeds | No |
| T6 | Proxy auth + `example.com` | Denied by Squid | No |
| T7 | CONNECT port 80 | Denied | No |
| T8 | SSM `StartSession` | Shell access | No |
| T9 | Egress IP via browser PAC | Public IP = EIP | No |
| T10 | Egress DIRECT other site | IP ≠ EIP | No |
| T11 | Log review | No credentials | No |

## Client platform matrix (fill in after testing)

| Platform | Browser / version | PAC honored? | Auth prompt? | app-dev via EIP? | Notes |
|----------|-------------------|--------------|--------------|------------------|-------|
| Windows 11 | Chrome current | | | | QUIC/DoH |
| Windows 11 | Firefox current | | | | |
| Windows 11 | Edge current | | | | |
| macOS | Safari current | | | | System PAC |
| macOS | Chrome current | | | | |
| Ubuntu 24.04 | Firefox current | | | | |
| Ubuntu 24.04 | Chromium | | | | |
| Android 14+ | Chrome | | | | App proxy limits |
| iOS 17+ | Safari | | | | MDM vs manual |

### Scenarios to exercise

- Login redirects and OAuth to **other domains** (may break or bypass proxy).
- WebSocket-heavy pages on allowed host.
- API calls from browser devtools to allowed vs denied hosts.
- Subresource loads from CDN on **different hostname** (likely DIRECT).
- Enable/disable **Secure DNS (DoH)** in browser and re-test.
- Disable **QUIC** in Chromium (`chrome://flags`) if behavior differs.

## DNS rebinding / IP literals

Squid denies CONNECT where the requested host is an **IPv4/IPv6 literal**. Clients resolving allowed names to IPs still use hostname in CONNECT for well-behaved browsers; malicious rebinding is **not fully eliminated**—document and monitor.

## What this design does not guarantee

- Proxy traffic on port 443 is **not** claimed to look like normal browsing to arbitrary observers.
- PAC is **not** system-wide enforcement on mobile.
- Domain allowlist does not block every indirect access pattern.
