# Agent Admin Template — Docker Mode Design

**Status:** Design approved, pending implementation plan
**Date:** 2026-04-18
**Author:** Rodrigo Hinojosa (with Claude Code)
**Scope:** New portable agents via Docker. Host-to-Docker migration is out of scope for this iteration.

---

## 1. Motivation

The current `agent-admin-template` scaffolds agents directly onto the host filesystem. This works but creates a long tail of operational problems:

- State scattered across `~/.claude-personal/`, `~/.claude-mem/`, `~/.codex/`, `~/.mcp-auth/`, plus the agent workspace under `~/Documents/Claude/Agents/<name>/`.
- Path changes (e.g. moving `~/Claude` → `~/Documents/Claude`) require manual patching across dotfiles, systemd units, `.claude.json`, `installed_plugins.json`, `history.jsonl`, `projects/` directories, and more.
- Multi-agent coexistence is ad-hoc (each agent competes for the same `CLAUDE_CONFIG_DIR` / ports / tmux namespaces unless carefully prefixed).
- Teardown leaves residues (8+ stale project entries, 1000+ log references after deleting a workspace).

Goal: **encapsulate all per-agent state and runtime behind a Docker boundary** so that `docker rm -v && rm -rf ~/agents/<name>` is a complete, reversible teardown.

### Non-goals

- Migrating the existing host-resident `rodri-agent` to Docker (separate future feature).
- Multi-architecture images.
- Registry push / CI distribution.
- Kubernetes / swarm orchestration.
- Observability stack (Prometheus, Grafana).

---

## 2. Decisions (locked)

| Decision | Choice | Rationale |
|---|---|---|
| Container topology | 1 container per agent | Simpler isolation, trivial naming |
| Wizard model | Hybrid: interactive on first run, declarative when config exists | Mirrors existing `setup.sh` detection of `agent.yml` |
| Heartbeat location | Inside container (busybox crond) | No host systemd pollution; portable across hosts |
| Cloudflared | Stays on host | Only used for SSH access (unchanged workflow) |
| Persistence | Workspace bind-mount + consolidated named volume for state | Developer keeps normal git/IDE workflow on the workspace; internal state stays opaque |
| Base image | `alpine:3.20` | Minimum footprint; target ≤ 200MB final |
| UID strategy | Build-arg matched to host `id -u` | Avoids bind-mount ownership mismatch |
| Runtime supervisor | Bash watchdog (ported from existing `rodri-agent.sh`) | Fewer moving parts than supervisord; already validated model |
| PID 1 | `tini` | Standard alpine package; reliable signal forwarding |
| Restart policy | `unless-stopped` | Matches current systemd semantics |
| Secrets (`.env`) | Host bind-mount, 0600 | Rotate without `docker exec`; tradeoff accepted |
| Capabilities | Drop ALL, add `CHOWN`, `SETUID`, `SETGID` only | Principle of least privilege |

---

## 3. Architecture

### 3.1 Host / Container / Volume layout

```
HOST (e.g. ferrari)
├── ~/agents/<name>/                    ← bind-mount (workspace)
│   ├── CLAUDE.md
│   ├── .env                            ← 0600, written by wizard
│   ├── agent.yml
│   ├── scripts/heartbeat/
│   │   ├── heartbeat.sh
│   │   ├── heartbeat.conf
│   │   └── logs/
│   ├── memory/, docs/
│   └── .git/
│
├── docker volume: <name>-state         ← consolidated named volume
│   mounted at /home/agent/ inside container:
│     /home/agent/.claude-personal/     ← sessions, history, plugins, file-history
│     /home/agent/.claude-mem/          ← memory index, logs
│     /home/agent/.codex/, .mcp-auth/   ← internal state
│
├── /etc/systemd/system/agent-<name>.service   ← host unit that wraps `docker compose up -d`
│
└── cloudflared (unchanged, SSH tunnels only)

CONTAINER (agent-admin:latest)
├── tini (PID 1)
│   └── entrypoint.sh
│       ├── first-run check → /opt/agent-admin/scripts/wizard-gum.sh
│       └── steady-state   → /opt/agent-admin/scripts/start_services.sh
│
├── /opt/agent-admin/                   ← baked in image (read-only runtime)
│   ├── entrypoint.sh
│   ├── scripts/start_services.sh       ← watchdog (ex-rodri-agent.sh)
│   ├── scripts/wizard-gum.sh           ← interactive first-run wizard
│   └── crontab.tpl
│
├── /workspace/                         ← bind-mount target
└── /home/agent/                        ← named volume target
```

### 3.2 Process tree inside container

```
PID 1: tini
  └── start_services.sh
        ├── crond (background, reads /etc/crontabs/agent)
        │     └── every 5 min: /workspace/scripts/heartbeat/heartbeat.sh
        │
        ├── tmux server (session "agent")
        │     └── claude CLI (Telegram polling)
        │
        └── watchdog loop (respawns tmux/claude with backoff)
```

### 3.3 Repo integration

The Docker mode is added to `agent-admin-template`, not a separate repo:

```
agent-admin-template/
├── docker/                          (new)
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── crontab.tpl
│   └── scripts/start_services.sh
│
├── modules/                         (new .tpl files)
│   ├── docker-compose.yml.tpl
│   └── systemd-host-docker.service.tpl
│
├── setup.sh                         (new --docker flag)
├── scripts/lib/wizard{,-gum}.sh     (branch on --docker)
│
├── tests/                           (new bats files)
│   ├── docker-render.bats
│   ├── docker-setup.bats
│   ├── docker-e2e-smoke.bats
│   └── fixtures/docker-agent.yml
│
└── docs/                            (new guides)
    ├── docker-mode.md
    ├── docker-architecture.md
    └── adding-an-mcp-docker.md
```

---

## 4. Lifecycle

### 4.1 Phase 1 — Scaffold (host)

```bash
./setup.sh --docker
```

- Interactive wizard on host (same UX as today): asks agent name, personality, MCPs, integrations.
- Does NOT ask for sensitive tokens (Telegram bot token, GitHub PAT) — those are deferred to the container wizard.
- Renders:
  - `~/agents/<name>/` with CLAUDE.md, scripts/, agent.yml, docker-compose.yml.
  - `/etc/systemd/system/agent-<name>.service` (wraps `docker compose up -d`).
- Detects host `$(id -u)` and `$(id -g)` → writes to `docker-compose.yml` as `AGENT_UID` / `AGENT_GID`.
- Output: instructions for `cd ~/agents/<name> && docker compose up -d && docker attach <name>`.

### 4.2 Phase 2 — First-run wizard (container)

Entrypoint logic:

```bash
#!/bin/sh
set -e
if [ ! -f /workspace/.env ] || ! grep -q "TELEGRAM_BOT_TOKEN" /workspace/.env; then
  exec /opt/agent-admin/scripts/wizard-gum.sh --in-container
fi
exec /opt/agent-admin/scripts/start_services.sh
```

- Interactive via `gum` (already a dependency in the template).
- Asks: Telegram bot token, chat id, optional GitHub PAT.
- Writes `/workspace/.env` with 0600 perms.
- Exits → Docker `unless-stopped` restarts container → entrypoint finds `.env` → Phase 3.

### 4.3 Phase 3 — Steady state

```bash
# start_services.sh (skeleton)
envsubst < /opt/agent-admin/crontab.tpl > /etc/crontabs/agent
crond -b -L /var/log/crond.log

tmux new-session -d -s agent -c /workspace \
  "CLAUDE_CONFIG_DIR=/home/agent/.claude-personal claude --channels plugin:telegram@claude-plugins-official"
tmux pipe-pane -t agent "cat >> /workspace/claude.log"

# Watchdog: relaunches tmux/claude on death with backoff (max 5 crashes / 5 min → exit 1)
CRASH_COUNT=0
WINDOW_START=$(date +%s)
MAX_CRASHES=5
WINDOW=300
while true; do
  sleep 10
  if ! tmux has-session -t agent 2>/dev/null || ! pgrep -f claude >/dev/null; then
    now=$(date +%s)
    [ $((now - WINDOW_START)) -gt $WINDOW ] && { CRASH_COUNT=0; WINDOW_START=$now; }
    CRASH_COUNT=$((CRASH_COUNT + 1))
    if [ $CRASH_COUNT -ge $MAX_CRASHES ]; then
      echo "CRITICAL: $MAX_CRASHES crashes in ${WINDOW}s, exiting for Docker to restart"
      exit 1
    fi
    respawn_tmux_session
  fi
done
```

### 4.4 Restart layers

```
watchdog in-container ──► Docker `unless-stopped` ──► systemd host unit
  (tmux/claude deaths)      (container exit)             (host reboot / container OOM)
```

Telegram alerting fires from the heartbeat script itself on failures it sees (existing behavior), providing out-of-band visibility when the in-container watchdog is not enough.

### 4.5 Connecting to the session

```bash
ssh <host>
docker exec -it <name> tmux attach -t agent
# Ctrl-b d to detach
```

Exactly one extra hop over the current `ssh <host> && tmux attach -t <name>` flow.

### 4.6 Upgrade & rollback

```bash
# Upgrade
docker tag agent-admin:latest agent-admin:prev
cd agent-admin-template && git pull
cd ~/agents/<name> && docker compose build && docker compose up -d

# Rollback
docker tag agent-admin:prev agent-admin:latest
docker compose up -d
```

Workspace bind-mount and state volume survive rebuilds.

### 4.7 Teardown

```bash
docker compose down -v                 # removes container + volume
rm -rf ~/agents/<name>                 # removes workspace
sudo systemctl disable --now agent-<name>.service
sudo rm /etc/systemd/system/agent-<name>.service
```

No residual state on the host outside these three paths.

---

## 5. Security

### 5.1 UID / GID matching

Dockerfile:

```dockerfile
FROM alpine:3.20
ARG UID=1000
ARG GID=1000
RUN addgroup -g $GID agent && adduser -D -u $UID -G agent agent
```

`setup.sh --docker` injects the host's UID/GID into the build context. Supports heterogeneous UIDs across ferrari/redbull/mclaren.

### 5.2 Volume init

On first container start, entrypoint (running briefly as root) chowns the named volume:

```sh
if [ "$(stat -c %U /home/agent)" = "root" ]; then
  chown -R agent:agent /home/agent
fi
exec su - agent -c /opt/agent-admin/scripts/start_services.sh
```

### 5.3 docker-compose.yml hardening

```yaml
services:
  <name>:
    image: agent-admin:latest
    build:
      context: ../../agent-admin-template/docker
      args:
        UID: "${AGENT_UID}"
        GID: "${AGENT_GID}"
    # No `user:` here: container starts as root so entrypoint can chown
    # the named volume on first run, then drops to `agent` via `su - agent`
    # before exec'ing start_services.sh.
    cap_drop: [ALL]
    cap_add: [CHOWN, SETUID, SETGID]
    security_opt: [no-new-privileges:true]
    read_only: false
    tmpfs: [/tmp:size=100m]
    restart: unless-stopped
    stop_grace_period: 30s
    volumes:
      - ./:/workspace
      - <name>-state:/home/agent
    # No ports exposed; Telegram is outbound-only (polling)
    # No /var/run/docker.sock; no docker-in-docker needed
volumes:
  <name>-state:
```

### 5.4 Network

- Outbound via default bridge (Telegram API, Anthropic API, GitHub, npm, MCPs).
- No inbound ports.
- No Docker socket exposure.

---

## 6. Error handling

| Failure | Detector | Recovery |
|---|---|---|
| Claude crash (isolated) | Watchdog `pgrep` | Respawn tmux session |
| Watchdog exceeds backoff threshold (5/5min) | `exit 1` | Docker restart |
| Container exit | Docker daemon | `unless-stopped` restart |
| Host reboot | systemd | Host unit starts container at boot |
| Heartbeat script failure | Heartbeat itself | Next run notifies via Telegram |
| Telegram token invalid | claude polling error visible in `/workspace/claude.log` | Manual rotation in `.env` + `docker compose restart` |
| Volume init failure (perms) | Entrypoint check | `exit 1`, Docker retries, clear log |
| Bind-mount missing | Entrypoint check | `exit 1`, systemd surfaces via `systemctl status` |
| Image build failure | `setup.sh --docker` | Catches, prints log, leaves no half-state |
| Wizard interrupted | Entrypoint detects incomplete `.env` on next run | Re-launches wizard |

Three restart layers (watchdog → Docker → systemd) plus heartbeat-driven Telegram alerting provide four independent paths to visibility.

---

## 7. Testing strategy

Stack: `bats-core` (existing repo convention).

### 7.1 Unit tests — `docker-render.bats`

- Render `docker-compose.yml.tpl` with `fixtures/docker-agent.yml` → valid YAML, contains expected keys.
- Render `crontab.tpl` with heartbeat interval substitution.
- `setup.sh --docker` detects UID/GID correctly on fixture user.

### 7.2 Setup tests — `docker-setup.bats`

- Flag parsing: `setup.sh --docker` routes to docker-mode branch.
- Scaffolding creates `~/agents/<test>/` with expected files.
- Host systemd unit file rendered with correct paths.

### 7.3 E2E smoke — `docker-e2e-smoke.bats` (skippable via `DOCKER_E2E=0`)

1. `./setup.sh --docker --non-interactive` produces a valid scaffold.
2. `docker compose build` completes.
3. `docker compose up -d` starts; `docker ps` shows running container.
4. Named volume created with correct ownership.
5. Wizard can be driven via piped input (mock tokens).
6. After wizard, `docker exec <name> tmux has-session -t agent` returns 0.
7. `docker compose down -v && rm -rf ~/agents/<test>` → no residue.

### 7.4 Manual smoke (documented in `docs/docker-mode.md`)

- Fresh agent end-to-end.
- Reboot recovery.
- Token rotation (edit `.env` host-side, restart).
- Upgrade path (template `git pull` → `docker compose build`).

---

## 8. Open questions / future work

- **Host → Docker migration** for existing agents (rodri-agent): separate spec.
- **Read-only root filesystem**: possible future hardening once MCP behavior is characterized.
- **Registry distribution**: currently local build only; ghcr.io push as future optional.
- **Multi-arch**: all current hosts share architecture; defer.
- **MCP native deps on musl**: document any MCP that requires glibc; provide `debian:13-slim` variant image as fallback.

---

## 9. Acceptance criteria

Design is ready for implementation when:

- [x] Decisions locked (§2).
- [x] Architecture diagrammed (§3).
- [x] Lifecycle phases specified (§4).
- [x] Security model defined (§5).
- [x] Failure modes enumerated (§6).
- [x] Test plan outlined (§7).
- [ ] Implementation plan authored via `writing-plans` skill.
- [ ] Plan executed and merged.
