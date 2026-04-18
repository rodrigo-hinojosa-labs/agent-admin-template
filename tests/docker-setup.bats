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

@test "--docker scaffold copies docker/ directory into destination" {
  mkdir -p "$TMP_TEST_DIR/installer"
  local dest="$TMP_TEST_DIR/docker-scaffold"
  run run_docker_wizard "$dest"
  [ "$status" -eq 0 ]
  [ -d "$dest/docker" ]
  [ -f "$dest/docker/Dockerfile" ]
  [ -f "$dest/docker/entrypoint.sh" ]
  [ -x "$dest/docker/entrypoint.sh" ]
  [ -f "$dest/docker/scripts/start_services.sh" ]
}

@test "--docker scaffold writes docker-compose.yml at workspace root" {
  mkdir -p "$TMP_TEST_DIR/installer"
  local dest="$TMP_TEST_DIR/docker-compose-out"
  run run_docker_wizard "$dest"
  [ "$status" -eq 0 ]
  [ -f "$dest/docker-compose.yml" ]
  grep -q "dockbot:" "$dest/docker-compose.yml"
  grep -q "dockbot-state:" "$dest/docker-compose.yml"
}

@test "--docker scaffold does NOT render agent-script-*.sh on host" {
  mkdir -p "$TMP_TEST_DIR/installer"
  local dest="$TMP_TEST_DIR/docker-no-host-launcher"
  run run_docker_wizard "$dest"
  [ "$status" -eq 0 ]
  # No user-level systemd unit in docker mode.
  [ ! -f "$HOME/.config/systemd/user/dockbot.service" ]
  [ ! -f "$HOME/Library/LaunchAgents/local.dockbot.plist" ]
  [ ! -f "$HOME/.local/bin/dockbot.sh" ]
}

@test "--uninstall in docker-mode workspace runs docker compose down -v (dry)" {
  mkdir -p "$TMP_TEST_DIR/installer"
  local dest="$TMP_TEST_DIR/docker-uninstall"
  run run_docker_wizard "$dest"
  [ "$status" -eq 0 ]

  # Stub docker so the test does not need a daemon. Record invocations.
  mkdir -p "$TMP_TEST_DIR/bin"
  cat > "$TMP_TEST_DIR/bin/docker" <<'STUB'
#!/bin/bash
echo "$@" >> "$TMP_TEST_DIR/docker-calls.log"
exit 0
STUB
  chmod +x "$TMP_TEST_DIR/bin/docker"
  export PATH="$TMP_TEST_DIR/bin:$PATH"

  cd "$dest"
  run ./setup.sh --uninstall --yes
  [ "$status" -eq 0 ]
  grep -q "compose down -v" "$TMP_TEST_DIR/docker-calls.log"
}
