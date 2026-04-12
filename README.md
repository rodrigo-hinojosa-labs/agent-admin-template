# agent-admin-template

Fork-friendly template for building Claude Code admin agents.

Turns the Claude Code CLI into a persistent, self-recovering personal admin agent with:
- **Wizard-driven setup** — answer a few questions, get a working agent
- **Installer → destination model** — the clone is just the installer; your agent lives at a path you choose
- **Pluggable notifications** — none, log, Telegram (trivially extensible)
- **Pre-configured MCPs** — Playwright, Fetch, Time, Sequential Thinking out of the box; optional Atlassian (multi-workspace) and GitHub
- **Persistent memory** (via `claude-mem` plugin)
- **Auto-recovery** — systemd timer (Linux) or launchd (macOS) keeps it running
- **Periodic heartbeat** — scheduled prompts that report back via your chosen channel

## How it works

The cloned repo is an **installer**. When you run `./setup.sh`:

1. The wizard asks you a destination directory (e.g. `~/Claude/Agents/my-agent`)
2. The installer **copies its system files** (`setup.sh`, `modules/`, `scripts/`) to that destination
3. It **moves** your `agent.yml` and `.env` to the destination
4. It `cd`s there, generates `CLAUDE.md` / `.mcp.json` / service units / heartbeat config
5. It initializes a git repo in the destination on branch `{agent-name}/live`

The installer clone is disposable after scaffolding — you can delete it. All subsequent operations (regenerate, uninstall) happen from inside the destination.

## Quick start

```bash
git clone https://github.com/rodrigo-hinojosa/agent-admin-template.git /tmp/agent-installer
cd /tmp/agent-installer
./setup.sh
# ...answer the wizard, including your destination path...
# ...after completion, the installer tells you where your agent lives...

# Now go to your new agent:
cd ~/Claude/Agents/my-agent   # (or wherever you chose)
claude                         # starts the agent

# Optional:
rm -rf /tmp/agent-installer    # delete the installer clone if you're done with it
```

## All flags

| Flag | Effect |
|---|---|
| (no flags) | Auto: run wizard if `agent.yml` missing, else regenerate |
| `--regenerate` | Re-render derived files from `agent.yml` (`.mcp.json`, `heartbeat.conf`, service unit, etc.). **Preserves `CLAUDE.md`.** Use after editing `agent.yml`. |
| `--force-claude-md` | With `--regenerate`, also overwrite `CLAUDE.md` (destructive). |
| `--destination PATH` | **Wizard only.** Skip the destination prompt and scaffold to `PATH`. |
| `--in-place` | **Wizard only.** Skip the scaffold step and generate files in the current directory (legacy behavior). |
| `--reset` | Delete `agent.yml` and re-run the wizard. |
| `--non-interactive` | Require `agent.yml` to exist; no prompts. Just regenerate. Good for CI. |
| `--uninstall` | Stop services, remove installed scripts/timers/plists/tmux sessions, and delete generated files inside the agent dir. |
| `--purge` | With `--uninstall`, also remove `agent.yml` and `.env`. |
| `--yes` / `-y` | With `--uninstall`, skip the confirmation prompt. |
| `--help` / `-h` | Show the usage message. |

## Lifecycle

### First install
```bash
./setup.sh                        # wizard → scaffold destination
```

### Edit config, apply changes
```bash
cd <destination>
vim agent.yml                     # change anything
./setup.sh --regenerate           # re-render derived files
```

### Reinstall from scratch
```bash
cd <destination>
./setup.sh --reset                # wipe agent.yml, re-run wizard
```

### Tear it all down
```bash
cd <destination>
./setup.sh --uninstall            # stop services, remove generated files (keeps agent.yml + .env)
./setup.sh --uninstall --purge    # also remove agent.yml + .env
```

## Requirements

- bash 4+
- [`yq`](https://github.com/mikefarah/yq) v4+
- [Claude Code CLI](https://claude.ai/code)
- `tmux`
- `jq` (for JSON validation in tests)
- `git` (for scaffold's git init)
- `systemd` (Linux) or `launchd` (macOS) if you want the service to auto-start

## File ownership

| File | Owner | On regenerate |
|---|---|---|
| `agent.yml` | user | never touched |
| `.env` | user | never touched |
| `CLAUDE.md` | user | preserved |
| everything else | system | re-rendered |

## Docs

- [Architecture](docs/architecture.md) — render engine, modules, data flow
- [Adding a notifier](docs/adding-a-notifier.md)
- [Adding an MCP](docs/adding-an-mcp.md)
- [Service architecture](docs/service-architecture.md) — auto-recovery, systemd/launchd
- [Parity notes](docs/parity-notes.md)

## License

MIT. See [LICENSE](LICENSE).
