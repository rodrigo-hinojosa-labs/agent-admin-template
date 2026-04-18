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
