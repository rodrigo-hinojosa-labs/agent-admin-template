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
CLAUDE_CMD='CLAUDE_CONFIG_DIR=/home/agent/.claude claude --channels plugin:telegram@claude-plugins-official'

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
