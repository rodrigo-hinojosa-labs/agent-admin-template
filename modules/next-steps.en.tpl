# Next steps — {{AGENT_NAME}}

Hi {{USER_NICKNAME}}. Your agent is ready at `{{DEPLOYMENT_WORKSPACE}}`.

{{#if CLAUDE_PROFILE_NEW}}
## ⚠ Claude login required before first run

This agent uses a **new isolated** Claude profile at `{{CLAUDE_CONFIG_DIR}}`.
It has no credentials yet, so the service will get stuck on the login/theme
wizard on first start. Do this **once** before enabling the service:

```bash
tmux new-session -d -s {{AGENT_NAME}}-setup "CLAUDE_CONFIG_DIR={{CLAUDE_CONFIG_DIR}} {{DEPLOYMENT_CLAUDE_CLI}}"
tmux attach -t {{AGENT_NAME}}-setup
# inside tmux: run /login, pick your theme, then Ctrl-b d to detach
tmux kill-session -t {{AGENT_NAME}}-setup
```

After that, the service/launchd unit will start cleanly.

{{/if}}
## Go to the workspace

```bash
cd {{DEPLOYMENT_WORKSPACE}}
```

{{#if SCAFFOLD_FORK_ENABLED}}
## Push the branch to your fork

```bash
git push -u origin {{SCAFFOLD_FORK_BRANCH}}
```

Your fork lives at: {{SCAFFOLD_FORK_URL}}

To replicate this agent on another host:

```bash
git clone {{SCAFFOLD_FORK_URL}}.git ~/Claude/Agents/{{AGENT_NAME}}
cd ~/Claude/Agents/{{AGENT_NAME}}
git checkout {{SCAFFOLD_FORK_BRANCH}}
# then run ./setup.sh --regenerate on the new host
```

{{/if}}
## Start the agent

```bash
{{DEPLOYMENT_CLAUDE_CLI}}
```

## First prompt (paste as-is into the first session)

```
First boot of agent {{AGENT_NAME}}. Validate in this order and fix anything missing:

1. `ssh -T git@github.com` responds with my GitHub username.
2. `gh auth status` reports an authenticated account with repo scope.
3. The GitHub MCP responds (list my public repos as a sanity check).
4. Current branch is {{SCAFFOLD_FORK_BRANCH}} and origin points to the fork.
{{#if SCAFFOLD_FORK_ENABLED}}
5. `git push` works without auth errors.
{{/if}}

If any step fails, walk me through fixing it before continuing.
```

{{#unless MCPS_GITHUB_ENABLED}}
## GitHub MCP (not configured)

GitHub MCP isn't enabled. To turn it on:

1. Create a PAT at https://github.com/settings/tokens with `repo` scope.
2. Add it to `.env`:
   ```
   GITHUB_PAT=your_token_here
   ```
3. Edit `agent.yml` and set `mcps.github.enabled: true`.
4. Run `./setup.sh --regenerate` to refresh `.mcp.json`.

{{/unless}}
{{#unless NOTIF_IS_TELEGRAM}}
## Telegram (two-way chat with the agent)

You didn't set up Telegram in the wizard. To chat with the agent from your phone:

1. Open Telegram and message [@BotFather](https://t.me/BotFather).
2. Send `/newbot`, pick a name and a username (must end in `bot`).
3. Copy the token BotFather gives you.
4. Install the chat plugin (once per user):
   ```bash
   {{DEPLOYMENT_CLAUDE_CLI}} plugin install telegram@claude-plugins-official
   ```
5. Inside the Claude session, run `/telegram:configure` and paste the token.
6. Message [@userinfobot](https://t.me/userinfobot) to get your numeric `chat_id`.
7. Run `/telegram:access` in Claude and add your `chat_id` to the allowlist.
8. Send a message to the bot and confirm it reaches the session.

{{/unless}}
{{#unless DEPLOYMENT_INSTALL_SERVICE}}
## Run the agent as a service (optional)

You picked `install_service: no`. If you later want {{AGENT_NAME}} to start on boot:

**Linux (systemd user):**
```bash
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

loginctl enable-linger $USER
systemctl --user daemon-reload
systemctl --user enable --now {{AGENT_NAME}}.service
systemctl --user status {{AGENT_NAME}}.service
```

**macOS (launchd):** create `~/Library/LaunchAgents/com.{{AGENT_NAME}}.plist` and load with `launchctl load -w`.

{{/unless}}
{{#if DEPLOYMENT_INSTALL_SERVICE}}
## Verify the service

```bash
systemctl --user status {{AGENT_NAME}}.service
systemctl --user restart {{AGENT_NAME}}.service   # if you need to restart
```

{{/if}}
## Useful commands

```bash
./setup.sh --regenerate          # after editing agent.yml
./setup.sh --sync-template       # pull template improvements into the fork
./setup.sh --uninstall           # tear down the agent
```

---

Hit a snag? Report it in the first session and we'll debug together.
