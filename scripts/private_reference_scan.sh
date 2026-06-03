#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if command -v rg >/dev/null 2>&1; then
  search=(rg --hidden --line-number --no-heading --color never)
  excludes=(
    --glob '!.git/**'
    --glob '!.build/**'
    --glob '!DerivedData/**'
    --glob '!benchmark-results/**'
    --glob '!scripts/private_reference_scan.sh'
    --glob '!**/*.pyc'
  )
else
  echo "private reference scan requires ripgrep (rg)" >&2
  exit 2
fi

failures=0

scan_literal() {
  local label="$1"
  local literal="$2"
  local output
  if output="$("${search[@]}" "${excludes[@]}" --fixed-strings "$literal" .)"; then
    echo "Private reference match: $label" >&2
    echo "$output" >&2
    failures=1
  fi
}

scan_regex() {
  local label="$1"
  local regex="$2"
  local output
  if output="$("${search[@]}" "${excludes[@]}" --pcre2 "$regex" .)"; then
    echo "Private reference match: $label" >&2
    echo "$output" >&2
    failures=1
  fi
}

scan_literal "private LAN IP" "10.0.0.22"
scan_literal "private Tailnet suffix" "tail0d9204"
scan_literal "private device name" "glados"
scan_literal "private user path" "/Users/matti"
scan_literal "private user path" "/Users/wayne"
scan_regex "concrete Tailscale IP" '\b100\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b'
scan_regex "committed bearer token" 'Bearer[[:space:]]+[A-Za-z0-9._~+/-]{16,}'
scan_regex "committed auth token value" 'WHISKER_AUTH_TOKEN=["'\'']?(?!<long-random-token>)(?!change-me)(?!your-token)[A-Za-z0-9._~+/-]{16,}'

if [[ "$failures" -ne 0 ]]; then
  exit 1
fi

echo "No private Whisker references found."
