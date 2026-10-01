# Security model and residual risks

## What Squid enforces

- Authenticated users only.
- **CONNECT only** to destination port **443** (HTTPS sites; not arbitrary TCP/UDP).
- **Any** destination hostname on port 443 for authenticated users (full-proxy mode). Split allowlist for `app-dev.nogap.ai` only is preserved in [`config/proxy.pac.split`](config/proxy.pac.split) + matching Squid ACL if you revert.
- Requests whose URL host is an **IPv4/IPv6 literal** are denied (all methods).
- Only **CONNECT** is permitted as an HTTP method through the proxy.

Squid **does not** provide perfect **IP-level egress enforcement**. Security groups also cannot filter outbound traffic by domain name.

## DNS rebinding and resolution

For allowed **hostnames**, Squid resolves the origin when establishing the tunnel. A malicious or compromised resolver could return unexpected addresses (**DNS rebinding**) while the CONNECT host header remains allowed. Mitigations are partial:

- Literal-IP CONNECT targets are blocked.
- Allowed names still depend on DNS at connection time.

Monitor application behavior; do not assume hostname ACLs alone prevent all rebinding scenarios.

## Client-side PAC

PAC can be edited on the client. **Server-side Squid ACLs remain authoritative** for traffic that uses the proxy.

PAC does not control non-browser apps, many mobile apps, DoH/DoT, or QUIC paths that bypass the proxy.

## TLS on the proxy port

Traffic to `proxy-dev.nogap.ai:443` is **TLS to the forward proxy**, not ordinary HTTPS to a web origin. This design does not claim indistinguishability from normal site browsing.

## No TLS interception

No `ssl_bump`, no client root CA. Encrypted contents inside CONNECT tunnels are not inspected.
