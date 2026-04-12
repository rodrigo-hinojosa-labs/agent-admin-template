# Next steps — {{AGENT_NAME}}

Hi {{USER_NICKNAME}}. Your agent is ready at `{{DEPLOYMENT_WORKSPACE}}`.

## 1. Go to the workspace

```bash
cd {{DEPLOYMENT_WORKSPACE}}
```

{{#if SCAFFOLD_FORK_ENABLED}}
## 2. Push the branch to your fork

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
## 3. Start the agent

```bash
{{DEPLOYMENT_CLAUDE_CLI}}
```

## 4. First prompt (paste as-is into the first session)

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
## 5. GitHub MCP (not configured)

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
## 6. Telegram (two-way chat with the agent)

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
## 7. Run the agent as a service (optional)

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
## 7. Verify the service

```bash
systemctl --user status {{AGENT_NAME}}.service
systemctl --user restart {{AGENT_NAME}}.service   # if you need to restart
```

{{/if}}
## 8. Useful commands

```bash
./setup.sh --regenerate          # after editing agent.yml
./setup.sh --sync-template       # pull template improvements (coming soon)
./setup.sh --uninstall           # tear down the agent
```

---

Hit a snag? Report it in the first session and we'll debug together.
