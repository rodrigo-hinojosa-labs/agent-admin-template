# Siguientes pasos — {{AGENT_NAME}}

Hola {{USER_NICKNAME}}. Tu agente está listo en `{{DEPLOYMENT_WORKSPACE}}`.

## 1. Ir al workspace

```bash
cd {{DEPLOYMENT_WORKSPACE}}
```

{{#if SCAFFOLD_FORK_ENABLED}}
## 2. Subir la rama al fork

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
## 3. Iniciar el agente

```bash
{{DEPLOYMENT_CLAUDE_CLI}}
```

## 4. Primer prompt (cópialo tal cual en la primera sesión)

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
## 5. GitHub MCP (no configurado)

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
## 6. Telegram (chat bidireccional con el agente)

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
## 7. Ejecutar el agente como servicio (opcional)

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
## 7. Verificar el servicio

```bash
systemctl --user status {{AGENT_NAME}}.service
systemctl --user restart {{AGENT_NAME}}.service   # si necesitas reiniciar
```

{{/if}}
## 8. Comandos útiles

```bash
./setup.sh --regenerate          # después de editar agent.yml
./setup.sh --sync-template       # traer mejoras del template (próximamente)
./setup.sh --uninstall           # desmontar el agente
```

---

Cualquier problema, cuéntamelo en la primera sesión y lo diagnosticamos juntos.
