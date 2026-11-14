#!/usr/bin/env bash
# Install pisbx and, with permission, its prerequisites.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="${PISBX_BIN_DIR:-$HOME/.local/bin}"
target="$bin_dir/pisbx"
cfg_dir="${PISBX_CONFIG_DIR:-$HOME/.config/pisbx}"

check_only=0
[ "${1:-}" = "--check" ] && check_only=1

mkdir -p "$bin_dir"
install -m 0755 "$here/pisbx" "$target"

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

# ---------------------------------------------------------------- platform
have() { command -v "$1" >/dev/null 2>&1; }

WSL=0
if grep -qi microsoft /proc/version 2>/dev/null; then WSL=1; fi

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
  case "$OS" in
    macos) have brew && { echo brew; return; } ;;
    windows) have winget && { echo winget; return; } ;;
  esac
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
    winget) echo "winget install $*" ;;
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
MISSING=()
PLAN=()
NO_RUNTIME=0
SANDBOX_OK=0
DOCKER_BIN=0
LIMA_BIN=0

detect() {
  MISSING=(); PLAN=(); NO_RUNTIME=0; SANDBOX_OK=0; DOCKER_BIN=0; LIMA_BIN=0
  for cmd in jq python3 openssl git skey node pi; do
    have "$cmd" || MISSING+=("$cmd")
  done
  DOCKER_DOWN=0
  have docker && DOCKER_BIN=1
  if [ "$DOCKER_BIN" == 1 ] && ! docker info >/dev/null 2>&1; then DOCKER_DOWN=1; fi
  have limactl && LIMA_BIN=1
  if [ "$DOCKER_BIN" == 0 ] && [ "$LIMA_BIN" == 0 ]; then
    MISSING+=("docker"); NO_RUNTIME=1
  fi
  local sandbox_pi="${PISBX_SANDBOX_PI:-$HOME/.pi/agent/npm/node_modules/.bin/pi}"
  if [ -x "$sandbox_pi" ] && "$sandbox_pi" --help 2>&1 | grep -q -- '--remote <url>'; then
    SANDBOX_OK=1
  fi
}

detect

printf 'prerequisites (%s%s):\n\n' "$OS" "$( [ "$WSL" == 1 ] && echo ', WSL' )"
for cmd in bash jq python3 openssl git skey node pi; do
  have "$cmd" && status ok "$cmd" || status MISS "$cmd"
done
if [ "$DOCKER_BIN" == 1 ]; then status ok "docker"; elif [ "$LIMA_BIN" == 1 ]; then status ok "limactl (VM runtime)"; else status MISS "docker or limactl"; fi
[ "$SANDBOX_OK" == 1 ] && status ok "sandbox pi (--remote)" || status opt "sandbox pi (only for --mode remote)"
have pnpm && status ok "pnpm (fast sync)" || status opt "pnpm (faster sync)"
have limactl && status ok "limactl (VM runtime)" || status opt "limactl (VM runtime)"
printf '\n'

if [ "${#MISSING[@]}" -eq 0 ]; then
  if [ "${DOCKER_DOWN:-0}" == 1 ]; then
    printf 'warning: docker is installed but the daemon is not reachable\n'
    case "$OS" in
      macos) printf '  start Docker Desktop (or: colima start) before pisbx bootstrap\n\n' ;;
      *) printf '  start it with: sudo systemctl start docker\n\n' ;;
    esac
  fi
  if [[ ":$PATH:" != *":$bin_dir:"* ]]; then
    printf 'add this to your shell profile:\n  export PATH="%s:$PATH"\n\n' "$bin_dir"
  fi
  printf 'next:\n'
  printf '  pisbx bootstrap          # build the sandbox images (required once)\n'
  printf '  pisbx init --dry-run     # see which providers would be registered\n'
  printf '  pisbx init               # register them in the OS keyring\n'
  printf '  pisbx doctor             # verify dependencies, keys, permissions\n\n'
  printf '  cd ~/code/my-project\n'
  printf '  pisbx run --model provider/model\n\n'
  printf '  pisbx update --check     # later: check for a newer commit\n'
  printf '  pisbx update             # pull, reinstall, rebuild images\n\n'
  printf 'docs: https://github.com/gwangjinkim/pisbx/tree/main/docs\n'
  exit 0
fi

# ---------------------------------------------------------------- plan
plan_dep() {
  if [ "$OS" = windows ] && [ "$WSL" = 0 ]; then
    PLAN+=("$1|")
    return
  fi
  case "$1" in
    jq|python3|openssl|git)
      cmd="$(pm_cmd "$(pkg_names "$1")")"; PLAN+=("$1|$cmd") ;;
    node)
      cmd="$(pm_cmd "$(pkg_names node)")"; PLAN+=("node|$cmd") ;;
    pi)
      if have npm; then PLAN+=("pi|npm install -g @earendil-works/pi-coding-agent")
      else PLAN+=("pi|"); fi ;;
    skey)
      if have cargo; then PLAN+=("skey|cargo install skey")
      elif have go; then PLAN+=("skey|go install github.com/gwangjinkim/skey/skey-go@latest")
      else PLAN+=("skey|"); fi ;;
    docker)
      case "$OS" in
        macos)
          if have brew; then PLAN+=("docker|brew install --cask docker")
          else PLAN+=("docker|"); fi ;;
        ubuntu|debian|pop|linuxmint)
          PLAN+=("docker|sudo apt-get update && sudo apt-get install -y docker.io && sudo usermod -aG docker \"$USER\" && (sudo systemctl enable --now docker || sudo service docker start)") ;;
        fedora|rhel|centos)
          PLAN+=("docker|sudo dnf install -y docker && sudo systemctl enable --now docker") ;;
        arch|manjaro)
          PLAN+=("docker|sudo pacman -S --needed --noconfirm docker && sudo systemctl enable --now docker") ;;
        alpine)
          PLAN+=("docker|sudo apk add docker && sudo rc-update add docker default && sudo service docker start") ;;
        opensuse*|suse)
          PLAN+=("docker|sudo zypper install -y docker && sudo systemctl enable --now docker") ;;
        *) PLAN+=("docker|") ;;
      esac ;;
  esac
}

for dep in ${MISSING[@]+"${MISSING[@]}"}; do plan_dep "$dep"; done

# ---------------------------------------------------------------- manual guide
manual_guide() {
  local missing_list="$*"
  printf '\nmanual setup for %s%s\n' "$OS" "$( [ "$WSL" == 1 ] && echo ' (WSL)' )"
  printf 'missing: %s\n\n' "$missing_list"

  printf 'Step 1 - base tools (jq, python3, openssl, git, node)\n'
  case "$OS" in
    macos)
      if have brew; then
        printf '  brew install jq python git node openssl\n'
      else
        printf '  install Homebrew first:\n'
        printf '    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"\n'
        printf '  then re-run this installer\n'
      fi ;;
    windows)
      printf '  recommend WSL2 + Ubuntu:\n'
      printf '    wsl --install -d Ubuntu\n'
      printf '  then inside Ubuntu run the Debian steps below\n' ;;
    *)
      case "$PM" in
        apt-get) printf '  sudo apt-get update && sudo apt-get install -y jq python3 openssl git nodejs npm\n' ;;
        dnf|yum) printf '  sudo dnf install -y jq python3 openssl git nodejs npm\n' ;;
        pacman) printf '  sudo pacman -S --needed jq python openssl git nodejs npm\n' ;;
        zypper) printf '  sudo zypper install -y jq python3 openssl git nodejs npm\n' ;;
        apk) printf '  sudo apk add jq python3 openssl git nodejs npm\n' ;;
        *) printf '  use your distribution package manager for: jq python3 openssl git nodejs npm\n' ;;
      esac ;;
  esac
  printf '\n'

  printf 'Step 2 - skey (OS keyring vault)\n'
  if have cargo; then
    printf '  cargo install skey\n'
  elif have go; then
    printf '  go install github.com/gwangjinkim/skey/skey-go@latest\n'
  else
    printf '  install Rust: curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh\n'
    printf '  then:         cargo install skey\n'
    printf '  or install Go: https://go.dev/dl/  then: go install github.com/gwangjinkim/skey/skey-go@latest\n'
  fi
  printf '\n'

  printf 'Step 3 - pi\n'
  printf '  npm install -g @earendil-works/pi-coding-agent\n'
  printf '  sandbox build (only for --mode remote): export PISBX_SANDBOX_PI=/path/to/pi\n'
  printf '  verify: pi --help 2>&1 | grep -- "--remote <url>"\n'
  printf '\n'

  printf 'Step 4 - container runtime\n'
  case "$OS" in
    macos)
      printf '  option A: Docker Desktop  https://docs.docker.com/desktop/install/mac-install/\n'
      printf '  option B: brew install colima docker && colima start\n'
      printf '  option C: brew install lima   (VM runtime: --runtime lima)\n'
      printf '  start the engine before running pisbx\n' ;;
    windows)
      printf '  install Docker Desktop with the WSL2 backend:\n'
      printf '    https://docs.docker.com/desktop/install/windows-install/\n'
      printf '  run pisbx inside WSL2, not Git Bash\n' ;;
    *)
      case "$PM" in
        apt-get) printf '  sudo apt-get install -y docker.io\n  sudo usermod -aG docker "$USER"\n  sudo systemctl enable --now docker   # or: sudo service docker start\n' ;;
        dnf|yum) printf '  sudo dnf install -y docker && sudo systemctl enable --now docker\n' ;;
        pacman) printf '  sudo pacman -S --needed docker && sudo systemctl enable --now docker\n' ;;
        zypper) printf '  sudo zypper install -y docker && sudo systemctl enable --now docker\n' ;;
        apk) printf '  sudo apk add docker && sudo rc-update add docker default && sudo service docker start\n' ;;
        *) printf '  install Docker Engine: https://docs.docker.com/engine/install/\n' ;;
      esac
      printf '  log out and back in after adding your user to the docker group\n' ;;
  esac
  printf '\n'

  printf 'Step 5 - verify\n'
  printf '  pisbx doctor\n'
  printf '  pisbx bootstrap\n'
  printf '  pisbx init\n'
  printf '\n'
}

# ---------------------------------------------------------------- permission
if [ "$check_only" == 1 ]; then
  printf 'missing prerequisites:\n\n'
  for entry in ${PLAN[@]+"${PLAN[@]}"}; do
    label="${entry%%|*}"; cmd="${entry#*|}"
    if [ -n "$cmd" ]; then printf '  %-8s %s\n' "$label" "$cmd"; else printf '  %-8s (manual)\n' "$label"; fi
  done
  manual_guide "${MISSING[*]}"
  exit 1
fi

printf 'missing prerequisites:\n\n'
for entry in ${PLAN[@]+"${PLAN[@]}"}; do
  label="${entry%%|*}"; cmd="${entry#*|}"
  if [ -n "$cmd" ]; then printf '  %-8s %s\n' "$label" "$cmd"; else printf '  %-8s (manual)\n' "$label"; fi
done

answer="n"
if [ -t 0 ] && [ -t 1 ]; then
  printf '\ninstall them now? [y/N] '
  read -r answer
fi

if [[ "$answer" =~ ^[Yy]$ ]]; then
  failed=0
  for entry in ${PLAN[@]+"${PLAN[@]}"}; do
    label="${entry%%|*}"; cmd="${entry#*|}"
    if [ -z "$cmd" ]; then
      printf '\nno automatic command for %s\n' "$label"
      failed=1
      continue
    fi
    printf '\n> %s\n' "$cmd"
    if ! bash -c "$cmd"; then
      printf 'x failed: %s\n' "$label"
      failed=1
    fi
  done
  detect
  if [ "${#MISSING[@]}" -gt 0 ]; then
    manual_guide "${MISSING[*]}"
    exit 1
  fi
  printf '\nall prerequisites are installed.\n\n'
  if [[ ":$PATH:" != *":$bin_dir:"* ]]; then
    printf 'add this to your shell profile:\n  export PATH="%s:$PATH"\n\n' "$bin_dir"
  fi
  if [ "${DOCKER_DOWN:-0}" == 1 ]; then
    printf 'warning: the docker daemon is not reachable yet\n'
    case "$OS" in
      macos) printf '  start Docker Desktop (or: colima start) before pisbx bootstrap\n' ;;
      *) printf '  start it with: sudo systemctl start docker\n' ;;
    esac
  fi
  printf 'next: pisbx bootstrap && pisbx init && pisbx doctor\n'
  exit 0
fi

manual_guide "${MISSING[*]}"
exit 1
