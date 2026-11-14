# Changelog

## 0.5.1

- **Auto mode fix:** a project with `pisbx.toml` now selects `container`, so
  `@earendil-works` extensions load from the project environment (verified).
- **Remote preflight:** when remote would use the `@fleetagent` build while
  global extensions target `@earendil-works`, `pisbx` stops with three options
  instead of emitting extension load errors.
- **`--no-extensions`:** run the sandbox without loading extensions.
- Verified: `mode=container` with a migrated environment loads all 8 extensions;
  `remote --no-extensions` runs clean.

## 0.5.0

- **`pisbx recover [--fix]`:** diagnoses leftover state after a crash
  (containers, stale temp agent dirs, worktrees, incomplete environment) and
  applies safe cleanup.
- **`pisbx clean`:** targeted cleanup with `--containers`, `--tmp`, `--work`,
  `--env`, `--all`, `--force`. Running containers are only removed with
  `--force`.
- **`pisbx sessions list|resume|export`:** inspect, resume by id/latest, and
  export sessions to HTML.
- Containers are labelled `pisbx=1` so cleanup can never touch unrelated ones.
- Session folders use the physical path, fixing `/tmp` vs `/private/tmp`.

## 0.4.0

- **`--workspace git`:** isolates the agent in a git worktree built from a
  snapshot of the dirty tree, copies untracked non-ignored files, excludes
  `.gitignore` entries such as `.env`, and commits results to `pisbx/<session>`
  on exit. The live tree is never modified.
- **`pisbx work list|clean`** manages worktrees under `.pisbx/work/`; they are
  kept after exit, including crashes.
- `[workspace] mode = "mount"|"git"` in `pisbx.toml`.
- `mount` remains the default.

## 0.3.2

- **`migrate` adopts the whole setup:** every extension with its exact version,
  interface files (`settings.json`, `mcp.json`, `AGENTS.md`, `SYSTEM.md`,
  `models-store.json`, `extensions/`, `skills/`, `rules/`, `prompt-templates/`,
  `themes/`, `statusline/`), and all `auth.json` entries. Writes
  `pisbx.toml`/`pisbx.lock` and builds `.pisbx/env`.
- **pnpm-backed environments:** `sync` writes an exact `package.json`, suppresses
  peer auto-install and lifecycle scripts, installs from a shared store, and
  copies `pnpm-lock.yaml` to `pisbx.pnpm-lock.yaml`.
- **Relocatable environments:** interface files are copied into `env/base/` and
  linked relatively, so the environment keeps working when bind-mounted into a
  container or VM.
- Measured: cold sync ~8.5s, warm sync ~0.65s, in-box startup ~0.6s with zero
  install.

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
