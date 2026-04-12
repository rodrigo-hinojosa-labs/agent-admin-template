#!/usr/bin/env bats

load helper

setup() {
  setup_tmp_dir
  cp -r "$REPO_ROOT/scripts" "$REPO_ROOT/modules" "$TMP_TEST_DIR/"
  cp "$REPO_ROOT/setup.sh" "$TMP_TEST_DIR/"
}

teardown() { teardown_tmp_dir; }

@test "wizard produces agent.yml with provided values" {
  cd "$TMP_TEST_DIR"
  run ./setup.sh <<EOF
my-test
TestAgent 🤖
Test role
Direct
Alice Example
Alice
UTC
alice@example.com
en
testhost
~/Claude/Agents/my-test
n
none
n
n
y
15m
Check status
y
y
n
EOF
  [ "$status" -eq 0 ]
  [ -f agent.yml ]
  [ "$(yq '.agent.name' agent.yml)" = "my-test" ]
  [ "$(yq '.user.nickname' agent.yml)" = "Alice" ]
  [ "$(yq '.features.heartbeat.interval' agent.yml)" = "15m" ]
  [ "$(yq '.notifications.channel' agent.yml)" = "none" ]
}
