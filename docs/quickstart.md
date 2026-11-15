# Quick start

This page is the long version of the README quick start: every command, what it
prints, and why the step exists.

## 0. Prerequisites

| Dependency | Why |
|---|---|
| `bash` 3.2+ | the launcher itself (macOS default is fine) |
| `jq` | reads the config, index, and session metadata |
| [`skey`](https://github.com/gwangjinkim/skey) | OS keyring vault |
| `docker` | sandbox runtime (`--runtime docker`, default) |
| `limactl` | optional VM runtime (`--runtime lima`) |
| a `pi` build with `--remote` | split mode (host orchestrator, sandboxed tools) |

Check everything at once:

```console
$ pibox doctor
pibox 0.2.0
config      /Users/you/.config/pibox/config.json
pi (host)   /Users/you/.local/bin/pi 1.5.0
pi (sandbox) /Users/you/.pi/agent/npm/node_modules/.bin/pi 0.2.15
docker      Docker version 27.5.1, build 9f9e405
lima        limactl version 2.2.1
lima vm     absent
mode        docker / auto

keyring (skey):
  opencode-go: app00, dev, prod

security checks:
  auth.json permissions: 600
  ok
```

If a line says `missing`, `doctor` prints the install command for your OS.

---

## 1. Install

```bash
git clone https://github.com/gwangjinkim/pibox.git
cd pibox
./install.sh
```

`install.sh` detects your OS and package manager. For each missing dependency it
prints the command (or a menu when there is a choice, such as Docker on macOS),
asks `[Y/n]`, and runs it immediately. If an automatic install fails it prints the
exact manual steps for that dependency and continues with the next one.

```bash
./install.sh --check    # show the plan, install nothing
```

It:

- copies `pibox` to `~/.local/bin` (or `$PIBOX_BIN_DIR`)
- records the clone location in `~/.config/pibox/install.json`, so `pibox update`
  knows where to pull from
- checks dependencies and prints what is missing

**Why:** the installed script and the Docker images have to move together. Recording
the repo path is what makes `pibox update` possible later.

---

## 2. Build the sandbox images (once)

```bash
pibox bootstrap            # ~730 MB per image
pibox bootstrap --minimal  # ~155 MB per image (Alpine + Bun binary)
```

This writes two Dockerfiles into `~/.config/pibox/docker/` and builds:

| Image | Used by | Contains |
|---|---|---|
| `pibox-sandbox` | `--mode remote` | the pi workspace daemon (`pi --daemon`) |
| `pibox-full` | `--mode container` | a complete pi install |

**Why it is a separate step:** images are large and change only when you upgrade
`pi`. Skipping it produces:

```
x image 'pibox-sandbox' is missing and no Dockerfile found at .../Dockerfile.sandbox
  (run: pibox bootstrap)
```

That error is not a bug; it means step 2 has not run yet.

---

## 3. Put a credential in the OS keyring

Two ways. Both prompt with hidden input and never print the value.

**Automatic** — import what pi already knows:

```bash
pibox init --dry-run   # see the plan
pibox init             # register missing providers
```

`init` reads `~/.pi/agent/auth.json` and classifies each entry:

| Entry | Action |
|---|---|
| literal key | asks you to store it in the keyring |
| `"$ENV_VAR"` | already safe, but registers the provider |
| `"!skey get …"` | dead reference (`skey get` is interactive-only), report it |
| OAuth | skipped; that belongs to `pi /login` |

**Manual** — one provider:

```bash
skey set opencode-go app00
```

```
Enter secret for opencode-go/app00:
```

See what is stored (names only):

```bash
skey list opencode-go
```

```
1) opencode-go/app00
2) opencode-go/dev
3) opencode-go/prod
```

Rotating a key is the same command; it overwrites.

**Why:** this is the only time you handle the raw secret. After this, it never
appears in a shell, a file, or a log.

Optional cleanup of old plaintext:

```bash
pibox migrate --dry-run
pibox migrate
```

`migrate` backs up `auth.json`, removes plaintext keys and dead `!command`
references, and keeps `$ENV` references and OAuth entries. Rollback is printed.

---

## 3b. Adopt your global setup (recommended)

If your global pi already has extensions, themes, a statusline, and MCP servers,
migrate them into a reproducible project environment:

```bash
cd ~/code/my-project
pibox migrate --dry-run     # inventory: every extension, interface file, auth entry
pibox migrate --register    # adopt, register missing keys, build .pibox/env
```

This writes `pibox.toml`, `pibox.lock`, `pibox.pnpm-lock.yaml`, and builds
`.pibox/env`. Later:

```bash
pibox add pi-effort         # warm sync is sub-second
pibox sync                  # rebuild the environment from the lock
```

See [environment.md](environment.md).

## 3c. Toolchains (composable)

```bash
pibox bootstrap --with python
pibox bootstrap --with node,rust,build      # TypeScript + Rust + C
pibox bootstrap --with python,node,go,rust,build,cli
```

| Feature | Aliases | Adds |
|---|---|---|
| python | py, uv | python3, pip, venv, uv |
| node | js, ts, typescript | node, npm, pnpm, yarn, typescript, tsx |
| go | golang | go, gopls, delve |
| rust | rs | rust, cargo, rustfmt, clippy, rust-analyzer |
| build | cc, c, gcc | gcc, g++, make |
| cli | tools | bat, eza, sd, dust, procs, btm, delta, hyperfine, tokei, hexyl, zoxide, just |

`pi`, bash, git, curl, jq, rg and fd are always included.

Shortcuts: `--minimal` (none, 155 MB), `--dev`/`--with all` (1.6 GB),
`--standard` (Debian, 733 MB). The selection is remembered in config.
See [combinations.md](combinations.md) for measured sizes and recipes.

Nothing is installed as root by default. For extra system packages in
`container` mode:

```bash
pibox run --mode container --root --model provider/model   # then: apk add ...
```

## 3d. Attach host folders

Docker cannot add a mount to a running container.

```bash
pibox attach add ~/data:/data:ro     # persisted in .pibox/attach
pibox run --model provider/model

pibox run --attach ~/data:/data:rw   # one-off
```

`~/.pibox/share` is always mounted at `/shared` (read-write) for files you drop
in while a session runs. To apply a new mount to an existing conversation, stop
and resume it; the picker keeps the history. See [safety.md](safety.md).

## 4. Run

```bash
cd ~/code/my-project
pibox run --model opencode-go/muse-spark-1.3-contributor
```

Expected output:

```
> model=opencode-go/muse-spark-1.3-contributor provider=opencode-go variant=app00 env=OPENCODE_API_KEY runtime=docker mode=remote
> starting sandbox daemon on 127.0.0.1:52048
> tools run in the container; key is written to an ephemeral 0600 agent dir
```

Everything after the known flags is forwarded to `pi`:

```bash
pibox run --model anthropic/claude-sonnet-4 -p "explain this repo"
pibox run --model openai/gpt-5.6 -c
pibox run --model google/gemini-3.1-pro --tools read,grep,find,ls
```

**Why no key flag:** the provider prefix selects the credential. There is no
environment variable to forget and no wrong-key mistake to make.

---

## 5. Choose a mode (when the dashboard matters)

| Mode | Sandbox | Config/extensions | Use when |
|---|---|---|---|
| `remote` (default) | tools in container, key stays on host | preserved, but extensions built for `@earendil-works` cannot load in the sandbox build | you want the key out of the sandbox |
| `container` | whole `pi` in container | fresh home volume; extensions live there | portability / CI |
| `native` | none | **exact**, same `pi` and same config | the dashboard and extensions must match |

```bash
pibox run --model provider/model              # remote
pibox run --model provider/model --mode native
```

`native` still takes the key from the keyring through an ephemeral `auth.json`, so
it is better than `export`, but there is no filesystem sandbox.

## 6. Sessions in an existing folder

Session files live under `~/.pi/agent/sessions/--<encoded-cwd>--/`. If that folder
already has sessions, the first run asks:

```
> found 2 previous session(s) for this folder
  [1] 2026-11-14 08:11   11K  01a1db17-14d8
  [2] 2026-11-14 08:02   9.8K 01a1d91c-f0da
  [Enter] latest   [1-2] choose   [n] new   [q] quit:
```

| Choice | Result |
|---|---|
| Enter | continues the most recent |
| `1`-`9` | resumes that specific session by id |
| `n` | starts a new session |
| `q` | exits without starting anything |

The prompt is skipped when:

- the folder has no sessions
- input is not a terminal (piped, CI, `-p`)
- you already passed `-c`, `--continue`, `--session`, `--resume`, `--fork`,
  `--no-session`, or `--session-dir`
- you pass `--session-mode continue` / `--session-mode new`, or set
  `PIBOX_SESSION_MODE`

In `container` and `lima` modes the host session directory is mounted into the
agent home, so `-c` finds the same history across runtimes.

**Why:** continuing history is what you usually want, but silently continuing a
stale session is a great way to confuse the agent. One prompt removes the ambiguity.

---

## 7. Verify the isolation

From inside the agent's shell:

```bash
head -1 /etc/os-release      # Debian, not your host
ls /workspace                # your project
env | grep -c API_KEY        # 0 in remote mode
```

`--mode remote` keeps the provider key on the host. `--mode container` runs all of
`pi` in the container, so the key is present there by construction.

---

## 8. Update

```bash
pibox update --check          # is there a newer commit?
pibox update                  # pull, reinstall, rebuild images
pibox update --no-bootstrap   # pull and reinstall, keep images
```

`update` uses `git pull --ff-only`, refuses a dirty checkout unless `--force`, and
reads the clone path from `~/.config/pibox/install.json`.

**Why:** updating only the script while keeping old images (or the reverse) is the
most common source of confusing failures.

---

## First-run troubleshooting

| Symptom | Fix |
|---|---|
| `image 'pibox-sandbox' is missing` | `pibox bootstrap` |
| `cannot reach the Docker engine` | start Docker Desktop / `sudo systemctl start docker` |
| `no credential registered for 'X'` | `skey set X default` |
| `the installed pi does not support --remote` | `PIBOX_SANDBOX_PI=/path/to/pi` (a build with `--remote`) |
| `sandbox daemon did not become ready` | `docker logs <name>`; usually port or token issues |
| no session prompt | non-TTY, or a session flag was already passed |
| `git pull --ff-only failed` | commit/stash, or `pibox update --force` |

More: [commands.md](commands.md) · [troubleshooting.md](troubleshooting.md)
