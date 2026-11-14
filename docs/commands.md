# Command reference

`pisbx` has one job: map a model to a credential, then run `pi` in a bounded
runtime. Everything here follows from that.

```
pisbx <command> [options]
```

---

## `pisbx init [--dry-run] [--register]`

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

## `pisbx migrate [--dry-run]`

Backs up `auth.json` to `auth.json.backup.<timestamp>` (mode `600`) and rewrites it:

- removes plaintext secrets
- removes `!command` references that cannot succeed
- keeps `$ENV_VAR` references and OAuth entries

Always preview:

```bash
pisbx migrate --dry-run
```

Rollback is printed at the end.

---

## `pisbx bootstrap`

Writes `~/.config/pisbx/docker/Dockerfile` and `Dockerfile.sandbox`, then builds
`pisbx-full` and `pisbx-sandbox`.

Must be run:

- after `install.sh`
- after `pisbx update` (unless you pass `--no-bootstrap`)

---

## `pisbx doctor`

Prints:

- versions of `pi`, `docker`, `limactl`
- the Lima VM state
- keyring entries (names and variants, never values)
- `auth.json` permissions
- warnings for plaintext keys, dead `!command` references, loose permissions

Exit code is non-zero when a security check fails, so it is usable in CI.

---

## `pisbx update [--check] [--no-bootstrap] [--force]`

| Option | Effect |
|---|---|
| `--check` | fetch and report whether a newer commit exists |
| `--no-bootstrap` | pull and reinstall, keep existing images |
| `--force` | allow updating a checkout with local changes |

Steps:

1. read the clone path from `~/.config/pisbx/install.json` (override with `PISBX_REPO`)
2. `git fetch`, then `git pull --ff-only`
3. run `install.sh` to refresh `~/.local/bin/pisbx`
4. run `pisbx bootstrap` unless `--no-bootstrap`

`upgrade` is an alias.

---

## `pisbx run --model <provider>/<model> [options] [-- <pi args>]`

| Option | Default | Meaning |
|---|---|---|
| `--model P/M` | required | the prefix `P` selects the credential |
| `--runtime docker\|lima` | `docker` | where tools execute |
| `--mode auto\|remote\|container\|native` | `auto` | remote = orchestrate on host, tools in container; native = your own `pi`, no sandbox |
| `--session-mode ask\|continue\|new` | `ask` | what to do when the folder already has sessions |
| `--dry-run` | off | print the plan; do not read a secret or start anything |
| `--force` | off | allow mounting `$HOME` or `/` as the workspace |

### Model resolution

```
--model opencode-go/muse-spark-1.3-contributor
        │            │
        │            └── passed to pi
        └── provider → OPENCODE_API_KEY → keyring variant
```

If the folder has sessions and you did not pass a session flag, `pisbx` asks:

```
[Enter] continue last   [n] new session   [q] quit
```

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
pisbx run --model opencode-go/muse-spark-1.3-contributor -p "explain this repo"
pisbx run --model anthropic/claude-sonnet-4 -- -c
```

---

## `pisbx vm status|start|stop|delete|shell`

Manages the Lima instance used by `--runtime lima`.

```bash
pisbx vm status
pisbx vm start
pisbx vm shell -- uname -a
```

If the VM does not exist:

```bash
limactl start --name=pisbx --tty=false template:docker-rootful
```

---

## `pisbx help` / `pisbx version`

---

## Environment variables

| Variable | Meaning |
|---|---|
| `PISBX_CONFIG_DIR` | config, generated Dockerfiles, `install.json` |
| `PISBX_IMAGE` | sandbox image tag (default `pisbx-sandbox`) |
| `PISBX_IMAGE_FULL` | whole-container image tag (default `pisbx-full`) |
| `PISBX_SANDBOX_PI` | host `pi` binary that supports `--remote` |
| `PISBX_PI` | `pi` binary used by `--mode native` (default: `pi`) |
| `PISBX_LIMA_NAME` | Lima instance name (default `pisbx`) |
| `PISBX_SESSION_MODE` | default for `--session-mode` |
| `PISBX_NO_EXTENSIONS=1` | pass `--no-extensions` in remote mode |
| `PISBX_REPO` | override the clone path used by `update` |
| `PI_SESSION_DIR` | override where sessions are discovered |
| `PI_CODING_AGENT_DIR` | pi agent directory (read-only discovery) |

---

## Files

| Path | Contents |
|---|---|
| `~/.config/pisbx/config.json` | provider → variant → env var (no secrets) |
| `~/.config/pisbx/install.json` | clone path + install timestamp |
| `~/.config/pisbx/docker/*.Dockerfile` | generated image recipes |
| `~/.pi/agent/sessions/--<cwd>--/*.jsonl` | session history used for the prompt |
| OS keyring, service `skey` | the secrets themselves |

---

## Exit codes

| Code | Meaning |
|---|---|
| `0` | success |
| `1` | general failure (missing dependency, missing credential, docker error) |
| `4` | requested runtime is unavailable (e.g. Lima VM absent/stopped) |
