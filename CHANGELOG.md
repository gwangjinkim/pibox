# Changelog

## 1.2.0

- **`pibox models [provider] [--providers]`:** list models from the local pi
  catalog, grouped by provider, with model counts and key status.
- **`pibox pick`:** interactive provider -> filter -> model picker. Prints only
  `provider/model` on stdout.
- **`pibox run` without `--model`:** opens the picker in a terminal;
  non-interactive runs still require `--model`.

## 1.1.0

- **Host folder attachments:** `pibox attach add|list|remove` persists mounts in
  `.pibox/attach`; `pibox run --attach host[:target][:ro|rw]` adds one for a
  single run. Default target `/attached/<name>`, default read-only.
- **`/shared`:** `~/.pibox/share` is always mounted read-write, so files can be
  dropped into a running session without restarting it.
- **`pibox repair`:** fixes `pibox-home` volume ownership after a `--root`
  session; also runs automatically after root sessions.
- **Fix:** container/lima sessions now mount at
  `/home/node/.pi/agent/sessions` (previously the wrong path without a project
  environment).
- **`docs/safety.md`:** recovery boundaries, running containers, session
  persistence, volume ownership, and attachments.

## 1.0.2

- Session picker lists up to nine previous sessions with timestamp, size and id.
  `[Enter]` resumes the latest, `1-9` resumes a specific session by id, `n` starts
  fresh, `q` quits.
- The session picker now appears immediately after the mode/extension preflight,
  before migration.
- Fixed a crash in the picker caused by splitting the mtime/path list incorrectly.

## 1.0.1

- **Fix preflight option 1:** choosing "migrate this project, then continue in
  container mode" now runs `pibox migrate` and continues the same run. It
  previously exited silently.
- `q` prints `aborted.`; dry runs show what option 1 would do without changing
  anything.

## 1.0.0

- Renamed to `pibox`; `pisbx` shim, `PISBX_*` compatibility, config migration.
- Composable images: `pibox bootstrap --with python,node,go,rust,build,cli`.
- `docs/combinations.md` with measured sizes.
- Image sizes: none 155 MB, cli 188 MB, python 260 MB, node 311 MB,
  build 363 MB, go 373 MB, rust 996 MB, node+rust+build 1.20 GB, all ~1.6 GB.

## 0.9.0

- Composable `--with` features and aliases (`py`, `js`, `ts`, `rs`, `cc`,
  `tools`, `all`), image tags encoding the selection, config persistence.
- Verified C + Rust + TypeScript (`FRIEND_RUST_C_TS_OK`).

## 0.8.0

- Go (`go`, `gopls`, `delve`) and Rust (`cargo`, `rustfmt`, `clippy`,
  `rust-analyzer`) in `--dev`; caches under the agent home.
- Verified `go run` and `rustc` (`GO_RUST_OK`).

## 0.7.1

- `--dev`: python3/pip/uv, node/npm/pnpm/yarn, typescript/tsx, gcc/make, and
  Rust CLI tools (rg, fd, bat, eza, sd, dust, procs, btm, delta, hyperfine,
  tokei, hexyl, zoxide, just).
- Verified TypeScript, Python (`uv`), C (`DEV_ALL_OK`).

## 0.7.0

- New `--dev` Alpine variant with a full development toolchain.

## 0.6.1

- `--root` for runtime `apk add` in container mode.
- `/home/node/.pi/AGENTS.md` environment notes in images.
- `bootstrap` always rebuilds.

## 0.6.0

- `bootstrap --minimal`: Alpine + Bun-compiled single binary (~155 MB).

## Installer

- `install.sh` now detects the OS and package manager, lists missing
  prerequisites, and offers to install them after one confirmation.
- Missing dependencies are attempted **one at a time, in dependency order**
  (base tools → node → skey → pi → runtime). Each one shows the command, asks
  `[Y/n]`, and runs it immediately. Docker on macOS offers a runtime menu
  (Desktop / colima / lima). If an automatic install fails, the exact manual
  steps for that dependency are printed and the installer continues.
- If Homebrew is missing on macOS, it offers to install it first.
- Per-OS commands: Homebrew (macOS), apt/dnf/pacman/zypper/apk (Linux), WSL
  guidance (Windows).
- `skey` is installed via `cargo install skey` or `go install`.
- `node` and `pi` are checked; the sandbox `pi` build is reported separately.
- If automation fails or is unavailable, a numbered step-by-step guide is printed
  (base tools, skey, pi, container runtime, verification).
- `./install.sh --check` reports the plan and per-dependency instructions without
  installing anything (exit 0 if complete, 1 if not). `--help` prints usage.
- `--check` does not touch `~/.local/bin` or the install metadata.
- Docker daemon reachability is checked and warned about.

## 0.5.2

- **Fix: container and lima modes now mount the project environment.** The
  environment was detected and reported but never added to `docker run`, so
  sandboxed container sessions had no extensions installed. Container/lima now
  mount `.pibox/env` at `/home/node/.pi/agent`, the pnpm store under
  `/home/node/.cache/pibox/pnpm-store`, and sessions inside the mounted env.
- Verified in a migrated project: `pi list` inside the container shows all 8
  packages under `/home/node/.pi/agent/npm/...` with no extension load errors.

## 0.5.1

- **Auto mode fix:** a project with `pibox.toml` now selects `container`, so
  `@earendil-works` extensions load from the project environment (verified).
- **Remote preflight:** when remote would use the `@fleetagent` build while
  global extensions target `@earendil-works`, `pibox` stops with three options
  instead of emitting extension load errors.
- **`--no-extensions`:** run the sandbox without loading extensions.
- Verified: `mode=container` with a migrated environment loads all 8 extensions;
  `remote --no-extensions` runs clean.

## 0.5.0

- **`pibox recover [--fix]`:** diagnoses leftover state after a crash
  (containers, stale temp agent dirs, worktrees, incomplete environment) and
  applies safe cleanup.
- **`pibox clean`:** targeted cleanup with `--containers`, `--tmp`, `--work`,
  `--env`, `--all`, `--force`. Running containers are only removed with
  `--force`.
- **`pibox sessions list|resume|export`:** inspect, resume by id/latest, and
  export sessions to HTML.
- Containers are labelled `pibox=1` so cleanup can never touch unrelated ones.
- Session folders use the physical path, fixing `/tmp` vs `/private/tmp`.

## 0.4.0

- **`--workspace git`:** isolates the agent in a git worktree built from a
  snapshot of the dirty tree, copies untracked non-ignored files, excludes
  `.gitignore` entries such as `.env`, and commits results to `pibox/<session>`
  on exit. The live tree is never modified.
- **`pibox work list|clean`** manages worktrees under `.pibox/work/`; they are
  kept after exit, including crashes.
- `[workspace] mode = "mount"|"git"` in `pibox.toml`.
- `mount` remains the default.

## 0.3.2

- **`migrate` adopts the whole setup:** every extension with its exact version,
  interface files (`settings.json`, `mcp.json`, `AGENTS.md`, `SYSTEM.md`,
  `models-store.json`, `extensions/`, `skills/`, `rules/`, `prompt-templates/`,
  `themes/`, `statusline/`), and all `auth.json` entries. Writes
  `pibox.toml`/`pibox.lock` and builds `.pibox/env`.
- **pnpm-backed environments:** `sync` writes an exact `package.json`, suppresses
  peer auto-install and lifecycle scripts, installs from a shared store, and
  copies `pnpm-lock.yaml` to `pibox.pnpm-lock.yaml`.
- **Relocatable environments:** interface files are copied into `env/base/` and
  linked relatively, so the environment keeps working when bind-mounted into a
  container or VM.
- Measured: cold sync ~8.5s, warm sync ~0.65s, in-box startup ~0.6s with zero
  install.

## 0.2.1

- **Config preservation:** the ephemeral agent directory now symlinks the real
  `settings.json`, `extensions/`, `npm/`, `statusline/`, themes, and sessions, so
  extensions and UI settings survive. Only `auth.json` is replaced.
- **New `--mode native`:** runs your installed `pi` with your full config and no
  sandbox. The key still comes from the keyring via an ephemeral `auth.json`.
- **Fidelity warning:** remote mode warns when `settings.json` declares packages,
  because the sandbox `pi` build cannot load extensions that import
  `@earendil-works/*`.
- `PIBOX_PI` selects the binary used by native mode.

## 0.2.0

- **Sessions:** when the working folder already has sessions, `pibox run` asks
  whether to continue the most recent one or start fresh. Skip with
  `--session-mode continue|new` or `PIBOX_SESSION_MODE`.
- **Session sharing:** `container` and `lima` modes now mount the host session
  directory at `/home/node/.pi/sessions`, so `-c` finds the same history.
- **Updating:** `pibox update` (alias `upgrade`) pulls the clone recorded at
  install time, refreshes `~/.local/bin/pibox`, and rebuilds the images.
  `--check` reports without changing anything; `--no-bootstrap` keeps images;
  `--force` allows a dirty checkout.
- **Install metadata:** `install.sh` writes `~/.config/pibox/install.json`
  (clone path, version, timestamp) with mode `600`.
- **Docs:** added `docs/quickstart.md`, `docs/commands.md`,
  `docs/troubleshooting.md`, `docs/design.md`, and a quick start at the top of the
  README.

## 0.1.0

- Initial launcher: provider → environment variable resolution, OS keyring via
  `skey`, `remote`/`container`/`lima` runtimes, `init`, `migrate`, `bootstrap`,
  `doctor`, `vm`.
