# Your AI Coding Agent Can Read Your API Keys. Here's the 60-Second Fix.

---

## Quick start

### 1. Install

```bash
git clone https://github.com/gwangjinkim/pibox.git
cd pibox
./install.sh
```

That puts `pibox` in `~/.local/bin`. Check it:

```bash
pibox doctor
```

You should see your `pi` version, Docker, and your keyring entries.

---

### 2. Put your key in the OS key vault (once per provider)

You have two ways. Both store the secret in your operating system's keychain —
macOS Keychain, Linux Secret Service, or Windows Credential Manager. Neither ever
prints the key.

**Option A — let it find what you already have:**

```bash
pibox init
```

It reads `~/.pi/agent/auth.json`, lists every provider you've configured, and asks
you to register the missing ones.

**Option B — do it by hand (one provider):**

```bash
skey set opencode-go app00
```

You'll see:

```
Enter secret for opencode-go/app00:
```

Type or paste the key. Nothing echoes. Nothing lands in your history. Press Enter,
and it's in the keyring.

See what's stored:

```bash
skey list opencode-go
```

```
1) opencode-go/app00
2) opencode-go/dev
3) opencode-go/prod
```

Names and variants only. Never values. To rotate a key later, run the same
`skey set` command again — it overwrites.

Do that once per provider you actually use. A typical setup:

```bash
skey set opencode-go app00
skey set anthropic default
skey set openai default
```

You will not type these names again.

---

### 3. Build the sandbox once

```bash
pibox bootstrap
```

Two small Docker images: one for running `pi`'s tools in a container, one for
running all of `pi` in a container. Re-run only when you upgrade `pi`.

---

### 4. Start pibox

```bash
cd ~/code/my-project
pibox run --model opencode-go/muse-spark-1.3-contributor
```

That's it. Everything after the flags is passed to `pi`:

```bash
pibox run --model anthropic/claude-sonnet-4 -p "explain this repo"
pibox run --model openai/gpt-5.6 -c
```

Notice what's **not** in that command: no `export`, no `.env`, no key name, no
`--api-key`, no remembering which provider wants `GEMINI_API_KEY` versus
`GOOGLE_API_KEY`.

You pick a model. `pibox` figures out the rest.

---

### 5. Check what it protects

From inside the agent's shell:

```bash
head -1 /etc/os-release      # Debian, not your Mac
ls /workspace                # your project
env | grep -c API_KEY        # 0
```

That last one is the point.

---

## What it protects — and what it doesn't

**It protects:**

- the key from shell history, `ps` output, `.env` files, Dockerfiles, and CI logs
- the key from the sandbox environment in `remote` mode — the sandbox gets only a
  random daemon token
- your other credentials, because they are never loaded or forwarded; an agent that
  needs one key gets exactly one
- your home directory and anything outside the mounted workspace

**It cannot protect:**

- the key that runs the model — it must exist wherever the model call is made (on
  your host in `remote` mode, inside the container in `container` mode), and it
  always exists on the provider's side
- secrets already inside your project directory, because `/workspace` is mounted
  read/write
- a malicious extension or MCP server running on your host as you
- prompt injection that runs commands inside the sandbox
- you, if you bypass the launcher and `export` the key yourself

It cannot protect the key that runs the model. It protects everything around it —
and that is where most leaks actually happen.

A container isolates your filesystem, not your credentials. `pibox` is built around
that distinction rather than pretending it doesn't exist.

---

## What you have to do if you don't use pibox

Here's the manual version. Every time.

```bash
# 1. remember which env var this provider wants
#    (ANTHROPIC_API_KEY? GEMINI_API_KEY? GOOGLE_API_KEY? OPENCODE_API_KEY?)
export ANTHROPIC_API_KEY=sk-ant-<your-key>

# 2. hope it isn't in your history
# 3. hope no extension, MCP server, or postinstall script reads process.env
# 4. remember to unset it later
```

And if you want the sandbox too:

```bash
# build the image yourself
docker build -t my-pi-image .

# start the daemon with a token you generated manually
docker run -d --name pi-sandbox \
  -e PI_DAEMON_TOKEN="$(openssl rand -hex 32)" \
  -v "$PWD:/workspace" \
  -p 127.0.0.1:8787:8787 \
  my-pi-image

# connect pi to it
PI_REMOTE_TOKEN=<same-token> pi --remote ws://127.0.0.1:8787/pi/workspace
```

Now do that again for the next project. Then remember to clean up the container.
Then remember which port you used. Then remember whether you put the key in `.env`
or `auth.json` or your shell. Then notice `auth.json` still has a plaintext key in
it.

The manual path has about twelve steps and five places to leak a secret.

And after all that, the key is still sitting in the agent's environment — which is
the part you cannot fix by being careful.

---

## What this actually buys you: mental overhead

This is the real feature, and it isn't the sandbox.

Before, every session started with a small stack of nagging questions:

- Which environment variable does this model need?
- Is it exported in *this* shell?
- Did I leave it in `.env`?
- Is it in my bash history?
- Is it in `auth.json` or the keyring or both?
- Did I clean up the container and the token?
- Which variant was I using — `app00` or `prod`?

`pibox` deletes that list. You remember **one** thing: the model you want.

```bash
pibox run --model opencode-go/muse-spark-1.3-contributor
```

Everything else — key lookup, variant selection, container startup, token
generation, cleanup — is somebody else's job now.

That is what "secure by default" should feel like: not more steps, fewer things to
remember.

---

## Why this matters now

### Your environment is a shared namespace

`export` doesn't put a key "in the tool." It puts it somewhere every child process
can read: the agent, its extensions, its MCP servers, its bash commands, and
anything they spawn.

On Linux, any process running as you can read `/proc/<pid>/environ`. On macOS,
`ps eww` shows it. Nothing exotic required.

### The supply chain knows this

Reading `process.env` is the dominant credential-theft technique in the JavaScript
ecosystem right now.

- **Shai-Hulud** (Sept 2025): npm worm, harvested environment variables and cloud
  metadata keys, published them to public GitHub repos, and used tokens found in
  those environments to spread.
  ([Wiz](https://www.wiz.io/blog/shai-hulud-npm-supply-chain-attack))
- **Shai-Hulud 2.0** (Nov 2025): moved to `preinstall`, harvested `.npmrc` and
  AWS/GCP/Azure keys from env vars, 25,000+ malicious repos, and tried to wipe the
  home directory as a fallback.
  ([Unit 42](https://unit42.paloaltonetworks.com/npm-supply-chain-attack))
- **s1ngularity / Nx** (Aug 2025): a malicious `postinstall` scraped `process.env`,
  then used the developer's own AI CLI to find more files to steal.
  ([Nx](https://nx.dev/blog/s1ngularity-postmortem))
- **Nx Console 18.95.0** (May 2026): a trojanized VS Code extension, live for 18
  minutes, that stole Claude Code configs, 1Password vaults, and cloud credentials —
  and read `/proc/*/mem` because secrets in memory are still readable.
  ([CSA](https://labs.cloudsecurityalliance.org/research/csa-research-note-vscode-extension-supply-chain-breach-20260))

A study of **27,261 VS Code extensions** found **8.5%** expose credential data to
other extensions. ([arXiv 2412.00707](https://arxiv.org/html/2412.00707v2)) Wiz
found **550+ live API secrets** in marketplace extensions, including OpenAI, Gemini,
Anthropic, and DeepSeek keys.
([Wiz](https://www.wiz.io/blog/supply-chain-risk-in-vscode-extension-marketplaces))

MCP made it worse: Wiz showed Amazon Q auto-executing an `mcp.json` from a cloned
repo with full environment inheritance. Opening the repo was enough.
([CVE-2026-12957](https://www.wiz.io/blog/amazon-q-vulnerability))

### Providers leak too

In January 2025, Wiz found a publicly reachable, unauthenticated ClickHouse database
belonging to DeepSeek. It contained over a million log entries — chat history,
backend details, and **API secrets**.

> "This database contained a significant volume of chat history, backend data and
> sensitive information, including log streams, API Secrets, and operational
> details."

([Wiz](https://www.wiz.io/blog/wiz-research-uncovers-exposed-deepseek-database-leak),
corroborated by
[WIRED](https://www.wired.com/story/exposed-deepseek-database-revealed-chat-prompts-and-internal-data))

Your key is a bearer token that lives in every log pipeline between you and the
model. You can't control that. You can control how many places it exists on your
machine.

### And agents break things

- **Replit / SaaStr** (July 2025): an agent ignored eleven freeze instructions, ran
  `db:push` against a shared database, and deleted 1,206 executive records — then
  fabricated data to cover it up.
  ([The Register](https://www.theregister.com/2025/07/21/replit_saastr_vibe_coding_incident))
- **Claude Code** (Sept 2026): deleted ~48,000 files in just over 100 seconds.
  ([TechRadar](https://www.techradar.com/pro/security/i-broke-something-a-claude-code-ai-agent-deleted-48-000-files-in-just-over-100-seconds-then-apologized-for-doing-so))

Containers don't prevent bad decisions. They bound the damage, and they let you
throw the environment away.

---

## FAQ, briefly

**Why not `.env` / `direnv` / 1Password CLI?**
They export the key into a long-lived shell or process. That's the thing we're
avoiding. `.env` also gets committed.

**Why not `pi --api-key`?**
It appears in `ps` and your shell history.

**Why not bake keys into the image?**
Images get copied, cached, pushed, and scanned. `ENV` and build args are readable
in image history.

**Will this hide my key from the sandbox completely?**
In the default `--mode remote`, the key stays on the host and the sandbox sees only
a random daemon token. Verified: `env | grep -c API_KEY` returns `0` inside the
sandbox. The permanent fix — a credential-injecting proxy — is next on the roadmap.

---

## The one-line version

```bash
pibox run --model opencode-go/muse-spark-1.3-contributor
```

One command. Key from the keyring. Tools in a container. Fewer things to remember,
fewer places to leak.

**Repo:** https://github.com/gwangjinkim/pibox
