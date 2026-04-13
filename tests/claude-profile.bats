#!/usr/bin/env bats

load helper

setup() {
  setup_tmp_dir
  cp -r "$REPO_ROOT/scripts" "$REPO_ROOT/modules" "$TMP_TEST_DIR/"
  cp "$REPO_ROOT/setup.sh" "$TMP_TEST_DIR/"
  touch "$TMP_TEST_DIR/.env"
}

teardown() { teardown_tmp_dir; }

write_agent_yml() {
  local claude_section="$1"
  cat > "$TMP_TEST_DIR/agent.yml" << EOF
version: 1
agent:
  name: profile-test
  display_name: "ProfileTest"
  role: "r"
  vibe: "v"
  use_default_principles: true
user:
  name: "A"
  nickname: "A"
  timezone: "UTC"
  email: "a@b.com"
  language: "en"
deployment:
  host: "h"
  workspace: "$TMP_TEST_DIR"
  install_service: true
${claude_section}
notifications:
  channel: none
features:
  heartbeat:
    enabled: false
    interval: "30m"
    timeout: 300
    retries: 1
    default_prompt: "ok"
mcps:
  atlassian: []
  github:
    enabled: false
EOF
}

@test "regenerate uses explicit claude.config_dir in systemd unit" {
  write_agent_yml 'claude:
  config_dir: "$HOME/.claude"
  profile_new: false'
  cd "$TMP_TEST_DIR"
  echo 'n' | ./setup.sh --regenerate

  local unit="$HOME/.config/systemd/user/profile-test.service"
  [ -f "$unit" ]
  grep -q "CLAUDE_CONFIG_DIR=$HOME/.claude$" "$unit"
  grep -q "TELEGRAM_STATE_DIR=$HOME/.claude/channels/telegram-profile-test$" "$unit"
  ! grep -q "claude-personal" "$unit"

  rm -f "$unit" "$HOME/.local/bin/profile-test.sh"
}

@test "regenerate falls back to ~/.claude-personal when claude section missing" {
  write_agent_yml ''
  cd "$TMP_TEST_DIR"
  echo 'n' | ./setup.sh --regenerate

  local unit="$HOME/.config/systemd/user/profile-test.service"
  [ -f "$unit" ]
  grep -q "CLAUDE_CONFIG_DIR=$HOME/.claude-personal$" "$unit"

  rm -f "$unit" "$HOME/.local/bin/profile-test.sh"
}

@test "next-steps includes /login block when profile_new=true" {
  write_agent_yml 'claude:
  config_dir: "$HOME/.claude-profile-test"
  profile_new: true'
  cd "$TMP_TEST_DIR"
  echo 'n' | ./setup.sh --regenerate

  # NEXT_STEPS is only rendered from the wizard path, not --regenerate; test
  # the render helper directly instead.
  source scripts/lib/render.sh
  render_load_context agent.yml
  export CLAUDE_CONFIG_DIR=$(eval echo "$CLAUDE_CONFIG_DIR")
  render_to_file modules/next-steps.en.tpl /tmp/ns-new.md
  grep -q "login required" /tmp/ns-new.md
  grep -q "$HOME/.claude-profile-test" /tmp/ns-new.md
  rm -f /tmp/ns-new.md "$HOME/.config/systemd/user/profile-test.service" "$HOME/.local/bin/profile-test.sh"
}

@test "next-steps omits /login block when profile_new=false" {
  write_agent_yml 'claude:
  config_dir: "$HOME/.claude"
  profile_new: false'
  cd "$TMP_TEST_DIR"
  echo 'n' | ./setup.sh --regenerate

  source scripts/lib/render.sh
  render_load_context agent.yml
  export CLAUDE_CONFIG_DIR=$(eval echo "$CLAUDE_CONFIG_DIR")
  render_to_file modules/next-steps.en.tpl /tmp/ns-shared.md
  ! grep -q "login required" /tmp/ns-shared.md
  rm -f /tmp/ns-shared.md "$HOME/.config/systemd/user/profile-test.service" "$HOME/.local/bin/profile-test.sh"
}
