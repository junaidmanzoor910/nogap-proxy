# Pre-deployment checklist

Complete **before** `terraform apply` or any billable AWS/DNS/ACME action.

## Approvals and policy

- [ ] Explicit written approval to create EC2, EIP, security group, and IAM role in **us-east-1** (`--profile dev`).
- [ ] Confirm **10** named users (usernames only) for provisioning; passwords generated at provision time, never committed.
- [ ] Confirm ingress **0.0.0.0/0** on TCP **443** and **8443** is acceptable, or update `proxy_client_cidr_ipv4` in Terraform.
- [ ] Confirm **no SSH** (SSM-only administration).

## DNS (Cloudflare — operator action, not automated here)

- [ ] Create **DNS-only (grey cloud)** `A` record: `proxy-dev.nogap.ai` → Terraform output `elastic_ip`.
- [ ] Do **not** orange-cloud proxy this hostname (see [CLOUDFLARE-DNS.md](CLOUDFLARE-DNS.md)).
- [ ] Do **not** change `app-dev.nogap.ai`.

## TLS (after DNS propagates)

- [ ] Create scoped Cloudflare API token (DNS edit for `nogap.ai` zone or single-record scope).
- [ ] Store token on instance at `/root/.secrets/cloudflare.ini` mode **0600** (see [CLOUDFLARE-DNS.md](CLOUDFLARE-DNS.md)).
- [ ] Run certbot DNS-01 **only after** approval; enable `certbot.timer` and deploy hook ([CERTBOT-RENEWAL.md](CERTBOT-RENEWAL.md)).

## Terraform

- [ ] Install Terraform **>= 1.5** locally.
- [ ] Copy `terraform/terraform.tfvars.example` → `terraform/terraform.tfvars` (no secrets).
- [ ] Choose state backend (local or encrypted S3); understand state may contain sensitive metadata.
- [ ] Run `terraform init` and `terraform plan` (review only until approved).

## Repository on instance

- [ ] Plan to copy this repo to `/opt/nogap-split-proxy` via SSM (S3 sync, git clone over HTTPS, or Session Manager port forwarding) — method is operator choice.

## Unresolved assumptions (confirm if different)

- Default VPC public subnet `subnet-0e1846394e4fca539` remains available.
- Verify AMI `ubuntu_ami_id` is **available**, **x86_64**, Ubuntu 24.04 in **us-east-1** before apply (`lifecycle.ignore_changes` on AMI can hide stale pins).
- Changing user-data **replaces** the instance (`user_data_replace_on_change = true`).
- Run `./tests/run-local-tests.sh` (Docker validates Squid **6.14** / Nginx on Ubuntu 24.04).
- Browser `PROXY` vs `HTTPS` PAC for TLS `https_port` is **not** universally verified — see [CLIENT-SETUP.md](CLIENT-SETUP.md).
