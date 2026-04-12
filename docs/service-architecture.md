# Service architecture

The agent runs as a persistent background service via `systemd --user` (Linux) or `launchd` (macOS). Inside the service, a bash launcher script wraps a `tmux` session that runs `claude`.

## Layers

```
systemd / launchd
  └── bash launcher (~/.local/bin/{agent}.sh)
        └── tmux session "{agent}"
              └── claude --channels plugin:telegram@claude-plugins-official
```

## Auto-recovery

The launcher script keeps a 10-second monitoring loop. Every tick:

1. Is the tmux session alive? If not, recreate it.
2. Is `claude` running inside the tmux session? If not, recreate the session.

If the session crashes 5+ times in 5 minutes, the launcher backs off for 60 seconds to avoid tight restart loops.

If the launcher itself dies, systemd (`Restart=on-failure`) or launchd (`KeepAlive`) brings it back. The goal: the agent stays up no matter what fails.

## Heartbeat timer

Separate from the main agent, the heartbeat runs on its own systemd timer (Linux) or launchd scheduled job (macOS). On each firing:

1. Read prompt + settings from `scripts/heartbeat/heartbeat.conf`
2. Create a short-lived tmux session named `{agent}-hb-{timestamp}`
3. Launch `claude --print "$PROMPT"` with the agent's workspace as cwd
4. Wait for completion (configurable timeout + retries)
5. Dispatch result to the configured notifier (`NOTIFY_CHANNEL`)
6. Record in `scripts/heartbeat/logs/heartbeat-history.log`

The heartbeat does NOT interrupt the main agent session.

## Why tmux

`tmux` gives you:
- Detached long-running processes
- Interactive `tmux attach -t {agent}` for debugging or resuming a conversation
- Clean crash detection (the launcher can check if `claude` is still alive inside the pane)

## Commands

Linux:
```bash
systemctl --user start {agent}.service
systemctl --user restart {agent}.service
systemctl --user stop {agent}.service
journalctl --user-unit {agent}.service -f
tmux attach -t {agent}
```

macOS:
```bash
launchctl kickstart -k gui/$(id -u)/local.{agent}
launchctl list | grep local.{agent}
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/local.{agent}.plist
tail -f ~/.local/share/{agent}/{agent}.log
tmux attach -t {agent}
```
