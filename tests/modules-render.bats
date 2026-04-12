#!/usr/bin/env bats

load helper

setup() {
  setup_tmp_dir
  load_lib yaml
  load_lib render
  FIXTURE="$TMP_TEST_DIR/agent.yml"
  cat > "$FIXTURE" << 'EOF'
version: 1
agent:
  name: my-bot
  display_name: "MyBot 🤖"
  role: "r"
  vibe: "v"
user:
  name: "A"
  nickname: "A"
  timezone: "UTC"
  email: "a@b.com"
  language: "en"
deployment:
  host: "h"
  workspace: "/home/a/wk"
  install_service: true
notifications:
  channel: telegram
features:
  heartbeat:
    enabled: true
    interval: "30m"
    timeout: 300
    retries: 1
    default_prompt: "ok"
mcps:
  atlassian: []
  github:
    enabled: false
EOF
  render_load_context "$FIXTURE"
  export NOTIFICATIONS_CHANNEL_IS_TELEGRAM=true
  export HOME_DIR="/Users/test"
}

teardown() { teardown_tmp_dir; }

@test "env-example includes telegram and omits github" {
  result=$(render_template "$REPO_ROOT/modules/env-example.tpl")
  [[ "$result" == *"NOTIFY_BOT_TOKEN="* ]]
  [[ "$result" != *"GITHUB_PAT="* ]]
}

@test "agent-script-linux.sh has agent name substituted" {
  result=$(render_template "$REPO_ROOT/modules/agent-script-linux.sh.tpl")
  [[ "$result" == *'SESSION="my-bot"'* ]]
  [[ "$result" == *'WORKDIR="/home/a/wk"'* ]]
}

@test "systemd.service has workspace" {
  result=$(render_template "$REPO_ROOT/modules/systemd.service.tpl")
  [[ "$result" == *"WorkingDirectory=/home/a/wk"* ]]
  [[ "$result" == *"my-bot.sh"* ]]
}

@test "launchd.plist has label and paths" {
  result=$(render_template "$REPO_ROOT/modules/launchd.plist.tpl")
  [[ "$result" == *"<string>local.my-bot</string>"* ]]
  [[ "$result" == *"/Users/test/.local/bin/my-bot.sh"* ]]
}

@test "heartbeat-conf has interval" {
  result=$(render_template "$REPO_ROOT/modules/heartbeat-conf.tpl")
  [[ "$result" == *'HEARTBEAT_INTERVAL="30m"'* ]]
  [[ "$result" == *'NOTIFY_CHANNEL="telegram"'* ]]
}
