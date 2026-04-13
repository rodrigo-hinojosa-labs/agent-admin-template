<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>local.{{AGENT_NAME}}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>{{HOME_DIR}}/.local/bin/{{AGENT_NAME}}.sh</string>
    </array>
    <key>WorkingDirectory</key>
    <string>{{DEPLOYMENT_WORKSPACE}}</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key><string>{{HOME_DIR}}</string>
        <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:{{HOME_DIR}}/.local/bin:{{HOME_DIR}}/.bun/bin:/usr/bin:/bin</string>
        <key>CLAUDE_CONFIG_DIR</key><string>{{CLAUDE_CONFIG_DIR}}</string>
        <key>TELEGRAM_STATE_DIR</key><string>{{TELEGRAM_STATE_DIR}}</string>
    </dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key>
    <dict><key>SuccessfulExit</key><false/></dict>
    <key>ThrottleInterval</key><integer>30</integer>
    <key>StandardOutPath</key><string>{{HOME_DIR}}/.local/share/{{AGENT_NAME}}/{{AGENT_NAME}}.log</string>
    <key>StandardErrorPath</key><string>{{HOME_DIR}}/.local/share/{{AGENT_NAME}}/{{AGENT_NAME}}.err</string>
</dict>
</plist>
