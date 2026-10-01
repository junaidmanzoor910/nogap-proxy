# Cost estimate (us-east-1)

All figures are **approximate** and depend on usage, pricing changes, and tax. Not a quote.

| Component | Assumption | Estimated monthly |
|-----------|------------|-------------------|
| EC2 `t3.small` | On-demand, 730 h/mo | ~USD 15–17 |
| EBS gp3 20 GiB | Root volume | ~USD 1.60–2 |
| Elastic IP | Attached to running instance | USD 0 incremental |
| Elastic IP | **Unattached** (avoid) | ~USD 3.60 |
| Public IPv4 | Account-level public IPv4 charge may apply per AWS policy | check current pricing |
| Data transfer out | Per GB via proxy to `app-dev.nogap.ai` / CloudFront | **variable** |
| CloudWatch Logs | Optional SSM/session or proxy logs | variable (per GB ingested) |
| S3 | Optional session log bucket | storage + requests |
| NAT Gateway | **Not used** in this design | USD 0 |
| VPC interface endpoints | Optional for SSM without public internet | ~USD 7–10+ per endpoint / AZ |

## Egress security group note

The template allows **0.0.0.0/0** egress so the instance can reach Systems Manager, DNS resolvers, Ubuntu mirrors, Cloudflare API for ACME, and HTTPS origins. Security groups **cannot** restrict egress by domain; Squid enforces destination host policy for **proxy clients**, not for the instance’s own outbound traffic.

### Practical least-privilege egress (optional hardening)

1. Add **VPC interface endpoints** for `ssm`, `ssmmessages`, `ec2messages` and restrict egress to those + resolver + NTP + Cloudflare API IP ranges (high maintenance).
2. Keep broad egress but rely on Squid ACL + no listening admin ports except 443/8443.

## IPv6

Default Terraform sets `enable_ipv6_ingress = false`. Cloud-init disables IPv6 on the instance to avoid unintended **AAAA** exposure. Enabling IPv6 requires explicit AAAA DNS and SG rules.
