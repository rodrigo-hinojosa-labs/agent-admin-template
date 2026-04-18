# Siguientes pasos — {{AGENT_NAME}}

Hola {{USER_NICKNAME}}. Tu agente está listo en `{{DEPLOYMENT_WORKSPACE}}`.

{{#if CLAUDE_PROFILE_NEW}}
## ⚠ Login de Claude requerido antes del primer arranque

Este agente usa un perfil **nuevo y aislado** de Claude en `{{CLAUDE_CONFIG_DIR}}`.
Aún no tiene credenciales, así que el servicio se va a quedar atascado en el
wizard de login/theme al primer arranque. Haz esto **una vez** antes de
habilitar el servicio:

```bash
tmux new-session -d -s {{AGENT_NAME}}-setup "CLAUDE_CONFIG_DIR={{CLAUDE_CONFIG_DIR}} {{DEPLOYMENT_CLAUDE_CLI}}"
tmux attach -t {{AGENT_NAME}}-setup
# dentro del tmux: corre /login, elige tema, luego Ctrl-b d para salir
tmux kill-session -t {{AGENT_NAME}}-setup
```

Después, el service/launchd va a arrancar limpio.

{{/if}}
## Ir al workspace

```bash
cd {{DEPLOYMENT_WORKSPACE}}
```

{{#if SCAFFOLD_FORK_ENABLED}}
## Subir la rama al fork

```bash
git push -u origin {{SCAFFOLD_FORK_BRANCH}}
```

Tu fork vive en: {{SCAFFOLD_FORK_URL}}

Para replicar este agente en otro host:

```bash
git clone {{SCAFFOLD_FORK_URL}}.git ~/Claude/Agents/{{AGENT_NAME}}
cd ~/Claude/Agents/{{AGENT_NAME}}
git checkout {{SCAFFOLD_FORK_BRANCH}}
# luego corre ./setup.sh --regenerate en el nuevo host
```

{{/if}}
{{#if DEPLOYMENT_MODE_IS_DOCKER}}
## Modo Docker — próximos pasos

Tu agente está configurado como contenedor Docker. Para lanzarlo por primera vez:

    cd {{DEPLOYMENT_WORKSPACE}}
    docker compose build
    docker compose up -d
    docker attach {{AGENT_NAME}}

El wizard de primer arranque del contenedor pedirá tu token de bot de Telegram y chat id, escribirá /workspace/.env (0600) y saldrá. La política `unless-stopped` de Docker reinicia el contenedor en estado estable.

Para reconectarte más tarde: `docker exec -it {{AGENT_NAME}} tmux attach -t agent` (Ctrl-b d para salir).

Consulta docs/docker-mode.md para actualización, rollback y desmontaje.

{{/if}}
{{#unless DEPLOYMENT_MODE_IS_DOCKER}}
## Iniciar el agente

```bash
{{DEPLOYMENT_CLAUDE_CLI}}
```

## Primer prompt (cópialo tal cual en la primera sesión)

```
Primer arranque del agente {{AGENT_NAME}}. Valida en este orden y corrige lo que falte:

1. `ssh -T git@github.com` responde con mi usuario de GitHub.
2. `gh auth status` reporta una cuenta autenticada con scope repo.
3. El MCP de GitHub responde (lista mis repos públicos como sanity check).
4. La rama actual es {{SCAFFOLD_FORK_BRANCH}} y el remote origin apunta al fork.
{{#if SCAFFOLD_FORK_ENABLED}}
5. Puedes hacer `git push` sin errores de auth.
{{/if}}

Si alguno falla, guíame paso a paso para arreglarlo antes de seguir.
```

{{#unless MCPS_GITHUB_ENABLED}}
## GitHub MCP (no configurado)

El MCP de GitHub no quedó habilitado. Para activarlo:

1. Crea un PAT en https://github.com/settings/tokens con scope `repo`.
2. Añádelo a `.env`:
   ```
   GITHUB_PAT=tu_token_aqui
   ```
3. Edita `agent.yml` y pon `mcps.github.enabled: true`.
4. Corre `./setup.sh --regenerate` para actualizar `.mcp.json`.

{{/unless}}
{{#unless NOTIF_IS_TELEGRAM}}
## Telegram (chat bidireccional con el agente)

No configuraste Telegram en el wizard. Si quieres chatear con el agente desde tu teléfono:

1. Abre Telegram y habla con [@BotFather](https://t.me/BotFather).
2. Envía `/newbot`, nombre y username (debe terminar en `bot`).
3. Copia el token que te da BotFather.
4. Instala el plugin de chat (una vez por usuario):
   ```bash
   {{DEPLOYMENT_CLAUDE_CLI}} plugin install telegram@claude-plugins-official
   ```
5. Dentro de la sesión de Claude, corre `/telegram:configure` y pega el token.
6. Habla con [@userinfobot](https://t.me/userinfobot) para obtener tu `chat_id` numérico.
7. Corre `/telegram:access` en Claude y añade tu `chat_id` a la allowlist.
8. Envía un mensaje al bot y confirma que llega a la sesión.

{{/unless}}
{{#unless DEPLOYMENT_INSTALL_SERVICE}}
## Ejecutar el agente como servicio (opcional)

Dijiste `install_service: no` en el wizard. Si después quieres que {{AGENT_NAME}} arranque solo al encender el computador:

**Linux (systemd user):**
```bash
# crea el unit
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/{{AGENT_NAME}}.service <<EOF
[Unit]
Description={{AGENT_NAME}} (Claude Code launcher)
After=network-online.target

[Service]
Type=simple
ExecStart=/home/$USER/.local/bin/{{AGENT_NAME}}.sh
Restart=on-failure

[Install]
WantedBy=default.target
EOF

# activar arranque en boot (linger permite correr sin sesión abierta)
loginctl enable-linger $USER
systemctl --user daemon-reload
systemctl --user enable --now {{AGENT_NAME}}.service
systemctl --user status {{AGENT_NAME}}.service
```

**macOS (launchd):** crea `~/Library/LaunchAgents/com.{{AGENT_NAME}}.plist` y carga con `launchctl load -w`.

{{/unless}}
{{#if DEPLOYMENT_INSTALL_SERVICE}}
## Verificar el servicio

```bash
systemctl --user status {{AGENT_NAME}}.service
systemctl --user restart {{AGENT_NAME}}.service   # si necesitas reiniciar
```

{{/if}}
{{/unless}}
## Comandos útiles

```bash
./setup.sh --regenerate          # después de editar agent.yml
./setup.sh --sync-template       # traer mejoras del template al fork
./setup.sh --uninstall           # desmontar el agente
```

---

Cualquier problema, cuéntamelo en la primera sesión y lo diagnosticamos juntos.
