# nogap-proxy: Disguised OpenVPN & Secure Egress

Reproducible **AWS EC2** deployment supporting **pure-software OpenVPN** with **traffic disguise** over **TCP 443** (anti-DPI via `tls-crypt` and active probe resistance via Nginx `port-share 8443`), alongside the existing Squid forward proxy. Administration via **SSM Session Manager** — **no SSH**.

## OpenVPN Disguised Architecture (Recommended)

```
Workstation/Clients ──── TCP 443 (Disguised HTTPS) ────► AWS EC2 (OpenVPN Server)
                                                                 │
                                ┌────────────────────────────────┴────────────────────────────────┐
                                ▼                                                                 ▼
                   Authorized Client (tls-crypt)                                  Non-VPN Probe / Port Scan
                                │                                                                 │
                                ▼                                                                 ▼
                 tun0 Interface (10.8.0.0/24)                                          port-share 127.0.0.1:8443
                                │                                                                 │
                                ▼                                                                 ▼
                     iptables NAT MASQUERADE                                           Nginx Disguise Web Server
                                │                                                    (Returns HTTPS 200 OK Website)
                                ▼
                   Egress via EC2 Elastic IP
```

- **Disguise Mechanism**: Listens on TCP port 443 (standard HTTPS). Uses `tls-crypt` to eliminate OpenVPN handshake signatures. Probes/scanners falling on port 443 get forwarded via `port-share` to a local Nginx site, appearing as a genuine HTTPS web server.
- **Software, Not Service**: Runs community OpenVPN software directly on EC2 and Linux workstations without third-party VPN SaaS or AWS Client VPN fees.
- **Interactive Control**: Manage via `./run-nogap-vpn.sh` or through the Web UI (`./run-ui.sh`).
- **Complete Walkthrough**: See [docs/OPENVPN-DISGUISED-SETUP.md](docs/OPENVPN-DISGUISED-SETUP.md).

## Quickstart (OpenVPN)

1. **Bootstrap EC2**: Run `sudo ./scripts/bootstrap-host-openvpn.sh` on EC2 (or use `cloud-init`).
2. **Fetch Profile**: `./run-nogap-vpn.sh fetch` (downloads `client.ovpn` via SSM).
3. **Connect**: `./run-nogap-vpn.sh start` (tunnels all workstation traffic through EC2).
4. **Status**: `./run-nogap-vpn.sh status` (verifies egress IP and latency).
5. **Verify Disguise**: `./run-nogap-vpn.sh probe` (verifies port 443 returns Nginx HTTPS 200).
6. **Disconnect**: `./run-nogap-vpn.sh stop` (restores local workstation routing).

## Project layout

| Path | Purpose |
|------|---------|
| `terraform/` | EC2, EIP, SG, IAM instance profile |
| `config/` | Squid template, Nginx PAC site, `proxy.pac` |
| `cloud-init/` | User-data template (no secrets) |
| `scripts/` | Bootstrap, deploy, users, cert examples, validation |
| `tests/` | Local PAC/ACL/secret tests |
| `docs/` | Checklists, cost, Cloudflare, clients, validation |

## Security model

| Control | Implementation |
|---------|------------------|
| Authentication | Squid `basic_ncsa_auth` + bcrypt hashes (`provision-user.sh`) |
| Destination | Authenticated CONNECT to **443** (full-proxy; split mode in `config/proxy.pac.split`) |
| Local inbound | PAC sends **localhost / 127.0.0.1 / \*.local** DIRECT (no nogap repo changes) |
| IP literals | Denied on CONNECT (see DNS rebinding notes) |
| Ingress | TCP **443**, **8443** only; **no** 22 |
| Admin | SSM + `AmazonSSMManagedInstanceCore` |
| TLS | LE DNS-01 via Cloudflare (operator-supplied token at deploy) |

Residual risks (DNS rebinding, non-CONNECT bypass prevented in config, IP-level limits): [docs/SECURITY.md](docs/SECURITY.md).

## Terraform operations notes

- **`user_data_replace_on_change = true`:** changing cloud-init/user-data **replaces** the EC2 instance on apply. Plan accordingly.
- **AMI pin:** verify `ubuntu_ami_id` is **x86_64** Noble 24.04 in **us-east-1** before apply:
  `aws ec2 describe-images --profile dev --region us-east-1 --image-ids <ami> --query 'Images[0].[Architecture,Name,State]'`
- **`lifecycle.ignore_changes = [ami]`** avoids drift replacement but can leave an old AMI; reconcile deliberately.
- **IMDSv2** required (`http_tokens = "required"`); **no** SSH key or TCP 22.

## Deployment stages (after explicit approval)

1. **Plan:** `cd terraform && terraform init && terraform plan -var-file=terraform.tfvars`
2. **Apply:** `terraform apply -var-file=terraform.tfvars` → note `elastic_ip`, `instance_id`
3. **DNS:** Grey-cloud `A` `proxy-dev.nogap.ai` → `elastic_ip` ([docs/CLOUDFLARE-DNS.md](docs/CLOUDFLARE-DNS.md))
4. **SSM:** `aws ssm start-session --profile dev --region us-east-1 --target <instance-id>`
5. **Sync repo** to `/opt/nogap-split-proxy`; run `scripts/bootstrap-host.sh`
6. **TLS:** certbot DNS-01 ([docs/CERTBOT-RENEWAL.md](docs/CERTBOT-RENEWAL.md), `scripts/certbot-dns-cloudflare.sh.example`)
7. **Config:** `sudo scripts/deploy-config.sh`
8. **Users:** `sudo scripts/provision-user.sh <user>` (×10)
9. **Validate:** [docs/POST-DEPLOYMENT-CHECKLIST.md](docs/POST-DEPLOYMENT-CHECKLIST.md), `scripts/validation/post-deploy-tests.sh`

## Local validation

```bash
chmod +x tests/run-local-tests.sh scripts/*.sh scripts/validation/*.sh
./tests/run-local-tests.sh
```

## Rollback

1. Revoke users; stop `squid`/`nginx` if needed.
2. `terraform destroy` (releases EIP if configured).
3. Remove Cloudflare `A` record for `proxy-dev.nogap.ai`.
4. Revoke Cloudflare API token used for ACME.

## Cost

See [docs/COST.md](docs/COST.md) (~USD 17–20/mo baseline before data transfer).

## Troubleshooting

| Symptom | Check |
|---------|--------|
| SSM offline | IAM profile, egress 443, `amazon-ssm-agent` status |
| Squid won't start | `squid -k parse`; TLS files in `/etc/squid/tls/` |
| `ERR_PROXY_CERTIFICATE_INVALID` | [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — use `squid-openssl`, verify chain on 443 |
| Browser won't proxy | HTTPS vs PROXY scheme; manual secure proxy test |
| Cert renewal fails | Token scope; `certbot renew --dry-run` |
| Local app uses `localhost:400x` APIs | DIRECT by design; use browser proxy for public URLs |
| “URL cannot be retrieved” | Squid 407 — [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) |

## Unresolved assumptions

- **Ingress 0.0.0.0/0** on 443/8443 unless you tighten `proxy_client_cidr_ipv4`.
- **Subnet/VPC/AMI** defaults match your account at apply time (see `terraform/variables.tf`).
- **squid-openssl** 6.14 on Ubuntu 24.04 (not GnuTLS `squid` package) for full TLS chain on 443.
- **Repository delivery** to the instance is manual via SSM (method not prescribed).

## Approval gate

Do **not** run `terraform apply`, certbot, DNS changes, or deploy scripts against production until you explicitly approve billable/mutating operations.
