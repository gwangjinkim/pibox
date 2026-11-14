# Image combinations

`pibox` builds Alpine images that contain **pi plus only the toolchains you
select**. There is no single "dev" image that you have to download in full.

## What is always there (the 155 MB base)

| Component | Why |
|---|---|
| pi (single Bun-compiled binary + assets) | the agent itself |
| Alpine + bash + busybox | shell and basic commands |
| git, curl, jq, less | repository and HTTP work |
| rg, fd | pi's search tools |
| ca-certificates, libstdc++ | TLS and the Bun binary |

This base is why `--minimal` is ~155 MB. Everything else is optional.

## Features and what they add

Sizes are the **measured full-image size when that feature is built alone**, on
arm64, Alpine 3.20, pi 1.5.2. The sandbox image is about 3 MB larger.

| Feature | Aliases | Adds | Standalone image | Added over base |
|---|---|---|---|---|
| `cli` | `tools` | bat, eza, sd, dust, procs, btm, delta, hyperfine, tokei, hexyl, zoxide, just | 188 MB | ~33 MB |
| `python` | `py`, `uv` | python3, pip, venv, uv | 260 MB | ~105 MB |
| `node` | `js`, `ts`, `typescript` | node, npm, pnpm, yarn, typescript, tsx | 311 MB | ~156 MB |
| `build` | `cc`, `c`, `gcc` | gcc, g++, make | 363 MB | ~208 MB |
| `go` | `golang` | go, gopls, delve | 373 MB | ~218 MB |
| `rust` | `rs` | rust, cargo, rustfmt, clippy, rust-analyzer | 996 MB | ~841 MB |

Rust is the expensive one: the Alpine `rust` package alone is ~505 MB, and with
cargo, clippy, rustfmt and rust-analyzer the feature adds ~840 MB.

## Measured combinations

| Command | Contains | Full image |
|---|---|---|
| `--minimal` (`--with none`) | base only | 155 MB |
| `--with cli` | base + Rust CLI tools | 188 MB |
| `--with python` | Python + uv | 260 MB |
| `--with node` | Node + package managers + TypeScript | 311 MB |
| `--with build` | C/C++ toolchain | 363 MB |
| `--with go` | Go + gopls + delve | 373 MB |
| `--with rust` | Rust + tooling | 996 MB |
| `--with rust,build,node` | Rust + C/C++ + TypeScript | 1.20 GB |
| `--with all` / `--dev` | every feature | ~1.6 GB |
| `--standard` | Debian + toolchain | 733 MB |

## Why this matters

- **Download time:** pulling a 1.6 GB image for a Python-only task is waste. The
  same task needs 260 MB.
- **Disk:** every variant keeps its own Alpine layers; the toolchain layer is the
  expensive part. Building only what you use keeps both the registry and local
  disk small.
- **Cache reuse:** `apk` packages are downloaded once into the BuildKit cache, so
  rebuilding a different combination mostly reuses downloads.
- **Switching is cheap in config, not in bytes:** `pibox run` remembers the last
  combination. Rebuild only when the project's language needs change.

## Recipes

| You are doing | Build with |
|---|---|
| read/edit, run tests of an existing Node repo | `--with node` |
| Python data work | `--with python` |
| TypeScript + Rust (Tauri, napi-rs) | `--with node,rust` |
| Rust + C/C++ (FFI, native crates) | `--with rust,build` |
| Go services | `--with go,build` |
| polyglot monorepo | `--with python,node,go,rust,build,cli` |
| Debian/glibc compatibility | `--standard` |
| nothing but pi | `--minimal` |

## Commands

```bash
pibox bootstrap --with python
pibox bootstrap --with node,rust,build
pibox bootstrap --with all
pibox bootstrap --minimal
pibox bootstrap --standard
```

Feature aliases: `py`, `js`, `ts`, `rs`, `cc`, `tools`, `all`, `none`.

The selection is stored in `~/.config/pibox/config.json`:

```json
{
  "defaults": {
    "variant": "alpine",
    "features": "node,rust,build",
    "image": "pibox-sandbox-dev-js-rs-cc",
    "image_full": "pibox-full-dev-js-rs-cc"
  }
}
```

`pibox run` uses those image names automatically. `PIBOX_IMAGE` and
`PIBOX_IMAGE_FULL` override them for one run.

## Adding more at runtime

Anything not in the image can be installed inside a `container` run:

```bash
pibox run --mode container --root --model provider/model
# then: apk add --no-cache <package>
```

Prefer a feature combination when you need the tool regularly; use `--root` for
one-off packages.
