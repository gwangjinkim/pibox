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

# every command must be discoverable from the short help
commands="$("$bin" help | awk '/^COMMANDS/{f=1;next} f&&/^  [a-z]/{print $1}' | sort -u)"
for c in init migrate bootstrap update doctor run vm version help; do
  if grep -qx "$c" <<<"$commands"; then
    printf 'ok   help lists %s\n' "$c"
  else
    printf 'FAIL help is missing %s\n' "$c"; fail=1
  fi
done

# aliases and alternate entry points
for inv in "--help" "-h" "help"; do
  check "help via $inv" bash -c "'$bin' $inv | grep -q '^COMMANDS'"
done
check "version" bash -c "'$bin' version | grep -Eq '^[0-9]+\.'"
check "help documents native mode" bash -c "'$bin' help | grep -q 'native'"

exit "$fail"
