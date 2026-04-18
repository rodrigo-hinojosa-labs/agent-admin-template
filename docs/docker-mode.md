# Docker Mode

Docker mode encapsulates all per-agent state and runtime inside a container, ensuring that teardown is clean and reversible: `docker rm -v && rm -rf ~/agents/<name>` removes all traces of the agent from the host.

Use `--docker` when you want isolated, portable agents with zero residue on teardown. See [Docker Architecture](docker-architecture.md) for the technical design.

## Prerequisites

- Docker v24+ (for `compose v2` integration)
- Docker Compose v2 (bundled with Docker Desktop; available separately on Linux)
- ~2GB disk for the image and state volume combined
- Bash 4+ on the host (for the installer wizard)

## Scaffold

Run the installer wizard with the `--docker` flag:

```bash
./setup.sh --docker
```

The wizard is interactive and runs on the host:

1. Agent name (e.g. `claude-dev`).
2. Personality and description.
3. Optional MCPs (Playwright, GitHub, Atlassian, etc.).
4. Notification channel (Telegram).

**Important:** Sensitive tokens (Telegram bot token, chat ID, GitHub PAT) are **not** requested here. They are deferred to the container's first-run wizard.

Output:

- `~/agents/<name>/` — workspace with `agent.yml`, `docker-compose.yml`, and scripts.
- `/etc/systemd/system/agent-<name>.service` — host unit to manage the container.
- On-screen instructions for next steps.

## First Boot

After scaffolding, start the agent:

```bash
cd ~/agents/<name>
docker compose up -d
docker attach <name>
```

The container starts and the in-container wizard fires (interactive via `gum` prompts):

1. **Telegram bot token** — the token from `@BotFather` on Telegram.
2. **Telegram chat ID** — your numeric user ID or group chat ID.
3. **GitHub PAT** (optional) — personal access token for the GitHub MCP.

The wizard writes `/workspace/.env` with 0600 permissions. Once complete, it exits. The container restarts (due to `unless-stopped` policy) and begins steady-state operation.

## Daily Use

Connect to the agent's tmux session:

```bash
ssh <host>
docker exec -it <name> tmux attach -t agent
```

This gives you an interactive Claude session. Detach with `Ctrl-b d` (standard tmux binding).

All agent output and interaction happens inside the container. There is no host-side tmux or CLI state.

## Upgrade

When you update the template:

```bash
# Tag the current image as backup
docker tag agent-admin:latest agent-admin:prev

# Update the template repo
cd agent-admin-template
git pull

# Rebuild and restart the container
cd ~/agents/<name>
docker compose build
docker compose up -d
```

The workspace bind-mount and state volume persist across rebuilds, so all agent data and configuration survive the upgrade.

## Rollback

If the new image is unstable:

```bash
docker tag agent-admin:prev agent-admin:latest
docker compose up -d
```

The container restarts with the previous image. No state is lost.

## Rotating Secrets

To update Telegram tokens or GitHub PAT without rebuilding:

```bash
# Edit the .env file on the host
nano ~/agents/<name>/.env

# Restart the container (applies new env vars)
docker compose restart
```

The agent picks up new tokens on the next connection attempt. Changes take effect immediately; no rebuild needed.

## Teardown

To remove the agent completely:

```bash
cd ~/agents/<name>
./setup.sh --uninstall --yes
```

This:

1. Stops the container.
2. Runs `docker compose down -v` (removes container and state volume).
3. Removes the host systemd unit.
4. Keeps the workspace directory.

To also delete the workspace:

```bash
./setup.sh --uninstall --yes --nuke
```

After teardown, no traces of the agent remain on the host (no dotfiles, no systemd units, no leftover state).

## Troubleshooting

### UID mismatch (permission errors in logs)

If you see permission errors on bind-mount files, verify that `docker.uid` in `agent.yml` matches the host user:

```bash
id -u  # your user ID on the host
grep "docker:" ~/agents/<name>/agent.yml  # should contain matching UID
```

If they differ:

```bash
# Edit agent.yml and update docker.uid to match your user ID
nano ~/agents/<name>/agent.yml
docker compose build
docker compose up -d
```

### Container logs

View container startup and runtime logs:

```bash
docker logs <name>
docker logs -f <name>  # follow in real time
```

### Crond logs

The heartbeat runs via `crond` inside the container. If the heartbeat is not firing, check:

```bash
docker exec <name> cat /workspace/claude.cron.log
```

### Wizard re-fires after reboot

If the wizard runs again on container restart, the `.env` file is missing or corrupted. Verify:

```bash
ls -la ~/agents/<name>/.env
cat ~/agents/<name>/.env | grep TELEGRAM_BOT_TOKEN
```

If missing, populate it and restart:

```bash
# Re-populate .env interactively
docker compose up  # (not -d) to run the wizard again
# Complete the prompts, then Ctrl-C and restart as daemon
docker compose up -d
```

If `.env` exists but the wizard still fires, check permissions:

```bash
stat ~/agents/<name>/.env  # should be 0600, owned by your user
```
