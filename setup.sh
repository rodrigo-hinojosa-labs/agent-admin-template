#!/usr/bin/env bash
# setup.sh — Wizard + regenerate orchestrator for agent-admin-template

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/scripts/lib/yaml.sh"
source "$SCRIPT_DIR/scripts/lib/render.sh"
source "$SCRIPT_DIR/scripts/lib/wizard.sh"

MODE="auto"
FORCE_CLAUDE_MD=false

print_usage() {
  cat << 'EOF'
Usage: ./setup.sh [options]

Options:
  (no flags)           Interactive wizard on first run; regenerate on subsequent runs.
  --regenerate         Re-render derived files from agent.yml (keeps CLAUDE.md).
  --force-claude-md    With --regenerate, also overwrite CLAUDE.md.
  --non-interactive    Fail if agent.yml missing; no prompts.
  --reset              Delete agent.yml and re-run the wizard.
  --help               Show this message.

Files:
  agent.yml            Source of truth (user-owned, gitignored by default).
  .env                 Secrets (user-owned, gitignored).
  CLAUDE.md            Generated once; user-owned after.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --regenerate) MODE="regenerate"; shift ;;
      --reset) MODE="reset"; shift ;;
      --non-interactive) MODE="non-interactive"; shift ;;
      --force-claude-md) FORCE_CLAUDE_MD=true; shift ;;
      --help|-h) print_usage; exit 0 ;;
      *) echo "Unknown option: $1" >&2; print_usage; exit 1 ;;
    esac
  done
}

run_wizard() {
  local agent_yml="$SCRIPT_DIR/agent.yml"
  local env_file="$SCRIPT_DIR/.env"

  echo ""
  echo "═══════════════════════════════════════════════════"
  echo " agent-admin-template — Interactive Setup"
  echo "═══════════════════════════════════════════════════"
  echo ""

  # ── 1. Identity ─────────────────────────────────────
  echo "▸ Agent identity"
  local agent_name agent_display agent_role agent_vibe
  agent_name=$(ask "Agent name (lowercase, no spaces)" "my-agent")
  agent_display=$(ask "Display name (with emoji)" "MyAgent 🤖")
  agent_role=$(ask "Role description" "Admin assistant for my ecosystem")
  agent_vibe=$(ask "Vibe / personality (one line)" "Direct, useful, no drama")
  echo ""

  # ── 2. User ─────────────────────────────────────────
  echo "▸ About you"
  local user_name user_nick first_name tz_default user_tz user_email user_lang
  user_name=$(ask_required "Your full name")
  first_name="${user_name%% *}"
  user_nick=$(ask "Nickname (how the agent should address you)" "$first_name")
  tz_default="UTC"
  if command -v timedatectl &>/dev/null; then
    tz_default=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")
  elif [ -L /etc/localtime ]; then
    tz_default=$(readlink /etc/localtime | sed 's|.*zoneinfo/||')
  fi
  user_tz=$(ask "Timezone" "$tz_default")
  user_email=$(ask_required "Primary email")
  user_lang=$(ask_choice "Preferred language" "en" "es en mixed")
  echo ""

  # ── 3. Deployment ───────────────────────────────────
  echo "▸ Deployment"
  local deploy_host deploy_ws deploy_svc
  deploy_host=$(ask "Host machine name" "$(hostname)")
  deploy_ws=$(ask "Workspace directory" "\$HOME/Claude/Agents/$agent_name")
  deploy_svc=$(ask_yn "Install as system service?" "y")
  echo ""

  # ── 4. Notifications ────────────────────────────────
  echo "▸ Notifications (pluggable)"
  echo "  Options: none | log (file only) | telegram"
  local notify_channel notify_bot_token="" notify_chat_id=""
  notify_channel=$(ask_choice "Notification channel" "none" "none log telegram")
  if [ "$notify_channel" = "telegram" ]; then
    echo "  Create a bot at @BotFather to get a token."
    notify_bot_token=$(ask_required "Bot token")
    echo "  Message @userinfobot to get your chat ID."
    notify_chat_id=$(ask_required "Chat ID")
  fi
  echo ""

  # ── 5. MCPs ─────────────────────────────────────────
  echo "▸ MCP servers"
  echo "  Pre-configured (zero config): playwright, fetch, time, sequential-thinking"
  echo ""
  local atlassian_entries=""
  local atlassian_env_vars=""
  if [ "$(ask_yn 'Enable Atlassian MCP?' 'n')" = "true" ]; then
    while true; do
      local ws_name ws_url ws_email ws_token
      ws_name=$(ask "Workspace name (e.g. personal, work)" "personal")
      ws_url=$(ask_required "Atlassian URL (e.g. https://yourco.atlassian.net)")
      ws_email=$(ask_required "Email")
      ws_token=$(ask_secret "API token")
      atlassian_entries="${atlassian_entries}  - name: ${ws_name}
    url: \"${ws_url}\"
    email: \"${ws_email}\"
"
      local upper
      upper=$(echo "$ws_name" | tr '[:lower:]' '[:upper:]')
      atlassian_env_vars="${atlassian_env_vars}ATLASSIAN_${upper}_TOKEN=${ws_token}
"
      if [ "$(ask_yn 'Add another Atlassian workspace?' 'n')" = "false" ]; then
        break
      fi
    done
  fi

  local github_enabled="false" github_pat=""
  if [ "$(ask_yn 'Enable GitHub MCP?' 'n')" = "true" ]; then
    github_enabled="true"
    github_pat=$(ask_secret "GitHub Personal Access Token")
  fi
  echo ""

  # ── 6. Features ─────────────────────────────────────
  echo "▸ Features"
  local hb_enabled hb_interval hb_prompt
  hb_enabled=$(ask_yn "Enable heartbeat (periodic auto-execution)?" "y")
  hb_interval="30m"
  hb_prompt="Check status and report"
  if [ "$hb_enabled" = "true" ]; then
    hb_interval=$(ask "Default interval" "30m")
    hb_prompt=$(ask "Default prompt" "Check status and report")
  fi
  echo ""

  # ── 7. Principles ───────────────────────────────────
  echo "▸ Agent principles"
  local use_defaults
  use_defaults=$(ask_yn "Use default opinionated agent principles? (recommended)" "y")
  echo ""

  # ── Summary ─────────────────────────────────────────
  echo "═══════════════════════════════════════════════════"
  echo " Summary"
  echo "═══════════════════════════════════════════════════"
  echo "  Agent:           $agent_display ($agent_name)"
  echo "  User:            $user_name (\"$user_nick\")"
  echo "  Timezone:        $user_tz"
  echo "  Workspace:       $deploy_ws"
  echo "  Service:         $deploy_svc"
  echo "  Notifications:   $notify_channel"
  echo "  Heartbeat:       $hb_enabled (interval: $hb_interval)"
  echo "  Atlassian:       $([ -n "$atlassian_entries" ] && echo "configured" || echo "disabled")"
  echo "  GitHub MCP:      $github_enabled"
  echo "  Default princ.:  $use_defaults"
  echo ""

  if [ "$(ask_yn 'Proceed?' 'y')" = "false" ]; then
    echo "Aborted."
    exit 0
  fi

  # ── Build YAML fragments before the heredoc ─────────
  local atlassian_yaml plugins_yaml
  if [ -n "$atlassian_entries" ]; then
    atlassian_yaml="  atlassian:
$atlassian_entries"
  else
    atlassian_yaml="  atlassian: []"
  fi

  if [ "$notify_channel" = "telegram" ]; then
    plugins_yaml="plugins:
  - telegram@claude-plugins-official
  - claude-mem@thedotmack"
  else
    plugins_yaml="plugins:
  - claude-mem@thedotmack"
  fi

  # ── Write agent.yml ─────────────────────────────────
  cat > "$agent_yml" << EOF
# Generated by setup.sh on $(date '+%Y-%m-%d %H:%M:%S')
# Edit this file and run ./setup.sh --regenerate to update derived files.
version: 1

agent:
  name: $agent_name
  display_name: "$agent_display"
  role: "$agent_role"
  vibe: "$agent_vibe"
  use_default_principles: $use_defaults

user:
  name: "$user_name"
  nickname: "$user_nick"
  timezone: "$user_tz"
  email: "$user_email"
  language: "$user_lang"

deployment:
  host: "$deploy_host"
  workspace: "$deploy_ws"
  install_service: $deploy_svc

notifications:
  channel: $notify_channel

features:
  heartbeat:
    enabled: $hb_enabled
    interval: "$hb_interval"
    timeout: 300
    retries: 1
    default_prompt: "$hb_prompt"

mcps:
  defaults:
    - playwright
    - fetch
    - time
    - sequential-thinking
$atlassian_yaml
  github:
    enabled: $github_enabled

$plugins_yaml
EOF

  cat > "$env_file" << EOF
# Generated by setup.sh on $(date '+%Y-%m-%d %H:%M:%S')
# NEVER commit this file.

EOF
  if [ "$notify_channel" = "telegram" ]; then
    cat >> "$env_file" << EOF
NOTIFY_BOT_TOKEN=$notify_bot_token
NOTIFY_CHAT_ID=$notify_chat_id

EOF
  fi
  [ -n "$atlassian_env_vars" ] && echo "$atlassian_env_vars" >> "$env_file"
  [ "$github_enabled" = "true" ] && echo "GITHUB_PAT=$github_pat" >> "$env_file"

  echo ""
  echo "✓ agent.yml and .env written"
  echo ""
  echo "NOTE: the file regeneration (CLAUDE.md, .mcp.json, services, etc.)"
  echo "      will be implemented in Task 11. For now, agent.yml + .env are written."
}

regenerate() {
  echo "[regenerate stub]"
}

main() {
  parse_args "$@"
  yaml_require_yq || exit 1

  local agent_yml="$SCRIPT_DIR/agent.yml"

  case "$MODE" in
    reset)
      echo "Resetting: removing agent.yml"
      rm -f "$agent_yml"
      run_wizard
      ;;
    non-interactive)
      if [ ! -f "$agent_yml" ]; then
        echo "ERROR: agent.yml not found; cannot run in --non-interactive mode" >&2
        exit 1
      fi
      regenerate
      ;;
    regenerate)
      if [ ! -f "$agent_yml" ]; then
        echo "ERROR: agent.yml not found; run wizard first" >&2
        exit 1
      fi
      regenerate
      ;;
    auto)
      if [ -f "$agent_yml" ]; then
        regenerate
      else
        run_wizard
      fi
      ;;
  esac
}

main "$@"
