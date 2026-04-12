[Unit]
Description={{AGENT_DISPLAY_NAME}} (Claude Code launcher)
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
WorkingDirectory={{DEPLOYMENT_WORKSPACE}}
ExecStart=%h/.local/bin/{{AGENT_NAME}}.sh
Restart=on-failure
RestartSec=30
Environment=HOME=%h
Environment=CLAUDE_CONFIG_DIR=%h/.claude-personal
Environment=TELEGRAM_STATE_DIR=%h/.claude-personal/channels/telegram-{{AGENT_NAME}}

[Install]
WantedBy=default.target
