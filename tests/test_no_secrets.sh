#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FAIL=0

# Patterns that should not appear in tracked templates (examples OK in .example files).
PATTERNS=(
  'dns_cloudflare_api_token\s*=\s*[^<]'
  'AKIA[0-9A-Z]{16}'
  'BEGIN (RSA |EC )?PRIVATE KEY'
  'proxy_password\s*=\s*["\x27][^"\x27]+'
)

while IFS= read -r -d '' f; do
  case "$f" in
    *.example|*/test_*|*/tests/*) continue ;;
  esac
  for p in "${PATTERNS[@]}"; do
    if grep -qE "$p" "$f" 2>/dev/null; then
      echo "FAIL: suspicious pattern in $f"
      FAIL=1
    fi
  done
done < <(find . -type f \( -name '*.tf' -o -name '*.sh' -o -name '*.conf' -o -name '*.pac' -o -name '*.md' -o -name '*.yaml' -o -name '*.tpl' \) ! -path './.git/*' -print0)

# Scripts that mutate secrets should be root-only in docs; check deploy scripts are not world-writable.
for s in scripts/*.sh; do
  [[ -f "$s" ]] || continue
  if [[ -x "$s" ]] && [[ "$(stat -c '%a' "$s")" == "777" ]]; then
    echo "FAIL: unsafe permissions on $s"
    FAIL=1
  fi
done

if [[ "$FAIL" -eq 0 ]]; then
  echo "PASS: no obvious secrets in repository templates"
fi
exit "$FAIL"
