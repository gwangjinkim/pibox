# Design

`pisbx` is one bash script by intention: it should be possible to read the whole
thing before trusting it with a key.

## Three concerns, kept separate

### 1. Credentials

- secrets live in the OS keyring via `skey` (macOS Keychain, Linux Secret Service,
  Windows Credential Manager)
- `~/.config/pisbx/config.json` maps `provider → variant → environment variable`
  and contains **no secrets**
- during `--mode remote`, the key is written to an ephemeral `0600 auth.json` in a
  `0700` directory, injected into a short-lived shell, and `unset` before `pi`
  starts
- the sandbox daemon receives only a random bearer token

The rule: a secret may exist in memory and briefly on disk, but never in argv,
never in the repository, never in an image layer.

### 2. Runtime

| Mode | Where `pi` runs | Where tools run | Where the key lives |
|---|---|---|---|
| `remote` (default when supported) | host | container daemon | host only |
| `container` | container | container | container env |
| `lima` | container in VM | container in VM | VM (via `0600` env-file) |

`remote` starts `pisbx-sandbox`, waits for `daemon ready`, and runs the host `pi`
with `--remote ws://127.0.0.1:<port>/pi/workspace`. The sandbox sees one bind mount
(`/workspace`) and nothing from the host home directory.

`container` runs the whole CLI in `pisbx-full` with a persistent named volume for
the agent home, plus a bind mount of the host session directory.

### 3. Sessions

Session history is per working directory:
`~/.pi/agent/sessions/--<encoded-cwd>--/*.jsonl` (or `$PI_SESSION_DIR`).

On start, `pisbx` checks that folder. If it has sessions and the invocation is
interactive, it asks:

```
[Enter] continue last   [n] new session   [q] quit
```

- `continue` adds `-c`
- `new` adds nothing
- the prompt is skipped for non-TTY input and when a session flag is already present

In container modes the host session directory is mounted at
`/home/node/.pi/sessions`, so the same history is visible everywhere.

## Images

`pisbx bootstrap` generates two Dockerfiles from pinned versions:

- `Dockerfile.sandbox` → `pisbx-sandbox` (`pi --daemon`, fleetagent build)
- `Dockerfile` → `pisbx-full` (complete `pi` install)

Both run as uid `1000`, with `/workspace` as the only host mount, `/tmp` as
container-local scratch, and no Docker socket.

## Update model

`install.sh` records the clone path in `install.json`. `pisbx update` runs:

```
git fetch → git pull --ff-only → install.sh → pisbx bootstrap
```

Script and images move together. `--check` reports without changing anything;
`--no-bootstrap` skips the rebuild.

## Threat model

**Designed to prevent**

- credentials in shell history, `ps`, argv, dotfiles, repos, images, CI logs
- credentials in the long-lived environment of the agent, its extensions, and MCP
  servers (remote mode)
- the agent touching files outside the mounted workspace
- an agent deleting your home directory

**Not prevented**

- a malicious extension or MCP server inside the trust boundary
- prompt injection that runs commands inside the sandbox
- provider-side breaches
- a user who bypasses the launcher and exports the key

## Roadmap

- credential-injecting proxy: the sandbox gets a dummy token and a local base URL;
  the host proxy injects the real key upstream
- multi-secret providers (Azure, Bedrock, Cloudflare)
- read-only workspace mode with a disposable copy
- shell completions and a `pisbx status` summary
