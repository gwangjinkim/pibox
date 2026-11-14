#!/usr/bin/env bash
# Install pibox and, with permission, its prerequisites one at a time.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="${PIBOX_BIN_DIR:-$HOME/.local/bin}"
target="$bin_dir/pibox"
cfg_dir="${PIBOX_CONFIG_DIR:-$HOME/.config/pibox}"

usage() {
  cat <<EOF
usage: ./install.sh [--check] [--help]

  (no option)  install pibox and check/install prerequisites
  --check      report missing prerequisites and exact commands, install nothing
  --help       show this message

exit codes:
  0  everything present (or installed)
  1  prerequisites missing or an install failed
  2  invalid option
EOF
}

check_only=0
case "${1:-}" in
  --check) check_only=1 ;;
  --help|-h) usage; exit 0 ;;
  "") ;;
  *) usage >&2; exit 2 ;;
esac

if [ "$check_only" == 0 ]; then
  mkdir -p "$bin_dir"
  install -m 0755 "$here/pibox" "$target"
ln -sf pibox "$bin_dir/pisbx"

  mkdir -p "$cfg_dir"
  if [ -f "$cfg_dir/install.json" ] && command -v jq >/dev/null 2>&1; then
    prev="$(jq -r '.repo // empty' "$cfg_dir/install.json" 2>/dev/null || true)"
    if [ -n "$prev" ] && [ "$prev" != "$here" ]; then
      printf 'note:      update will now track %s\n' "$here"
      printf '           (previously %s)\n' "$prev"
    fi
  fi
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg repo "$here" --arg version "$("$here/pibox" version)" \
       --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '{repo:$repo, version:$version, installed_at:$at}' >"$cfg_dir/install.json"
    chmod 600 "$cfg_dir/install.json"
    printf 'repo:      %s\n' "$here"
  fi
  printf 'installed: %s\n\n' "$target"
fi

# ---------------------------------------------------------------- platform
have() { command -v "$1" >/dev/null 2>&1; }

WSL=0
grep -qi microsoft /proc/version 2>/dev/null && WSL=1

detect_os() {
  case "$(uname -s)" in
    Darwin) echo macos ;;
    Linux)
      if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        echo "${ID:-linux}"
      else
        echo linux
      fi ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *) echo unknown ;;
  esac
}
OS="$(detect_os)"

detect_pm() {
  if [ "$OS" = macos ]; then have brew && { echo brew; return; }; fi
  for pm in apt-get dnf pacman zypper apk yum; do
    have "$pm" && { echo "$pm"; return; }
  done
  echo none
}
PM="$(detect_pm)"

pm_cmd() {
  case "$PM" in
    brew) echo "brew install $*" ;;
    apt-get) echo "sudo apt-get update && sudo apt-get install -y $*" ;;
    dnf|yum) echo "sudo dnf install -y $*" ;;
    pacman) echo "sudo pacman -S --needed --noconfirm $*" ;;
    zypper) echo "sudo zypper install -y $*" ;;
    apk) echo "sudo apk add $*" ;;
    *) echo "" ;;
  esac
}

pkg_names() {
  case "$1" in
    python3) [ "$PM" = brew ] && echo python || echo python3 ;;
    node) [ "$PM" = brew ] && echo node || echo "nodejs npm" ;;
    *) echo "$1" ;;
  esac
}

status() { printf '  %-5s %s\n' "$1" "$2"; }

# ---------------------------------------------------------------- detection
ORDER=(jq python3 openssl git node skey pi docker)
MISSING=()
DOCKER_BIN=0
LIMA_BIN=0
DOCKER_DOWN=0
SANDBOX_OK=0

detect() {
  MISSING=(); DOCKER_BIN=0; LIMA_BIN=0; DOCKER_DOWN=0; SANDBOX_OK=0
  for dep in "${ORDER[@]}"; do
    case "$dep" in
      docker) ;;
      *) have "$dep" || MISSING+=("$dep") ;;
    esac
  done
  have docker && DOCKER_BIN=1
  have limactl && LIMA_BIN=1
  if [ "$DOCKER_BIN" == 0 ] && [ "$LIMA_BIN" == 0 ]; then MISSING+=("docker"); fi
  if [ "$DOCKER_BIN" == 1 ] && ! docker info >/dev/null 2>&1; then DOCKER_DOWN=1; fi
  local sandbox_pi="${PIBOX_SANDBOX_PI:-$HOME/.pi/agent/npm/node_modules/.bin/pi}"
  if [ -x "$sandbox_pi" ] && "$sandbox_pi" --help 2>&1 | grep -q -- '--remote <url>'; then
    SANDBOX_OK=1
  fi
}

dep_present() {
  case "$1" in
    docker) have docker || have limactl ;;
    *) have "$1" ;;
  esac
}

dep_title() {
  case "$1" in
    jq) echo "jq (JSON parsing)" ;;
    python3) echo "python3 (helper + TOML parsing)" ;;
    openssl) echo "openssl (daemon token)" ;;
    git) echo "git (update + git workspace)" ;;
    node) echo "node + npm (pi runtime)" ;;
    skey) echo "skey (OS keyring vault)" ;;
    pi) echo "pi (agent CLI)" ;;
    docker) echo "docker or lima (sandbox runtime)" ;;
    *) echo "$1" ;;
  esac
}

dep_cmd() {
  case "$1" in
    jq|python3|openssl|git|node) pm_cmd "$(pkg_names "$1")" ;;
    skey)
      if have cargo; then echo "cargo install skey"
      elif have go; then echo "go install github.com/gwangjinkim/skey/skey-go@latest"
      else echo ""; fi ;;
    pi)
      if have npm; then echo "npm install -g @earendil-works/pi-coding-agent"
      else echo ""; fi ;;
    docker)
      case "$OS" in
        macos) if have brew; then echo "brew install --cask docker"; else echo ""; fi ;;
        ubuntu|debian|pop|linuxmint)
          echo "sudo apt-get update && sudo apt-get install -y docker.io && sudo usermod -aG docker \"$USER\" && (sudo systemctl enable --now docker || sudo service docker start)" ;;
        fedora|rhel|centos) echo "sudo dnf install -y docker && sudo systemctl enable --now docker" ;;
        arch|manjaro) echo "sudo pacman -S --needed --noconfirm docker && sudo systemctl enable --now docker" ;;
        alpine) echo "sudo apk add docker && sudo rc-update add docker default && sudo service docker start" ;;
        opensuse*|suse) echo "sudo zypper install -y docker && sudo systemctl enable --now docker" ;;
        *) echo "" ;;
      esac ;;
    *) echo "" ;;
  esac
}

dep_hint() {
  case "$1" in
    jq|python3|openssl|git|node)
      local pkgs cmd; pkgs="$(pkg_names "$1")"; cmd="$(pm_cmd "$pkgs")"
      if [ -n "$cmd" ]; then
        printf '  install with:\n    %s\n' "$cmd"
      else
        if [ "$OS" = macos ]; then
          printf '  no package manager found (Homebrew is not installed)\n'
          printf '  install Homebrew first:\n'
          printf '    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"\n'
          printf '  then re-run: ./install.sh\n'
        elif [ "$OS" = windows ] && [ "$WSL" = 0 ]; then
          printf '  use WSL2:\n    wsl --install -d Ubuntu\n  then run this installer inside Ubuntu\n'
        else
          printf '  install %s with your distribution package manager\n' "$pkgs"
        fi
      fi
      if [ "$1" = node ]; then
        printf '    verify: node --version && npm --version\n'
      fi ;;
    skey)
      if have cargo; then
        printf '    cargo install skey\n'
      elif have go; then
        printf '    go install github.com/gwangjinkim/skey/skey-go@latest\n'
      else
        printf '    install Rust:  curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh\n'
        printf '    then:          cargo install skey\n'
        printf '    or Go:         https://go.dev/dl/ then go install github.com/gwangjinkim/skey/skey-go@latest\n'
      fi
      printf '    verify: skey --help\n' ;;
    pi)
      if have npm; then
        printf '    npm install -g @earendil-works/pi-coding-agent\n'
      else
        printf '    install node/npm first (see above), then:\n'
        printf '    npm install -g @earendil-works/pi-coding-agent\n'
      fi
      printf '    verify: pi --version\n' ;;
    docker)
      case "$OS" in
        macos)
          printf '    option A (smallest): brew install colima docker && colima start\n'
          printf '    option B: Docker Desktop  https://docs.docker.com/desktop/install/mac-install/\n'
          printf '    option C: brew install lima   (VM runtime)\n' ;;
        windows)
          printf '    install Docker Desktop with the WSL2 backend:\n'
          printf '      https://docs.docker.com/desktop/install/windows-install/\n'
          printf '    run pibox inside WSL2, not Git Bash\n' ;;
        *)
          case "$PM" in
            apt-get) printf '    sudo apt-get install -y docker.io\n    sudo usermod -aG docker "$USER"\n    sudo systemctl enable --now docker   # or: sudo service docker start\n' ;;
            dnf|yum) printf '    sudo dnf install -y docker && sudo systemctl enable --now docker\n' ;;
            pacman) printf '    sudo pacman -S --needed docker && sudo systemctl enable --now docker\n' ;;
            zypper) printf '    sudo zypper install -y docker && sudo systemctl enable --now docker\n' ;;
            apk) printf '    sudo apk add docker && sudo rc-update add docker default && sudo service docker start\n' ;;
            *) printf '    install Docker Engine: https://docs.docker.com/engine/install/\n' ;;
          esac
          printf '    log out and back in after adding your user to the docker group\n' ;;
      esac
      printf '    verify: docker info\n' ;;
  esac
}

detect

printf 'prerequisites (%s%s):\n\n' "$OS" "$( [ "$WSL" == 1 ] && echo ', WSL' )"
for dep in "${ORDER[@]}"; do
  if dep_present "$dep"; then status ok "$dep"; else status MISS "$dep"; fi
done
[ "$DOCKER_DOWN" == 1 ] && status warn "docker daemon not reachable"
[ "$SANDBOX_OK" == 1 ] && status opt "sandbox pi (--remote, only for --mode remote)"
have pnpm && status ok "pnpm (fast sync)" || status opt "pnpm (faster sync)"
printf '\n'

if [ "$check_only" == 1 ]; then
  if [ "${#MISSING[@]}" -eq 0 ]; then
    printf 'all prerequisites present\n'
    exit 0
  fi
  printf 'missing prerequisites:\n\n'
  for dep in "${ORDER[@]}"; do
    dep_present "$dep" && continue
    printf '%s\n' "$(dep_title "$dep")"
    dep_hint "$dep"
    printf '\n'
  done
  exit 1
fi

if [ "${#MISSING[@]}" -eq 0 ]; then
  if [ "$DOCKER_DOWN" == 1 ]; then
    printf 'warning: docker is installed but the daemon is not reachable\n'
    case "$OS" in
      macos) printf '  start Docker Desktop (or: colima start) before pibox bootstrap\n\n' ;;
      *) printf '  start it with: sudo systemctl start docker\n\n' ;;
    esac
  fi
  if [[ ":$PATH:" != *":$bin_dir:"* ]]; then
    printf 'add this to your shell profile:\n  export PATH="%s:$PATH"\n\n' "$bin_dir"
  fi
  printf 'next:\n'
  printf '  pibox bootstrap          # build the sandbox images (required once)\n'
  printf '  pibox init --dry-run     # see which providers would be registered\n'
  printf '  pibox init               # register them in the OS keyring\n'
  printf '  pibox doctor             # verify dependencies, keys, permissions\n\n'
  printf '  cd ~/code/my-project\n'
  printf '  pibox run --model provider/model\n\n'
  printf '  pibox update --check     # later: check for a newer commit\n'
  printf '  pibox update             # pull, reinstall, rebuild images\n\n'
  printf 'docs: https://github.com/gwangjinkim/pibox/tree/main/docs\n'
  exit 0
fi

# ---------------------------------------------------------------- one by one
printf 'missing prerequisites:\n\n'
for dep in "${ORDER[@]}"; do
  dep_present "$dep" && continue
  printf '  %s\n' "$(dep_title "$dep")"
done
printf '\n'

ask_yes() {
  local a
  printf '  %s [Y/n] ' "$1"
  read -r a
  case "$a" in n|N|no|NO) return 1 ;; *) return 0 ;; esac
}

run_cmd() {
  printf '  > %s\n' "$1"
  bash -c "$1"
}

choose_skey() {
  if have cargo; then echo "cargo install skey"; return; fi
  if have go; then echo "go install github.com/gwangjinkim/skey/skey-go@latest"; return; fi
  printf '  options:\n' >&2
  printf '    1) install Rust (rustup), then cargo install skey\n' >&2
  printf '    2) install with Go (requires go)\n' >&2
  printf '    3) skip\n' >&2
  printf '  choose [1-3]: ' >&2
  local c; read -r c
  case "$c" in
    1|"") echo 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && . "$HOME/.cargo/env" && cargo install skey' ;;
    2) echo 'go install github.com/gwangjinkim/skey/skey-go@latest' ;;
    *) echo "" ;;
  esac
}

choose_docker() {
  case "$OS" in
    macos)
      if have brew; then
        printf '  options:\n' >&2
        printf '    1) colima (recommended)  brew install colima docker && colima start\n' >&2
        printf '    2) Docker Desktop        brew install --cask docker\n' >&2
        printf '    3) lima (VM)             brew install lima\n' >&2
        printf '    4) skip\n' >&2
        printf '  choose [1-4]: ' >&2
        local c; read -r c
        case "$c" in
          1|"") echo "brew install colima docker && colima start" ;;
          2) echo "brew install --cask docker" ;;
          3) echo "brew install lima" ;;
          *) echo "" ;;
        esac
      else
        echo ""
      fi ;;
    *) dep_cmd docker ;;
  esac
}

# ---------------------------------------------------------------- non-interactive
if ! [ -t 0 ] || ! [ -t 1 ]; then
  printf 'non-interactive shell: printing the manual steps instead.\n\n'
  for dep in "${ORDER[@]}"; do
    dep_present "$dep" && continue
    printf '%s\n' "$(dep_title "$dep")"
    dep_hint "$dep"
    printf '\n'
  done
  printf 'then run: pibox doctor\n'
  exit 1
fi

# ---------------------------------------------------------------- Homebrew first
if [ "$OS" = macos ] && [ "$PM" = none ]; then
  printf 'Homebrew is not installed, which blocks automatic installs.\n'
  if ask_yes "Install Homebrew now?"; then
    run_cmd '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' || true
    [ -x /opt/homebrew/bin/brew ] && export PATH="/opt/homebrew/bin:$PATH"
    [ -x /usr/local/bin/brew ] && export PATH="/usr/local/bin:$PATH"
    PM="$(detect_pm)"
  fi
  printf '\n'
fi

# ---------------------------------------------------------------- one by one
i=0
total=0
for dep in "${ORDER[@]}"; do dep_present "$dep" || total=$((total+1)); done

for dep in "${ORDER[@]}"; do
  dep_present "$dep" && continue
  i=$((i+1))
  printf '[%d/%d] %s is missing.\n' "$i" "$total" "$(dep_title "$dep")"

  case "$dep" in
    skey)   cmd="$(choose_skey)" ;;
    docker) cmd="$(choose_docker)" ;;
    *)      cmd="$(dep_cmd "$dep" || true)" ;;
  esac

  if [ -z "$cmd" ]; then
    printf '  no automatic option on this platform.\n'
    dep_hint "$dep"
    printf '\n'
    continue
  fi

  printf '  command:\n    %s\n' "$cmd"
  if ask_yes "Run it now?"; then
    if run_cmd "$cmd" && dep_present "$dep"; then
      printf '  installed.\n'
    else
      printf '  that did not work.\n'
      dep_hint "$dep"
    fi
  else
    printf '  skipped. run later:\n    %s\n' "$cmd"
  fi
  printf '\n'
done

detect
if [ "${#MISSING[@]}" -gt 0 ]; then
  printf 'still missing:\n\n'
  for dep in "${ORDER[@]}"; do
    dep_present "$dep" && continue
    printf '%s\n' "$(dep_title "$dep")"
    dep_hint "$dep"
    printf '\n'
  done
  printf 'then run: pibox doctor\n'
  exit 1
fi

if [ "$DOCKER_DOWN" == 1 ]; then
  printf 'warning: docker is installed but the daemon is not reachable\n'
  case "$OS" in
    macos) printf '  start Docker Desktop (or: colima start) before pibox bootstrap\n\n' ;;
    *) printf '  start it with: sudo systemctl start docker\n\n' ;;
  esac
fi

printf 'all prerequisites are installed.\n\n'
if [[ ":$PATH:" != *":$bin_dir:"* ]]; then
  printf 'add this to your shell profile:\n  export PATH="%s:$PATH"\n\n' "$bin_dir"
fi
printf 'next: pibox bootstrap && pibox init && pibox doctor\n'
exit 0
