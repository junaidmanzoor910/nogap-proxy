# Administration via AWS Systems Manager (no SSH)

## Instance requirements

- IAM instance profile with **AmazonSSMManagedInstanceCore** (see `terraform/main.tf`).
- **amazon-ssm-agent** installed and enabled (Ubuntu 24.04 AMI + cloud-init).
- Outbound **HTTPS (443)** to AWS endpoints and working DNS.
- **No** inbound TCP 22; **no** EC2 key pair.

## SSM connectivity (us-east-1)

Verify current AWS documentation for your partition. Typically the instance needs HTTPS to:

- `ssm.us-east-1.amazonaws.com`
- `ssmmessages.us-east-1.amazonaws.com`
- `ec2messages.us-east-1.amazonaws.com`

These resolve to **public** AWS endpoint IPs unless you configure **VPC interface endpoints**.

### Optional VPC endpoints (extra cost)

Interface endpoints for `com.amazonaws.us-east-1.ssm`, `ssmmessages`, and `ec2messages` let the instance reach SSM without internet egress to those services. You still need DNS resolution and likely egress for OS updates, ACME, and proxy traffic to application origins. See [COST.md](COST.md).

## Operator IAM (least privilege example)

Attach to humans/groups that administer this host:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:StartSession"
      ],
      "Resource": [
        "arn:aws:ec2:us-east-1:*:instance/*",
        "arn:aws:ssm:us-east-1:*:document/SSM-SessionManagerRunShell"
      ],
      "Condition": {
        "StringEquals": {
          "ssm:resourceTag/Project": "nogap-split-proxy"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:TerminateSession",
        "ssm:ResumeSession"
      ],
      "Resource": "arn:aws:ssm:us-east-1:*:session/${aws:userid}-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:DescribeInstanceInformation",
        "ec2:DescribeInstances"
      ],
      "Resource": "*"
    }
  ]
}
```

Tighten `Resource` ARNs to the specific instance ID after creation.

## Start a session

```bash
aws ssm start-session \
  --profile dev \
  --region us-east-1 \
  --target <instance-id>
```

Requires [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) on the workstation.

## Session logging (optional)

Enable SSM session logging to **CloudWatch Logs** or **S3** for audit. Consider:

- Sessions may expose commands; restrict log access.
- Additional ingestion/storage cost.
- Do not log proxy user passwords in session transcripts (avoid running `provision-user.sh` with passwords visible in command line — use interactive prompts).

## Deploying configuration without SSH

1. `terraform apply` (after approval).
2. `aws ssm start-session` to the instance.
3. Copy repository to `/opt/nogap-split-proxy` (e.g. `aws s3 sync` from a private bucket, or paste via secure internal process).
4. Run `scripts/bootstrap-host.sh`, issue TLS certs, `scripts/deploy-config.sh`, `scripts/provision-user.sh`.
