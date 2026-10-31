# Project UAI MCP

The desktop bridge exposes the connected Roblox client's tools to MCP harnesses.
Claude Code, Codex, Cursor and OpenCode can connect over Streamable HTTP. Harnesses
that launch local commands, including Claude Desktop, can use the stdio adapter.
The harness supplies its own model; tool calls go directly to Roblox's validated
dispatcher and return its actual execution receipt.

Connected Obsidian vaults are available through the `obsidian` tool group, subject
to the same session and tool permissions. Connect folders in **Settings → Obsidian**
first. Read-only vault policy also applies to MCP calls; a harness cannot add
arbitrary vault roots or enable editing through those tools. Notes read by a
harness enter that harness's context. See [Obsidian setup](../docs/OBSIDIAN.md).

Start the desktop bridge, load the updated UAI client in Roblox, and open
**Settings → MCP** in the bridge for connection details and configuration examples.
Use **Copy setup prompt** to give your local coding agent the exact connection
details and instructions to configure its harness, then verify tool discovery.
The desktop endpoint is `http://127.0.0.1:28791/mcp`; a terminal bridge normally uses
`http://127.0.0.1:8790/mcp`. Both accept `/api/mcp` as an alias. All HTTP requests
require `Authorization: Bearer <bridge token>`.

The desktop app's **MCP access** switch controls admission when Cowork starts.
Stop Cowork to change it, then start again. Terminal users can set
`UAI_MCP_DISABLED=1` before launching the bridge. When disabled, `/mcp` and
`/api/mcp` reject connections with HTTP 503, and the authenticated capability and
configuration routes report `enabled: false`. This switch is independent of the
private MCP connection used by the optional OpenCode inference tunnel.

## Connect a harness

The desktop executable provides a stdio entry point. Replace the example path
with the location of your downloaded executable:

```json
{
  "mcpServers": {
    "projectuai": {
      "command": "C:\\Tools\\UAI-Bridge-3.5.6-win-x64.exe",
      "args": ["--mcp-stdio"]
    }
  }
}
```

The adapter discovers the already-running desktop bridge and its current token
using the same native-only local discovery route as Roblox. It does not start a
second desktop window or bridge. Keep the bridge running before the harness
starts this command. This configuration survives token rotation on app restart;
reconnect the MCP server in the harness after restarting the desktop bridge.

From a Git checkout, the equivalent command is:

```powershell
node C:\path\to\projectuai\bridge\server.js --mcp-stdio
```

For a terminal bridge on port 8790, set `UAI_BRIDGE_TOKEN` in the harness's process
environment and append `--url http://127.0.0.1:8790`. `UAI_BRIDGE_URL` is also
supported. Credentials go in the environment, not command-line arguments.

For HTTP-capable clients, use their supported remote-server configuration.
Cursor's `.cursor/mcp.json` accepts:

```json
{
  "mcpServers": {
    "projectuai": {
      "url": "http://127.0.0.1:28791/mcp",
      "headers": { "Authorization": "Bearer <bridge token>" }
    }
  }
}
```

Claude Code can add the same endpoint from PowerShell after setting the token:

```powershell
claude mcp add --transport http projectuai http://127.0.0.1:28791/mcp --header "Authorization: Bearer $env:UAI_BRIDGE_TOKEN"
```

Codex's `config.toml` supports an environment-backed bearer token:

```toml
[mcp_servers.projectuai]
url = "http://127.0.0.1:28791/mcp"
bearer_token_env_var = "UAI_BRIDGE_TOKEN"
```

OpenCode's `opencode.json` uses its `mcp` object:

```json
{
  "mcp": {
    "projectuai": {
      "type": "remote",
      "url": "http://127.0.0.1:28791/mcp",
      "headers": { "Authorization": "Bearer <bridge token>" },
      "oauth": false,
      "enabled": true
    }
  }
}
```

These examples configure external harnesses to use Roblox tools. OpenCode's
separate built-in free-model inference integration remains independent.

## Tools, approvals and lifecycle

- Tools are discovered from the connected game, including supported host tools.
  Disabled groups, missing executor capabilities and denied permission policies
  are excluded. Discovery refreshes with `notifications/tools/list_changed`.
  An older or disconnected game exposes an empty catalogue; reload/connect the
  client and refresh tools in the harness.
- Each MCP connection owns an isolated ephemeral UAI conversation. It does not
  switch the selected browser conversation. Calls carry their MCP session ID and
  a separate execution ID across the existing authenticated inbox/receipt path.
- Roblox validates arguments and applies the current permission policy at
  execution time. **Approve pending prompts in Project UAI**, either in Roblox
  or the bridge. The external harness cannot grant itself permission via MCP.
- MCP cancellation targets that connection's individual call. Closing a session
  releases its work; ending a stdio process deletes its HTTP session. Cancelling
  remains cooperative and cannot undo already-applied effects or kill native
  executor work. Game/tool time limits continue to apply.
- There is no new overall inference or tool-request deadline in the bridge.
  A tool result comes from the game receipt. An uncertain delivery, game restart,
  or lost connection is reported explicitly and is never silently replayed.
  Inspect Roblox before manually repeating an action with an uncertain outcome.
- Losing an HTTP response does not cancel its tool. Repeating the same JSON-RPC
  request ID and identical arguments within the same live MCP session reattaches
  to the pending call or returns its retained result. Reusing the ID for different
  arguments is rejected. A new MCP session is a new execution scope.

## Protocol and limits

The server implements `initialize`, `notifications/initialized`, `ping`,
`tools/list`, `tools/call` and `notifications/cancelled`, plus GET notification
streams and DELETE session termination. It negotiates versions `2025-11-25`,
`2025-06-18`, `2025-03-26` and `2024-11-05`. HTTP POST may return JSON or SSE;
clients must send `Accept: application/json, text/event-stream` and
`Content-Type: application/json`. Include the initialization response's
`Mcp-Session-Id` on subsequent requests and the negotiated
`MCP-Protocol-Version`. An expired session returns HTTP 404. The legacy separate
SSE endpoint transport is not implemented; older harnesses should use stdio.

Tool results use MCP text content and, when the game supplies an object,
`structuredContent`. Tool/permission failures set `isError`; invalid requests
use JSON-RPC errors. A caller-provided `_meta.progressToken` receives progress
notifications while waiting for Roblox or approval. JSON-RPC batch requests,
sampling, roots, resources, prompts, OAuth, and elicitation are not advertised.

Bounds: 32 MCP sessions, 8 pending calls per session, 64 total pending calls,
512 retained call IDs per session, 1 MiB request bodies, 4 MiB results and a
16 MiB shared result cache. Evicting a cached result never permits reexecution of
its old request ID. Idle sessions without pending calls or an open notification
stream expire after 30 minutes. Responses to slow clients use bounded buffering.
Restarting the bridge clears MCP sessions and in-memory receipts; reconnect the
harness explicitly rather than retrying an uncertain action.

The endpoint is loopback-only and checks Host, Origin and the bridge bearer
token. It does not support query-string tokens or remote exposure. Connection
details at authenticated `GET /api/mcp/config` contain no token. The stdio
adapter restricts URL targets to loopback and reserves stdout for MCP messages.

## Verification

After manually reviewing source and test changes, run the focused bridge tests:

```powershell
node --test bridge/tests/mcp.test.js bridge/tests/security.test.js
```

`mcp.test.js` exercises protocol lifecycle, schema and permission filtering,
receipt results, semantic errors, concurrent harness isolation, cancellation,
reconnection without replay, game restart uncertainty, notifications and the
actual stdio process. Roblox dispatcher behavior is covered separately by
`luajit test/mcp_bridge.lua`. These do not assert native Roblox rendering or every
third-party harness version's UI behavior.

An optional interoperability test uses the official MCP JavaScript SDK's real
`StreamableHTTPClientTransport` and `StdioClientTransport`. Install the SDK
outside this checkout, set `MCP_SDK_MODULE` to its `@modelcontextprotocol/sdk`
package directory, then run `node --test bridge/tests/mcp-sdk.test.js`.
It validates schemas, execution receipts, cancellation and catalogue changes
through both transports; it does not invoke a model or use provider credentials.
