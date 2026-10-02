#!/usr/bin/env bash
# scripts/fetch-client-ovpn.sh
# Fetches the self-contained client.ovpn profile from the EC2 instance via AWS SSM.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_FILE="${ROOT}/config/client.ovpn"

INSTANCE_ID="${EC2_PROXY_INSTANCE_ID:-i-0a38b5d00fc34ff1f}"
REGION="${AWS_REGION:-ap-south-1}"
PROFILE="${AWS_PROFILE:-stagging}"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red() { printf '\033[31m%s\033[0m\n' "$*"; }

bold "==> Fetching OpenVPN client profile from EC2 (${INSTANCE_ID})..."

# Try retrieving via AWS SSM RunShellScript
if command -v aws >/dev/null 2>&1; then
  echo "Executing SSM command to read /opt/nogap-openvpn/client.ovpn..."
  CMD_ID=$(aws ssm send-command \
    --profile "${PROFILE}" \
    --region "${REGION}" \
    --instance-ids "${INSTANCE_ID}" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["cat /opt/nogap-openvpn/client.ovpn"]' \
    --query "Command.CommandId" \
    --output text 2>/dev/null || true)

  if [[ -n "$CMD_ID" && "$CMD_ID" != "None" ]]; then
    echo "Waiting for command execution (ID: ${CMD_ID})..."
    for ((i=0; i<15; i++)); do
      STATUS=$(aws ssm get-command-invocation \
        --profile "${PROFILE}" \
        --region "${REGION}" \
        --command-id "${CMD_ID}" \
        --instance-id "${INSTANCE_ID}" \
        --query "Status" \
        --output text 2>/dev/null || echo "Pending")

      if [[ "$STATUS" == "Success" ]]; then
        aws ssm get-command-invocation \
          --profile "${PROFILE}" \
          --region "${REGION}" \
          --command-id "${CMD_ID}" \
          --instance-id "${INSTANCE_ID}" \
          --query "StandardOutputContent" \
          --output text > "$TARGET_FILE"
        chmod 600 "$TARGET_FILE"
        green "✓ Successfully fetched client profile to: ${TARGET_FILE}"
        exit 0
      elif [[ "$STATUS" == "Failed" || "$STATUS" == "Cancelled" ]]; then
        break
      fi
      sleep 2
    done
  fi
fi

yellow "Could not fetch automatically via AWS CLI (credentials may need refresh or instance is initializing)."
echo ""
echo "To fetch manually via SSM Session Manager:"
echo "1. Connect: aws ssm start-session --profile ${PROFILE} --region ${REGION} --target ${INSTANCE_ID}"
echo "2. Run on EC2: cat /opt/nogap-openvpn/client.ovpn"
echo "3. Copy the output and save to: ${TARGET_FILE}"
echo ""
