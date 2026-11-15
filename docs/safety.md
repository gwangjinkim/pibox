# Safety and recovery

## `pibox recover` is read-only

Without flags it only reports:

- `pibox` containers (label `pibox=1` or name `pibox-*`)
- temp agent dirs older than 10 minutes
- git worktrees under `.pibox/work/`
- an incomplete project environment
- session count for the folder

It starts nothing and deletes nothing.

## `pibox recover --fix` is conservative

It:

- removes **stopped** containers only
- keeps **running** containers and warns:
  `running container kept: <name> (Up ...) - use --force to remove`
- removes stale temp dirs, overwriting `auth.json` before deletion
- removes **clean** worktrees only; branches are never deleted
- rebuilds an incomplete environment

## `pibox clean --force` is the only command that stops running sessions

Plain `pibox clean` removes stopped containers and stale temp dirs. Adding
`--force` includes running containers. Do not use `--force` while a session you
care about is active.

`pibox clean --env` deletes `.pibox/env`; `pibox sync` rebuilds it.

## `pibox repair`

The container home lives in the `pibox-home` volume. Running a container as root
(`--root`) can leave files owned by root, after which the normal user cannot write
`trust.json` or sessions.

```bash
pibox repair
```

This runs a one-off root container that `chown -R 1000:1000 /home/node/.pi` inside
the volume. Pibox also runs it automatically after a `--root` container session.

## Sessions survive a killed container

Session files are written incrementally on the host
(`~/.pi/agent/sessions/--<project>--/`). Killing a container stops the process; it
does not delete the conversation.

What is lost: the in-flight turn, the container's temporary state, and any
unflushed output.

What survives: the session JSONL, project files (bind mount), `.pibox/env`,
installed packages, and the host session index.

Resume:

```bash
pibox run --model provider/model      # numbered session picker
pibox sessions list
pibox sessions resume latest --model provider/model
```

## Attaching host folders

Docker cannot add a mount to a running container. Use one of these instead.

### Pre-declared mounts

```bash
pibox attach add ~/data:/data:ro
pibox attach add ~/Downloads              # -> /attached/Downloads, read-only
pibox attach list
pibox run --model provider/model
```

Stored in `.pibox/attach` (machine-local, not committed). The format is
`host[:target][:ro|rw]`; the default target is `/attached/<basename>` and the
default mode is `ro`.

One-off mounts:

```bash
pibox run --model provider/model --attach ~/data:/data:rw
```

### Live file drops

`~/.pibox/share` is always mounted at `/shared` (read-write). You can copy files
into it while a session is running and the agent sees them immediately:

```bash
cp report.pdf ~/.pibox/share/
```

### Applying a new mount to an existing session

Stop the session, then start it again with the attachment; the session picker
resumes the same conversation with the new mount.

```bash
pibox attach add ~/data:/data:ro
pibox run --model provider/model      # choose the previous session
```

## Checking state

```bash
pibox recover                         # read-only inventory
docker ps --filter label=pibox=1      # pibox containers
pibox sessions list                   # sessions for this folder
pibox doctor                          # keys, docker/lima, permissions
```
