# boxout

Isolated Docker environment for AI coding agents.

Agents get full access to your project directory and outbound network,
with Docker/Compose access via a filtered socket proxy — and nothing else.

## What's isolated

| | Agent sees |
|---|---|
| Filesystem | Current project only (`/workspace`) |
| Network | Full outbound internet |
| Docker | Compose up/down/build/logs/exec (no delete/prune) |
| Host filesystem | Not visible |
| Host home dir | Not visible |
| Other projects | Not visible |

## Setup

### 1. Place boxout somewhere on your PATH

```bash
mv boxout ~/.boxout
# in ~/.zshrc or ~/.bashrc:
export PATH="$HOME/.boxout:$PATH"
```

Then reload: `source ~/.zshrc`

### 2. Build the image (once)

```bash
boxout --build bash
# ctrl-d to exit after it builds
```

### 3. Verify the Docker socket path

The proxy mounts `/var/run/docker.sock`. On Colima, verify:

```bash
ls -la /var/run/docker.sock
# should point to ~/.colima/default/docker.sock or exist directly
```

If not symlinked, either add the symlink or update `docker-compose.yml`:
```yaml
volumes:
  - ~/.colima/default/docker.sock:/var/run/docker.sock:ro
```

## Usage

```bash
# From any project directory:
boxout claude              # Claude Code
boxout codex               # OpenAI Codex
boxout bash                # Interactive shell
boxout npm run dev         # Any command

# Options
boxout --build claude      # Rebuild image first
boxout --no-proxy claude   # No Docker access
boxout --image my-img bash # Custom image

# Lifecycle
boxout stop                # Stop the socket proxy
boxout clean               # Stop proxy + remove volumes
```

## API keys

These env vars are automatically forwarded from the host if set:

- `ANTHROPIC_API_KEY`
- `OPENAI_API_KEY`
- `GITHUB_TOKEN`
- `NPM_TOKEN`

## Config persistence

Agent config and anything written to `$HOME` inside the container lives in a
named Docker volume (`boxout-home`), not on the host. Authenticate once; it
persists across runs.

To reset (e.g. force re-auth):
```bash
boxout clean
# or just the volume:
docker volume rm boxout-home
```

## Customizing the Dockerfile

The image ships with Node.js LTS (via mise), Claude Code, Codex CLI, Python 3,
Docker CLI + Compose, and common dev tools (ripgrep, jq, git, curl).

Add whatever your projects need. Runtime versions (Node, Python, Go, etc.) are
better managed per-project via `.mise.toml`, which boxout picks up automatically.

To rebuild after changes:
```bash
boxout --build bash
```

## Claude Code permissions

Defaults live in `config/claude/settings.json` and sync into the container on
every start. Since Docker is the real security boundary, the permission layer
can be kept permissive inside it.

**Allowed**

- Full read/write/edit within `/workspace` — operations outside still prompt
- All Bash commands — Docker containment makes a fine-grained allowlist more
  friction than it's worth
- All outbound HTTP/HTTPS (`WebFetch`, `WebSearch`)

**Denied**

Narrow list focused on what's meaningful even inside a container:

- `sudo`, `su` — privilege escalation (the container user has no sudo access anyway)
- `ssh`, `scp` — could open channels outside the container
- `nc`, `netcat`, `socat` — general-purpose tunneling; no legitimate dev use

**Secrets files**

Claude's file tools are blocked from reading `.env`, `.env.*.*`
(e.g. `.env.production.local`), `*.pem`, and `*.key`. `.env.example` is
intentionally excluded and stays accessible.

These rules apply to Claude's built-in file tools only, not Bash — `cat .env`
still works. They guard against accidental reads and naive prompt injection,
not a determined attacker.

## Boxout vs Claude Code's native sandbox

Claude Code ships a `/sandbox` command (bubblewrap on Linux) as an alternative
isolation mechanism. The critical difference:

**Native sandbox only wraps Bash subprocess execution.** Claude's built-in file
tools (`Read`, `Edit`, `Write`) run directly on the host, constrained only by
the permissions allow/deny list — not OS-level enforcement. A prompt injection
via the Read tool can reach `~/.ssh`, `~/.aws`, or any sensitive host path.
In boxout, those paths don't exist.

| | Boxout | Native sandbox |
|---|---|---|
| Isolation scope | Everything — file tools + Bash + subprocesses | Bash subprocesses only |
| Host file exposure | None | Claude's file tools hit host directly |
| Mechanism | Docker (kernel namespaces + cgroups) | bubblewrap (unprivileged namespaces) |
| Docker support | Full, via socket proxy | Incompatible |
| Permission UX | Broad allow list (low friction) | `autoAllowBashIfSandboxed` auto-executes |
| Host toolchain | Image-only | Full host tools available |
| Per-project isolation | Clean (separate mount per project) | Shares host home + env vars |

The file-tool gap and Docker incompatibility are architectural constants — not
gaps that are likely to close in a future release.

## TODO

- **Docker exec scoping:** The socket proxy permits `docker exec` into any
  running container on the host. [docker-proxy-filter](https://github.com/FoxxMD/docker-proxy-filter)
  could add container-name allowlisting for tighter control.
