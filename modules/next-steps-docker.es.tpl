# {{AGENT_DISPLAY_NAME}} — siguientes pasos (modo Docker)

Tu agente está estructurado como contenedor Docker en `{{DEPLOYMENT_WORKSPACE}}`.

## Primer arranque

```bash
cd {{DEPLOYMENT_WORKSPACE}}
docker compose build
docker compose up -d
docker attach {{AGENT_NAME}}
```

El wizard del primer arranque del contenedor te pide el token del bot de Telegram y el chat id, escribe `/workspace/.env` (0600), y luego sale. La política `unless-stopped` de Docker reinicia el contenedor a estado estable.

## Uso diario

Reconecta desde cualquier terminal:

```bash
docker exec -it {{AGENT_NAME}} tmux attach -t agent
```

`Ctrl-b d` para desconectarte sin matar la sesión.

## Upgrade y desmantelamiento

Ver [docs/docker-mode.md](docs/docker-mode.md) para upgrade, rollback, rotación de secretos, y desmantelamiento.

## Comandos útiles

```bash
./setup.sh --regenerate          # después de editar agent.yml
./setup.sh --uninstall --yes     # detener contenedor, remover volumen, unit file
./setup.sh --uninstall --nuke --yes  # también borrar el directorio del workspace
```
