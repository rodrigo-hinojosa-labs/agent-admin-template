# Quickstart — Agentic mode (English)

Instead of answering the interactive wizard, you clone the repo, open a Claude Code session in the cloned directory, and paste a single prompt that drives `./setup.sh` end-to-end.

## When to use this mode

- You're already working inside Claude Code and don't want to drop to the shell.
- You want to reproduce the same agent across multiple hosts with identical configuration.
- You prefer reviewing the configuration block in one place before running.

## Prerequisites

- `git`, `yq`, `gh`, and `claude` installed.
- A GitHub Personal Access Token with `repo` scope (and `delete_repo` if you plan to use `--delete-fork` later).
- Push access to the fork owner (your personal account or an org you belong to).

## Steps

1. Clone the repo and enter it:
   ```bash
   git clone https://github.com/rodrigo-hinojosa-labs/agent-admin-template.git
   cd agent-admin-template
   ```
2. Open Claude Code:
   ```bash
   claude
   ```
3. Fill in the configuration block below with your values.
4. Paste the configuration block followed by the instruction block into the Claude session.
5. Claude validates prerequisites, runs `./setup.sh`, and shows you the rendered `NEXT_STEPS.md` when done.

---

## Block 1 — Configuration (fill in before pasting)

```
AGENT_NAME="linus"
DISPLAY_NAME="Linus 🐧"
ROLE="Admin assistant for my ecosystem"
VIBE="Direct, useful, no drama"

USER_NAME="Rodrigo Hinojosa"
NICKNAME="Rodri"
TIMEZONE="America/Santiago"
EMAIL="you@example.com"
LANGUAGE="en"                    # es | en | mixed

HOST=""                          # empty = hostname -s of the current host
DESTINATION="$HOME/Claude/Agents/linus"
INSTALL_SERVICE="y"              # y | n

FORK_ENABLED="y"                 # y | n — if n, all FORK_* are ignored
FORK_OWNER="rodri-agents"        # user or organization
FORK_NAME=""                     # empty = <agent>-<host>
FORK_PRIVATE="y"
TEMPLATE_URL="https://github.com/rodrigo-hinojosa-labs/agent-admin-template"
FORK_PAT=""                      # ghp_... with repo scope

HEARTBEAT_NOTIF="none"           # none | log | telegram
ATLASSIAN_ENABLED="n"
GITHUB_MCP_ENABLED="n"
GITHUB_MCP_EMAIL=""              # if ENABLED=y
GITHUB_MCP_PAT=""                # if ENABLED=y — may reuse FORK_PAT

HEARTBEAT_ENABLED="n"
HEARTBEAT_INTERVAL="30m"
HEARTBEAT_PROMPT="Check status and report"
USE_DEFAULT_PRINCIPLES="y"
```

## Block 2 — Instructions (paste as-is after block 1)

```
Run the agent-admin-template wizard using the values above.

Before running:
1. Confirm `yq`, `git`, and `gh` are on PATH.
2. If FORK_ENABLED="y", export GH_TOKEN=$FORK_PAT and verify `gh api user` returns a valid login.
3. Verify $DESTINATION does not already exist.
4. If any required value is empty (AGENT_NAME, USER_NAME, EMAIL, or — when FORK_ENABLED=y — FORK_OWNER and FORK_PAT), stop and ask me for the missing values before continuing.

Then:
5. Build the wizard stdin with `printf`, honoring the exact prompt order:
   - Agent identity: AGENT_NAME, DISPLAY_NAME, ROLE, VIBE
   - About you: USER_NAME, NICKNAME, TIMEZONE, EMAIL, LANGUAGE
   - Deployment: HOST, DESTINATION, INSTALL_SERVICE
   - Fork: FORK_ENABLED [if y: FORK_OWNER, FORK_NAME, FORK_PRIVATE, TEMPLATE_URL, FORK_PAT]
   - Heartbeat notifications: HEARTBEAT_NOTIF
   - MCPs: ATLASSIAN_ENABLED [if y: atlassian loop], GITHUB_MCP_ENABLED [if y: email + PAT]
   - Features: HEARTBEAT_ENABLED [if y: INTERVAL, PROMPT]
   - Principles: USE_DEFAULT_PRINCIPLES
   - Action: "" (proceed)

6. Pipe that stdin to `./setup.sh` and capture stdout+stderr.
7. If any scaffold step fails (fork creation, fetch, rebase), show me the full error and stop — do not silently "fix" by mutating agent.yml without asking.
8. On success, print the `NEXT_STEPS.md` rendered into $DESTINATION and summarize:
   - The live branch created (e.g. `<host>-<agent>-v1/live`)
   - The fork URL
   - What's still pending (initial push, SSH/MCP validation, plugin install)

Don't ask for confirmation between steps — proceed unless a required value is missing or a validation fails.
```

---

## Security

⚠ The PAT lives in the Claude session's context. If your memory system (`claude-mem`, similar plugins) indexes sessions, **treat the token as compromised** and revoke it at https://github.com/settings/tokens when you're done. Generate a new one for ongoing use.

## Alternative: interactive wizard

If you prefer the traditional terminal-prompt flow, run `./setup.sh` and answer each question by hand — see the [Quick start](../README.md#quick-start) section of the README.
