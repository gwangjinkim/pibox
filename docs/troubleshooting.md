# Troubleshooting

Most failures fall into five buckets: images not built, Docker not running, no
credential registered, a `pi` build without `--remote`, or a dirty git checkout.

---

## `image 'pibox-sandbox' is missing and no Dockerfile found`

You have not run bootstrap in this config directory.

```bash
pibox bootstrap
```

If you previously used a different `PIBOX_CONFIG_DIR`, either export it again or run
bootstrap with it:

```bash
PIBOX_CONFIG_DIR=/path/to/config pibox bootstrap
```

---

## `cannot reach the Docker engine`

```bash
docker info
```

| OS | Fix |
|---|---|
| macOS | start Docker Desktop or OrbStack |
| Linux | `sudo systemctl start docker` and add your user to the `docker` group |
| Windows | start Docker Desktop with the WSL2 backend, run `pibox` inside WSL2 |

Docker group membership is root-equivalent. `pibox` does not change that; it changes
what the agent can reach.

---

## `no credential registered for 'X'`

```bash
skey set X default
```

or import everything pi already knows:

```bash
pibox init
```

Check what is registered (names only):

```bash
skey list
```

---

## `--env VAR is required` (older versions)

This came from a bug where a missing credential produced an empty environment
variable name. Update:

```bash
pibox update
```

---

## `the installed pi does not support --remote`

Split mode needs a `pi` build that implements the workspace daemon. The installed
`pi` may be a newer build without it.

Point `pibox` at a sandbox-capable build:

```bash
PIBOX_SANDBOX_PI="$HOME/.pi/agent/npm/node_modules/.bin/pi" \
  pibox run --model opencode-go/muse-spark-1.3-contributor
```

Check quickly:

```bash
pi --help | grep -- '--remote <url>'
```

If the help is printed on stderr (some builds do that):

```bash
pi --help 2>&1 | grep -- '--remote <url>'
```

Alternative: use `--mode container`, which does not need `--remote`.

---

## `sandbox daemon did not become ready`

Inspect the container logs:

```bash
docker ps -a | grep pibox
docker logs <name>
```

Common causes:

- a token shorter than 32 bytes (the daemon rejects it)
- Docker bridge networking disabled
- the port was taken between allocation and start

Re-run; `pibox` allocates a fresh port. If it persists, run the daemon manually:

```bash
docker run --rm -it -e PI_DAEMON_TOKEN="$(openssl rand -hex 32)" \
  -v "$PWD:/workspace" -p 127.0.0.1:8787:8787 pibox-sandbox
```

---

## The session prompt does not appear

By design, the prompt is skipped when:

- the folder has no sessions
- stdin/stdout is not a terminal
- you passed a session flag (`-c`, `--session`, `--resume`, `--fork`, `--no-session`)
- `--session-mode` or `PIBOX_SESSION_MODE` was set

Inspect what `pibox` sees:

```bash
ls ~/.pi/agent/sessions/--$(pwd | sed 's|^/||; s|/|-|g')--/
```

Force a choice:

```bash
pibox run --model provider/model --session-mode continue
pibox run --model provider/model --session-mode new
```

---

## Sessions do not carry over between host and container

`pibox` mounts `~/.pi/agent/sessions` (or `$PI_SESSION_DIR`) into
`/home/node/.pi/sessions` in `container` and `lima` modes. If you changed
`PI_SESSION_DIR`, export the same value for the container run.

---

## `git pull --ff-only failed` during `pibox update`

```bash
git -C "$(jq -r .repo ~/.config/pibox/install.json)" status
```

| Cause | Fix |
|---|---|
| local edits | commit or stash them, or `pibox update --force` |
| diverged branch | resolve manually, then `pibox update --no-bootstrap` |
| no upstream | `git branch --set-upstream-to=origin/main` |

If the clone moved, re-run `install.sh` from the new location or set `PIBOX_REPO`.

---

## `limactl: command not found` / VM absent

```bash
# macOS
brew install lima
# Linux
sudo apt-get install lima
```

Create the VM once:

```bash
limactl start --name=pibox --tty=false template:docker-rootful
```

Then build the full image inside it:

```bash
limactl shell pibox -- docker build -t pibox-full ~/.config/pibox/docker
```

`pibox vm status` reports the current state.

---

## macOS: `bash` errors about empty arrays or `${var,,}`

Some features are intentionally avoided so the script runs on macOS's default bash
3.2. If you see syntax errors, check which shell is executing:

```bash
head -1 "$(command -v pibox)"
bash --version
```

`#!/usr/bin/env bash` must resolve to bash, not `sh`.

---

## The key still appears inside the sandbox

Expected in `--mode container`: the whole `pi` process, including model calls, runs
in the container, so the credential exists there.

In `--mode remote` the key stays on the host. Verify:

```bash
# inside the agent
env | grep -c API_KEY
```

If this is non-zero in remote mode, you bypassed the launcher (for example, by
exporting the key yourself). Always start through `pibox run`.

---

## Something else

```bash
pibox doctor
pibox run --model provider/model --dry-run
```

`--dry-run` prints the exact command, with secrets redacted, without starting a
container. Attach that output to an issue.
