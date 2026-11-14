# pisbx

**Run `pi` with your API keys in the OS keyring and its tools inside a container or VM.**

You pick a model. `pisbx` works out which environment variable that provider needs,
pulls the secret from your OS keyring, and starts `pi` in a sandbox — without ever
putting a credential in your shell history, your repo, your Docker image, or the
agent's long-lived environment.

```console
$ pisbx run --model opencode-go/muse-spark-1.3-contributor
> provider=opencode-go variant=app00 env=OPENCODE_API_KEY runtime=docker mode=remote
> starting sandbox daemon on 127.0.0.1:52048
> tools run in the container; key is written to an ephemeral 0600 agent dir
```

No `export`. No `.env`. No key names to remember.

---

## Quick start

```bash
# 1. install
git clone https://github.com/gwangjinkim/pisbx.git
cd pisbx && ./install.sh

# 2. build the sandbox images once (required before the first run)
pisbx bootstrap

# 3. put a credential in the OS keyring (hidden prompt)
pisbx init                     # import providers from ~/.pi/agent/auth.json
# or directly:
skey set opencode-go app00

# 4. run from the project you want the agent to see
cd ~/code/my-project
pisbx run --model opencode-go/muse-spark-1.3-contributor

# 5. later, update the clone and rebuild the images
pisbx update
```

If the folder already has sessions, `pisbx` asks whether to continue the last one
or start fresh. Skip the prompt with `--session-mode continue` or `--session-mode new`.

First-run checklist:

| Check | Why |
|---|---|
| `pisbx doctor` | dependencies, Docker/Lima, keyring entries, file permissions |
| `pisbx bootstrap` | without it you get `image 'pisbx-sandbox' is missing` |
| `pisbx migrate --dry-run` | optional: strip plaintext keys from `auth.json` |

More: [Quick start](docs/quickstart.md) · [Command reference](docs/commands.md) ·
[Troubleshooting](docs/troubleshooting.md)

---

## Status

`pisbx` is a small, auditable launcher (one bash script). It is **not** a security
boundary by itself: read [Threat model](#threat-model) and
[Verified limitations](#verified-limitations) before relying on it for untrusted
code.

Requires: `bash`, `jq`, [`skey`](https://github.com/gwangjinkim/skey),
`docker` and/or `limactl`, and a `pi` build that supports `--remote`.

---

## Why pisbx?

### 1. An AI coding agent's environment *is* a credential store

A coding agent needs to read your repository, run shell commands, load extensions,
and start MCP servers. Every one of those children inherits the agent's process
environment. On Linux any process running as you can read another process's
environment from `/proc/<pid>/environ`; on macOS `ps eww` exposes it; on Windows
it is readable by anything in the same session.

So this is the normal, documented setup for most AI coding tools:

```bash
export ANTHROPIC_API_KEY=sk-ant-<your-key>  # now readable by every child process
pi
```

The key is not "in the tool". It is in the *environment*, which is a shared,
world-readable-to-your-user namespace that any dependency, extension, MCP server,
postinstall hook, or prompt-injected shell command can read.

`pisbx` changes the question from *"can this dependency read my key?"* (yes) to
*"is my key in this process at all?"* (no, until the moment of use).

### 2. The software supply chain actively harvests environment variables

This is not hypothetical. The dominant credential theft technique in the
JavaScript ecosystem is precisely "read `process.env`, read `.npmrc`, read dotfiles,
POST them somewhere".

| Incident | What it did | Source |
|---|---|---|
| **Shai-Hulud** (Sep 2025) | npm worm; ran `TruffleHog`, harvested **environment variables** and cloud IMDS keys, published stolen secrets to public GitHub repos, self-propagated using npm tokens found in the env | [Wiz](https://www.wiz.io/blog/shai-hulud-npm-supply-chain-attack) |
| **Shai-Hulud 2.0** (Nov 2025) | moved to `preinstall`, harvested `.npmrc`, GitHub PATs and **AWS/GCP/Azure keys from env vars**, 25,000+ malicious repos; fallback tried to destroy the home directory | [Unit 42](https://unit42.paloaltonetworks.com/npm-supply-chain-attack) |
| **s1ngularity / Nx** (Aug 2025) | malicious npm release ran a `postinstall` that scraped `process.env`, then **abused locally configured AI CLIs (Claude, Gemini) to find more files to steal** | [Nx postmortem](https://nx.dev/blog/s1ngularity-postmortem), [StepSecurity](https://www.stepsecurity.io/blog/supply-chain-security-alert-popular-nx-build-system-package-compromised-with-data-stealing-malware) |
| **GhostAction** (Sep 2025) | 3,325 secrets stolen from 817 repos via injected workflows | [GitGuardian](https://blog.gitguardian.com/ghostaction-campaign-3-325-secrets-stolen) |
| **Nx Console 18.95.0** (May 2026) | trojanized VS Code extension, live for 18 minutes, harvested Claude Code configs, 1Password, npm/GitHub/AWS credentials; read `/proc/*/mem` to catch secrets **loaded in memory** | [CSA](https://labs.cloudsecurityalliance.org/research/csa-research-note-vscode-extension-supply-chain-breach-20260) |
| **Malicious "AI" extensions** (Jan 2026) | two extensions with **1.5M installs** exfiltrated developer files and `.env` API keys to China-based servers | [BleepingComputer](https://www.bleepingcomputer.com/news/security/malicious-ai-extensions-on-vscode-marketplace-steal-developer-data/) |

The last two matter for a different reason: they attack the *editor and agent
tooling*, not the npm package. Installing an AI extension is installing code that
runs with your privileges and your environment.

### 3. Extensions do not have to be malicious to leak keys

A large-scale study of **27,261 VS Code extensions** found that **8.5% (2,325)**
improperly expose credential-related data through commands, user input, global
state, or configuration — all readable by any other installed extension:

> "An attacker, through a malicious extension, can easily retrieve this API key
> using `vscode.workspace.getConfiguration().get()`."
> — [Protect Your Secrets: Understanding and Measuring Data Exposure in VSCode Extensions (arXiv 2412.00707)](https://arxiv.org/html/2412.00707v2)

Wiz separately found **550+ validated secrets** sitting in plain sight across
500+ extensions in the VS Code and Open VSX marketplaces — the same marketplaces
used by Cursor, Windsurf and other VS Code forks — including **OpenAI, Gemini,
Anthropic, xAI and DeepSeek** API keys:

> [Supply Chain Risk in VSCode Extension Marketplaces — Wiz](https://www.wiz.io/blog/supply-chain-risk-in-vscode-extension-marketplaces)

And MCP made it worse: Wiz showed that Amazon Q auto-loaded and executed
`mcp.json` from a cloned repository **with full environment inheritance**, so
simply opening a malicious repo could exfiltrate AWS credentials and API keys
(CVE-2026-12957):

> "spawned processes inherited the developer's full environment … AWS credentials,
> API keys, SSH agent sockets."
> — [Wiz: Amazon Q vulnerability](https://www.wiz.io/blog/amazon-q-vulnerability)

If your agent's environment contains `OPENAI_API_KEY`, then the trust boundary of
that key is *every MCP server you have ever approved, every extension you have ever
installed, and every repository you have ever opened*. That is not a boundary.

### 4. The providers themselves leak keys

This is the part people skip. Even if your machine is clean, your key also lives on
the provider's infrastructure — and that infrastructure has failed in public.

In January 2025, Wiz Research found a **publicly reachable, unauthenticated
ClickHouse database belonging to DeepSeek**, containing over a million log entries
with **chat history, API secrets, backend details, and operational metadata**:

> "This database contained a significant volume of chat history, backend data and
> sensitive information, including log streams, **API Secrets**, and operational
> details."
> — [Wiz Research](https://www.wiz.io/blog/wiz-research-uncovers-exposed-deepseek-database-leak)

Corroborated by [WIRED](https://www.wired.com/story/exposed-deepseek-database-revealed-chat-prompts-and-internal-data)
("users' API authentication tokens") and [Reuters](https://www.reuters.com/technology/artificial-intelligence/sensitive-deepseek-data-exposed-web-israeli-cyber-firm-says-2025-01-29).

The lesson is not "DeepSeek bad" — the same class of accidental exposure has hit
many vendors. The lesson is: **your API key is a bearer token that is only as safe
as every log pipeline, analytics job, support tool, and database in the provider's
stack.** Minimising where it exists locally is one of the few levers you fully
control. Rotation is the other; scoped keys are the third.

### 5. Blast radius: agents delete things

Your credentials are not the only asset. A coding agent with a shell is a shell:

- **Replit / SaaStr (July 2025):** an agent ignored eleven freeze instructions and
  ran `db:push` against a database shared with production, deleting 1,206 executive
  records and 1,196 company profiles — then fabricated data and fake unit tests to
  cover it up.
  ([The Register](https://www.theregister.com/2025/07/21/replit_saastr_vibe_coding_incident))
- **Claude Code (Sep 2026):** mishandled Windows junctions and deleted ~48,000
  files plus a Git object database in just over 100 seconds.
  ([TechRadar](https://www.techradar.com/pro/security/i-broke-something-a-claude-code-ai-agent-deleted-48-000-files-in-just-over-100-seconds-then-apologized-for-doing-so))

Containers and VMs do not prevent bad decisions. They bound the consequences: the
agent sees one mount, not your whole home directory, and you can throw the
environment away.

**Sources are listed in full at the bottom.**

---

## What pisbx does

Four principles:

1. **The keyring is the only source of truth.** Secrets live in the OS keyring
   (via `skey`: macOS Keychain, Linux Secret Service, Windows Credential Manager).
   `pisbx` never prints them and never stores them in config.
2. **Never argv.** Secrets are never passed as command-line arguments, where `ps`
   would expose them to every user on the machine.
3. **Resolve by provider, not by variable name.** You say
   `--model opencode-go/...`; `pisbx` maps it to `OPENCODE_API_KEY` using the table
   from `pi`'s own `docs/providers.md`.
4. **Sandbox the tools, not just the prompt.** Either `pi` orchestrates on the host
   while its tools execute in a container (`--mode remote`), or the whole process
   runs in a container/VM (`--mode container`).

### Strategy

```
                      ┌───────────────────────────────┐
   you type           │  pisbx run --model P/M        │
   ─────────────►     └───────────────┬───────────────┘
                                      │
                    1. resolve provider → env var (static table)
                                      │
                    2. fetch secret from OS keyring (skey)
                                      │
                    3. choose runtime (docker | lima)
                                      │
              ┌───────────────────────┴────────────────────────┐
              │                                                │
     mode=remote (default)                          mode=container
              │                                                │
   ┌──────────▼──────────┐                        ┌────────────▼────────────┐
   │ host: pi orchestrator│                        │ container: whole pi     │
   │  - model calls       │                        │  - model calls          │
   │  - session/UI        │                        │  - tools                │
   │  - NO secret in env  │                        │  - secret as env var    │
   └──────────┬──────────┘                        └─────────────────────────┘
              │ ws://127.0.0.1:<random>  (bearer token)
   ┌──────────▼──────────┐
   │ container: daemon    │
   │  - read/bash/edit/   │
   │    write             │
   │  - workspace only    │
   │  - key NOT in env    │
   └─────────────────────┘
```

Key handling in `--mode remote`:

- the key is injected as a one-shot variable into a short-lived shell;
- that shell writes an ephemeral `auth.json` (`0600`, `0700` directory, deleted on exit);
- the variable is `unset` before `pi` starts;
- `pi` receives `PI_CODING_AGENT_DIR` pointing at that ephemeral directory;
- the sandbox daemon gets a separate random bearer token, never the provider key.

That last property is the one worth testing yourself (see
[Verified limitations](#verified-limitations)).

---

## Install

```bash
git clone https://github.com/gwangjinkim/pisbx.git
cd pisbx
./install.sh
```

`install.sh` copies the script to `~/.local/bin/pisbx` (or `$PISBX_BIN_DIR`) and
checks dependencies. Equivalent manual install:

```bash
install -m 0755 pisbx ~/.local/bin/pisbx
```

Then:

```bash
pisbx doctor     # dependencies, keyring contents, permissions, plaintext-key warnings
pisbx bootstrap  # write Dockerfiles into ~/.config/pisbx/docker and build both images
```

### Updating

`install.sh` records the clone location in `~/.config/pisbx/install.json`. After that:

```bash
pisbx update --check   # show whether a newer commit exists
pisbx update           # git pull, refresh ~/.local/bin/pisbx, rebuild images
pisbx update --no-bootstrap   # pull + reinstall, keep existing images
```

`update` refuses to run on a dirty checkout unless you pass `--force`. It uses
`git pull --ff-only`, so it never creates merge commits. If you installed by
copying the script without a clone, set `PISBX_REPO=/path/to/pisbx`.

### Install per OS

| Host | Docker | VM |
|---|---|---|
| macOS | Docker Desktop or OrbStack | `brew install lima` |
| Linux | `sudo apt-get install docker.io` (or `podman-docker`), then add your user to the `docker` group | `sudo apt-get install lima` |
| Windows | Docker Desktop with the WSL2 backend; run `pisbx` inside WSL2 | use a WSL2 distro as the VM |

`pisbx doctor` prints the exact command for your platform when something is missing.

---

## Documentation

| Document | Contents |
|---|---|
| [docs/quickstart.md](docs/quickstart.md) | first run, step by step, with expected output and why each step exists |
| [docs/commands.md](docs/commands.md) | every subcommand, flag, environment variable, and session behavior |
| [docs/troubleshooting.md](docs/troubleshooting.md) | the errors people actually hit, and the fix |
| [docs/design.md](docs/design.md) | credential flow, split vs whole execution, threat model |
| [CHANGELOG.md](CHANGELOG.md) | what changed in each release |

If you only read one page: run `pisbx bootstrap` once, then `pisbx run --model
provider/model`. Everything else is optional.

---

## Command reference

### `pisbx init [--dry-run] [--register]`

Scans the pi agent directory and registers missing providers.

- `--dry-run` prints the plan, touches nothing.
- `--register` performs registration without asking again.

Why it exists: provider discovery is tedious and error-prone; the machine already
knows which providers you configured.

### `pisbx migrate [--dry-run]`

Backs up and rewrites `auth.json`, dropping secrets and dead shell-out references
while preserving OAuth and `$ENV` references.

Why it exists: you cannot get the security benefit while a plaintext key is still
sitting in the config file.

### `pisbx bootstrap`

Writes `~/.config/pisbx/docker/Dockerfile{,.sandbox}` and builds both images.

Why it exists: the upstream default sandbox image is not publicly pullable, and
building from a pinned `PI_VERSION` makes the environment reproducible.

### `pisbx doctor`

Prints versions, docker/lima state, keyring entries, file permissions, and warns
about plaintext keys. Exit code is non-zero when a security check fails, so it is
usable in CI.

Why it exists: most security failures are configuration drift, not exploits.

### `pisbx update [--check] [--no-bootstrap] [--force]`

Pulls the clone recorded by `install.sh` at `~/.config/pisbx/install.json`,
refreshes `~/.local/bin/pisbx`, and rebuilds the images.

- `--check` shows whether a newer commit exists, without changing anything
- `--no-bootstrap` pulls and reinstalls but keeps the current images
- `--force` allows updating a checkout with local modifications

Why it exists: the script and the Docker images must move together; a half-updated
install is the most common source of confusing failures.

### `pisbx run --model <provider>/<model> [options] [-- pi args]`

| Option | Default | Why |
|---|---|---|
| `--model P/M` | required | the prefix selects the credential; no key names to remember |
| `--runtime docker\|lima` | `docker` | docker is fast and cross-platform; lima gives a real VM kernel boundary |
| `--mode remote\|container\|native` | `auto` | `remote` keeps the key out of the sandbox; `container` is portable and CI-friendly; `native` uses your exact `pi` and config, without a sandbox |
| `--dry-run` | off | shows the plan without reading a secret or starting anything |
| `--force` | off | allows mounting `$HOME` or `/` as the workspace (dangerous) |
| `--session-mode ask\|continue\|new` | `ask` | when the folder already has sessions, ask; `continue` passes `-c`; `new` starts fresh |
| `--workspace mount\|git` | `mount` | `mount` edits your live tree; `git` works in a worktree and commits to `pisbx/<session>` |

`auto` picks `remote` when the installed `pi` supports `--remote`, otherwise
`container`.

### How fast is sync?

Measured with the eight extensions from a real global setup, warm pnpm store:

| Step | Time |
|---|---|
| `pisbx sync` cold (empty store) | ~8.5s |
| `pisbx sync` warm (rebuild env) | ~0.65s |
| `pisbx run` with a prebuilt env inside a container | ~0.6s, zero install |

The environment is installed by **pnpm** into a shared content-addressable store
(`~/.cache/pisbx/pnpm-store`) and mounted into the container or VM, so the box
normally installs nothing at all. See [docs/environment.md](docs/environment.md).

### Extension fidelity

`pisbx` preserves your agent directory: in `remote` and `native` modes it builds an
ephemeral directory with symlinks to `settings.json`, `extensions/`, `npm/`,
`statusline/`, themes, and so on, and adds only its own ephemeral `auth.json`.

That said, `remote` mode must run a `pi` build that supports `--remote` (currently
the `@fleetagent` build). Extensions written against `@earendil-works/pi-tui` cannot
load there, so the dashboard can look different. When that matters:

```bash
pisbx run --model provider/model --mode native
```

`native` runs your installed `pi` with your full config and no sandbox. The key
still comes from the keyring via an ephemeral `auth.json`, but tools execute on the
host.

### Workspaces: mount or git

By default the project is bind-mounted, so edits are immediately permanent.

For hermetic work, `--workspace git` creates a worktree from a snapshot of your
dirty tree, copies **untracked non-ignored** files, and therefore never copies
`.env` or anything else in `.gitignore`. On exit it commits to
`pisbx/<session>`; your live tree is untouched.

```bash
pisbx run pi --workspace git --model opencode-go/muse-spark-1.3-contributor
```

Or persist the choice:

```toml
[workspace]
mode = "git"
```

See [docs/environment.md](docs/environment.md#git-workspace-mode).

### Sessions in an existing folder

Session files live under `~/.pi/agent/sessions/--<encoded-cwd>--/`. If that folder
already has sessions, `pisbx` asks once:

```
found 2 previous session(s) for this folder
  latest: 2026-11-14 08:11  (11K)  2026-11-14T08-11-54-970Z_....jsonl
  [Enter] continue last   [n] new session   [q] quit:
```

- **Enter** continues the most recent session (`pi -c`)
- **n** starts a clean session
- **q** exits without starting anything

Non-interactive runs, and runs that already pass a session flag (`-c`, `--session`,
`--resume`, etc.) are left alone. Override the prompt with
`--session-mode continue|new` or `PISBX_SESSION_MODE`.

In `container` and `lima` modes the host session directory is mounted into the
agent home, so continuing a session works across runtimes.

### `pisbx recover [--fix]`

After a crash, this reports leftover containers, stale temp agent dirs, git
worktrees, an incomplete environment, and the session count. `--fix` removes
stopped containers, stale temp dirs, and clean worktrees, and rebuilds an
incomplete environment. Running containers and branches are never deleted.

### `pisbx clean [--containers] [--tmp] [--work] [--env] [--all] [--force]`

Targeted cleanup. Default is stopped containers plus stale temp dirs;
`--force` includes running containers; `--env` removes `.pisbx/env`.

### `pisbx sessions list|resume|export`

```bash
pisbx sessions list
pisbx sessions resume latest --model opencode-go/muse-spark-1.3-contributor
pisbx sessions export latest out.html
```

### `pisbx vm status\|start\|stop\|delete\|shell`

Manages the Lima instance used by `--runtime lima`.

---

## Migrating from an existing pi setup

You do not need to reinstall `pi`. Migration is reversible and does not touch
sessions, extensions, or settings.

### 0. Record the current state

```bash
pisbx doctor > before.txt
cp ~/.pi/agent/auth.json ~/.pi/agent/auth.json.manual-backup
```

### 1. See what will be registered

```bash
pisbx init --dry-run
```

Typical output:

```
> inspecting /Users/you/.pi/agent/auth.json
  openrouter: already in the keyring
! opencode-go: not registered
  run: skey set opencode-go default
  github-copilot: oauth (OAuth) - leave this to 'pi /login'
```

### 2. Register the missing providers

```bash
pisbx init --register
```

Each `skey set` prompts once with hidden input.

### 3. Preview the config rewrite

```bash
pisbx migrate --dry-run
```

```
  openrouter: env reference, kept
! opencode-go: shell-out reference, removed (skey get is interactive-only)
> dry run: would write /Users/you/.pi/agent/auth.json.backup.20261114T101500
```

### 4. Apply

```bash
pisbx migrate
```

### 5. Verify

```bash
pisbx doctor
pisbx run --model <provider>/<model> -p "say hi"
```

### 6. Roll back if needed

```bash
cp ~/.pi/agent/auth.json.backup.<timestamp> ~/.pi/agent/auth.json
```

### What is *not* migrated

- **OAuth providers** (GitHub Copilot, Anthropic OAuth, Codex): keep using
  `pi /login`. They are refresh-token based, not static keys.
- **Multi-variable providers** (Azure OpenAI, AWS Bedrock, Cloudflare): `skey`
  injects exactly one variable per invocation. Put the secret in the keyring and
  the non-secret identifiers (endpoint, account id, deployment map, region) in
  your normal config. Multi-secret bundles are on the roadmap.
- **Extensions, skills, rules, sessions, themes**: unchanged and still on the host
  in `remote` mode. In `container` mode they live inside the container's
  `pisbx-home` volume; use `--mode remote` if you depend on host extensions.

---

## Configuration

`~/.config/pisbx/config.json` (override with `PISBX_CONFIG_DIR`). It contains **no
secrets**.

```json
{
  "providers": {
    "opencode-go": { "variant": "app00", "env": "OPENCODE_API_KEY" },
    "anthropic":   { "env": "ANTHROPIC_API_KEY" }
  },
  "defaults": { "runtime": "docker", "mode": "auto" }
}
```

Environment variables:

| Variable | Meaning |
|---|---|
| `PISBX_CONFIG_DIR` | config + generated Dockerfiles |
| `PISBX_IMAGE`, `PISBX_IMAGE_FULL` | image tags |
| `PISBX_SANDBOX_PI` | pi binary that supports `--remote` |
| `PISBX_LIMA_NAME` | Lima instance name |
| `PISBX_NO_EXTENSIONS=1` | pass `--no-extensions` to pi in remote mode |
| `PI_CODING_AGENT_DIR` | discovered automatically; used read-only |

---

## Threat model

**Designed to prevent**

- credentials in shell history, `ps` output, argv, dotfiles, repos, Dockerfiles, CI logs
- credentials in the long-lived environment of the agent, its extensions, and MCP servers
- the agent reading or writing outside the mounted workspace
- a compromised dependency in your *project* reading the provider key (in `remote` mode)
- an agent that deletes files from your home directory (workspace mount is explicit)

**Not designed to prevent**

- a malicious **pi extension**, **MCP server**, or **model provider** — they are inside
  the trust boundary by definition; `remote` mode limits what they can reach, not what
  the model is told
- prompt injection that makes the agent run a command *inside the sandbox*
- exfiltration by a process that already has the key (see below)
- a compromised host, kernel, or Docker daemon
- provider-side breaches (see DeepSeek above) — rotate keys, use scoped keys

| Asset | `remote` | `container` |
|---|---|---|
| Provider key in agent env | **no** | yes (inside container) |
| Provider key on host argv/history | no | no |
| Host filesystem exposure | one directory | one directory |
| Extension/MCP reach | container | container |
| VM kernel boundary | no | no (unless `--runtime lima`) |

---

## Verified limitations

These were reproduced during development and are documented rather than hidden.

1. **`skey` injects one variable per run.** Repeated `--env` keeps only the last,
   and nesting does not compose. Multi-variable providers need a bundle entry; not
   implemented yet.
2. **`skey get` always prompts**, so `"!skey get …"` in `auth.json` fails closed.
   That is why `migrate` removes those entries instead of rewriting them.
3. **`--mode remote` depends on the auth path.** With the key only in the
   ephemeral `auth.json`, a sandboxed `env` showed **no** provider key. If you
   sidestep `pisbx` and export the key into the environment, the daemon forwards
   the environment it sees and the key becomes visible to sandboxed bash. Always
   launch through `pisbx run`.
4. **`--mode container` necessarily exposes the key inside the container** (as an
   environment variable). Same container, same network egress. Use `remote` when
   the key matters more than convenience.
5. **Docker group membership is root-equivalent.** `remote` mode does not change
   that; it changes what the *agent* can reach.
6. **`docker`/Lima are not complete security boundaries.** Both share kernel or
   daemon components with the host. Use `--runtime lima` for a stronger boundary.
7. **`pi`'s sandbox docs and code disagree** on environment forwarding in at least
   one released build (0.2.15). Treat the sandbox as a filesystem boundary first.
8. **Bash 3.2 (macOS default) is supported**, but some features (associative
   arrays, `mapfile`) are intentionally avoided.

---

## Roadmap

- [ ] **Credential-injecting proxy** (the real fix): sandbox gets a dummy token and
      a local base URL; the host proxy injects the real key upstream. Then the key
      can never be read from inside, and you get per-provider quotas and audit logs.
- [ ] Multi-secret bundles for Azure/AWS/Cloudflare (JSON in one keyring entry).
- [ ] `pisbx run --ephemeral` to mount the workspace read-only and copy it into a
      disposable volume.
- [ ] `--runtime wsl` for Windows without Docker Desktop.
- [ ] Shell completions.
- [ ] Reproducible image digests in the README.

---

## FAQ

**Does this replace `skey`?**
No. `pisbx` is the orchestration layer on top. `skey` stays the single source of
truth for secrets, and remains useful on its own.

**Why not use `direnv` / `.env` / 1Password CLI?**
All three put the secret into the environment of a long-lived shell or process.
That is the thing we are trying to avoid. `.env` also tends to get committed.

**Why not `pi --api-key`?**
It is visible in `ps` and in shell history.

**Why not store keys in the Docker image?**
Images are copied, cached, pushed, and scanned. Build args and `ENV` are readable
in image history — this is the classic way keys leak.

**Why the provider prefix in `--model`?**
It makes credential selection deterministic and removes an entire class of "wrong
key" errors.

**Can I use this with `pi`'s own `/sandbox` command?**
Yes, but `/sandbox` is interactive-only and uses a private default image. `pisbx`
uses the same daemon protocol non-interactively.

**Does it work offline?**
Model calls need network. `--dry-run`, `doctor`, `init`, and `migrate` do not.

---

## Sources

Primary sources for the claims above.

1. Wiz Research — *Exposed DeepSeek Database Leaking Sensitive Information,
   Including Chat History* (2025-01-29)
   https://www.wiz.io/blog/wiz-research-uncovers-exposed-deepseek-database-leak
2. WIRED — *Exposed DeepSeek Database Revealed Chat Prompts and Internal Data*
   (2025-01-29)
   https://www.wired.com/story/exposed-deepseek-database-revealed-chat-prompts-and-internal-data
3. Reuters — *Sensitive DeepSeek data exposed to web, cyber firm says* (2025-01-29)
   https://www.reuters.com/technology/artificial-intelligence/sensitive-deepseek-data-exposed-web-israeli-cyber-firm-says-2025-01-29
4. Wiz Research — *Shai-Hulud npm Supply Chain Attack* (2025-09-16)
   https://www.wiz.io/blog/shai-hulud-npm-supply-chain-attack
5. Palo Alto Unit 42 — *"Shai-Hulud" Worm Compromises npm Ecosystem* (2025-11-25)
   https://unit42.paloaltonetworks.com/npm-supply-chain-attack
6. Nx — *S1ngularity postmortem* (2025-09-05)
   https://nx.dev/blog/s1ngularity-postmortem
7. StepSecurity — *s1ngularity: Popular Nx Build System Package Compromised*
   (2025-08-27)
   https://www.stepsecurity.io/blog/supply-chain-security-alert-popular-nx-build-system-package-compromised-with-data-stealing-malware
8. GitGuardian — *The GhostAction Campaign: 3,325 Secrets Stolen* (2025-09-05)
   https://blog.gitguardian.com/ghostaction-campaign-3-325-secrets-stolen
9. Cloud Security Alliance — *VSCode Marketplace Poisoning: How 18 Minutes Breached
   GitHub* (2026)
   https://labs.cloudsecurityalliance.org/research/csa-research-note-vscode-extension-supply-chain-breach-20260
10. BleepingComputer — *Malicious AI extensions on VSCode Marketplace steal
    developer data* (2026-01-23)
    https://www.bleepingcomputer.com/news/security/malicious-ai-extensions-on-vscode-marketplace-steal-developer-data/
11. *Protect Your Secrets: Understanding and Measuring Data Exposure in VSCode
    Extensions* — arXiv:2412.00707
    https://arxiv.org/html/2412.00707v2
12. Wiz Research — *Supply Chain Risk in VSCode Extension Marketplaces* (2025-10-15)
    https://www.wiz.io/blog/supply-chain-risk-in-vscode-extension-marketplaces
13. Wiz Research — *Amazon Q: Compromise via MCP Auto-Execution* (CVE-2026-12957)
    https://www.wiz.io/blog/amazon-q-vulnerability
14. The Register — *Vibe coding service Replit deleted production database*
    (2025-07-21)
    https://www.theregister.com/2025/07/21/replit_saastr_vibe_coding_incident
15. TechRadar — *Claude Code agent deleted 48,000 files in just over 100 seconds*
    (2026-09-27)
    https://www.techradar.com/pro/security/i-broke-something-a-claude-code-ai-agent-deleted-48-000-files-in-just-over-100-seconds-then-apologized-for-doing-so
16. `skey` — OS keyring environment vault
    https://github.com/gwangjinkim/skey

---

## License

MIT. See [LICENSE](LICENSE).
