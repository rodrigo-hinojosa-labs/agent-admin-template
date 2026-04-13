# agent-admin-template

Fork-friendly template for building Claude Code admin agents.

Turns the Claude Code CLI into a persistent, self-recovering personal admin agent with:
- **Wizard-driven setup** — answer a few questions, get a working agent
- **Installer → destination model** — the clone is just the installer; your agent lives at a path you choose
- **Pluggable heartbeat notifier** — none, log, or a standalone Telegram bot (easy to extend)
- **Pre-configured MCPs** — Playwright, Fetch, Time, Sequential Thinking out of the box; optional Atlassian (multi-workspace) and GitHub
- **Persistent memory** (via `claude-mem` plugin)
- **Auto-recovery** — systemd timer (Linux) or launchd (macOS) keeps it running
- **Periodic heartbeat** — scheduled prompts that report back via your chosen channel

## Telegram: two separate things

This template treats Telegram as two distinct concerns:

| Use case | How to set it up |
|----------|------------------|
| **Bidirectional chat with the agent** (you message the agent from Telegram, it replies) | Install the official plugin: `claude plugin install telegram@claude-plugins-official` and follow its setup. Independent of this template. |
| **Heartbeat status pings** (one-way "heartbeat ran / failed" notifications) | Choose `telegram` during the wizard's "Heartbeat notifications" step. Uses a standalone bot + chat ID in `.env` (`NOTIFY_BOT_TOKEN` / `NOTIFY_CHAT_ID`). |

You can use either, both (with different bots to separate chat from alerts), or neither.

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

## Quickstart — Agentic mode

Prefer to drive setup from inside a Claude Code session instead of answering prompts in the terminal? Open `claude` in the cloned directory and paste the prompt from one of the guides below — Claude validates prerequisites, runs the wizard with your pre-filled values, and shows you the rendered `NEXT_STEPS.md`.

- 🇪🇸 [Modo agéntico — guía en español](docs/agentic-quickstart.es.md)
- 🇬🇧 [Agentic mode — guide in English](docs/agentic-quickstart.en.md)

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
| `--nuke` | With `--uninstall`, also remove the workspace directory itself (and its parent if left empty). Implies `--purge`. |
| `--yes` / `-y` | With `--uninstall`, skip the confirmation prompt. |
| `--sync-template` | Pull upstream template improvements into the fork: fetch `upstream/main`, fast-forward local `main`, push to `origin`, rebase the live branch. Fork-based agents only. |
| `--delete-fork` | With `--uninstall`, also delete the GitHub fork (irreversible). Requires `--yes`. PAT needs `delete_repo` scope. |
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
./setup.sh --uninstall --nuke     # everything above + delete the workspace dir itself
./setup.sh --uninstall --nuke --delete-fork --yes   # full teardown incl. GitHub fork (irreversible)
```

## Claude profile (config dir)

The agent runs Claude Code with `CLAUDE_CONFIG_DIR` pointing at a directory that holds the login, plugins and MCP config. The wizard picks this for you:

- **Auto-inherit** — if the wizard is launched from a Claude Code session that already has `$CLAUDE_CONFIG_DIR` set (agentic mode), the agent inherits that profile verbatim. No extra `/login` needed.
- **Existing profile** — if you have `~/.claude`, `~/.claude-personal`, `~/.claude-enterprise` (or similar) already, the wizard offers them as a pick-list. The agent shares login + plugins with whichever you choose.
- **New isolated** — explicit opt-in. The wizard creates `~/.claude-<agent>` and flags that you'll need to run `/login` once inside the tmux session after install. `NEXT_STEPS.md` also spells out the exact commands.

The choice is stored at `claude.config_dir` in `agent.yml`. Edit it and run `./setup.sh --regenerate` to switch profiles on an existing agent.

## Fork-based workflow

When the wizard creates a fork (default when you answer `Y` to *"Create a GitHub fork?"*), the destination is a git repo pointing at:

- `origin` → your fork (e.g. `rodri-agents/<agent>-agent`)
- `upstream` → the template repo (e.g. `rodrigo-hinojosa-labs/agent-admin-template`)

The live branch is named `<host>-<agent>-v<N>/live` (e.g. `ferrari-demo-1/live`). The number increments from existing `*-*-v*/live` branches on the fork so scaffolding the same agent on a new host gives you `v2`, `v3`, etc.

### Pulling template improvements
```bash
cd <destination>
./setup.sh --sync-template
```
This does: `git fetch upstream && git merge --ff-only upstream/main` on `main`, pushes `main` to `origin`, then `git rebase main` on the live branch. Aborts cleanly on any divergence or conflict with instructions to resolve.

### Replicating an agent on another host
```bash
git clone https://github.com/<owner>/<fork>.git ~/Claude/Agents/<agent>
cd ~/Claude/Agents/<agent>
git checkout <branch>          # the *-v*/live branch you scaffolded
./setup.sh --regenerate        # re-render derived files for this host
```

## Interactive wizard

The wizard uses [`gum`](https://github.com/charmbracelet/gum) for arrow-key-capable prompts (edit text with left/right, select options with up/down). On first run, `setup.sh` auto-downloads gum to `scripts/vendor/bin/gum` (gitignored, ~5MB, one-time).

If you're running in a non-interactive shell (CI, piped stdin), the wizard falls back to plain `read` prompts — no gum needed.

After filling in all answers, the summary screen shows every choice numbered. Pick **edit** to jump back and change a specific field without re-answering everything, **proceed** to continue, or **abort** to cancel.

## Requirements

- bash 4+
- [`yq`](https://github.com/mikefarah/yq) v4+
- [Claude Code CLI](https://claude.ai/code)
- `tmux`
- `jq` (for JSON validation in tests)
- `git` (for scaffold's git init)
- [`gh`](https://cli.github.com/) CLI (only if you enable the GitHub fork flow — scaffold uses it for `repo fork`, `repo edit`, `api branches`, `repo delete`)
- `curl` and `tar` (for the gum bootstrap on first run — already present on macOS/Linux)
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
