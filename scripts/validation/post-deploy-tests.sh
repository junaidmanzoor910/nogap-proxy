#!/usr/bin/env bash
# Post-deployment checks — run from operator workstation after explicit approval and deploy.
# Requires: curl, openssl, aws cli (profile dev, region us-east-1). Does not print credentials.
set -euo pipefail

PROXY_HOST="${PROXY_HOST:-proxy-dev.nogap.ai}"
PAC_PORT="${PAC_PORT:-8443}"
PROXY_PORT="${PROXY_PORT:-443}"
APP_HOST="${APP_HOST:-app-dev.nogap.ai}"
AWS_PROFILE="${AWS_PROFILE:-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"
INSTANCE_ID="${INSTANCE_ID:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROXY_HOST PAC_PORT PROXY_PORT APP_HOST
export PROXY_USER="${PROXY_USER:-}" PROXY_PASS="${PROXY_PASS:-}"
bash "${SCRIPT_DIR}/tls-chain-tests.sh"

echo "=== PAC fetch ==="
curl -fsS "https://${PROXY_HOST}:${PAC_PORT}/proxy.pac" | head -5

if [[ -n "$INSTANCE_ID" ]]; then
  echo "=== SSM ping (dry) ==="
  aws ssm describe-instance-information --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --filters "Key=InstanceIds,Values=${INSTANCE_ID}" --query 'InstanceInformationList[0].PingStatus' --output text
fi

echo "Post-deploy script finished. Compare egress IP manually (PAC on vs DIRECT)."
