#!/usr/bin/env bash
# Validate a PEM fullchain file (no secret output). Source from deploy/certbot scripts.
validate_fullchain_pem() {
  local pem_file="$1"
  local min_certs="${2:-1}"

  if [[ ! -f "$pem_file" ]]; then
    echo "Missing certificate file: $pem_file" >&2
    return 1
  fi
  local count
  count=$(grep -c 'BEGIN CERTIFICATE' "$pem_file" || true)
  if [[ "$count" -lt "$min_certs" ]]; then
    echo "Expected at least $min_certs certificate(s) in $pem_file, found $count" >&2
    return 1
  fi
  openssl x509 -in "$pem_file" -noout -subject >/dev/null
  return 0
}

# When installing from Let's Encrypt live directory, require leaf + intermediate(s).
validate_le_fullchain_pem() {
  local pem_file="$1"
  validate_fullchain_pem "$pem_file" 2
}
