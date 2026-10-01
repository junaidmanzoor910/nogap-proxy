#!/usr/bin/env bash
# scripts/tail-ec2-logs.sh: View live access logs from the Mumbai EC2 proxy.
set -euo pipefail

INSTANCE_ID="${EC2_PROXY_INSTANCE_ID:-i-0a38b5d00fc34ff1f}"
REGION="${AWS_REGION:-ap-south-1}"
PROFILE="${AWS_PROFILE:-stagging}"

echo "Connecting to EC2 ${INSTANCE_ID} (${REGION}) live Squid access log..."
echo "Press Ctrl+C to stop."
echo "----------------------------------------------------------------------"

aws ssm start-session \
  --profile "${PROFILE}" \
  --region "${REGION}" \
  --target "${INSTANCE_ID}" \
  --document-name "AWS-StartInteractiveCommand" \
  --parameters 'command=["sudo tail -f /var/log/squid/access.log"]'
