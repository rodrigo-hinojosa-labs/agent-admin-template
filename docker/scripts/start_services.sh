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

# ── 4. Claude launch command builder ──────────────────────
build_claude_cmd() {
  local base="CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR_VAL claude"
  if ensure_plugin_installed "$REQUIRED_CHANNEL_PLUGIN" \
     && [ -d "$(plugin_cache_dir_for "$REQUIRED_CHANNEL_PLUGIN")" ]; then
    # Plugin is installed — make sure its channel-scoped .env has the token
    # before we attach --channels, or the MCP server errors out on boot.
    ensure_channel_env_synced "telegram" "TELEGRAM_BOT_TOKEN" || true
    echo "$base --channels plugin:$REQUIRED_CHANNEL_PLUGIN"
  else
    echo "$base"
  fi
}

# ── 5. tmux session lifecycle ─────────────────────────────
start_session() {
  local cmd
  cmd=$(build_claude_cmd)
  log "launching: $cmd"
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  sleep 1
  tmux new-session -d -s "$SESSION" -c "$WORKDIR" "$cmd"
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

# ── 6. Watchdog ───────────────────────────────────────────
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
