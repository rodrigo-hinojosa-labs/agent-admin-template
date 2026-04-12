#!/usr/bin/env bash
# Shared test helpers

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_TEST_DIR=""

setup_tmp_dir() {
  TMP_TEST_DIR=$(mktemp -d)
  export TMP_TEST_DIR
}

teardown_tmp_dir() {
  [ -n "$TMP_TEST_DIR" ] && [ -d "$TMP_TEST_DIR" ] && rm -rf "$TMP_TEST_DIR"
}

load_lib() {
  source "$REPO_ROOT/scripts/lib/$1.sh"
}
