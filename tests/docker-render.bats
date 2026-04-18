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
