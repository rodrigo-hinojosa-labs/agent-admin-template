#!/usr/bin/env bats

load helper

setup() {
  setup_tmp_dir
  # Copy entire repo (simulating a fresh clone)
  cp -r "$REPO_ROOT/." "$TMP_TEST_DIR/"
  cd "$TMP_TEST_DIR"
  # Remove any state from the current working copy
  rm -f agent.yml .env CLAUDE.md .mcp.json .env.example
}

teardown() { teardown_tmp_dir; }

@test "E2E: fresh wizard with defaults produces functional agent" {
  cd "$TMP_TEST_DIR"
  # 20 answers for the wizard:
  # 1. agent name (e2e-bot)
  # 2. agent display (E2EBot 🤖)
  # 3. agent role (Test role)
  # 4. agent vibe (Test vibe)
  # 5. user full name (Test User)
  # 6. user nickname (Test)
  # 7. timezone (UTC)
  # 8. email (test@example.com)
  # 9. language (en)
  # 10. host (test-host)
  # 11. workspace (~/Claude/Agents/e2e-bot)
  # 12. install_service (n)
  # 13. notifications channel (none)
  # 14. atlassian (n)
  # 15. github (n)
  # 16. heartbeat enabled (y)
  # 17. heartbeat interval (30m)
  # 18. heartbeat prompt (Test prompt)
  # 19. use default principles (y)
  # 20. confirm/proceed (y)
  run ./setup.sh <<EOF
e2e-bot
E2EBot 🤖
Test role
Test vibe
Test User
Test
UTC
test@example.com
en
test-host
~/Claude/Agents/e2e-bot
n
none
n
n
y
30m
Test prompt
y
y
EOF
  [ "$status" -eq 0 ]
  [ -f agent.yml ]
  [ -f .env ]

  # Content checks for agent.yml
  [ "$(yq '.agent.name' agent.yml)" = "e2e-bot" ]
  [ "$(yq '.agent.display_name' agent.yml)" = "E2EBot 🤖" ]
  [ "$(yq '.user.name' agent.yml)" = "Test User" ]
  [ "$(yq '.user.nickname' agent.yml)" = "Test" ]
  [ "$(yq '.deployment.host' agent.yml)" = "test-host" ]
  [ "$(yq '.notifications.channel' agent.yml)" = "none" ]
  [ "$(yq '.features.heartbeat.enabled' agent.yml)" = "true" ]
  [ "$(yq '.features.heartbeat.interval' agent.yml)" = "30m" ]
  [ "$(yq '.features.heartbeat.default_prompt' agent.yml)" = "Test prompt" ]

  # Now run regenerate to produce derived files
  # Pass 'n' to skip plugin install prompt
  run bash -c "echo 'n' | ./setup.sh --regenerate"
  [ "$status" -eq 0 ]

  # Verify all derived files exist
  [ -f CLAUDE.md ]
  [ -f .mcp.json ]
  [ -f .env.example ]
  [ -f scripts/heartbeat/heartbeat.conf ]

  # CLAUDE.md should contain agent display name
  grep -q "E2EBot" CLAUDE.md

  # .mcp.json should be valid JSON
  jq . .mcp.json > /dev/null

  # heartbeat.conf should have the interval
  grep -q 'HEARTBEAT_INTERVAL="30m"' scripts/heartbeat/heartbeat.conf
}
