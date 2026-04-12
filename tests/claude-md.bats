#!/usr/bin/env bats

load helper

setup() {
  setup_tmp_dir
  load_lib yaml
  load_lib render
}

teardown() { teardown_tmp_dir; }

@test "CLAUDE.md renders agent identity" {
  cat > "$TMP_TEST_DIR/agent.yml" << 'EOF'
version: 1
agent:
  name: demo
  display_name: "Demo 🤖"
  role: "Test role"
  vibe: "Test vibe"
  use_default_principles: true
user:
  name: "Alice"
  nickname: "Alice"
  timezone: "UTC"
  email: "a@b.com"
  language: "en"
deployment:
  host: "testbox"
  workspace: "/tmp/demo"
  install_service: false
notifications:
  channel: none
features:
  heartbeat:
    enabled: true
    interval: "15m"
    default_prompt: "test"
mcps:
  atlassian: []
  github:
    enabled: false
EOF
  render_load_context "$TMP_TEST_DIR/agent.yml"
  export NOTIFICATIONS_CHANNEL_IS_TELEGRAM=false
  result=$(render_template "$REPO_ROOT/modules/claude-md.tpl")
  [[ "$result" == *"Demo 🤖"* ]]
  [[ "$result" == *"address as **Alice**"* ]]
  [[ "$result" == *"Heartbeat"* ]]
  [[ "$result" == *"Default interval:** 15m"* ]]
  [[ "$result" == *"Core Truths"* ]]
  [[ "$result" != *"Telegram Integration"* ]]
}

@test "CLAUDE.md omits default principles when disabled" {
  cat > "$TMP_TEST_DIR/agent.yml" << 'EOF'
version: 1
agent:
  name: demo
  display_name: "Demo"
  role: "R"
  vibe: "V"
  use_default_principles: false
user:
  name: "A"
  nickname: "A"
  timezone: "UTC"
  email: "a@b.com"
  language: "en"
deployment:
  host: "h"
  workspace: "/tmp"
  install_service: false
notifications:
  channel: none
features:
  heartbeat:
    enabled: false
mcps:
  atlassian: []
  github:
    enabled: false
EOF
  render_load_context "$TMP_TEST_DIR/agent.yml"
  export NOTIFICATIONS_CHANNEL_IS_TELEGRAM=false
  result=$(render_template "$REPO_ROOT/modules/claude-md.tpl")
  [[ "$result" == *"<!-- Define the principles"* ]]
  [[ "$result" != *"Genuinely useful"* ]]
}
