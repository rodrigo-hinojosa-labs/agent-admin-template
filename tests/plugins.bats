#!/usr/bin/env bats

load helper

setup() {
  setup_tmp_dir
  cp -r "$REPO_ROOT/scripts" "$REPO_ROOT/modules" "$TMP_TEST_DIR/"
  cp "$REPO_ROOT/setup.sh" "$TMP_TEST_DIR/"
  cat > "$TMP_TEST_DIR/agent.yml" << 'EOF'
version: 1
agent: {name: pbot, display_name: "PBot", role: r, vibe: v, use_default_principles: true}
user: {name: A, nickname: A, timezone: UTC, email: a@b.com, language: en}
deployment: {host: h, workspace: /tmp/pbot, install_service: false}
notifications: {channel: none}
features: {heartbeat: {enabled: false}}
mcps: {atlassian: [], github: {enabled: false}}
plugins:
  - claude-mem@thedotmack
  - telegram@claude-plugins-official
EOF
}

teardown() { teardown_tmp_dir; }

@test "install_plugins emits correct commands when user says yes" {
  cd "$TMP_TEST_DIR"
  mkdir -p stubs
  cat > stubs/claude << STUB
#!/bin/bash
echo "[claude-stub] \$@" >> "$TMP_TEST_DIR/claude-calls.log"
STUB
  chmod +x stubs/claude
  export PATH="$TMP_TEST_DIR/stubs:$PATH"
  run bash -c "yes y | ./setup.sh --regenerate"
  [ "$status" -eq 0 ]
  grep -q "plugin install claude-mem@thedotmack" "$TMP_TEST_DIR/claude-calls.log"
  grep -q "plugin install telegram@claude-plugins-official" "$TMP_TEST_DIR/claude-calls.log"
}

@test "install_plugins skipped when user says no" {
  cd "$TMP_TEST_DIR"
  mkdir -p stubs
  cat > stubs/claude << STUB
#!/bin/bash
echo "[claude-stub] \$@" >> "$TMP_TEST_DIR/claude-calls.log"
STUB
  chmod +x stubs/claude
  export PATH="$TMP_TEST_DIR/stubs:$PATH"
  run bash -c "echo 'n' | ./setup.sh --regenerate"
  [ "$status" -eq 0 ]
  [ ! -f "$TMP_TEST_DIR/claude-calls.log" ]
}
