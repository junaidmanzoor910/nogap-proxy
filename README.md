# nogap-split-proxy

Reproducible **AWS EC2** deployment for an **authenticated HTTPS forward proxy** (Squid) with PAC on Nginx (**8443**). Default: **full-machine egress** via proxy (HTTPS CONNECT to any host on **443**). Administration via **SSM Session Manager** — **no SSH**.

**Status:** Project artifacts only. **No AWS resources, DNS, or certificates have been created by this repository run.**

## Architecture

```
Browser/system proxy → HTTPS proxy-dev.nogap.ai:443 (TLS) → Squid → Internet (egress via Elastic IP)
localhost / .local   → DIRECT (destination only — local inbound unchanged)
PAC URL       → https://proxy-dev.nogap.ai:8443/proxy.pac (Nginx TLS, not CONNECT proxy)
Workstation   → `./run-nogap-local-proxy.sh` (interactive); details → [docs/NOGAP-LOCAL-EC2-EGRESS.md](docs/NOGAP-LOCAL-EC2-EGRESS.md)
Admin         → AWS SSM StartSession (no TCP 22)
```

Squid enforces allowlists even if clients edit PAC. No TLS interception; no client root CA.

## Prerequisites

- AWS CLI profile **`dev`**, region **`us-east-1`** (pass `--region us-east-1` even if profile region unset).
- Terraform **>= 1.5** (not required for local tests).
- Cloudflare DNS control for **`proxy-dev.nogap.ai`** (grey cloud **A** → Elastic IP).
- Operator IAM for `ssm:StartSession` (see [docs/SSM-ADMIN.md](docs/SSM-ADMIN.md)).

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
