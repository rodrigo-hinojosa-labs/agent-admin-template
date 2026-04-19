# {{AGENT_DISPLAY_NAME}} — siguientes pasos (modo Docker)

Tu agente está scaffoldeado como contenedor Docker en `{{DEPLOYMENT_WORKSPACE}}`.

## 1. Build y arranque

```bash
cd {{DEPLOYMENT_WORKSPACE}}
docker compose build
docker compose up -d
docker attach {{AGENT_NAME}}
```

El contenedor arranca Claude Code directamente — sin prompts ni wizards todavía.
Para salir de `docker attach` sin matar el contenedor: `Ctrl-p Ctrl-q` (NO `Ctrl-c`).

## 2. Login en Claude (una sola vez)

Dentro de la sesión:

1. Elige un tema (Enter acepta el default) y confirma trust en `/workspace`.
2. Corre `/login`, abre la URL en el navegador, autoriza, pega el código de vuelta. Las credenciales viven en el named volume (`{{AGENT_NAME}}-state`) y sobreviven rebuilds.
3. Escribe `/exit` (o Ctrl-D). Claude cierra; el watchdog se entera y re-evalúa qué lanzar.

## 3. Ingresa el token del bot de Telegram

Reconéctate a la sesión tmux:

```bash
docker exec -it -u agent {{AGENT_NAME}} tmux attach -t agent
```

El supervisor ahora detecta el perfil autenticado y lanza el wizard in-container:

- `Telegram bot token (from @BotFather):` — pega tu token.
- `Add a GitHub Personal Access Token (for gh / MCP)?` — opcional.
- Por cada workspace de Atlassian declarado en `agent.yml`, pega el API token (o Enter para saltarlo).

El wizard escribe `/workspace/.env` (0600) y sale. El watchdog ve que la sesión murió, re-decide, y esta vez arranca Claude con `--channels plugin:telegram@claude-plugins-official`. El MCP server del plugin (`bun server.ts`) arranca solo y empieza a polear Telegram.

## 4. Emparejar tu cuenta de Telegram

Re-attach una vez más:

```bash
docker exec -it -u agent {{AGENT_NAME}} tmux attach -t agent
```

Luego:

1. Mándale un DM al bot desde Telegram — te responde con un código de 6 caracteres.
2. En la sesión de Claude: `/telegram:access pair <código>` (aprueba el overwrite de `access.json`).
3. Tu chat id queda en el allowlist; el bot confirma con "you're in".
4. Manda otro DM para verificar — el mensaje llega a Claude y Claude responde.

Para salir sin matar la sesión: `Ctrl-b d`.

## Uso diario

```bash
# Reconectar a la sesión
docker exec -it -u agent {{AGENT_NAME}} tmux attach -t agent

# Rotar un secreto
$EDITOR {{DEPLOYMENT_WORKSPACE}}/.env
docker compose restart

# Actualizar a una versión nueva del template
cd {{DEPLOYMENT_WORKSPACE}}
git pull                                 # si tu workspace es un fork
docker compose build && docker compose up -d
```

## Desmantelamiento

```bash
./setup.sh --uninstall --yes             # detiene contenedor, remueve named volume + unit de host
./setup.sh --uninstall --nuke --yes      # también borra este directorio de workspace
```

## Troubleshooting

Issues comunes y soluciones en [docs/docker-mode.md](docs/docker-mode.md) (plugin no conecta, permisos, crond silencioso, UID mismatch, etc.).
