#!/usr/bin/env bash
# Install pisbx into ~/.local/bin (or $PISBX_BIN_DIR).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="${PISBX_BIN_DIR:-$HOME/.local/bin}"
target="$bin_dir/pisbx"

mkdir -p "$bin_dir"
install -m 0755 "$here/pisbx" "$target"

printf 'installed: %s\n\n' "$target"

missing=0
for cmd in bash jq skey docker; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'missing: %s\n' "$cmd"
    missing=1
  fi
done
command -v limactl >/dev/null 2>&1 || printf 'optional: limactl (for --runtime lima)\n'

if [[ ":$PATH:" != *":$bin_dir:"* ]]; then
  printf '\nadd this to your shell profile:\n  export PATH="%s:$PATH"\n' "$bin_dir"
fi

if [[ "$missing" == 1 ]]; then
  printf '\ninstall the missing dependencies, then run: pisbx doctor\n'
  exit 0
fi

printf '\nnext:\n  pisbx init --dry-run   # see which providers would be registered\n  pisbx init             # register them in the OS keyring\n  pisbx doctor\n  pisbx bootstrap        # build the sandbox images\n'
