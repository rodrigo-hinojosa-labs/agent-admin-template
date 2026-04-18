#!/bin/sh
# Container entrypoint. Runs as root (per compose config -- no `user:` key)
# so it can fix volume ownership, then drops to `agent` via su-exec.
set -eu

WORKSPACE=/workspace
AGENT_HOME=/home/agent
CRONTAB_DST=/etc/crontabs/agent

log() { printf '[entrypoint] %s\n' "$*"; }

# 1. First-run volume init: chown /home/agent if it is still root-owned.
if [ "$(stat -c %U /home/agent)" = "root" ]; then
  log "chowning /home/agent to agent:agent (first-run volume init)"
  chown -R agent:agent /home/agent
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
  log "first-run detected -- launching wizard"
  exec su-exec agent /opt/agent-admin/scripts/wizard-container.sh
fi

# 4. Steady state: drop to agent and exec the service supervisor.
log "starting services"
exec su-exec agent /opt/agent-admin/scripts/start_services.sh
