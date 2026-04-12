{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp@latest"]
    },
    "fetch": {
      "command": "uvx",
      "args": ["mcp-server-fetch"]
    },
    "time": {
      "command": "uvx",
      "args": ["mcp-server-time", "--local-timezone={{USER_TIMEZONE}}"]
    },
    "sequential-thinking": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
    }{{#each MCPS_ATLASSIAN}},
    "atlassian-{{name}}": {
      "command": "uvx",
      "args": ["mcp-atlassian"],
      "env": {
        "CONFLUENCE_URL": "{{url}}/wiki",
        "CONFLUENCE_USERNAME": "{{email}}",
        "CONFLUENCE_API_TOKEN": "${ATLASSIAN_{{NAME}}_TOKEN}",
        "JIRA_URL": "{{url}}",
        "JIRA_USERNAME": "{{email}}",
        "JIRA_API_TOKEN": "${ATLASSIAN_{{NAME}}_TOKEN}"
      }
    }{{/each}}{{#if MCPS_GITHUB_ENABLED}},
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_PAT}"
      }
    }{{/if}}
  }
}
