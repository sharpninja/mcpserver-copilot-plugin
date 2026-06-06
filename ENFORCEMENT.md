# Per-Turn Enforcement Protocol (Copilot) - v4 Shared Protocol

This plugin implements the McpServer **v4 Shared Enforcement Protocol** for Copilot agent sessions.
See `packages/mcpserver-agent-core` (`@sharpninja/mcpserver-agent-core`) for the shared core reference.

Copilot consumes this plugin as an MCP server. The server does not (and cannot)
intercept Copilot's message loop - Copilot decides when to call MCP tools. This
document specifies the Per-User-Message contract that the Copilot **agent** must
follow, plus the helper scripts in `lib/` that automate the bookkeeping.

## Why this is required

`AGENTS-README-FIRST.yaml` in every MCP-enabled workspace mandates:

- **Rule 2**: Post a new session log turn before starting work on each user
  message.
- **Rule 10**: Do not ship code you have not verified compiles.
- **Before Delivering Output**: Session log must be current, decisions
  recorded, code compiles.

These rules have no hook-based enforcement in Copilot (unlike Claude Code).
Compliance is agent-driven.

## Tool Name Surfaces

Copilot-visible plugin tools use the host-facing names exposed by this plugin.
The helper scripts still call `workflow.sessionlog.*`, `workflow.todo.*`, and
`workflow.requirements.*` through the plugin workflow/REPL shim. Those
`workflow.*` names are not literal native McpServer MCP tool names. Native
McpServer `/mcp-transport` discovery uses names such as `sessionlog_*`,
`todo_*`, and `requirements_*`; hosted-agent adapters may expose aliases such as
`mcp_session_*`.

Do not search generic MCP discovery for literal `workflow.*` names and call the
plugin unavailable solely because those names are absent. Validate Copilot's
plugin tools, marker trust, and helper script path instead.

## The Three Scripts

The plugin ships three bash scripts in `lib/` that Copilot agents should invoke
per user message:

### Phase 1 - On user message receipt

```bash
echo '{"prompt":"<verbatim user message>"}' | bash ${COPILOT_PLUGIN_ROOT}/lib/user-prompt-submit.sh
```

What it does:
- Reads the active `sessionId` from `cache/session-state.yaml`
- Builds a fresh `req-<yyyyMMddTHHmmssZ>-prompt-xxxx` requestId
- Invokes `workflow.sessionlog.beginTurn` via `mcpserver-repl`
- Writes `cache/current-turn.yaml` so Phase 3 can verify completion

### Phase 2 - After every code edit

```bash
echo '{"tool_name":"Edit","tool_input":{"file_path":"<absolute path>"}}' \
  | bash ${COPILOT_PLUGIN_ROOT}/lib/code-verify.sh
```

Runs `dotnet build` (for .NET files) or `tsc --noEmit` (for TypeScript)
against the containing project. Updates `cache/current-turn.yaml` with
`lastBuildStatus` and increments `codeEdits`. Appends a session log action
via `workflow.sessionlog.appendActions`.

If the build fails, stdout contains build errors. The agent should fix them
before the next phase.

### Phase 3 - Before final response

```bash
bash ${COPILOT_PLUGIN_ROOT}/lib/stop-gate.sh
```

Returns `decision: block` with reason if:
- Turn is still `in_progress` - agent forgot `workflow.sessionlog.completeTurn`
- `lastBuildStatus: failed` - build is broken

When blocked, fulfill the missing requirement. Call the MCP tool
`session_complete_turn` with a response summary, or fix the build, then
re-run `stop-gate.sh`.

## Why scripts and not MCP tools?

The scripts coordinate shared state (`cache/current-turn.yaml`) that needs
to persist across MCP tool invocations. They can also run `dotnet build` /
`tsc` which are not surfaced as MCP tools. A future version may expose
equivalent MCP tools that wrap these scripts; until then, invoke via shell.

## Integration hint for Copilot prompts

Add to the agent's system prompt or task instructions:

```
Before calling any other tool on a new user message, run
  echo '{"prompt":"..."}' | bash $COPILOT_PLUGIN_ROOT/lib/user-prompt-submit.sh

After editing any .cs/.axaml/.ts/.tsx file, run
  echo '{"tool_name":"Edit","tool_input":{"file_path":"..."}}' | bash $COPILOT_PLUGIN_ROOT/lib/code-verify.sh

Before emitting your final response, run
  bash $COPILOT_PLUGIN_ROOT/lib/stop-gate.sh
```

## sourceType

This plugin's agent identity is `Copilot`. Session logs created by this plugin
use `"sourceType": "Copilot"` in all MCP session-log API calls.

## See also

- `hooks.json` at plugin root - hook configuration for lifecycle events
- `AGENTS-README-FIRST.yaml` in each workspace - authoritative contract
  these scripts implement.
