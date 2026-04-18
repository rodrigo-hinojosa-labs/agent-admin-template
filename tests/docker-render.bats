#!/usr/bin/env bats

load helper

setup() {
  setup_tmp_dir
  load_lib yaml
  load_lib render
  FIXTURE="$REPO_ROOT/tests/fixtures/docker-agent.yml"
  render_load_context "$FIXTURE"
  export HOME_DIR="/home/test"
}

teardown() { teardown_tmp_dir; }

@test "docker-agent fixture exposes deployment.mode=docker" {
  [ "${DEPLOYMENT_MODE:-}" = "docker" ]
}

@test "docker-compose.yml.tpl renders with agent name as service" {
  result=$(render_template "$REPO_ROOT/modules/docker-compose.yml.tpl")
  [[ "$result" == *"  dockbot:"* ]]
}

@test "docker-compose.yml.tpl sets build args from docker.uid/gid" {
  result=$(render_template "$REPO_ROOT/modules/docker-compose.yml.tpl")
  [[ "$result" == *'UID: "1000"'* ]]
  [[ "$result" == *'GID: "1000"'* ]]
}

@test "docker-compose.yml.tpl mounts workspace and named state volume" {
  result=$(render_template "$REPO_ROOT/modules/docker-compose.yml.tpl")
  [[ "$result" == *"./:/workspace"* ]]
  [[ "$result" == *"dockbot-state:/home/agent"* ]]
}

@test "docker-compose.yml.tpl drops all caps and re-adds only the three" {
  result=$(render_template "$REPO_ROOT/modules/docker-compose.yml.tpl")
  [[ "$result" == *"cap_drop:"* ]]
  [[ "$result" == *"cap_add:"* ]]
  [[ "$result" == *"CHOWN"* ]]
  [[ "$result" == *"SETUID"* ]]
  [[ "$result" == *"SETGID"* ]]
}

@test "docker-compose.yml.tpl uses unless-stopped and no published ports" {
  result=$(render_template "$REPO_ROOT/modules/docker-compose.yml.tpl")
  [[ "$result" == *"restart: unless-stopped"* ]]
  [[ "$result" != *"ports:"* ]]
}

@test "systemd-host-docker unit has Type=oneshot RemainAfterExit=yes" {
  result=$(render_template "$REPO_ROOT/modules/systemd-host-docker.service.tpl")
  [[ "$result" == *"Type=oneshot"* ]]
  [[ "$result" == *"RemainAfterExit=yes"* ]]
}

@test "systemd-host-docker ExecStart runs docker compose up -d in workspace" {
  result=$(render_template "$REPO_ROOT/modules/systemd-host-docker.service.tpl")
  [[ "$result" == *"WorkingDirectory=/home/test/agents/dockbot"* ]]
  [[ "$result" == *"ExecStart=/usr/bin/docker compose up -d"* ]]
  [[ "$result" == *"ExecStop=/usr/bin/docker compose down"* ]]
}

@test "systemd-host-docker unit description includes agent display name" {
  result=$(render_template "$REPO_ROOT/modules/systemd-host-docker.service.tpl")
  [[ "$result" == *"Description=DockBot 🐳 (Docker)"* ]]
}

@test "crontab.tpl contains heartbeat invocation against workspace" {
  # The runtime uses envsubst, but shape is the same: $AGENT_NAME + cron schedule.
  content=$(< "$REPO_ROOT/docker/crontab.tpl")
  [[ "$content" == *"/workspace/scripts/heartbeat/heartbeat.sh"* ]]
  [[ "$content" == *'${HEARTBEAT_CRON}'* ]]
}
