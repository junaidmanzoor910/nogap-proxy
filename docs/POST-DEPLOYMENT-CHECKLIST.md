# Post-deployment checklist

After `terraform apply`, DNS, certificate issuance, and `deploy-config.sh`.

## Infrastructure

- [ ] `elastic_ip` matches Cloudflare `A` record for `proxy-dev.nogap.ai` (grey cloud).
- [ ] EC2 registered in SSM (**PingStatus: Online**).
- [ ] No security group rule on TCP **22**; instance has **no** key pair.

## TLS and services

- [ ] Instance runs **`squid-openssl`** (`squid -v` shows OpenSSL, not GnuTLS-only build).
- [ ] `bash scripts/validation/tls-chain-tests.sh` passes: **≥ 2** certs on **443**, `verify return code: 0`, hostname match.
- [ ] `openssl s_client` shows valid cert for `proxy-dev.nogap.ai` on **443** and **8443**.
- [ ] `sudo squid -k parse` succeeds on instance.
- [ ] `sudo nginx -t` succeeds on instance.
- [ ] `curl -fsS https://proxy-dev.nogap.ai:8443/proxy.pac` returns PAC.

## Authentication and ACL

- [ ] Ten users provisioned via `provision-user.sh` (bcrypt hashes in `/etc/squid/passwords`).
- [ ] CONNECT to `https://app-dev.nogap.ai/` succeeds with valid credentials via proxy.
- [ ] CONNECT to `https://example.com/` **fails** with same credentials.
- [ ] CONNECT to non-443 port **fails**.
- [ ] Logs contain **no** passwords or `Proxy-Authorization` values.

## Client validation

- [ ] PAC configured on at least one desktop browser; `app-dev.nogap.ai` egress shows **Elastic IP**.
- [ ] Unrelated site egress shows **non-EIP** (DIRECT).
- [ ] Review [VALIDATION.md](VALIDATION.md) client matrix; record devices tested.

## Operations

- [ ] Certbot timer active; `certbot renew --dry-run` succeeds.
- [ ] Log rotation configured; CloudWatch/S3 session logging decision documented if enabled.
- [ ] Rollback steps in README understood.
