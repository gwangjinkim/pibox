#!/usr/bin/env bash
# Smoke tests that never read a secret and never start a container.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bin="$here/pisbx"
fail=0

check() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf 'ok   %s\n' "$name"
  else
    printf 'FAIL %s\n' "$name"; fail=1
  fi
}

check "syntax"            bash -n "$bin"
check "version"           "$bin" version
check "help"              "$bin" help
check "help mentions run" bash -c "'$bin' help | grep -q 'pisbx run'"
check "dry-run needs model to fail" bash -c "! '$bin' run --dry-run 2>/dev/null"
check "no literal key patterns in tracked files" bash -c "
  ! grep -rIE 'sk-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|oc_sk_[A-Za-z0-9]{10,}' \
      '$here' --exclude-dir=.git --exclude='*.md' --exclude='*.backup.*'
"

exit "$fail"
