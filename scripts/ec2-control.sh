#!/usr/bin/env bash
# scripts/ec2-control.sh: Start, stop, or check status of the NoGap EC2 Squid proxy instance.
set -euo pipefail

INSTANCE_ID="${EC2_PROXY_INSTANCE_ID:-i-0a38b5d00fc34ff1f}"
REGION="${AWS_REGION:-ap-south-1}"
PROFILE="${AWS_PROFILE:-stagging}"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red() { printf '\033[31m%s\033[0m\n' "$*"; }

get_state() {
  aws ec2 describe-instances \
    --profile "${PROFILE}" \
    --region "${REGION}" \
    --instance-ids "${INSTANCE_ID}" \
    --query "Reservations[0].Instances[0].State.Name" \
    --output text 2>/dev/null || echo "unknown"
}

get_ip() {
  aws ec2 describe-instances \
    --profile "${PROFILE}" \
    --region "${REGION}" \
    --instance-ids "${INSTANCE_ID}" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text 2>/dev/null || echo "unknown"
}

action="${1:-status}"

case "$action" in
  start)
    current="$(get_state)"
    if [[ "$current" == "running" ]]; then
      green "✓ EC2 instance ${INSTANCE_ID} is already running."
      echo "Egress Elastic IP: $(get_ip)"
      exit 0
    fi

    bold "==> Starting EC2 Proxy instance (${INSTANCE_ID})..."
    aws ec2 start-instances \
      --profile "${PROFILE}" \
      --region "${REGION}" \
      --instance-ids "${INSTANCE_ID}" >/dev/null

    yellow "Waiting for instance to reach 'running' state..."
    aws ec2 wait instance-running \
      --profile "${PROFILE}" \
      --region "${REGION}" \
      --instance-ids "${INSTANCE_ID}"

    green "✓ EC2 instance is now running!"
    echo "Elastic IP: $(get_ip)"
    ;;

  stop)
    current="$(get_state)"
    if [[ "$current" == "stopped" ]]; then
      yellow "EC2 instance ${INSTANCE_ID} is already stopped."
      exit 0
    fi

    bold "==> Stopping EC2 Proxy instance (${INSTANCE_ID})..."
    aws ec2 stop-instances \
      --profile "${PROFILE}" \
      --region "${REGION}" \
      --instance-ids "${INSTANCE_ID}" >/dev/null

    yellow "Waiting for instance to stop..."
    aws ec2 wait instance-stopped \
      --profile "${PROFILE}" \
      --region "${REGION}" \
      --instance-ids "${INSTANCE_ID}"

    yellow "✓ EC2 instance is now stopped."
    echo "Note: Elastic IP $(get_ip) remains preserved."
    ;;

  restart)
    "$0" stop
    "$0" start
    ;;

  status|state)
    state="$(get_state)"
    ip="$(get_ip)"
    case "$state" in
      running)
        green "EC2 Instance: ${INSTANCE_ID} is RUNNING"
        echo "Elastic IP: ${ip} (${REGION})"
        ;;
      stopped)
        yellow "EC2 Instance: ${INSTANCE_ID} is STOPPED"
        echo "Preserved Elastic IP: ${ip}"
        ;;
      pending|stopping)
        yellow "EC2 Instance: ${INSTANCE_ID} is in transition (${state})"
        ;;
      *)
        red "EC2 Instance: ${INSTANCE_ID} state is ${state}"
        ;;
    esac
    ;;

  json)
    state="$(get_state)"
    ip="$(get_ip)"
    printf '{"instanceId":"%s","state":"%s","publicIp":"%s","region":"%s"}\n' \
      "${INSTANCE_ID}" "${state}" "${ip}" "${REGION}"
    ;;

  *)
    echo "Usage: $0 {start|stop|restart|status|json}"
    exit 1
    ;;
esac
