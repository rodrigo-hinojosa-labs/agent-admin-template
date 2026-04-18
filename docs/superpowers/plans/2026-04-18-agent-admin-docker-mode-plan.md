# Agent-Admin Docker Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `--docker` mode to `agent-admin-template` that scaffolds a containerized agent (alpine-based image, workspace bind-mount, consolidated named volume for internal state, host systemd unit wrapping `docker compose up -d`).

**Architecture:** The existing bash template engine (`scripts/lib/render.sh`) stays unchanged. A new `docker/` directory ships Dockerfile + in-container scripts. New `modules/docker-compose.yml.tpl` and `modules/systemd-host-docker.service.tpl` render per-agent. `setup.sh` gains a `--docker` flag that (a) sets `deployment.mode: docker` in `agent.yml`, (b) skips host-side `agent-script-*.sh` / user systemd / launchd rendering, (c) renders docker-compose + host system unit instead. Secrets move from host wizard to a container-side first-run wizard; the host wizard collects only non-secret config. Tests follow the existing `bats-core` pattern: render tests, setup flag tests, and an opt-in E2E docker smoke.

**Tech Stack:** bash 4+, `yq`, `jq`, `bats-core`, `perl -0777` (template engine), `gum` (wizard UI), `tini` (container PID 1), `busybox crond` (in-container heartbeat), `alpine:3.20` (base image), `docker compose v2`, systemd (host unit).

**Out of scope for this plan:** Host → Docker migration of `rodri-agent`, multi-arch builds, registry push, readonly rootfs hardening.

---

## File Structure

**New files:**

| Path | Responsibility |
|---|---|
| `docker/Dockerfile` | Image definition (alpine + tini + bash + tmux + nodejs/npm + claude CLI + gum + busybox crond). Build-arg `UID`/`GID`. |
| `docker/entrypoint.sh` | PID-1 entrypoint. Chowns volume on first run; detects missing `.env` → exec wizard; otherwise exec start_services.sh as `agent` user. |
| `docker/crontab.tpl` | Cron line template for in-container heartbeat. Rendered at container startup by `envsubst`. |
| `docker/scripts/start_services.sh` | Steady-state: starts `crond`, starts `tmux` session, watchdog loop. |
| `docker/scripts/wizard-container.sh` | gum-driven first-run wizard that runs inside the container. Asks for Telegram token/chat id and optional GitHub PAT; writes `/workspace/.env` with 0600. |
| `modules/docker-compose.yml.tpl` | Per-agent compose file (image, build, volumes, cap_drop/add, no ports, unless-stopped). |
| `modules/systemd-host-docker.service.tpl` | `/etc/systemd/system/agent-<name>.service` that wraps `docker compose up -d` (and `down` on stop). |
| `tests/fixtures/docker-agent.yml` | Minimal `agent.yml` with `deployment.mode: docker`. |
| `tests/docker-render.bats` | Unit tests for the three new templates. |
| `tests/docker-setup.bats` | Flag parsing + scaffolding tests (no docker daemon required). |
| `tests/docker-e2e-smoke.bats` | E2E smoke, opt-in via `DOCKER_E2E=1`. |
| `docs/docker-mode.md` | User-facing guide: install, lifecycle, teardown, troubleshooting. |
| `docs/docker-architecture.md` | Architecture reference mirroring `docs/architecture.md`, docker-specific. |
| `docs/adding-an-mcp-docker.md` | How MCP config differs inside a container (paths, musl caveats). |

**Modified files:**

| Path | Change |
|---|---|
| `setup.sh` | New `--docker` flag → sets `MODE_DOCKER=true` and influences `parse_args`, `run_wizard`, `regenerate`, `install_service`, `uninstall`. |
| `scripts/lib/render.sh` | No change (render engine is sufficient). |
| `scripts/lib/wizard.sh` / `wizard-gum.sh` | No change (container-side wizard is its own script). |
| `tests/helper.bash` | No change. |
| `.gitignore` | Add `docker/scripts/vendor/` (if gum is ever shipped inside the image build context). |

**File ownership rules (unchanged):** `agent.yml`, `.env`, `CLAUDE.md` are user-owned. `docker-compose.yml`, the host systemd unit, and anything under `docker/` in the destination are system-owned (re-rendered on `--regenerate`).

---

## Task 1: Add `deployment.mode` schema + fixture

**Goal:** Lock in the YAML field that branches docker vs. host mode, with a fixture that later render tests depend on.

**Files:**
- Create: `tests/fixtures/docker-agent.yml`
- Modify: (none yet — `setup.sh` writes the new field in a later task)
- Test: `tests/docker-render.bats` (first test only)

- [ ] **Step 1: Write the failing test**

Create `tests/docker-render.bats` with the first assertion:

```bash
#!/usr/bin/env bats

load helper

setup() {
  setup_tmp_dir
  load_lib yaml
  load_lib render
  FIXTURE="$REPO_ROOT/tests/fixtures/docker-agent.yml"
  render_load_context "$FIXTURE"
  export HOME_DIR="/home/test"
}

teardown() { teardown_tmp_dir; }

@test "docker-agent fixture exposes deployment.mode=docker" {
  [ "${DEPLOYMENT_MODE:-}" = "docker" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/docker-render.bats`
Expected: FAIL — fixture does not exist yet.

- [ ] **Step 3: Create the fixture**

Create `tests/fixtures/docker-agent.yml`:

```yaml
version: 1
agent:
  name: dockbot
  display_name: "DockBot 🐳"
  role: "test agent for docker mode"
  vibe: "terse"
  use_default_principles: true
user:
  name: "Alice Example"
  nickname: "Alice"
  timezone: "UTC"
  email: "alice@example.com"
  language: "en"
deployment:
  host: "testhost"
  workspace: "/home/test/agents/dockbot"
  mode: "docker"
  install_service: true
  claude_cli: "claude"
docker:
  image_tag: "agent-admin:latest"
  uid: 1000
  gid: 1000
  state_volume: "dockbot-state"
  base_image: "alpine:3.20"
claude:
  config_dir: "/home/agent/.claude-personal"
  profile_new: true
notifications:
  channel: telegram
features:
  heartbeat:
    enabled: true
    interval: "30m"
    timeout: 300
    retries: 1
    default_prompt: "Check status and report"
mcps:
  defaults:
    - fetch
    - time
  atlassian: []
  github:
    enabled: false
    email: ""
plugins:
  - telegram@claude-plugins-official
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats tests/docker-render.bats`
Expected: PASS — `DEPLOYMENT_MODE` env var is exported by `render_load_context` and equals `docker`.

- [ ] **Step 5: Commit**

```bash
git add tests/fixtures/docker-agent.yml tests/docker-render.bats
git commit -m "test(docker): add fixture and smoke assertion for deployment.mode=docker"
```

---

## Task 2: Render `modules/docker-compose.yml.tpl`

**Goal:** Ship a template that renders a valid docker-compose file from the fixture. No host-level wiring yet.

**Files:**
- Create: `modules/docker-compose.yml.tpl`
- Modify: `tests/docker-render.bats` (add compose-render tests)

- [ ] **Step 1: Write the failing tests**

Append to `tests/docker-render.bats`:

```bash
@test "docker-compose.yml.tpl renders with agent name as service" {
  result=$(render_template "$REPO_ROOT/modules/docker-compose.yml.tpl")
  [[ "$result" == *"  dockbot:"* ]]
}

@test "docker-compose.yml.tpl sets build args from docker.uid/gid" {
  result=$(render_template "$REPO_ROOT/modules/docker-compose.yml.tpl")
  [[ "$result" == *'UID: "1000"'* ]]
  [[ "$result" == *'GID: "1000"'* ]]
}

@test "docker-compose.yml.tpl mounts workspace and named state volume" {
  result=$(render_template "$REPO_ROOT/modules/docker-compose.yml.tpl")
  [[ "$result" == *"./:/workspace"* ]]
  [[ "$result" == *"dockbot-state:/home/agent"* ]]
}

@test "docker-compose.yml.tpl drops all caps and re-adds only the three" {
  result=$(render_template "$REPO_ROOT/modules/docker-compose.yml.tpl")
  [[ "$result" == *"cap_drop:"* ]]
  [[ "$result" == *"cap_add:"* ]]
  [[ "$result" == *"CHOWN"* ]]
  [[ "$result" == *"SETUID"* ]]
  [[ "$result" == *"SETGID"* ]]
}

@test "docker-compose.yml.tpl uses unless-stopped and no published ports" {
  result=$(render_template "$REPO_ROOT/modules/docker-compose.yml.tpl")
  [[ "$result" == *"restart: unless-stopped"* ]]
  [[ "$result" != *"ports:"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/docker-render.bats`
Expected: FAIL — `modules/docker-compose.yml.tpl` does not exist (`render_template: template not found`).

- [ ] **Step 3: Create the template**

Create `modules/docker-compose.yml.tpl`:

```yaml
# docker-compose.yml — {{AGENT_DISPLAY_NAME}}
# Generated by setup.sh. Edit modules/docker-compose.yml.tpl to change.

services:
  {{AGENT_NAME}}:
    image: {{DOCKER_IMAGE_TAG}}
    container_name: {{AGENT_NAME}}
    build:
      context: ./docker
      args:
        UID: "{{DOCKER_UID}}"
        GID: "{{DOCKER_GID}}"
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETUID
      - SETGID
    security_opt:
      - no-new-privileges:true
    read_only: false
    tmpfs:
      - /tmp:size=100m
    restart: unless-stopped
    stop_grace_period: 30s
    volumes:
      - ./:/workspace
      - {{DOCKER_STATE_VOLUME}}:/home/agent
    env_file:
      - ./.env

volumes:
  {{DOCKER_STATE_VOLUME}}:
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/docker-render.bats`
Expected: all five compose-render tests PASS.

- [ ] **Step 5: Commit**

```bash
git add modules/docker-compose.yml.tpl tests/docker-render.bats
git commit -m "feat(docker): add docker-compose.yml template with hardened compose config"
```

---

## Task 3: Render `modules/systemd-host-docker.service.tpl`

**Goal:** Host systemd unit that wraps `docker compose up -d` / `down`. This lets the host boot the container automatically.

**Files:**
- Create: `modules/systemd-host-docker.service.tpl`
- Modify: `tests/docker-render.bats`

- [ ] **Step 1: Write the failing tests**

Append to `tests/docker-render.bats`:

```bash
@test "systemd-host-docker unit has Type=oneshot RemainAfterExit=yes" {
  result=$(render_template "$REPO_ROOT/modules/systemd-host-docker.service.tpl")
  [[ "$result" == *"Type=oneshot"* ]]
  [[ "$result" == *"RemainAfterExit=yes"* ]]
}

@test "systemd-host-docker ExecStart runs docker compose up -d in workspace" {
  result=$(render_template "$REPO_ROOT/modules/systemd-host-docker.service.tpl")
  [[ "$result" == *"WorkingDirectory=/home/test/agents/dockbot"* ]]
  [[ "$result" == *"ExecStart=/usr/bin/docker compose up -d"* ]]
  [[ "$result" == *"ExecStop=/usr/bin/docker compose down"* ]]
}

@test "systemd-host-docker unit description includes agent display name" {
  result=$(render_template "$REPO_ROOT/modules/systemd-host-docker.service.tpl")
  [[ "$result" == *"Description=DockBot 🐳 (Docker)"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/docker-render.bats`
Expected: three new tests FAIL.

- [ ] **Step 3: Create the template**

Create `modules/systemd-host-docker.service.tpl`:

```ini
[Unit]
Description={{AGENT_DISPLAY_NAME}} (Docker)
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory={{DEPLOYMENT_WORKSPACE}}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/docker-render.bats`
Expected: all compose + systemd tests PASS.

- [ ] **Step 5: Commit**

```bash
git add modules/systemd-host-docker.service.tpl tests/docker-render.bats
git commit -m "feat(docker): add host systemd unit template wrapping docker compose"
```

---

## Task 4: Render `docker/crontab.tpl`

**Goal:** In-container cron line that fires the existing `scripts/heartbeat/heartbeat.sh` on the agent's configured interval. The template is copied into the image and rendered at container start by `envsubst` — but we still unit-test it via the bash template engine for shape correctness.

**Files:**
- Create: `docker/crontab.tpl`
- Modify: `tests/docker-render.bats`

- [ ] **Step 1: Write the failing test**

Append to `tests/docker-render.bats`:

```bash
@test "crontab.tpl contains heartbeat invocation against workspace" {
  # The runtime uses envsubst, but shape is the same: $AGENT_NAME + cron schedule.
  content=$(< "$REPO_ROOT/docker/crontab.tpl")
  [[ "$content" == *"/workspace/scripts/heartbeat/heartbeat.sh"* ]]
  [[ "$content" == *'${HEARTBEAT_CRON}'* ]]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/docker-render.bats`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Create the file**

Create `docker/crontab.tpl`:

```
# Cron for in-container agent heartbeat.
# Rendered at container startup: envsubst < /opt/agent-admin/crontab.tpl > /etc/crontabs/agent
${HEARTBEAT_CRON} agent /workspace/scripts/heartbeat/heartbeat.sh >> /workspace/scripts/heartbeat/logs/cron.log 2>&1
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats tests/docker-render.bats`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add docker/crontab.tpl tests/docker-render.bats
git commit -m "feat(docker): add in-container crontab template for heartbeat"
```

---

## Task 5: Write the Dockerfile

**Goal:** Reproducible image with alpine:3.20 + bash + tmux + nodejs + claude CLI + gum + tini + busybox-extras. Build-time UID/GID. No secrets. No daemons started here — entrypoint handles that.

**Files:**
- Create: `docker/Dockerfile`
- Modify: `tests/docker-render.bats` (shape assertions only — no actual build)

- [ ] **Step 1: Write the failing tests**

Append to `tests/docker-render.bats`:

```bash
@test "Dockerfile builds from alpine:3.20 base" {
  content=$(< "$REPO_ROOT/docker/Dockerfile")
  [[ "$content" == *"FROM alpine:3.20"* ]]
}

@test "Dockerfile accepts UID/GID build args and creates agent user" {
  content=$(< "$REPO_ROOT/docker/Dockerfile")
  [[ "$content" == *"ARG UID=1000"* ]]
  [[ "$content" == *"ARG GID=1000"* ]]
  [[ "$content" == *"addgroup -g"* ]]
  [[ "$content" == *"adduser -D -u"* ]]
}

@test "Dockerfile installs required runtime packages" {
  content=$(< "$REPO_ROOT/docker/Dockerfile")
  for pkg in bash tmux tini nodejs npm git curl; do
    [[ "$content" == *"$pkg"* ]]
  done
}

@test "Dockerfile ENTRYPOINT uses tini then entrypoint.sh" {
  content=$(< "$REPO_ROOT/docker/Dockerfile")
  [[ "$content" == *"ENTRYPOINT"* ]]
  [[ "$content" == *"/sbin/tini"* ]]
  [[ "$content" == *"/opt/agent-admin/entrypoint.sh"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/docker-render.bats`
Expected: four new tests FAIL.

- [ ] **Step 3: Create the Dockerfile**

Create `docker/Dockerfile`:

```dockerfile
# syntax=docker/dockerfile:1.6
FROM alpine:3.20

ARG UID=1000
ARG GID=1000

# Runtime packages. `tini` for PID 1, `bash` for scripts, `tmux` for the
# persistent session, `nodejs`/`npm` for the claude CLI, `git` for repo ops,
# `curl` for bootstrapping, `perl` for the template engine, `yq`/`jq` for
# config, `busybox-extras` for `crond`, `gum` for the in-container wizard.
RUN apk add --no-cache \
      bash \
      tini \
      tmux \
      nodejs \
      npm \
      git \
      curl \
      perl \
      jq \
      yq \
      gettext \
      busybox-extras \
      shadow \
      su-exec \
      ca-certificates

# Install gum from the charmbracelet tap alternative: use the static binary.
ARG GUM_VERSION=0.14.5
RUN set -eux; \
    arch=$(uname -m); \
    case "$arch" in \
      x86_64) gum_arch="x86_64" ;; \
      aarch64) gum_arch="arm64" ;; \
      *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_linux_${gum_arch}.tar.gz" \
      | tar -xz -C /tmp; \
    mv "/tmp/gum_${GUM_VERSION}_linux_${gum_arch}/gum" /usr/local/bin/gum; \
    rm -rf /tmp/gum_*

# Install Claude Code CLI globally so both root (for first-run chown) and
# the `agent` user can invoke it.
RUN npm install -g @anthropic-ai/claude-code

# Create the non-root agent user matching host UID/GID.
RUN addgroup -g "$GID" agent \
 && adduser -D -u "$UID" -G agent -s /bin/bash agent

# Copy in the in-image scripts (baked at build time, read-only at runtime).
COPY entrypoint.sh /opt/agent-admin/entrypoint.sh
COPY crontab.tpl /opt/agent-admin/crontab.tpl
COPY scripts/start_services.sh /opt/agent-admin/scripts/start_services.sh
COPY scripts/wizard-container.sh /opt/agent-admin/scripts/wizard-container.sh
RUN chmod +x /opt/agent-admin/entrypoint.sh \
             /opt/agent-admin/scripts/start_services.sh \
             /opt/agent-admin/scripts/wizard-container.sh

# Workspace is bind-mounted at runtime; /home/agent is a named volume.
WORKDIR /workspace

# tini is PID 1; entrypoint.sh runs as root briefly, drops to agent.
ENTRYPOINT ["/sbin/tini", "--", "/opt/agent-admin/entrypoint.sh"]
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/docker-render.bats`
Expected: all Dockerfile tests PASS.

- [ ] **Step 5: Commit**

```bash
git add docker/Dockerfile tests/docker-render.bats
git commit -m "feat(docker): add alpine-based Dockerfile with UID/GID build args"
```

---

## Task 6: Write `docker/entrypoint.sh`

**Goal:** tini-invoked entrypoint. Runs as root briefly to chown the named volume, renders the crontab, then drops to `agent` and execs either the container wizard (first run) or `start_services.sh` (steady state).

**Files:**
- Create: `docker/entrypoint.sh`
- Modify: `tests/docker-render.bats`

- [ ] **Step 1: Write the failing tests**

Append to `tests/docker-render.bats`:

```bash
@test "entrypoint.sh chowns /home/agent when owned by root" {
  content=$(< "$REPO_ROOT/docker/entrypoint.sh")
  [[ "$content" == *"chown -R agent:agent /home/agent"* ]]
}

@test "entrypoint.sh renders crontab from envsubst template" {
  content=$(< "$REPO_ROOT/docker/entrypoint.sh")
  [[ "$content" == *"envsubst"* ]]
  [[ "$content" == *"/opt/agent-admin/crontab.tpl"* ]]
  [[ "$content" == *"/etc/crontabs/agent"* ]]
}

@test "entrypoint.sh routes to wizard when .env missing TELEGRAM_BOT_TOKEN" {
  content=$(< "$REPO_ROOT/docker/entrypoint.sh")
  [[ "$content" == *"/workspace/.env"* ]]
  [[ "$content" == *"TELEGRAM_BOT_TOKEN"* ]]
  [[ "$content" == *"wizard-container.sh"* ]]
}

@test "entrypoint.sh execs start_services.sh as agent user" {
  content=$(< "$REPO_ROOT/docker/entrypoint.sh")
  [[ "$content" == *"su-exec agent"* || "$content" == *"exec su agent"* ]]
  [[ "$content" == *"start_services.sh"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/docker-render.bats`
Expected: four new tests FAIL.

- [ ] **Step 3: Create the file**

Create `docker/entrypoint.sh`:

```sh
#!/bin/sh
# Container entrypoint. Runs as root (per compose config — no `user:` key)
# so it can fix volume ownership, then drops to `agent` via su-exec.
set -eu

WORKSPACE=/workspace
AGENT_HOME=/home/agent
CRONTAB_DST=/etc/crontabs/agent

log() { printf '[entrypoint] %s\n' "$*"; }

# 1. First-run volume init: chown /home/agent if it is still root-owned.
if [ "$(stat -c %U "$AGENT_HOME")" = "root" ]; then
  log "chowning $AGENT_HOME to agent:agent (first-run volume init)"
  chown -R agent:agent "$AGENT_HOME"
fi

# 2. Render /etc/crontabs/agent from the image-baked template. Requires
#    HEARTBEAT_CRON to be available (set below from HEARTBEAT_INTERVAL).
if [ -f /opt/agent-admin/crontab.tpl ]; then
  export HEARTBEAT_CRON="${HEARTBEAT_CRON:-*/30 * * * *}"
  envsubst < /opt/agent-admin/crontab.tpl > "$CRONTAB_DST"
  chmod 0644 "$CRONTAB_DST"
  log "crontab rendered"
fi

# 3. First-run wizard check. If the workspace .env is missing, or lacks the
#    Telegram bot token, launch the interactive wizard (as agent) so the
#    operator can paste secrets without leaving the container.
ENV_FILE="$WORKSPACE/.env"
if [ ! -f "$ENV_FILE" ] || ! grep -q "^TELEGRAM_BOT_TOKEN=" "$ENV_FILE"; then
  log "first-run detected — launching wizard"
  exec su-exec agent /opt/agent-admin/scripts/wizard-container.sh
fi

# 4. Steady state: drop to agent and exec the service supervisor.
log "starting services"
exec su-exec agent /opt/agent-admin/scripts/start_services.sh
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/docker-render.bats`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add docker/entrypoint.sh tests/docker-render.bats
git commit -m "feat(docker): add container entrypoint with volume init and wizard fork"
```

---

## Task 7: Write `docker/scripts/start_services.sh`

**Goal:** Steady-state supervisor: launches crond, starts the tmux session that runs claude, watchdog loop with 5-crashes-in-5-minutes exit-to-docker-restart policy. Port the watchdog shape from `modules/agent-script-linux.sh.tpl`.

**Files:**
- Create: `docker/scripts/start_services.sh`
- Modify: `tests/docker-render.bats`

- [ ] **Step 1: Write the failing tests**

Append to `tests/docker-render.bats`:

```bash
@test "start_services.sh starts crond in background" {
  content=$(< "$REPO_ROOT/docker/scripts/start_services.sh")
  [[ "$content" == *"crond"* ]]
  [[ "$content" == *"-b"* ]]
}

@test "start_services.sh starts tmux session named 'agent'" {
  content=$(< "$REPO_ROOT/docker/scripts/start_services.sh")
  [[ "$content" == *'tmux new-session -d -s agent'* ]]
  [[ "$content" == *"CLAUDE_CONFIG_DIR=/home/agent/.claude-personal"* ]]
}

@test "start_services.sh has 5-crashes-in-5-minutes backoff" {
  content=$(< "$REPO_ROOT/docker/scripts/start_services.sh")
  [[ "$content" == *"MAX_CRASHES=5"* ]]
  [[ "$content" == *"WINDOW=300"* ]]
  [[ "$content" == *"exit 1"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/docker-render.bats`
Expected: three new tests FAIL.

- [ ] **Step 3: Create the file**

Create `docker/scripts/start_services.sh`:

```bash
#!/bin/bash
# In-container supervisor. Runs as the `agent` user (entrypoint drops privs).
# Responsibilities:
#   1. Start crond so the heartbeat fires on schedule.
#   2. Launch the persistent tmux session running claude.
#   3. Watchdog loop: respawn tmux/claude on death, exit to Docker on excessive crashes.

set -euo pipefail

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [start_services] $*"; }

# ── 1. crond ──────────────────────────────────────────────
log "starting crond"
crond -b -L /workspace/claude.cron.log

# ── 2. tmux + claude ──────────────────────────────────────
SESSION="agent"
WORKDIR="/workspace"
CLAUDE_CMD='CLAUDE_CONFIG_DIR=/home/agent/.claude-personal claude --channels plugin:telegram@claude-plugins-official'

MAX_CRASHES=5
WINDOW=300
CRASH_COUNT=0
WINDOW_START=$(date +%s)

start_session() {
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  sleep 1
  tmux new-session -d -s "$SESSION" -c "$WORKDIR" "$CLAUDE_CMD"
  tmux pipe-pane -t "$SESSION" "cat >> /workspace/claude.log"
  sleep 2
  tmux has-session -t "$SESSION" 2>/dev/null
}

claude_running() {
  tmux has-session -t "$SESSION" 2>/dev/null || return 1
  pgrep -f "claude" >/dev/null 2>&1
}

log "starting tmux session '$SESSION'"
if ! start_session; then
  log "ERROR: initial tmux session failed to start"
  exit 1
fi

# ── 3. Watchdog ───────────────────────────────────────────
while true; do
  sleep 10
  if claude_running; then
    continue
  fi

  now=$(date +%s)
  if [ $(( now - WINDOW_START )) -gt $WINDOW ]; then
    CRASH_COUNT=0
    WINDOW_START=$now
  fi
  CRASH_COUNT=$(( CRASH_COUNT + 1 ))

  if [ $CRASH_COUNT -ge $MAX_CRASHES ]; then
    log "CRITICAL: $MAX_CRASHES crashes in ${WINDOW}s — exiting for Docker to restart"
    exit 1
  fi

  log "claude died (crash $CRASH_COUNT/${MAX_CRASHES} in window) — respawning"
  start_session || log "WARN: respawn failed, will retry in 10s"
done
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/docker-render.bats`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add docker/scripts/start_services.sh tests/docker-render.bats
git commit -m "feat(docker): add in-container supervisor with tmux+claude watchdog"
```

---

## Task 8: Write `docker/scripts/wizard-container.sh`

**Goal:** First-run interactive wizard invoked when `/workspace/.env` is missing. Uses `gum` (already in the image). Prompts for Telegram bot token, chat id, optional GitHub PAT. Writes `/workspace/.env` with mode 0600 and exits — Docker's `unless-stopped` policy restarts the container, and the entrypoint's second pass will now fall through to `start_services.sh`.

**Files:**
- Create: `docker/scripts/wizard-container.sh`
- Modify: `tests/docker-render.bats`

- [ ] **Step 1: Write the failing tests**

Append to `tests/docker-render.bats`:

```bash
@test "wizard-container.sh uses gum for prompts" {
  content=$(< "$REPO_ROOT/docker/scripts/wizard-container.sh")
  [[ "$content" == *"gum input"* ]]
  [[ "$content" == *"--password"* ]]
}

@test "wizard-container.sh writes .env with 0600 permissions" {
  content=$(< "$REPO_ROOT/docker/scripts/wizard-container.sh")
  [[ "$content" == *"chmod 0600"* ]]
  [[ "$content" == *"/workspace/.env"* ]]
}

@test "wizard-container.sh exits 0 after writing so Docker restarts the container" {
  content=$(< "$REPO_ROOT/docker/scripts/wizard-container.sh")
  [[ "$content" == *"exit 0"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/docker-render.bats`
Expected: three new tests FAIL.

- [ ] **Step 3: Create the file**

Create `docker/scripts/wizard-container.sh`:

```bash
#!/bin/bash
# In-container first-run wizard. Collects secrets the host wizard refused to
# touch (Telegram bot token, GitHub PAT), writes them to /workspace/.env with
# mode 0600, and exits so `unless-stopped` restarts the container into its
# steady state.
set -euo pipefail

ENV_FILE="/workspace/.env"

echo ""
echo "╭──────────────────────────────────────────────╮"
echo "│ First-run setup for your dockerized agent    │"
echo "│ (values are written to /workspace/.env 0600) │"
echo "╰──────────────────────────────────────────────╯"
echo ""

# Telegram — required for the agent to be reachable.
BOT=$(gum input --password --prompt "Telegram bot token (from @BotFather): ")
CHAT=$(gum input --prompt "Your Telegram chat id (from @userinfobot): ")

# GitHub PAT — optional. Gum returns empty on skip.
if gum confirm "Add a GitHub Personal Access Token (for gh / MCP)?" --default=no; then
  GH_PAT=$(gum input --password --prompt "GitHub PAT: ")
else
  GH_PAT=""
fi

umask 077
{
  echo "# Generated by docker/scripts/wizard-container.sh on $(date '+%Y-%m-%d %H:%M:%S')"
  echo "# NEVER commit this file."
  echo
  echo "TELEGRAM_BOT_TOKEN=${BOT}"
  echo "TELEGRAM_CHAT_ID=${CHAT}"
  [ -n "$GH_PAT" ] && echo "GITHUB_PAT=${GH_PAT}"
} > "$ENV_FILE"
chmod 0600 "$ENV_FILE"

echo ""
echo "✓ /workspace/.env written. Exiting — Docker will restart into steady state."
exit 0
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/docker-render.bats`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add docker/scripts/wizard-container.sh tests/docker-render.bats
git commit -m "feat(docker): add in-container first-run wizard for secrets"
```

---

## Task 9: Add `--docker` flag parsing to `setup.sh`

**Goal:** Introduce a `--docker` flag that only affects parsing; no behavior yet. This isolates flag-plumbing from downstream logic changes.

**Files:**
- Modify: `setup.sh` (around `parse_args` and `print_usage`, lines 104-169)
- Create: `tests/docker-setup.bats`

- [ ] **Step 1: Write the failing test**

Create `tests/docker-setup.bats`:

```bash
#!/usr/bin/env bats

load helper

setup() { setup_tmp_dir; }
teardown() { teardown_tmp_dir; }

@test "setup.sh --help lists --docker flag" {
  run "$REPO_ROOT/setup.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--docker"* ]]
}

@test "setup.sh --docker --help coexists (flag is parsed, not rejected)" {
  run "$REPO_ROOT/setup.sh" --docker --help
  [ "$status" -eq 0 ]
  [[ "$output" != *"Unknown option"* ]]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/docker-setup.bats`
Expected: both tests FAIL.

- [ ] **Step 3: Modify `setup.sh`**

Edit `setup.sh`. After line 110 (`IN_PLACE=false`), add:

```bash
MODE_DOCKER=false
```

In `print_usage` (around line 139), add between `--in-place` and `--help`:

```
  --docker             Scaffold a containerized agent (Docker + compose + host
                       systemd unit wrapping `docker compose up -d`) instead
                       of running claude directly on the host.
```

In `parse_args` (around line 164), add a new case branch before the wildcard:

```bash
      --docker) MODE_DOCKER=true; shift ;;
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats tests/docker-setup.bats`
Expected: both tests PASS.

- [ ] **Step 5: Commit**

```bash
git add setup.sh tests/docker-setup.bats
git commit -m "feat(docker): add --docker flag parsing to setup.sh"
```

---

## Task 10: Host wizard defers secrets when `--docker` is set

**Goal:** In `run_wizard`, when `MODE_DOCKER=true`, skip the Telegram bot token / chat id prompts and the GitHub PAT prompt; write `deployment.mode: docker` plus a `docker:` section to `agent.yml`.

**Files:**
- Modify: `setup.sh` (`run_wizard`, lines 318-347 for notifications; 376-381 for GitHub; 514-557 for agent.yml heredoc)
- Modify: `tests/docker-setup.bats`

- [ ] **Step 1: Write the failing test**

Append to `tests/docker-setup.bats`:

```bash
# Helper: run wizard piping answers through stdin, with --docker flag.
run_docker_wizard() {
  local dest="$1"
  cp -r "$REPO_ROOT/scripts" "$REPO_ROOT/modules" "$REPO_ROOT/docker" "$TMP_TEST_DIR/installer/"
  cp "$REPO_ROOT/setup.sh" "$TMP_TEST_DIR/installer/"
  cd "$TMP_TEST_DIR/installer"
  # Answers: name, display, role, vibe, user_name, nick, tz, email, lang,
  # host, destination, install_service, fork=n, heartbeat yes, interval, prompt,
  # defaults yes, atlassian=n, github=n, proceed.
  ./setup.sh --docker --destination "$dest" <<EOF
dockbot
DockBot
r
v
Alice
Alice
UTC
a@b.com
en
host
n
n
y
30m
ok
y
n
n
proceed
EOF
}

@test "--docker wizard does not prompt for Telegram secrets" {
  mkdir -p "$TMP_TEST_DIR/installer"
  local dest="$TMP_TEST_DIR/docker-agent"
  run run_docker_wizard "$dest"
  [ "$status" -eq 0 ]
  # .env must NOT contain secrets — those are deferred to container wizard.
  [ -f "$dest/.env" ]
  ! grep -q "^TELEGRAM_BOT_TOKEN=" "$dest/.env"
  ! grep -q "^NOTIFY_BOT_TOKEN=.\+" "$dest/.env"
}

@test "--docker wizard writes deployment.mode=docker and docker.* in agent.yml" {
  mkdir -p "$TMP_TEST_DIR/installer"
  local dest="$TMP_TEST_DIR/docker-agent-yml"
  run run_docker_wizard "$dest"
  [ "$status" -eq 0 ]
  [ -f "$dest/agent.yml" ]
  [ "$(yq '.deployment.mode' "$dest/agent.yml")" = "docker" ]
  [ "$(yq '.docker.uid' "$dest/agent.yml")" = "$(id -u)" ]
  [ "$(yq '.docker.gid' "$dest/agent.yml")" = "$(id -g)" ]
  [ "$(yq '.docker.state_volume' "$dest/agent.yml")" = "dockbot-state" ]
  [ "$(yq '.docker.image_tag' "$dest/agent.yml")" = "agent-admin:latest" ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/docker-setup.bats`
Expected: two new tests FAIL.

- [ ] **Step 3: Modify `setup.sh`**

In `run_wizard`, wrap the Telegram credential block (lines 329-346) with a docker check. Replace:

```bash
  local notify_channel notify_bot_token="" notify_chat_id=""
  notify_channel=$(ask_choice "Heartbeat notification channel" "none" "none log telegram")
  if [ "$notify_channel" = "telegram" ]; then
    echo "  Heartbeat will use a dedicated bot (separate from the chat plugin)."
    echo "  Create it at @BotFather and copy its token."
    echo "  (Press Enter to skip — fill NOTIFY_BOT_TOKEN in .env later.)"
    notify_bot_token=$(ask_secret "Heartbeat bot token (or skip)")
    echo "  Message @userinfobot to get your chat ID (numeric, like 5616135342)."
    echo "  (Press Enter to skip — fill NOTIFY_CHAT_ID in .env later.)"
    notify_chat_id=$(ask "Chat ID (or skip)" "")
    if [ -z "$notify_bot_token" ] || [ -z "$notify_chat_id" ]; then
      echo ""
      echo "  ⚠  Telegram credentials incomplete — heartbeat pings are disabled"
      echo "     until you fill the missing value(s) in .env:"
      [ -z "$notify_bot_token" ] && echo "       NOTIFY_BOT_TOKEN=..."
      [ -z "$notify_chat_id" ]   && echo "       NOTIFY_CHAT_ID=..."
    fi
  fi
```

with:

```bash
  local notify_channel notify_bot_token="" notify_chat_id=""
  notify_channel=$(ask_choice "Heartbeat notification channel" "none" "none log telegram")
  if [ "$notify_channel" = "telegram" ]; then
    if [ "$MODE_DOCKER" = true ]; then
      echo "  Docker mode: Telegram credentials will be collected inside the container"
      echo "  on first boot. Skipping token/chat_id prompts here."
    else
      echo "  Heartbeat will use a dedicated bot (separate from the chat plugin)."
      echo "  Create it at @BotFather and copy its token."
      echo "  (Press Enter to skip — fill NOTIFY_BOT_TOKEN in .env later.)"
      notify_bot_token=$(ask_secret "Heartbeat bot token (or skip)")
      echo "  Message @userinfobot to get your chat ID (numeric, like 5616135342)."
      echo "  (Press Enter to skip — fill NOTIFY_CHAT_ID in .env later.)"
      notify_chat_id=$(ask "Chat ID (or skip)" "")
      if [ -z "$notify_bot_token" ] || [ -z "$notify_chat_id" ]; then
        echo ""
        echo "  ⚠  Telegram credentials incomplete — heartbeat pings are disabled"
        echo "     until you fill the missing value(s) in .env:"
        [ -z "$notify_bot_token" ] && echo "       NOTIFY_BOT_TOKEN=..."
        [ -z "$notify_chat_id" ]   && echo "       NOTIFY_CHAT_ID=..."
      fi
    fi
  fi
```

Wrap the GitHub PAT ask (lines 376-381) similarly. Replace:

```bash
  if [ "$(ask_yn 'Enable GitHub MCP?' 'n')" = "true" ]; then
    github_enabled="true"
    github_email=$(ask "GitHub account email" "$user_email")
    github_pat=$(ask_secret "GitHub Personal Access Token")
  fi
```

with:

```bash
  if [ "$(ask_yn 'Enable GitHub MCP?' 'n')" = "true" ]; then
    github_enabled="true"
    github_email=$(ask "GitHub account email" "$user_email")
    if [ "$MODE_DOCKER" = true ]; then
      echo "  Docker mode: PAT collected inside container on first boot."
    else
      github_pat=$(ask_secret "GitHub Personal Access Token")
    fi
  fi
```

In the `agent.yml` heredoc (starting at line 496), after the `deployment:` block (line 518) inject a `mode` field and after the `claude:` block add a `docker:` block. Replace:

```bash
deployment:
  host: "$deploy_host"
  workspace: "$deploy_ws"
  install_service: $deploy_svc
  claude_cli: "$(detect_claude_cli)"
```

with:

```bash
deployment:
  host: "$deploy_host"
  workspace: "$deploy_ws"
  mode: $([ "$MODE_DOCKER" = true ] && echo "docker" || echo "host")
  install_service: $deploy_svc
  claude_cli: "$(detect_claude_cli)"
```

And after the existing `claude:` block (line 523), inject:

```bash
$(if [ "$MODE_DOCKER" = true ]; then cat <<DOCKER_BLOCK

docker:
  image_tag: "agent-admin:latest"
  uid: $(id -u)
  gid: $(id -g)
  state_volume: "${agent_name}-state"
  base_image: "alpine:3.20"
DOCKER_BLOCK
fi)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/docker-setup.bats`
Expected: all docker-setup tests PASS.

- [ ] **Step 5: Commit**

```bash
git add setup.sh tests/docker-setup.bats
git commit -m "feat(docker): defer secret prompts to container and emit docker.* in agent.yml"
```

---

## Task 11: `regenerate` branches on `deployment.mode`

**Goal:** When `deployment.mode=docker`, render `docker-compose.yml`, copy the `docker/` directory into the destination (so the build context lives next to compose), and skip the host `agent-script-*.sh` / user systemd / launchd rendering. Keep rendering: `CLAUDE.md`, `.mcp.json`, `.env.example`, `heartbeat.conf`.

**Files:**
- Modify: `setup.sh` (`regenerate`, lines 900-990; `scaffold_destination`, lines 815-898; `install_service`, lines 992-1021)
- Modify: `tests/docker-setup.bats`

- [ ] **Step 1: Write the failing tests**

Append to `tests/docker-setup.bats`:

```bash
@test "--docker scaffold copies docker/ directory into destination" {
  mkdir -p "$TMP_TEST_DIR/installer"
  local dest="$TMP_TEST_DIR/docker-scaffold"
  run run_docker_wizard "$dest"
  [ "$status" -eq 0 ]
  [ -d "$dest/docker" ]
  [ -f "$dest/docker/Dockerfile" ]
  [ -f "$dest/docker/entrypoint.sh" ]
  [ -x "$dest/docker/entrypoint.sh" ]
  [ -f "$dest/docker/scripts/start_services.sh" ]
}

@test "--docker scaffold writes docker-compose.yml at workspace root" {
  mkdir -p "$TMP_TEST_DIR/installer"
  local dest="$TMP_TEST_DIR/docker-compose-out"
  run run_docker_wizard "$dest"
  [ "$status" -eq 0 ]
  [ -f "$dest/docker-compose.yml" ]
  grep -q "dockbot:" "$dest/docker-compose.yml"
  grep -q "dockbot-state:" "$dest/docker-compose.yml"
}

@test "--docker scaffold does NOT render agent-script-*.sh on host" {
  mkdir -p "$TMP_TEST_DIR/installer"
  local dest="$TMP_TEST_DIR/docker-no-host-launcher"
  run run_docker_wizard "$dest"
  [ "$status" -eq 0 ]
  # No user-level systemd unit in docker mode.
  [ ! -f "$HOME/.config/systemd/user/dockbot.service" ]
  [ ! -f "$HOME/Library/LaunchAgents/local.dockbot.plist" ]
  [ ! -f "$HOME/.local/bin/dockbot.sh" ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/docker-setup.bats`
Expected: three new tests FAIL.

- [ ] **Step 3: Modify `scaffold_destination` to copy `docker/`**

In `scaffold_destination` (line 859), change:

```bash
  for item in modules scripts; do
    [ -d "$src_dir/$item" ] && cp -R "$src_dir/$item" "$dest/"
  done
```

to:

```bash
  for item in modules scripts docker; do
    [ -d "$src_dir/$item" ] && cp -R "$src_dir/$item" "$dest/"
  done
```

And after the `chmod +x` block (line 864), ensure docker scripts are executable:

```bash
  if [ -d "$dest/docker" ]; then
    find "$dest/docker" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
  fi
```

- [ ] **Step 4: Modify `regenerate` to branch on mode**

In `regenerate`, after the `.env.example` render (around line 975) insert:

```bash
  # Docker mode: render docker-compose.yml and optionally the host systemd
  # unit; skip the host-side launcher scripts.
  if [ "${DEPLOYMENT_MODE:-host}" = "docker" ]; then
    render_to_file "$modules_dir/docker-compose.yml.tpl" "$SCRIPT_DIR/docker-compose.yml"
    echo "  ✓ docker-compose.yml"
  fi
```

Replace the host service install block (lines 983-985):

```bash
  if [ "${DEPLOYMENT_INSTALL_SERVICE:-false}" = "true" ]; then
    install_service "$os" "$agent_name" "$workspace"
  fi
```

with:

```bash
  if [ "${DEPLOYMENT_INSTALL_SERVICE:-false}" = "true" ]; then
    if [ "${DEPLOYMENT_MODE:-host}" = "docker" ]; then
      install_service_docker "$agent_name" "$workspace"
    else
      install_service "$os" "$agent_name" "$workspace"
    fi
  fi
```

Add a new function right after `install_service` (line 1021):

```bash
# Docker mode: render a system-wide systemd unit that wraps `docker compose up -d`.
# This requires sudo to install; if the user did not grant it, we print the
# rendered file and instructions for a manual install.
install_service_docker() {
  local agent_name="$1" workspace="$2"
  local modules_dir="$SCRIPT_DIR/modules"
  local unit_file="/etc/systemd/system/agent-${agent_name}.service"
  local staged
  staged=$(mktemp)
  render_to_file "$modules_dir/systemd-host-docker.service.tpl" "$staged"

  if sudo -n true 2>/dev/null; then
    sudo cp "$staged" "$unit_file"
    sudo systemctl daemon-reload
    echo "  ✓ $unit_file"
    echo "  → enable with: sudo systemctl enable --now agent-${agent_name}.service"
  else
    cp "$staged" "$SCRIPT_DIR/agent-${agent_name}.service"
    echo "  ◦ agent-${agent_name}.service staged in workspace (sudo unavailable)"
    echo "    install manually: sudo cp ./agent-${agent_name}.service ${unit_file}"
    echo "                      sudo systemctl daemon-reload && sudo systemctl enable --now agent-${agent_name}.service"
  fi
  rm -f "$staged"
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bats tests/docker-setup.bats`
Expected: all docker-setup tests PASS.

- [ ] **Step 6: Commit**

```bash
git add setup.sh tests/docker-setup.bats
git commit -m "feat(docker): render docker-compose and host unit in regenerate; skip host launcher"
```

---

## Task 12: Uninstall branches on `deployment.mode`

**Goal:** `./setup.sh --uninstall` in a docker-mode workspace runs `docker compose down -v` (removing the named state volume) and removes `/etc/systemd/system/agent-<name>.service`. With `--nuke`, also deletes the workspace.

**Files:**
- Modify: `setup.sh` (`uninstall`, lines 1042-1240)
- Modify: `tests/docker-setup.bats`

- [ ] **Step 1: Write the failing test**

Append to `tests/docker-setup.bats`:

```bash
@test "--uninstall in docker-mode workspace runs docker compose down -v (dry)" {
  mkdir -p "$TMP_TEST_DIR/installer"
  local dest="$TMP_TEST_DIR/docker-uninstall"
  run run_docker_wizard "$dest"
  [ "$status" -eq 0 ]

  # Stub docker so the test does not need a daemon. Record invocations.
  mkdir -p "$TMP_TEST_DIR/bin"
  cat > "$TMP_TEST_DIR/bin/docker" <<'STUB'
#!/bin/bash
echo "$@" >> "$TMP_TEST_DIR/docker-calls.log"
exit 0
STUB
  chmod +x "$TMP_TEST_DIR/bin/docker"
  export PATH="$TMP_TEST_DIR/bin:$PATH"

  cd "$dest"
  run ./setup.sh --uninstall --yes
  [ "$status" -eq 0 ]
  grep -q "compose down -v" "$TMP_TEST_DIR/docker-calls.log"
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/docker-setup.bats`
Expected: FAIL (uninstall currently uses host-only cleanup).

- [ ] **Step 3: Modify `uninstall`**

At the start of `uninstall` — right after `render_load_context "$agent_yml"` (line 1064) — read the mode:

```bash
  local mode="${DEPLOYMENT_MODE:-host}"
```

In the "This will remove" echo block (lines 1080-1095), branch on `mode`:

```bash
  case "$mode" in
    docker)
      echo "  - docker compose down -v (stops container, removes ${agent_name}-state volume)"
      echo "  - /etc/systemd/system/agent-${agent_name}.service (if present)"
      ;;
    *)
      # existing host-mode listing unchanged
      ;;
  esac
```

In the "Stopping services" block (lines 1119-1165), add a docker branch before the existing `case "$os"`:

```bash
  if [ "$mode" = "docker" ]; then
    if command -v docker &>/dev/null; then
      (cd "$SCRIPT_DIR" && docker compose down -v 2>/dev/null) && \
        echo "  ✓ docker compose down -v (container + state volume removed)" || \
        echo "  ⚠ docker compose down -v failed or already down"
    else
      echo "  ⚠ docker not on PATH — skipping container teardown"
    fi
    local unit_file="/etc/systemd/system/agent-${agent_name}.service"
    if [ -f "$unit_file" ]; then
      if sudo -n true 2>/dev/null; then
        sudo systemctl disable --now "agent-${agent_name}.service" 2>/dev/null || true
        sudo rm -f "$unit_file" && echo "  ✓ removed $unit_file" || true
        sudo systemctl daemon-reload 2>/dev/null || true
      else
        echo "  ◦ $unit_file present — remove manually with sudo"
      fi
    fi
    rm -f "$SCRIPT_DIR/docker-compose.yml" && echo "  ✓ docker-compose.yml" || true
  else
    # existing host-mode cleanup (the original `case "$os"`)
    ...
  fi
```

Wrap the original `case "$os" in linux) ... darwin) ... esac` (lines 1126-1165) inside the `else` branch of the docker check.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/docker-setup.bats`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add setup.sh tests/docker-setup.bats
git commit -m "feat(docker): teardown via docker compose down -v and host unit removal"
```

---

## Task 13: Non-interactive render path for `--regenerate` in docker mode

**Goal:** `./setup.sh --regenerate` (no wizard) in a scaffolded docker workspace re-renders `docker-compose.yml` without touching `.env` or `CLAUDE.md`. This is mostly proving Task 11's branching also fires through the non-wizard entry path.

**Files:**
- Modify: `tests/docker-setup.bats` (no code change expected — verification test)

- [ ] **Step 1: Write the failing test**

Append to `tests/docker-setup.bats`:

```bash
@test "--regenerate in docker-mode workspace re-renders docker-compose.yml" {
  mkdir -p "$TMP_TEST_DIR/installer"
  local dest="$TMP_TEST_DIR/docker-regen"
  run run_docker_wizard "$dest"
  [ "$status" -eq 0 ]
  rm "$dest/docker-compose.yml"
  [ ! -f "$dest/docker-compose.yml" ]

  cd "$dest"
  run ./setup.sh --regenerate
  [ "$status" -eq 0 ]
  [ -f "$dest/docker-compose.yml" ]
  grep -q "dockbot:" "$dest/docker-compose.yml"
}
```

- [ ] **Step 2: Run the test**

Run: `bats tests/docker-setup.bats`
Expected: PASS if Task 11 was implemented correctly. If it fails, the docker branch in `regenerate` is gated incorrectly; fix and re-run.

- [ ] **Step 3: Commit (if any fix was needed)**

```bash
git add setup.sh tests/docker-setup.bats
git commit -m "test(docker): verify --regenerate reproduces docker-compose.yml"
```

If no code change was required, commit only the new test:

```bash
git add tests/docker-setup.bats
git commit -m "test(docker): cover --regenerate for docker-mode workspace"
```

---

## Task 14: E2E smoke test (opt-in via `DOCKER_E2E=1`)

**Goal:** A single bats file that drives the full happy path against a real docker daemon. Skipped by default so CI without docker still passes.

**Files:**
- Create: `tests/docker-e2e-smoke.bats`

- [ ] **Step 1: Write the test**

Create `tests/docker-e2e-smoke.bats`:

```bash
#!/usr/bin/env bats

load helper

setup() {
  if [ "${DOCKER_E2E:-0}" != "1" ]; then
    skip "set DOCKER_E2E=1 to run (requires a working docker daemon)"
  fi
  command -v docker >/dev/null 2>&1 || skip "docker not on PATH"
  docker info >/dev/null 2>&1 || skip "docker daemon not reachable"
  setup_tmp_dir
  mkdir -p "$TMP_TEST_DIR/installer"
  cp -r "$REPO_ROOT/scripts" "$REPO_ROOT/modules" "$REPO_ROOT/docker" "$TMP_TEST_DIR/installer/"
  cp "$REPO_ROOT/setup.sh" "$TMP_TEST_DIR/installer/"
  [ -f "$REPO_ROOT/.gitignore" ] && cp "$REPO_ROOT/.gitignore" "$TMP_TEST_DIR/installer/"
  [ -f "$REPO_ROOT/LICENSE" ] && cp "$REPO_ROOT/LICENSE" "$TMP_TEST_DIR/installer/"
}

teardown() {
  if [ -n "${E2E_AGENT_DIR:-}" ] && [ -d "$E2E_AGENT_DIR" ]; then
    (cd "$E2E_AGENT_DIR" && docker compose down -v 2>/dev/null || true)
  fi
  teardown_tmp_dir
}

@test "E2E: scaffold + build + up + healthcheck" {
  E2E_AGENT_DIR="$TMP_TEST_DIR/e2e-agent"
  export E2E_AGENT_DIR

  cd "$TMP_TEST_DIR/installer"
  ./setup.sh --docker --destination "$E2E_AGENT_DIR" <<EOF
e2ebot
E2EBot
r
v
Alice
Alice
UTC
a@b.com
en
host
n
n
y
30m
ok
y
n
n
proceed
EOF

  [ -f "$E2E_AGENT_DIR/docker-compose.yml" ]

  # Pre-seed .env so the container skips the wizard and goes straight to steady state.
  cat > "$E2E_AGENT_DIR/.env" <<'ENV'
TELEGRAM_BOT_TOKEN=00000:fake
TELEGRAM_CHAT_ID=0
ENV
  chmod 0600 "$E2E_AGENT_DIR/.env"

  cd "$E2E_AGENT_DIR"
  run docker compose build
  [ "$status" -eq 0 ]

  run docker compose up -d
  [ "$status" -eq 0 ]

  # Wait up to 30s for the container to be running.
  local i=0
  while [ $i -lt 30 ]; do
    if docker inspect --format '{{.State.Running}}' e2ebot 2>/dev/null | grep -q "true"; then
      break
    fi
    sleep 1
    i=$((i+1))
  done
  [ "$(docker inspect --format '{{.State.Running}}' e2ebot)" = "true" ]

  # Named volume exists and is owned by our UID.
  run docker volume inspect e2ebot-state
  [ "$status" -eq 0 ]

  # Tmux session eventually comes up (claude may fail without real credentials,
  # which is fine — the session is what we care about in the smoke).
  i=0
  while [ $i -lt 20 ]; do
    if docker exec e2ebot tmux has-session -t agent 2>/dev/null; then
      break
    fi
    sleep 1
    i=$((i+1))
  done
  run docker exec e2ebot tmux has-session -t agent
  [ "$status" -eq 0 ]

  # Teardown: down -v must leave no container and no volume.
  docker compose down -v
  ! docker inspect e2ebot 2>/dev/null
  ! docker volume inspect e2ebot-state 2>/dev/null
}
```

- [ ] **Step 2: Run the test (skipped by default)**

Run: `bats tests/docker-e2e-smoke.bats`
Expected: one test SKIPPED (because `DOCKER_E2E` is unset).

- [ ] **Step 3: Run with docker (optional local verification)**

Run: `DOCKER_E2E=1 bats tests/docker-e2e-smoke.bats`
Expected (on a host with docker): PASS. Allow up to ~3 minutes for the first build (npm install of the Claude CLI dominates).

- [ ] **Step 4: Commit**

```bash
git add tests/docker-e2e-smoke.bats
git commit -m "test(docker): add opt-in E2E smoke covering build/up/tmux/teardown"
```

---

## Task 15: Documentation

**Goal:** Ship three docs so operators can use, understand, and extend docker mode without reading setup.sh.

**Files:**
- Create: `docs/docker-mode.md`
- Create: `docs/docker-architecture.md`
- Create: `docs/adding-an-mcp-docker.md`

- [ ] **Step 1: Write `docs/docker-mode.md`**

Create `docs/docker-mode.md` with these sections:

1. **When to use docker mode** — brief (1 para): "use `--docker` when you want teardown to be `docker rm -v && rm -rf <workspace>` with no host residue". Link to architecture doc.
2. **Prerequisites** — docker v24+, docker compose v2, enough disk (~2GB for image + state volume).
3. **Scaffold** — code block: `./setup.sh --docker` walkthrough; show wizard skipping Telegram prompts.
4. **First boot** — `cd ~/agents/<name> && docker compose up -d && docker attach <name>` → wizard fires → fill tokens → container restarts into steady state.
5. **Daily use** — `ssh <host>; docker exec -it <name> tmux attach -t agent`; Ctrl-b d to detach.
6. **Upgrade** — template `git pull` → `docker compose build` → `up -d`. Note `docker tag <name>:latest <name>:prev` for rollback.
7. **Rotating secrets** — edit `~/agents/<name>/.env`, `docker compose restart`.
8. **Teardown** — `./setup.sh --uninstall --yes` (runs `docker compose down -v`), add `--nuke` to delete the workspace.
9. **Troubleshooting** — common failures: `chown` loop if UID mismatch (check `docker.uid` in `agent.yml`); `crond` silent (check `/workspace/claude.cron.log`); wizard re-fires after reboot (workspace `.env` deleted or corrupted).

- [ ] **Step 2: Write `docs/docker-architecture.md`**

Create `docs/docker-architecture.md` — mirror the spec's §3 diagram (host/container/volume layout + process tree) and §4 lifecycle. Link back to the spec for rationale.

- [ ] **Step 3: Write `docs/adding-an-mcp-docker.md`**

Create `docs/adding-an-mcp-docker.md`. Points to cover:

- MCP paths inside the container: workspace files are at `/workspace/...`, home-scope config at `/home/agent/.claude-personal/...`.
- alpine musl caveat: any MCP whose native binary expects glibc (e.g. old sqlite bindings) needs the `debian:13-slim` variant image — document the knob (change `docker.base_image` in `agent.yml`, adjust Dockerfile to accept the arg).
- Environment variables flow from `/workspace/.env` via `env_file` in compose, not via `docker run -e`.
- Link to `docs/adding-an-mcp.md` for the template side (modules/mcp-json.tpl is unchanged — the same entries work inside the container).

- [ ] **Step 4: Commit**

```bash
git add docs/docker-mode.md docs/docker-architecture.md docs/adding-an-mcp-docker.md
git commit -m "docs(docker): add user guide, architecture reference, and MCP notes"
```

---

## Task 16: Update `README.md` and top-level docs pointers

**Goal:** Make docker mode discoverable from the entry points.

**Files:**
- Modify: `README.md` (add a short paragraph + link to `docs/docker-mode.md`)
- Modify: `docs/architecture.md` (add one-line pointer to `docs/docker-architecture.md`)

- [ ] **Step 1: Edit `README.md`**

Add a new section just above the "Features" or equivalent, titled `### Docker mode (optional)`, with:

> For a portable, self-contained deployment, scaffold with `./setup.sh --docker`. The agent runs in an alpine container, with its workspace bind-mounted and all internal state on a single named volume. See [docs/docker-mode.md](docs/docker-mode.md) for setup, upgrade, and teardown.

- [ ] **Step 2: Edit `docs/architecture.md`**

Append a single line at the end, under a new `## See also` heading if not present:

> - [Docker mode architecture](docker-architecture.md) — containerized deployment variant.

- [ ] **Step 3: Run the full test suite to verify no regressions**

Run: `bats tests/`
Expected: all existing tests still PASS. All docker-* tests PASS. E2E smoke SKIPPED (unless `DOCKER_E2E=1`).

- [ ] **Step 4: Commit**

```bash
git add README.md docs/architecture.md
git commit -m "docs: surface docker mode from README and architecture index"
```

---

## Post-plan verification checklist

Before opening the PR, run from the repo root:

1. `bats tests/` — full suite green (E2E skipped).
2. `shellcheck setup.sh scripts/lib/*.sh scripts/heartbeat/*.sh docker/*.sh docker/scripts/*.sh` — no new warnings beyond pre-existing.
3. Spot-check: `./setup.sh --help` lists `--docker`.
4. Local smoke (if docker available): `DOCKER_E2E=1 bats tests/docker-e2e-smoke.bats` on one host.
5. Regenerate test on an existing host-mode agent still works (`cd <host-agent> && ./setup.sh --regenerate`) — proves we did not break the default path.

---

## Spec coverage self-review

Mapping every spec section to the tasks that implement it:

| Spec § | Coverage |
|---|---|
| §2 Decisions — 1 container / agent | Task 2 (compose `container_name`), Task 5 (Dockerfile) |
| §2 Hybrid wizard | Task 10 (host side), Task 8 (container side) |
| §2 Heartbeat inside container | Task 4 (crontab.tpl), Task 6 (entrypoint.sh renders it), Task 7 (crond in start_services.sh) |
| §2 Cloudflared stays on host | Intentionally out of scope — no changes |
| §2 Bind-mount + named volume | Task 2 (compose volumes), Task 6 (entrypoint chown) |
| §2 alpine:3.20 | Task 5 |
| §2 UID build-arg | Task 5 (Dockerfile args), Task 10 (wizard writes `docker.uid`), Task 2 (compose injects) |
| §2 Bash watchdog supervisor | Task 7 |
| §2 tini PID 1 | Task 5 (apk add tini), Task 5 (ENTRYPOINT) |
| §2 restart: unless-stopped | Task 2 |
| §2 .env 0600 | Task 8 (container wizard chmod), Task 2 (compose env_file reference) |
| §2 Capabilities drop/add | Task 2 |
| §3.1 Layout | Task 2 (compose), Task 5 (Dockerfile), Task 6 (entrypoint paths) |
| §3.2 Process tree | Task 7 |
| §3.3 Repo integration | Tasks 2/3/5/6/7/8/11 + Task 14 E2E |
| §4.1 Scaffold phase | Tasks 9, 10, 11 |
| §4.2 First-run wizard | Task 6 (entrypoint routing) + Task 8 (wizard body) |
| §4.3 Steady state | Task 7 |
| §4.4 Restart layers | Task 7 (watchdog) + Task 2 (unless-stopped) + Task 11 (host unit) |
| §4.5 Connect to session | Task 15 (docs) |
| §4.6 Upgrade/rollback | Task 15 (docs) |
| §4.7 Teardown | Task 12 |
| §5.1 UID/GID matching | Task 5, Task 10 |
| §5.2 Volume init | Task 6 |
| §5.3 Compose hardening | Task 2 |
| §5.4 Network | Task 2 (no `ports:`; no socket bind) |
| §6 Error matrix | Task 7 (watchdog), Task 2 (unless-stopped), Task 11 (systemd), Task 6 (entrypoint checks) |
| §7.1 Unit tests | Tasks 2–8 bats coverage |
| §7.2 Setup tests | Tasks 9–13 |
| §7.3 E2E smoke | Task 14 |
| §7.4 Manual smoke docs | Task 15 |
| §8 Open questions | Out of scope; documented in docs/docker-mode.md troubleshooting and `adding-an-mcp-docker.md` |

No spec gaps identified.

---

## Execution handoff

Plan complete. Two execution options:

1. **Subagent-Driven (recommended)** — one fresh subagent per task, human review between tasks.
2. **Inline Execution** — execute in the current session with checkpoints after Tasks 4, 8, 12, 15.

Pick one to proceed.
