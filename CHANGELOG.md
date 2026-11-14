# Changelog

## 0.2.1

- **Config preservation:** the ephemeral agent directory now symlinks the real
  `settings.json`, `extensions/`, `npm/`, `statusline/`, themes, and sessions, so
  extensions and UI settings survive. Only `auth.json` is replaced.
- **New `--mode native`:** runs your installed `pi` with your full config and no
  sandbox. The key still comes from the keyring via an ephemeral `auth.json`.
- **Fidelity warning:** remote mode warns when `settings.json` declares packages,
  because the sandbox `pi` build cannot load extensions that import
  `@earendil-works/*`.
- `PISBX_PI` selects the binary used by native mode.

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
