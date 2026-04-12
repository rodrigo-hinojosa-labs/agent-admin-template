#!/usr/bin/env bash
# setup.sh — Wizard + regenerate orchestrator for agent-admin-template

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/scripts/lib/yaml.sh"
source "$SCRIPT_DIR/scripts/lib/render.sh"
source "$SCRIPT_DIR/scripts/lib/wizard.sh"

MODE="auto"
FORCE_CLAUDE_MD=false
UNINSTALL_PURGE=false
UNINSTALL_YES=false
DESTINATION=""
IN_PLACE=false

print_usage() {
  cat << 'EOF'
Usage: ./setup.sh [options]

Options:
  (no flags)           Interactive wizard on first run; regenerate on subsequent runs.
  --regenerate         Re-render derived files from agent.yml (keeps CLAUDE.md).
  --force-claude-md    With --regenerate, also overwrite CLAUDE.md.
  --non-interactive    Fail if agent.yml missing; no prompts.
  --reset              Delete agent.yml and re-run the wizard.
  --uninstall          Remove installed services, agent scripts, timers, tmux
                       sessions, and generated files inside the repo.
                       Preserves agent.yml and .env unless --purge is given.
  --purge              With --uninstall, also remove agent.yml and .env.
  --yes                With --uninstall, skip the confirmation prompt.
  --destination PATH   (wizard only) Use PATH instead of prompting for the destination.
  --in-place           (wizard only) Skip scaffold — generate files in the current
                       directory (legacy behavior).
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
      --uninstall) MODE="uninstall"; shift ;;
      --purge) UNINSTALL_PURGE=true; shift ;;
      --yes|-y) UNINSTALL_YES=true; shift ;;
      --destination) DESTINATION="$2"; shift 2 ;;
      --in-place) IN_PLACE=true; shift ;;
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
  if [ -n "$DESTINATION" ]; then
    deploy_ws="$DESTINATION"
    echo "  Agent destination directory: $deploy_ws (from --destination flag)"
  else
    deploy_ws=$(ask "Agent destination directory" "\$HOME/Claude/Agents/$agent_name")
  fi
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

  local src_dir="$SCRIPT_DIR"
  scaffold_destination
  regenerate

  if [ "$IN_PLACE" != true ] && [ -d "$SCRIPT_DIR/.git" ]; then
    (
      cd "$SCRIPT_DIR"
      git add -A
      git -c user.email="setup@agent-admin-template.local" -c user.name="agent-admin-template" \
        commit -q -m "chore: initial agent scaffold from agent-admin-template"
    )
    echo "  ✓ initial commit on ${AGENT_NAME}/live"
  fi

  if [ "$IN_PLACE" != true ]; then
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo " Your agent is ready at:"
    echo "   $SCRIPT_DIR"
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "Next steps:"
    echo "  cd $SCRIPT_DIR"
    echo "  claude                            # start the agent"
    echo "  ./setup.sh --regenerate           # after editing agent.yml"
    echo "  ./setup.sh --uninstall            # undo install"
    echo ""
    echo "The installer clone ($src_dir) is no longer needed and can be deleted."
  fi
}

# Copy system files to the destination, move agent.yml/.env, chdir, git init.
# If IN_PLACE=true or destination == SCRIPT_DIR, skip (user chose in-place mode).
scaffold_destination() {
  local src_dir="$SCRIPT_DIR"
  local agent_yml="$SCRIPT_DIR/agent.yml"
  local env_file="$SCRIPT_DIR/.env"

  # Resolve destination from agent.yml
  local dest
  dest=$(yq '.deployment.workspace' "$agent_yml")
  # Expand $HOME / ~
  dest=$(eval echo "$dest")

  if [ "$IN_PLACE" = true ]; then
    echo "▸ --in-place mode: skipping destination scaffold"
    return 0
  fi

  if [ "$dest" = "$src_dir" ]; then
    echo "▸ Destination equals current directory: running in-place"
    return 0
  fi

  # Safety: never scaffold to $HOME itself
  if [ "$dest" = "$HOME" ]; then
    echo "ERROR: destination cannot be \$HOME itself ($HOME)" >&2
    echo "       Choose a subdirectory like \$HOME/Claude/Agents/{agent-name}" >&2
    exit 1
  fi

  # Safety: destination must not already exist
  if [ -e "$dest" ]; then
    echo "ERROR: destination already exists: $dest" >&2
    echo "       Choose a fresh path, or remove the existing one first." >&2
    exit 1
  fi

  echo ""
  echo "▸ Scaffolding destination: $dest"
  mkdir -p "$dest"

  # Copy system files (installer → destination)
  local item
  for item in setup.sh .gitignore LICENSE; do
    [ -e "$src_dir/$item" ] && cp "$src_dir/$item" "$dest/"
  done
  for item in modules scripts; do
    [ -d "$src_dir/$item" ] && cp -R "$src_dir/$item" "$dest/"
  done
  # Ensure setup.sh is executable
  chmod +x "$dest/setup.sh"
  find "$dest/scripts" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

  # Move agent.yml + .env (transactional: copy, verify, delete source)
  cp "$agent_yml" "$dest/agent.yml" && [ -f "$dest/agent.yml" ] && rm "$agent_yml"
  if [ -f "$env_file" ]; then
    cp "$env_file" "$dest/.env" && [ -f "$dest/.env" ] && rm "$env_file"
  fi

  echo "  ✓ system files copied"
  echo "  ✓ agent.yml and .env moved"

  # Git init with {agent-name}/live branch
  local agent_name_for_branch
  agent_name_for_branch=$(yq '.agent.name' "$dest/agent.yml")
  local branch="${agent_name_for_branch}/live"
  (
    cd "$dest"
    git init -b "$branch" -q 2>/dev/null || git init -q  # older git may not support -b
    if [ "$(git symbolic-ref --short HEAD 2>/dev/null)" != "$branch" ]; then
      git checkout -b "$branch" -q 2>/dev/null || true
    fi
  )
  echo "  ✓ git init (branch: $branch)"

  # Redirect all subsequent operations to $dest
  SCRIPT_DIR="$dest"
  cd "$dest"
}

regenerate() {
  local agent_yml="$SCRIPT_DIR/agent.yml"
  local modules_dir="$SCRIPT_DIR/modules"
  local os
  os=$(uname -s | tr '[:upper:]' '[:lower:]')  # darwin | linux

  echo "▸ Loading context from agent.yml"
  render_load_context "$agent_yml"

  # Warn if agent.yml workspace differs from current directory (post-scaffold)
  local yml_workspace
  yml_workspace=$(eval echo "${DEPLOYMENT_WORKSPACE:-}")
  local current_dir
  current_dir=$(cd "$SCRIPT_DIR" && pwd)
  local yml_resolved
  yml_resolved=$(cd "$yml_workspace" 2>/dev/null && pwd || echo "$yml_workspace")

  if [ "$IN_PLACE" != true ] && [ -f "$SCRIPT_DIR/agent.yml" ] && [ -n "$yml_workspace" ] && [ "$yml_resolved" != "$current_dir" ]; then
    echo ""
    echo "WARNING: agent.yml's deployment.workspace ($yml_workspace) differs from the"
    echo "         current directory ($current_dir). The workspace field is fixed at"
    echo "         scaffold time; regenerate does NOT relocate files. If you want to"
    echo "         move the agent, uninstall here and re-run the installer."
    echo ""
  fi

  # Derived env vars not in YAML
  export HOME_DIR="$HOME"
  export OS="$os"
  if [ "${NOTIFICATIONS_CHANNEL:-none}" = "telegram" ]; then
    export NOTIFICATIONS_CHANNEL_IS_TELEGRAM=true
  else
    export NOTIFICATIONS_CHANNEL_IS_TELEGRAM=false
  fi

  local agent_name="$AGENT_NAME"
  local workspace
  workspace=$(eval echo "$DEPLOYMENT_WORKSPACE")

  echo "▸ Rendering modules"

  # CLAUDE.md — only if missing or --force-claude-md
  if [ ! -f "$SCRIPT_DIR/CLAUDE.md" ] || [ "$FORCE_CLAUDE_MD" = true ]; then
    if [ -f "$SCRIPT_DIR/CLAUDE.md" ] && [ "$FORCE_CLAUDE_MD" = true ]; then
      if [ "$(ask_yn 'Overwrite existing CLAUDE.md? THIS IS DESTRUCTIVE' 'n')" = "false" ]; then
        echo "  skipping CLAUDE.md (preserved)"
      else
        render_to_file "$modules_dir/claude-md.tpl" "$SCRIPT_DIR/CLAUDE.md"
        echo "  ✓ CLAUDE.md (overwritten)"
      fi
    else
      render_to_file "$modules_dir/claude-md.tpl" "$SCRIPT_DIR/CLAUDE.md"
      echo "  ✓ CLAUDE.md"
    fi
  else
    echo "  ◦ CLAUDE.md (preserved — use --force-claude-md to overwrite)"
  fi

  # .mcp.json
  render_to_file "$modules_dir/mcp-json.tpl" "$SCRIPT_DIR/.mcp.json"
  echo "  ✓ .mcp.json"

  # .env.example
  render_to_file "$modules_dir/env-example.tpl" "$SCRIPT_DIR/.env.example"
  echo "  ✓ .env.example"

  # heartbeat.conf
  if [ "${FEATURES_HEARTBEAT_ENABLED:-false}" = "true" ]; then
    render_to_file "$modules_dir/heartbeat-conf.tpl" "$SCRIPT_DIR/scripts/heartbeat/heartbeat.conf"
    echo "  ✓ scripts/heartbeat/heartbeat.conf"
  fi

  if [ "${DEPLOYMENT_INSTALL_SERVICE:-false}" = "true" ]; then
    install_service "$os" "$agent_name" "$workspace"
  fi

  echo ""
  echo "✓ Regeneration complete."
  maybe_print_plugin_hints
}

install_service() {
  local os="$1" agent_name="$2" workspace="$3"
  local modules_dir="$SCRIPT_DIR/modules"

  mkdir -p "$HOME/.local/bin"

  case "$os" in
    linux)
      render_to_file "$modules_dir/agent-script-linux.sh.tpl" "$HOME/.local/bin/${agent_name}.sh"
      chmod +x "$HOME/.local/bin/${agent_name}.sh"
      echo "  ✓ ~/.local/bin/${agent_name}.sh"

      mkdir -p "$HOME/.config/systemd/user"
      render_to_file "$modules_dir/systemd.service.tpl" "$HOME/.config/systemd/user/${agent_name}.service"
      systemctl --user daemon-reload 2>/dev/null || true
      echo "  ✓ ~/.config/systemd/user/${agent_name}.service"
      echo "  → enable with: systemctl --user enable --now ${agent_name}.service"
      ;;
    darwin)
      render_to_file "$modules_dir/agent-script-mac.sh.tpl" "$HOME/.local/bin/${agent_name}.sh"
      chmod +x "$HOME/.local/bin/${agent_name}.sh"
      echo "  ✓ ~/.local/bin/${agent_name}.sh"

      mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.local/share/${agent_name}"
      render_to_file "$modules_dir/launchd.plist.tpl" "$HOME/Library/LaunchAgents/local.${agent_name}.plist"
      echo "  ✓ ~/Library/LaunchAgents/local.${agent_name}.plist"
      echo "  → load with: launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/local.${agent_name}.plist"
      ;;
  esac
}

# Print (do not execute) suggested plugin install commands so the user can run
# them on their own terms.
maybe_print_plugin_hints() {
  local agent_yml="$SCRIPT_DIR/agent.yml"
  local plugin_count
  plugin_count=$(yq '.plugins | length' "$agent_yml" 2>/dev/null || echo 0)
  [ "$plugin_count" -le 0 ] && return 0

  echo ""
  echo "▸ Suggested Claude Code plugins (install at your discretion):"
  local i p
  for i in $(seq 0 $((plugin_count - 1))); do
    p=$(yq ".plugins[$i]" "$agent_yml")
    echo "    claude plugin install $p"
  done
}

# Undo what install_service + regenerate created. Always safe to re-run.
# Preserves agent.yml and .env unless --purge is set.
uninstall() {
  local agent_yml="$SCRIPT_DIR/agent.yml"
  local env_file="$SCRIPT_DIR/.env"

  if [ ! -f "$agent_yml" ]; then
    echo "ERROR: agent.yml not found; nothing to uninstall." >&2
    echo "       (If you manually deleted agent.yml but files linger, remove them by hand.)" >&2
    exit 1
  fi

  render_load_context "$agent_yml"
  local agent_name="${AGENT_NAME:-}"
  if [ -z "$agent_name" ]; then
    echo "ERROR: agent.name missing from agent.yml; cannot identify what to uninstall." >&2
    exit 1
  fi

  local os
  os=$(uname -s | tr '[:upper:]' '[:lower:]')

  echo ""
  echo "═══════════════════════════════════════════════════"
  echo " Uninstall — ${agent_name}"
  echo "═══════════════════════════════════════════════════"
  echo ""
  echo "This will remove:"
  echo "  - tmux session: ${agent_name} (if running)"
  case "$os" in
    linux)
      echo "  - ~/.local/bin/${agent_name}.sh"
      echo "  - ~/.config/systemd/user/${agent_name}.service (stop + disable)"
      echo "  - ~/.config/systemd/user/${agent_name}-heartbeat.{service,timer} (if present)"
      ;;
    darwin)
      echo "  - ~/.local/bin/${agent_name}.sh"
      echo "  - ~/Library/LaunchAgents/local.${agent_name}.plist (unload + delete)"
      echo "  - ~/Library/LaunchAgents/local.${agent_name}-heartbeat.plist (if present)"
      echo "  - ~/.local/share/${agent_name}/ (log directory)"
      ;;
  esac
  echo "  - Generated repo files: CLAUDE.md, .mcp.json, .env.example,"
  echo "    scripts/heartbeat/heartbeat.conf, scripts/heartbeat/logs/"
  if [ "$UNINSTALL_PURGE" = true ]; then
    echo "  - agent.yml (source of truth)"
    echo "  - .env (secrets)"
  else
    echo ""
    echo "Preserved (pass --purge to also remove):"
    echo "  - agent.yml"
    echo "  - .env"
  fi
  echo ""

  if [ "$UNINSTALL_YES" != true ]; then
    if [ "$(ask_yn 'Continue?' 'n')" != "true" ]; then
      echo "Aborted."
      exit 0
    fi
  fi

  echo ""
  echo "▸ Stopping services"

  # Kill tmux session if present.
  if command -v tmux &>/dev/null; then
    tmux kill-session -t "$agent_name" 2>/dev/null && echo "  ✓ killed tmux session: ${agent_name}" || true
  fi

  case "$os" in
    linux)
      # Main service
      systemctl --user stop "${agent_name}.service" 2>/dev/null && echo "  ✓ stopped ${agent_name}.service" || true
      systemctl --user disable "${agent_name}.service" 2>/dev/null && echo "  ✓ disabled ${agent_name}.service" || true

      # Heartbeat timer (may or may not exist; launch.sh install uses {agent}-heartbeat)
      systemctl --user stop "${agent_name}-heartbeat.timer" 2>/dev/null && echo "  ✓ stopped ${agent_name}-heartbeat.timer" || true
      systemctl --user disable "${agent_name}-heartbeat.timer" 2>/dev/null && echo "  ✓ disabled ${agent_name}-heartbeat.timer" || true

      echo ""
      echo "▸ Removing files"
      rm -f "$HOME/.local/bin/${agent_name}.sh" && echo "  ✓ ~/.local/bin/${agent_name}.sh" || true
      rm -f "$HOME/.config/systemd/user/${agent_name}.service" && echo "  ✓ ~/.config/systemd/user/${agent_name}.service" || true
      rm -f "$HOME/.config/systemd/user/${agent_name}-heartbeat.service" \
            "$HOME/.config/systemd/user/${agent_name}-heartbeat.timer" 2>/dev/null && \
        echo "  ✓ heartbeat service/timer units (if any)" || true

      systemctl --user daemon-reload 2>/dev/null || true
      ;;
    darwin)
      local plist="$HOME/Library/LaunchAgents/local.${agent_name}.plist"
      local hb_plist="$HOME/Library/LaunchAgents/local.${agent_name}-heartbeat.plist"

      for p in "$plist" "$hb_plist"; do
        [ -f "$p" ] || continue
        launchctl bootout "gui/$(id -u)" "$p" 2>/dev/null || \
          launchctl unload "$p" 2>/dev/null || true
        echo "  ✓ unloaded $(basename "$p" .plist)"
      done

      echo ""
      echo "▸ Removing files"
      rm -f "$HOME/.local/bin/${agent_name}.sh" && echo "  ✓ ~/.local/bin/${agent_name}.sh" || true
      for p in "$plist" "$hb_plist"; do
        [ -f "$p" ] && rm -f "$p" && echo "  ✓ $p" || true
      done
      rm -rf "$HOME/.local/share/${agent_name}" 2>/dev/null && echo "  ✓ ~/.local/share/${agent_name}/" || true
      ;;
  esac

  echo ""
  echo "▸ Removing generated repo files"
  rm -f "$SCRIPT_DIR/CLAUDE.md" && echo "  ✓ CLAUDE.md" || true
  rm -f "$SCRIPT_DIR/.mcp.json" && echo "  ✓ .mcp.json" || true
  rm -f "$SCRIPT_DIR/.env.example" && echo "  ✓ .env.example" || true
  rm -f "$SCRIPT_DIR/scripts/heartbeat/heartbeat.conf" && echo "  ✓ scripts/heartbeat/heartbeat.conf" || true
  rm -rf "$SCRIPT_DIR/scripts/heartbeat/logs" && echo "  ✓ scripts/heartbeat/logs/" || true

  if [ "$UNINSTALL_PURGE" = true ]; then
    echo ""
    echo "▸ Purging source of truth and secrets"
    rm -f "$agent_yml" && echo "  ✓ agent.yml" || true
    rm -f "$env_file" && echo "  ✓ .env" || true
  fi

  echo ""
  echo "✓ Uninstall complete."
  if [ "$UNINSTALL_PURGE" != true ]; then
    echo "  agent.yml and .env preserved — run ./setup.sh to reinstall from them."
  fi
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
    uninstall)
      uninstall
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
