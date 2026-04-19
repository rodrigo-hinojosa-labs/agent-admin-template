#!/bin/bash
# In-container supervisor. Runs as the `agent` user (entrypoint drops privs).
# Responsibilities:
#   1. Start crond so the heartbeat fires on schedule.
#   2. Before each claude launch, try to auto-install the required plugins
#      (idempotent; silently no-ops if the user hasn't /login'd yet).
#   3. Launch the persistent tmux session running claude. Enable `--channels`
#      only if the channel plugin is actually present; otherwise the plugin
#      MCP server would error at startup and spam the watchdog.
#   4. Watchdog loop: respawn tmux/claude on death, exit to Docker on
#      excessive crashes. Post-login, the first respawn auto-installs the
#      plugin and the second respawn attaches --channels.

set -euo pipefail

# Always write logs to stderr so functions that `echo` a value for
# capture (e.g. build_claude_cmd via $(...)) aren't polluted.
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [start_services] $*" >&2; }

# ── 1. crond ──────────────────────────────────────────────
log "starting crond"
crond -b -L /workspace/claude.cron.log

# ── 2. Config ─────────────────────────────────────────────
SESSION="agent"
WORKDIR="/workspace"
CLAUDE_CONFIG_DIR_VAL="/home/agent/.claude"
REQUIRED_CHANNEL_PLUGIN="telegram@claude-plugins-official"

MAX_CRASHES=5
WINDOW=300
CRASH_COUNT=0
WINDOW_START=$(date +%s)

# ── 3. Plugin auto-install ────────────────────────────────
# `claude plugin install` requires an authenticated profile. On first boot
# (before the user runs /login inside tmux) it will fail — that's fine; we
# swallow the error and launch claude without --channels so the user can
# actually get through /login. On the next watchdog respawn (after /login),
# the install succeeds and --channels attaches automatically.
plugin_cache_dir_for() {
  # telegram@claude-plugins-official → /home/agent/.claude/plugins/cache/claude-plugins-official/telegram
  local spec="$1"
  local name="${spec%@*}"
  local marketplace="${spec#*@}"
  echo "$HOME/.claude/plugins/cache/$marketplace/$name"
}

ensure_plugin_installed() {
  local spec="$1"
  local cache
  cache=$(plugin_cache_dir_for "$spec")
  if [ -d "$cache" ]; then
    return 0
  fi
  log "attempting to install plugin: $spec"
  if CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR_VAL" claude plugin install "$spec" >/dev/null 2>&1; then
    log "plugin installed: $spec"
    return 0
  fi
  log "plugin install skipped (not authenticated yet or install failed): $spec"
  return 1
}

# Channel plugins (e.g. telegram) read their bot token from a channel-
# scoped .env at ~/.claude/channels/<channel>/.env — not from the
# workspace .env. Sync it on demand so the user never has to run
# `/telegram:configure <token>` manually.
ensure_channel_env_synced() {
  local channel="$1"
  local workspace_key="$2"
  local channel_env="$HOME/.claude/channels/${channel}/.env"

  if [ -f "$channel_env" ] && grep -q "^${workspace_key}=" "$channel_env" 2>/dev/null; then
    return 0
  fi

  local token
  token=$(grep "^${workspace_key}=" /workspace/.env 2>/dev/null | head -1 | cut -d= -f2-)
  [ -z "$token" ] && return 1

  mkdir -p "$(dirname "$channel_env")"
  umask 077
  if [ -f "$channel_env" ]; then
    # Preserve other lines, replace/add the target key.
    if grep -q "^${workspace_key}=" "$channel_env"; then
      sed -i "s|^${workspace_key}=.*|${workspace_key}=${token}|" "$channel_env"
    else
      echo "${workspace_key}=${token}" >> "$channel_env"
    fi
  else
    echo "${workspace_key}=${token}" > "$channel_env"
  fi
  chmod 0600 "$channel_env"
  log "synced ${workspace_key} from /workspace/.env → ${channel_env}"
}

# ── 4. Launch-decision helpers ────────────────────────────
# Whether /workspace/.env contains a non-empty TELEGRAM_BOT_TOKEN.
has_telegram_token() {
  [ -f /workspace/.env ] || return 1
  local val
  val=$(grep "^TELEGRAM_BOT_TOKEN=" /workspace/.env 2>/dev/null | head -1 | cut -d= -f2-)
  [ -n "$val" ]
}

# Build the next tmux command based on current state. Three cases:
#   A. Not authenticated → bare `claude` so the user can `/login`.
#   B. Authenticated, no Telegram bot token yet → interactive wizard to
#      collect it. Writes /workspace/.env then exits; watchdog re-decides.
#   C. Authenticated and token present → `claude --channels plugin:...` with
#      the channel-scoped .env synced beforehand.
next_tmux_cmd() {
  local base="CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR_VAL claude"
  if ! ensure_plugin_installed "$REQUIRED_CHANNEL_PLUGIN"; then
    # Case A: still not authenticated (or install genuinely failed).
    echo "$base"
    return
  fi
  if ! has_telegram_token; then
    # Case B: authenticated, need the bot token.
    log "authenticated profile detected with no Telegram token — launching wizard"
    echo "/opt/agent-admin/scripts/wizard-container.sh"
    return
  fi
  # Case C: steady state with channel attached. Skip permission prompts —
  # the agent's only interactive driver in steady state is the remote
  # Telegram user (you), so an approval prompt would just stall every
  # reply. The container is the security boundary; tool calls inside it
  # can't escape to the host beyond what the bind-mount + named volume
  # already expose.
  ensure_channel_env_synced "telegram" "TELEGRAM_BOT_TOKEN" || true
  echo "$base --channels plugin:$REQUIRED_CHANNEL_PLUGIN --dangerously-skip-permissions"
}

# ── 5. tmux session lifecycle ─────────────────────────────
start_session() {
  local cmd
  cmd=$(next_tmux_cmd)
  log "launching: $cmd"
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  sleep 1
  tmux new-session -d -s "$SESSION" -c "$WORKDIR" "$cmd"
  tmux pipe-pane -t "$SESSION" "cat >> /workspace/claude.log"
  sleep 2
  tmux has-session -t "$SESSION" 2>/dev/null
}

# Session is "alive" when the tmux session still exists. Whatever is running
# inside it (claude, the wizard) is the supervisor's concern — this just
# tells the watchdog when it needs to re-decide. Dropping the pgrep claude
# check also prevents false positives during the Telegram wizard phase.
session_alive() {
  tmux has-session -t "$SESSION" 2>/dev/null
}

log "starting tmux session '$SESSION'"
if ! start_session; then
  log "ERROR: initial tmux session failed to start"
  exit 1
fi

# ── 6. Watchdog ───────────────────────────────────────────
# Poll every 2s so the re-attach gap between Claude dying (/exit) and the
# next tmux session coming up is barely noticeable. Cheap check — just
# `tmux has-session`.
while true; do
  sleep 2
  if session_alive; then
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
