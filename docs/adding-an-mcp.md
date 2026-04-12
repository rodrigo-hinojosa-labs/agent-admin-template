# Adding an MCP

The template comes with four MCPs pre-configured (playwright, fetch, time, sequential-thinking) and two opt-in (atlassian, github). To add your own:

## 1. Update the wizard

In `setup.sh`, under the MCP step, add a prompt for your MCP:

```bash
if [ "$(ask_yn 'Enable ExampleMCP?' 'n')" = "true" ]; then
  example_enabled="true"
  example_token=$(ask_secret "Example API token")
fi
```

## 2. Update agent.yml

Ensure your field is written in the `mcps:` section of the generated `agent.yml`:

```yaml
mcps:
  example:
    enabled: $example_enabled
```

## 3. Update `modules/mcp-json.tpl`

Add a conditional block:

```
{{#if MCPS_EXAMPLE_ENABLED}},
"example": {
  "command": "...",
  "env": {
    "EXAMPLE_TOKEN": "${EXAMPLE_TOKEN}"
  }
}
{{/if}}
```

Watch the leading comma if you're appending to an existing JSON object.

## 4. Update `modules/env-example.tpl`

```
{{#if MCPS_EXAMPLE_ENABLED}}
# Example MCP
EXAMPLE_TOKEN=
{{/if}}
```

## 5. Add tests

In `tests/mcp-json.bats`, add a test case with a fixture enabling your MCP and assert on the generated JSON structure.

## Multi-instance MCPs

If your MCP has multiple accounts/workspaces (like Atlassian with work + personal), model it as an array in `agent.yml`:

```yaml
mcps:
  example:
    - name: work
      key: "..."
    - name: personal
      key: "..."
```

And use `{{#each MCPS_EXAMPLE}}...{{/each}}` in the template. See `modules/mcp-json.tpl` for the Atlassian example.
