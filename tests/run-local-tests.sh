#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FAIL=0

run_suite() {
  local name="$1"
  shift
  echo "== ${name} =="
  if "$@"; then
    echo "RESULT: ${name} PASS"
  else
    echo "RESULT: ${name} FAIL"
    FAIL=1
  fi
}

run_suite "PAC matching" python3 tests/test_pac_matching.py -v
run_suite "Workstation PAC" python3 tests/test_workstation_pac.py -v
run_suite "Squid ACL static checks" python3 tests/test_squid_acl.py -v
run_suite "Secret scan" bash tests/test_no_secrets.sh
run_suite "OpenVPN disguised architecture" bash tests/test_openvpn_disguise.sh

if command -v docker >/dev/null 2>&1; then
  run_suite "Containerized Squid/Nginx validation" bash tests/validate-services-docker.sh
  run_suite "squid-openssl TLS chain (Docker)" bash tests/validate-squid-openssl-chain-docker.sh
else
  echo "SKIP: docker not installed — containerized squid/nginx validation not run"
fi

if command -v terraform >/dev/null 2>&1; then
  run_suite "Terraform validate" bash -ec 'cd terraform && terraform init -backend=false -input=false >/dev/null && terraform validate'
elif command -v docker >/dev/null 2>&1; then
  run_suite "Terraform validate (Docker)" bash -ec \
    "docker run --rm -v \"${ROOT}:/repo\" -w /repo/terraform hashicorp/terraform:1.9.8 init -backend=false -input=false >/dev/null && docker run --rm -v \"${ROOT}:/repo\" -w /repo/terraform hashicorp/terraform:1.9.8 validate"
else
  echo "SKIP: terraform and docker unavailable"
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "Local test run finished with failures"
  exit 1
fi
echo "Local test run complete."
