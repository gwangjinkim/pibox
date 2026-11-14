#!/usr/bin/env bash
# Install pisbx into ~/.local/bin (or $PISBX_BIN_DIR).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="${PISBX_BIN_DIR:-$HOME/.local/bin}"
target="$bin_dir/pisbx"

mkdir -p "$bin_dir"
install -m 0755 "$here/pisbx" "$target"

cfg_dir="${PISBX_CONFIG_DIR:-$HOME/.config/pisbx}"
mkdir -p "$cfg_dir"
if [ -f "$cfg_dir/install.json" ] && command -v jq >/dev/null 2>&1; then
  prev="$(jq -r '.repo // empty' "$cfg_dir/install.json" 2>/dev/null || true)"
  if [ -n "$prev" ] && [ "$prev" != "$here" ]; then
    printf 'note:      update will now track %s\n' "$here"
    printf '           (previously %s)\n' "$prev"
  fi
fi
if command -v jq >/dev/null 2>&1; then
  jq -n --arg repo "$here" --arg version "$("$here/pisbx" version)" \
     --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '{repo:$repo, version:$version, installed_at:$at}' >"$cfg_dir/install.json"
  chmod 600 "$cfg_dir/install.json"
  printf 'repo:      %s\n' "$here"
fi

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

cat <<'NEXT'

next:
  pisbx bootstrap          # build the sandbox images (required once)
  pisbx init --dry-run     # see which providers would be registered
  pisbx init               # register them in the OS keyring
  pisbx doctor             # verify dependencies, keys, permissions

  cd ~/code/my-project
  pisbx run --model provider/model

  pisbx update --check     # later: check for a newer commit
  pisbx update             # pull, reinstall, rebuild images

docs: https://github.com/gwangjinkim/pisbx/tree/main/docs
NEXT

