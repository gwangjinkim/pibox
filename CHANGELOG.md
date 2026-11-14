# Changelog

## 0.2.0

- **Sessions:** when the working folder already has sessions, `pisbx run` asks
  whether to continue the most recent one or start fresh. Skip with
  `--session-mode continue|new` or `PISBX_SESSION_MODE`.
- **Session sharing:** `container` and `lima` modes now mount the host session
  directory at `/home/node/.pi/sessions`, so `-c` finds the same history.
- **Updating:** `pisbx update` (alias `upgrade`) pulls the clone recorded at
  install time, refreshes `~/.local/bin/pisbx`, and rebuilds the images.
  `--check` reports without changing anything; `--no-bootstrap` keeps images;
  `--force` allows a dirty checkout.
- **Install metadata:** `install.sh` writes `~/.config/pisbx/install.json`
  (clone path, version, timestamp) with mode `600`.
- **Docs:** added `docs/quickstart.md`, `docs/commands.md`,
  `docs/troubleshooting.md`, `docs/design.md`, and a quick start at the top of the
  README.

## 0.1.0

- Initial launcher: provider → environment variable resolution, OS keyring via
  `skey`, `remote`/`container`/`lima` runtimes, `init`, `migrate`, `bootstrap`,
  `doctor`, `vm`.
