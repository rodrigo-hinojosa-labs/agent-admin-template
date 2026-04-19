# {{AGENT_DISPLAY_NAME}} — siguientes pasos (modo Docker)

Tu agente está scaffoldeado como contenedor Docker en `{{DEPLOYMENT_WORKSPACE}}`.

## 1. Build y arranque

```bash
cd {{DEPLOYMENT_WORKSPACE}}
docker compose build
docker compose up -d
docker attach {{AGENT_NAME}}
```

El wizard dentro del contenedor te pide el bot token (de @BotFather) y, opcionalmente, un GitHub PAT. Escribe `/workspace/.env` (0600) y sale — la política `unless-stopped` de Docker reinicia el contenedor a estado estable en segundos.

Para salir de `docker attach` sin matar el contenedor: `Ctrl-p Ctrl-q` (NO `Ctrl-c`).

## 2. Autenticación única de Claude

Después del reinicio, reconéctate a la sesión:

```bash
docker exec -it {{AGENT_NAME}} tmux attach -t agent
```

Dentro de la sesión:

1. Elige un tema (Enter acepta el default) y confirma trust en `/workspace`.
2. `/login` → abre la URL en el navegador → autoriza → pega el código de vuelta. Las credenciales viven en el named volume (`{{AGENT_NAME}}-state`) y sobreviven rebuilds.
3. Escribe `/exit` (o Ctrl-D). El watchdog respawneará Claude automáticamente — en ese respawn, `start_services.sh` detecta que el perfil ya está autenticado e instala el plugin `telegram@claude-plugins-official` con `--channels` habilitado. No tienes que hacer `/plugin install` manualmente.

## 3. Emparejar tu cuenta de Telegram

1. Mándale un DM al bot desde Telegram — te responde con un código de 6 caracteres.
2. En la sesión de Claude: `/telegram:access pair <código>` (aprueba el overwrite de `access.json`).
3. Tu chat id queda en el allowlist; el bot confirma con "you're in".
4. Manda otro mensaje desde Telegram para verificar que llega a Claude.

Para desconectarte sin matar la sesión: `Ctrl-b d`.

## Uso diario

```bash
# Reconectar a la sesión
docker exec -it {{AGENT_NAME}} tmux attach -t agent

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
