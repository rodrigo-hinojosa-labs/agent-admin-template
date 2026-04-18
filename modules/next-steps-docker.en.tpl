# {{AGENT_DISPLAY_NAME}} — next steps (Docker mode)

Your agent is scaffolded as a Docker container at `{{DEPLOYMENT_WORKSPACE}}`.

## First boot

```bash
cd {{DEPLOYMENT_WORKSPACE}}
docker compose build
docker compose up -d
docker attach {{AGENT_NAME}}
```

The container's first-run wizard asks for your Telegram bot token and chat id, writes `/workspace/.env` (0600), then exits. Docker's `unless-stopped` policy restarts the container into steady state.

## Daily use

Reconnect from any terminal:

```bash
docker exec -it {{AGENT_NAME}} tmux attach -t agent
```

`Ctrl-b d` to detach without killing the session.

## Upgrade and teardown

See [docs/docker-mode.md](docs/docker-mode.md) for upgrade, rollback, rotating secrets, and teardown.

## Useful commands

```bash
./setup.sh --regenerate          # after editing agent.yml
./setup.sh --uninstall --yes     # stop container, remove named volume, unit file
./setup.sh --uninstall --nuke --yes  # also delete the workspace directory
```
