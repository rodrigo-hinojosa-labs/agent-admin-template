#!/usr/bin/env bats

load helper

setup() { setup_tmp_dir; }
teardown() { teardown_tmp_dir; }

@test "setup.sh --help lists --docker flag" {
  run "$REPO_ROOT/setup.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--docker"* ]]
}

@test "setup.sh --docker --help coexists (flag is parsed, not rejected)" {
  run "$REPO_ROOT/setup.sh" --docker --help
  [ "$status" -eq 0 ]
  [[ "$output" != *"Unknown option"* ]]
}

# Helper: run wizard piping answers through stdin, with --docker flag.
run_docker_wizard() {
  local dest="$1"
  cp -r "$REPO_ROOT/scripts" "$REPO_ROOT/modules" "$REPO_ROOT/docker" "$TMP_TEST_DIR/installer/"
  cp "$REPO_ROOT/setup.sh" "$TMP_TEST_DIR/installer/"
  cd "$TMP_TEST_DIR/installer"
  # Answers: name, display, role, vibe, user_name, nick, tz, email, lang,
  # host, destination, install_service, fork=n, heartbeat yes, interval, prompt,
  # defaults yes, atlassian=n, github=n, proceed.
  ./setup.sh --docker --destination "$dest" <<EOF
dockbot
DockBot
r
v
Alice
Alice
UTC
a@b.com
en
host
n
n
y
30m
ok
y
n
n
proceed
EOF
}

@test "--docker wizard does not prompt for Telegram secrets" {
  mkdir -p "$TMP_TEST_DIR/installer"
  local dest="$TMP_TEST_DIR/docker-agent"
  run run_docker_wizard "$dest"
  [ "$status" -eq 0 ]
  # .env must NOT contain secrets — those are deferred to container wizard.
  [ -f "$dest/.env" ]
  ! grep -q "^TELEGRAM_BOT_TOKEN=" "$dest/.env"
  ! grep -q "^NOTIFY_BOT_TOKEN=.\+" "$dest/.env"
}

@test "--docker wizard writes deployment.mode=docker and docker.* in agent.yml" {
  mkdir -p "$TMP_TEST_DIR/installer"
  local dest="$TMP_TEST_DIR/docker-agent-yml"
  run run_docker_wizard "$dest"
  [ "$status" -eq 0 ]
  [ -f "$dest/agent.yml" ]
  [ "$(yq '.deployment.mode' "$dest/agent.yml")" = "docker" ]
  [ "$(yq '.docker.uid' "$dest/agent.yml")" = "$(id -u)" ]
  [ "$(yq '.docker.gid' "$dest/agent.yml")" = "$(id -g)" ]
  [ "$(yq '.docker.state_volume' "$dest/agent.yml")" = "dockbot-state" ]
  [ "$(yq '.docker.image_tag' "$dest/agent.yml")" = "agent-admin:latest" ]
}
