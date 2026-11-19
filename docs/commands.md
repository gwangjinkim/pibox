# Command reference

`pibox` has one job: map a model to a credential, then run `pi` in a bounded
runtime. Everything here follows from that.

```
pibox <command> [options]
```

---

## `pibox init [--dry-run] [--register]`

Reads `~/.pi/agent/auth.json` (or `$PI_CODING_AGENT_DIR/auth.json`) and registers
every `api_key` provider in the OS keyring through `skey`.

| Option | Effect |
|---|---|
| `--dry-run` | print the plan, touch nothing |
| `--register` | register missing providers without asking again |

Classification:

| Entry | Action |
|---|---|
| literal secret | prompt to store in keyring |
| `"$ENV_VAR"` | keep; register the provider |
| `"!command"` | report as dead (`skey get` is interactive-only) |
| OAuth | skip; use `pi /login` |

---

## `pibox migrate [--dry-run] [--register] [--no-sync] [--keep-auth]`

Adopts the global pi setup into the current project.

Inventory:

- all extensions from `settings.json` with exact versions
- interface files: `settings.json`, `mcp.json`, `AGENTS.md`, `SYSTEM.md`,
  `models-store.json`, `extensions/`, `skills/`, `rules/`, `prompt-templates/`,
  `themes/`, `statusline/`
- all `auth.json` entries, classified

Output: `pibox.toml`, `pibox.lock`, `.pibox/env`.

| Option | Effect |
|---|---|
| `--dry-run` | print the inventory only |
| `--register` | register missing providers in the keyring |
| `--no-sync` | skip building `.pibox/env` |
| `--keep-auth` | leave `auth.json` untouched |

`auth.json` is backed up before rewriting; rollback is printed.

## `pibox export [--global]`

Snapshot package versions into `pibox.toml` and `pibox.lock`. By default it reads
the project environment if one exists, otherwise the global agent directory.

## `pibox sync`

Recreate `.pibox/env` from the manifest and lock using pnpm:

- writes `npm/package.json` with exact versions
- writes `.npmrc` with `auto-install-peers=false`, `strict-peer-dependencies=false`,
  `ignore-scripts=true`
- installs from `~/.cache/pibox/pnpm-store`
- copies the resulting `pnpm-lock.yaml` to `pibox.pnpm-lock.yaml` for transitive
  reproducibility

## `pibox add` / `pibox remove`

```bash
pibox add pi-effort                 # shorthand for npm:pi-effort
pibox add @scope/pkg@1.2.3
pibox remove npm:pi-effort
```

`add` resolves the current version when omitted, updates the lock, rewrites the
manifest, and re-syncs the environment.

---

## `pibox bootstrap [--with LIST | --minimal | --dev | --standard] [--runtime docker|container]`

Builds both images. Features can be combined. `--runtime container` builds into
Apple's container storage instead of Docker (macOS 26+).

| Feature | Aliases | Adds |
|---|---|---|
| python | py, uv | python3, pip, venv, uv |
| node | js, ts, typescript | node, npm, pnpm, yarn, typescript, tsx |
| go | golang | go, gopls, delve |
| rust | rs | rust, cargo, rustfmt, clippy, rust-analyzer |
| build | cc, c, gcc | gcc, g++, make |
| cli | tools | bat, eza, sd, dust, procs, btm, delta, hyperfine, tokei, hexyl, zoxide, just |

```bash
pibox bootstrap --with node,rust,build
pibox bootstrap --minimal        # none
pibox bootstrap --dev            # all
pibox bootstrap --standard       # Debian
```

Image names include the selection, e.g. `pibox-full-dev-js-rs-cc`. The choice is
stored as `defaults.variant=alpine`, `defaults.features`, `defaults.image`, and
`defaults.image_full`; `PIBOX_IMAGE` / `PIBOX_IMAGE_FULL` override the tags.

## `pibox doctor`

Prints:

- versions of `pi`, `docker`, `limactl`
- the Lima VM state
- keyring entries (names and variants, never values)
- `auth.json` permissions
- warnings for plaintext keys, dead `!command` references, loose permissions

Exit code is non-zero when a security check fails, so it is usable in CI.

---

## `pibox update [--check] [--no-bootstrap] [--force]`

| Option | Effect |
|---|---|
| `--check` | fetch and report whether a newer commit exists |
| `--no-bootstrap` | pull and reinstall, keep existing images |
| `--force` | allow updating a checkout with local changes |

Steps:

1. read the clone path from `~/.config/pibox/install.json` (override with `PIBOX_REPO`)
2. `git fetch`, then `git pull --ff-only`
3. run `install.sh` to refresh `~/.local/bin/pibox`
4. run `pibox bootstrap` unless `--no-bootstrap`

`upgrade` is an alias.

---

## `pibox run --model <provider>/<model> [options] [-- <pi args>]`

| Option | Default | Meaning |
|---|---|---|
| `--model P/M` | required | the prefix `P` selects the credential |
| `--runtime docker\|container\|lima` | `docker` | where tools execute (`container` = Apple's CLI, macOS 26+, whole-container mode only; remote mode stays Docker-only) |
| `--mode auto\|remote\|container\|native` | `auto` | remote = orchestrate on host, tools in container; native = your own `pi`, no sandbox |
| `--session-mode ask\|continue\|new` | `ask` | what to do when the folder already has sessions |
| `--workspace mount\|git` | `mount` | live bind mount, or an isolated git worktree |
| `--dry-run` | off | print the plan; do not read a secret or start anything |
| `--force` | off | allow mounting `$HOME` or `/` as the workspace |
| `--no-extensions` | off | pass `--no-extensions` to pi |
| `--root` | off | run the container as root (container mode only) so tools can install packages |
| `--attach host[:target][:ro\|rw]` | — | mount an extra host folder (repeatable) |
| `--pick-model` | off | choose provider/model interactively |

### Mode selection

`--mode auto` (default):

- if the project has `pibox.toml` → `container` (project environment is mounted)
- otherwise `remote` when the sandbox `pi` supports `--remote`
- otherwise `container`

If remote is selected but your global `settings.json` lists packages that import
`@earendil-works/*`, `pibox` refuses to start and prints three options:

1. run `pibox migrate` for this project, then continue in container mode
2. `--mode native` (no sandbox, exact setup)
3. `--no-extensions` (sandboxed, extensions off)

Option 1 is executed automatically: it writes `pibox.toml`/`pibox.lock`, builds
`.pibox/env`, then continues the same run in container mode. This replaces a wall of extension
load errors.

### Model resolution

```
--model opencode-go/muse-spark-1.3-contributor
        │            │
        │            └── passed to pi
        └── provider → OPENCODE_API_KEY → keyring variant
```

If the folder has sessions and you did not pass a session flag, `pibox` lists the
latest up to nine and asks:

```
  [1] 2026-11-14 08:11   11K  01a1db17-14d8
  [2] 2026-11-14 08:02   9.8K 01a1d91c-f0da
  [Enter] latest   [1-2] choose   [n] new   [q] quit
```

A number resumes that session with `--session <id>`; Enter continues the latest.

`--session-mode` skips the prompt:

- `continue` → adds `-c`
- `new` → starts fresh
- `ask` → prompt (default)

The prompt is suppressed automatically for non-TTY input and when any of
`-c`, `--continue`, `--session`, `--resume`, `--fork`, `--no-session`, or
`--session-dir` is already present.

### Extension fidelity

The agent directory is preserved in `remote` and `native` modes: settings,
extensions, packages, themes, statusline, and sessions are symlinked into an
ephemeral directory that carries only an ephemeral `auth.json`.

`remote` still needs a `pi` build with `--remote`. Extensions that import
`@earendil-works/pi-tui` cannot load under the `@fleetagent` sandbox build, so the
TUI can differ. Use `--mode native` when you need the exact setup.

### Passthrough

Everything unrecognized, and everything after `--`, goes to `pi`:

```bash
pibox run --model opencode-go/muse-spark-1.3-contributor -p "explain this repo"
pibox run --model anthropic/claude-sonnet-4 -- -c
```

---

## `pibox recover [--fix]`

Diagnoses state left behind by a crash:

- running and stopped `pibox-*` containers (labelled `pibox=1`)
- stale temp agent dirs older than 10 minutes (`.pibox.*` under `$TMPDIR` and `/tmp`)
- git worktrees under `.pibox/work/`
- an incomplete environment (lock lists extensions, `env/npm` missing)
- session count for the current folder

`--fix` applies safe cleanup:

- removes **stopped** containers; running ones are kept with a warning
  (`pibox clean --force` is the only command that stops running containers)
- removes stale temp dirs (overwrites `auth.json` before deleting)
- removes clean worktrees (branches are never deleted)
- rebuilds an incomplete environment

## `pibox clean [--containers] [--tmp] [--work] [--env] [--all] [--force]`

Targeted cleanup. Default: stopped containers + stale temp dirs.

| Flag | Effect |
|---|---|
| `--containers` | remove stopped `pibox` containers |
| `--tmp` | remove stale temp agent dirs |
| `--work` | prune clean git worktrees |
| `--env` | delete `.pibox/env` (rebuild with `pibox sync`) |
| `--force` | include running containers |
| `--all` | all of the above except removing running containers |

## `pibox backup [create [name]|list|restore NAME|clean NAME]`

Snapshot machine-local state into `~/.pibox/backups/<stamp>[-name]/`
(`PIBOX_BACKUP_DIR` overrides): pibox config, agent dir without sessions,
`auth.json`, or `npm/` (rebuilt by `sync`), the project manifest+lock, a
doctor snapshot, and provider names. The keyring is never touched, so no
secrets are ever written to a backup.

- `create [name]` snapshots the present (default name: the timestamp)
- `list` shows name, size, date, and project root per backup
- `restore NAME` snapshots the present first (rollback safety net), then
  restores config, agent dir, and — if run where the backup's project lives —
  the manifest; ends by telling you how to undo it
- `clean NAME` removes one backup

After restoring: `pibox sync`, `pibox doctor`, then re-register your own keys
(`pi` login, then `pibox init --register`).

## `pibox sessions list|resume|export`

```bash
pibox sessions list
pibox sessions resume latest --model opencode-go/muse-spark-1.3-contributor
pibox sessions resume 01a1db17 --model provider/model -- -p "continue"
pibox sessions export latest out.html
```

- `list` shows timestamp, size, and session id for this folder
- `resume` restarts pi with `--session <path>`; `--model` defaults to
  `defaultProvider/defaultModel` from `settings.json`
- `export` uses `pi --export` to produce a standalone HTML file

Session folders are computed from the **physical** working directory, so `/tmp`
and `/private/tmp` resolve to the same session directory.

## `pibox work list|clean`

- `list` shows worktrees under `.pibox/work/` and their change count
- `clean` removes worktrees with no changes; worktrees with uncommitted changes are
  kept

## Git workspace mode

`--workspace git` (or `[workspace] mode = "git"` in `pibox.toml`):

1. `git stash create` snapshots tracked dirty changes (no stash entry is added)
2. `git worktree add --detach .pibox/work/<session> <snapshot>`
3. untracked **non-ignored** files are copied; `.gitignore` excludes `.env`
4. a baseline commit is made so copied files are not reported as agent edits
5. on exit, changes are committed to branch `pibox/<session>`

The live tree is never modified. Review with
`git diff <base>..pibox/<session>`, merge with `git merge`, remove with
`git worktree remove`.

Requirements: a git repository with at least one commit. Add `.pibox/` to
`.gitignore`.

## `pibox vm status|start|stop|delete|shell`

Manages the Lima instance used by `--runtime lima`.

```bash
pibox vm status
pibox vm start
pibox vm shell -- uname -a
```

If the VM does not exist:

```bash
limactl start --name=pibox --tty=false template:docker-rootful
```

---

## `pibox help` / `pibox version`

---

## Environment variables

| Variable | Meaning |
|---|---|
| `PIBOX_CONFIG_DIR` | config, generated Dockerfiles, `install.json` |
| `PIBOX_VARIANT` | `standard` or `minimal` (image variant) |
| `PIBOX_IMAGE` | sandbox image tag (default `pibox-sandbox`) |
| `PIBOX_IMAGE_FULL` | whole-container image tag (default `pibox-full`) |
| `PIBOX_SANDBOX_PI` | host `pi` binary that supports `--remote` |
| `PIBOX_PI` | `pi` binary used by `--mode native` (default: `pi`) |
| `PIBOX_LIMA_NAME` | Lima instance name (default `pibox`) |
| `PIBOX_SESSION_MODE` | default for `--session-mode` |
| `PIBOX_NO_EXTENSIONS=1` | pass `--no-extensions` in remote mode |
| `PIBOX_REPO` | override the clone path used by `update` |
| `PIBOX_PNPM_STORE` | pnpm store (default `~/.cache/pibox/pnpm-store`) |
| `PIBOX_OFFLINE=1` | install only from the store |
| `PIBOX_FROZEN=1` | require `pnpm-lock.yaml` to be current |
| `PI_SESSION_DIR` | override where sessions are discovered |
| `PI_CODING_AGENT_DIR` | pi agent directory (read-only discovery) |

---

## Files

| Path | Contents |
|---|---|
| `~/.config/pibox/config.json` | provider → variant → env var (no secrets) |
| `~/.config/pibox/install.json` | clone path + install timestamp |
| `~/.config/pibox/docker/*.Dockerfile` | generated image recipes |
| `~/.pi/agent/sessions/--<cwd>--/*.jsonl` | session history used for the prompt |
| OS keyring, service `skey` | the secrets themselves |

---

## Exit codes

| Code | Meaning |
|---|---|
| `0` | success |
| `1` | general failure (missing dependency, missing credential, docker error) |
| `4` | requested runtime is unavailable (e.g. Lima VM absent/stopped) |
