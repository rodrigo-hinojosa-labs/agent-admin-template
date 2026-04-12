# agent-admin-template

Fork-friendly template for building Claude Code admin agents.

Turns the Claude Code CLI into a persistent, self-recovering personal admin agent with:
- **Wizard-driven setup** — answer a few questions, get a working agent
- **Pluggable notifications** — none, log, Telegram (trivially extensible)
- **Pre-configured MCPs** — Playwright, Fetch, Time, Sequential Thinking out of the box; optional Atlassian (multi-workspace) and GitHub
- **Persistent memory** (via `claude-mem` plugin)
- **Auto-recovery** — systemd timer (Linux) or launchd (macOS) keeps it running
- **Periodic heartbeat** — scheduled prompts that report back via your chosen channel

## Quick start

```bash
gh repo clone rodrigo-hinojosa/agent-admin-template my-agent
cd my-agent
./setup.sh
```

The wizard asks about identity, user, deployment, notifications, MCPs, and features. Press Enter to accept defaults.

## Requirements

- bash 4+
- [`yq`](https://github.com/mikefarah/yq) v4+
- [Claude Code CLI](https://claude.ai/code)
- `tmux`
- `jq` (for JSON validation in tests)
- `systemd` (Linux) or `launchd` (macOS) if you want the service to auto-start

## Re-running

```bash
./setup.sh                      # first-run wizard, or regenerate if agent.yml exists
./setup.sh --regenerate         # explicit regenerate (keeps your CLAUDE.md)
./setup.sh --reset              # wipe agent.yml and re-run the wizard
./setup.sh --uninstall          # undo install: stop services, remove scripts, timers, generated files
./setup.sh --uninstall --purge  # also remove agent.yml and .env
./setup.sh --help               # all flags
```

## File ownership

| File         | Owner  | On regenerate |
|--------------|--------|---------------|
| `agent.yml`  | user   | never touched |
| `.env`       | user   | never touched |
| `CLAUDE.md`  | user   | preserved     |
| everything else | system | re-rendered |

## Docs

- [Architecture](docs/architecture.md) — render engine, modules, data flow
- [Adding a notifier](docs/adding-a-notifier.md)
- [Adding an MCP](docs/adding-an-mcp.md)
- [Service architecture](docs/service-architecture.md) — auto-recovery, systemd/launchd
- [Parity notes](docs/parity-notes.md) — how the template output compares to the reference `rodri-agent-admin` baseline

## License

MIT. See [LICENSE](LICENSE).
