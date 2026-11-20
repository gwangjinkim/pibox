# Container engines

pibox runs pi on two local engines — `docker` (default everywhere) and
Apple's `container` CLI (macOS 26+, Apple silicon) — plus a `lima` VM
backend. This page is the whole story: how the engine is chosen, what
differs, and how to move between them.

## How the engine is chosen

Highest precedence first:

1. `--runtime <engine>` on the command line.
2. `PIBOX_ENGINE=<engine>` in the environment (scripts, CI).
3. A saved default from a previous interactive choice
   (`~/.config/pibox/config.json`, `defaults.runtime`).
4. **Otherwise, on a terminal, pibox asks.** It lists the engines with what
   it detected, preselects the OS recommendation (Apple `container` on macOS
   when its service is up, Docker elsewhere), and offers to remember your
   pick. Non-terminal runs silently use the OS recommendation instead of
   hanging on a prompt you cannot see.

Examples:

```bash
pibox run --runtime container --model opencode-go/muse-spark-1.3-contributor
PIBOX_ENGINE=docker pibox run --model ...   # script-friendly override
```

## Per-engine notes

**Docker** (default) is the reference backend: full flags (`--init`,
`--cap-drop`, `--security-opt`), `remote` (split) mode, `git` workspaces.
Requires a running daemon (`pibox doctor` reports it).

**Apple `container`** (recommended on macOS when `container system start`
is running) rebuilds the same Dockerfiles into Apple's own image/volume
stores. Deliberate differences:

- No `--init`, `--cap-drop`, `--security-opt`, or `--read-only` (Apple
  documents no equivalents).
- `remote`/split mode stays Docker-only; `--mode auto` selects
  whole-container mode under `--runtime container`. Asking for `--mode
  remote` with `--runtime container` fails fast with that explanation.
- `pibox-home` lives in Apple's store and is seeded from the image plus
  chowned on first use (first run may take a moment).
- `pibox update` rebuilds with `PIBOX_ENGINE` if set, else the Docker
  default; pass `--runtime container` to `pibox bootstrap` explicitly.

**Lima** (`--runtime lima`) runs the whole-container path inside the VM
(`limactl start --name=pibox --tty=false template:docker-rootful`; build
inside with `limactl shell pibox -- docker build -t pibox-full $DOCKER_DIR`).
Keep workspaces under `$HOME` (only shared directories mount into the VM).
Note: VM mode passes the credential to the guest — prefer Docker or Apple
`container` for tighter key isolation.

## Switching engines

Home volumes do not cross engine stores. Everything else does: keys (OS
keyring via `skey`), `pibox.toml`/`pibox.lock`, `.pibox/` envs and
attachments, host session dirs, and the last-model memory.

To switch, rebuild and re-login on the new engine:

```bash
pibox bootstrap --runtime container   # images in Apple's store
pibox run --runtime container ...     # fresh pibox-home; logins carry over only via your own auth
```

Your project manifest, extensions, and sessions are engine-independent and
come along untouched. Delete the old engine's leftovers with `pibox clean`
(docker) or `container volume list` / `container rm` (Apple).
