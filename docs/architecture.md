# Architecture

agent-admin-template is a bash-based template generator that produces a personalized Claude Code admin agent from a single source of truth (`agent.yml`).

## Two layers

**Configuration layer (user-owned):**
- `agent.yml` — structured config (identity, user, deployment, notifications, features, MCPs, plugins)
- `.env` — secrets (tokens, credentials)
- `CLAUDE.md` — agent personality; generated once, then owned by the user

**System layer (template-owned):**
- `modules/*.tpl` — templates with `{{PLACEHOLDER}}`, `{{#if}}`, `{{#each}}` syntax
- `scripts/lib/` — shared bash libraries (render engine, YAML reader, wizard helpers)
- `scripts/heartbeat/` — heartbeat runtime and pluggable notifier drivers
- `setup.sh` — wizard + regenerate orchestrator

## Render engine

The render engine (`scripts/lib/render.sh`) is a minimal template processor with three features:

**Placeholders:** `{{UPPERCASE_VAR}}` → substitute with env var value. All YAML scalar paths are exposed as env vars: `.agent.name` → `AGENT_NAME`, `.user.nickname` → `USER_NICKNAME`, etc.

**Conditionals:**
- `{{#if VAR}}...{{/if}}` — include block if `VAR == "true"`
- `{{#unless VAR}}...{{/unless}}` — include block if `VAR != "true"`

**Loops:** `{{#each ARRAY_VAR}}...{{/each}}` iterates over a YAML array. Inside the block, `{{fieldname}}` references each item's fields (lowercase).

Implemented in bash + perl -0777 for multi-line regex. Limitation: no nested conditionals or loops (flat only). This is intentional — if you need more, rewrite in a real templating language.

## Data flow

```
user → setup.sh wizard → writes agent.yml + .env
                      ↓
         render_load_context(agent.yml) exports env vars
                      ↓
         For each module in modules/*.tpl:
           render_to_file(tpl, destination)
                      ↓
         Final files: CLAUDE.md, .mcp.json, .env.example,
                      scripts/heartbeat/heartbeat.conf,
                      ~/.local/bin/{agent}.sh (Linux) or launchd plist
```

## Tests

`bats-core` drives ~40 tests across unit and integration levels:
- `tests/yaml.bats` — yaml.sh reader
- `tests/render.bats` — render engine primitives
- `tests/wizard.bats` — prompt helpers
- `tests/setup.bats` + `tests/wizard-flow.bats` — setup.sh integration
- `tests/claude-md.bats`, `mcp-json.bats`, `modules-render.bats` — per-module rendering
- `tests/notifiers.bats` — heartbeat notifier drivers
- `tests/regenerate.bats`, `tests/plugins.bats` — regenerate + plugin install flows
- `tests/e2e-smoke.bats` — end-to-end wizard → functional agent
