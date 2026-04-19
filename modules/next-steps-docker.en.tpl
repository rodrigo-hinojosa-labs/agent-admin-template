# {{AGENT_DISPLAY_NAME}} — next steps (Docker mode)

Your agent is scaffolded as a Docker container at `{{DEPLOYMENT_WORKSPACE}}`.

## 1. Build and launch

```bash
cd {{DEPLOYMENT_WORKSPACE}}
docker compose build
docker compose up -d
docker attach {{AGENT_NAME}}
```

The in-container wizard asks for your Telegram bot token (from @BotFather) and optionally a GitHub PAT. It writes `/workspace/.env` (0600) and exits — Docker's `unless-stopped` policy restarts the container into steady state within seconds.

Detach from `docker attach` without killing the container: `Ctrl-p Ctrl-q` (NOT `Ctrl-c`).

## 2. One-time Claude authentication

After the container restarts, reconnect to the session and finish first-run setup:

```bash
docker exec -it {{AGENT_NAME}} tmux attach -t agent
```

Inside the session:

1. Pick a theme (Enter accepts the default).
2. `/login` → open the URL in your browser → authorize → paste the code back. Credentials land on the named state volume (`{{AGENT_NAME}}-state`) and survive rebuilds.
3. `/plugin install telegram@claude-plugins-official` → adds the two-way Telegram bridge.
4. `/reload-plugins`.

## 3. Pair your Telegram account

1. DM your bot from Telegram — it replies with a 6-character code.
2. In the Claude session: `/telegram:access pair <code>` (approve the overwrite of `access.json` when prompted).
3. Your chat id is now on the allowlist; the bot will confirm with "you're in".
4. Send another message from Telegram to verify it reaches Claude.

Detach with `Ctrl-b d`.

## Daily use

```bash
# Reconnect to the session
docker exec -it {{AGENT_NAME}} tmux attach -t agent

# Rotate a secret
$EDITOR {{DEPLOYMENT_WORKSPACE}}/.env
docker compose restart

# Upgrade to a new template version
cd {{DEPLOYMENT_WORKSPACE}}
git pull                                 # if your workspace is a fork
docker compose build && docker compose up -d
```

## Teardown

```bash
./setup.sh --uninstall --yes             # stops container, removes named volume + host unit
./setup.sh --uninstall --nuke --yes      # also deletes this workspace directory
```

## Troubleshooting

Common issues and fixes live in [docs/docker-mode.md](docs/docker-mode.md) (plugin not connected, permission prompts, crond silent, UID mismatch, etc.).
