# Embedding examples

A complete custom UI built with **Project UAI UI LIB**, connected to a live UAI
conversation and a small host-owned settings model. It demonstrates composition,
tool registration, state binding, request handling, and cleanup without building
GUI objects in consumer code. The separate [SDK example](sdk.lua) runs without
mounting the native app and exposes owned tools, requests, and teardown.

Read [Embedding Project UAI](../../docs/EMBEDDING.md) for the runtime reference and
[UI_LIBRARY.md](../../docs/UI_LIBRARY.md) for the UI API. The example targets
Project UAI 2.5.6 with embedding SDK 1.0.0 and UI LIB 1.2.1.

## UI-free SDK example

```lua
local integration = loadstring(game:HttpGet(
	"https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/main/examples/embedding/sdk.lua"
))()
-- After a real provider/model has been configured:
local request, why = integration.ask("Call sdk_example_status and summarize the result.")
if not request then warn(why) end
-- In a yieldable task: local result, waitError = request.await(30)
-- integration.destroy() releases this integration's tool/listener and requests Stop.
```

Loading this entry does not send a request. It boots with `ui = false` and
`reuse = true`, owns the read tool `sdk_example_status`, and opens an ephemeral
conversation with only that tool allowed. It leaves current conversation
selection unchanged. A reused client preserves its boot context, UI mount state,
providers, and permissions. If setup is needed, `integration.client.show("providers")`
explicitly mounts the native app. The SDK can also save user-supplied provider
settings through the [provider API](../../docs/EMBEDDING.md#provider-api).

`ask(text)` returns a request or `nil, reason`. Progress and final results go to
the host console. `request.result` contains a structured outcome once settled;
`request.onComplete(fn)` registers another observer, and `request.cancel()` asks
for cooperative Stop. `await` timeout stops waiting without cancelling the turn.

Call `integration.destroy()` before loading this example again: its stable scope
ID rejects a second live owner. Teardown releases its tool and listener without
unloading the shared client or deleting its conversation. A subsequent load
reuses the named conversation and validates its tool policy. The conversation
is ephemeral, but diagnostics and provider traffic are still normal client work.

## Run the assistant workbench

In a Roblox executor host that supports HTTP and `loadstring`:

```lua
local integration = loadstring(game:HttpGet(
	"https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/main/examples/embedding/launcher.lua"
))()
```

For a reproducible distribution, copy `launcher.lua` into your host project and
replace its `revision = "main"` with one reviewed commit SHA. The same revision
is then used for the runtime, UI bundle, and both modules. Pin the entry-loader
URL too if you distribute it as a separate remote script. The launcher's internal
revision determines its dependency URLs; pinning only the outer URL does not
change that variable.

The launcher passes `reuse = true` to the client bundle. A live copy of the same
build is reused without toggling; a first boot starts the standard app with a
short host prompt. It loads UI LIB and the example
modules, installs the model/tools once for that client, and creates the workbench
window. Downloads and compilation are checked separately.

The window initially attaches to `uai.sessions.current()`. It does not create a
fresh conversation on every rerun. An existing client's provider configuration,
permission mode, boot prompt, and tools remain its own settings. Configure a
provider/model with **Providers**, then use **Send** when ready. The launcher
does not automatically submit a request or switch permission mode.

## Files and return values

| File | Returns | Responsibility |
| --- | --- | --- |
| `launcher.lua` | `{ client, UI, model, window, session }` | Downloads and composes the example |
| `host_tools.lua` | Installer function `(uai) -> model` | Owns local state and registers two tools |
| `assistant_panel.lua` | Factory `(uai, UI, options) -> window, session` | Declares and binds the custom view |
| `sdk.lua` | `{ client, scope, session, created, ask, destroy }` | UI-free runtime example with a read tool and structured requests |

`host_tools.lua` and `assistant_panel.lua` return factories. Execute or require
each module to obtain its factory, then call it with the dependencies.
`launcher.lua` and `sdk.lua` are executable entry points; evaluating either
directly returns its composed integration.

```lua
integration.window:Minimize()
integration.window:Show()
print(integration.model.read().batchSize)
```

Runtime/model calls use dots; UI object calls use colons.

## Compose it in your own host

After loading the module factories at your entry point, pass explicit handles:

```lua
-- uai and UI are already loaded.
-- installModel and createPanel are the factories returned by the module files.
local model = installModel(uai)
local session = assert(uai.sessions.open("my-host-workbench", { title = "My workbench assistant" }))
local window = createPanel(uai, UI, {
	Id = "my-host-workbench",
	Session = session,
	Model = model,
})
```

If using ModuleScripts, `require(HostTools)` and `require(AssistantPanel)` return
those same factories. Requiring them does not make the full UAI runtime available
in a vanilla LocalScript: supply a deliberate compatible runtime integration.
For Studio UI without an agent, use the standalone
[ModuleScript setup](../../docs/UI_LIBRARY.md#local-modulescript-setup) instead.

### Panel options

| Option | Default | Meaning |
| --- | --- | --- |
| `Id` | `embedding-workbench` | Stable UI window ID; a rerun replaces the old view |
| `Session` | `uai.sessions.current()` | Live registered conversation from `current`, `open`, or `newThread` |
| `Model` | Absent | Optional read/update/subscribe model; adds the Workbench tab |
| `Parent` | Library default | Parent for the library-owned ScreenGui; not Frame docking |

The factory rejects an unavailable or untracked conversation. A session made
with `sessions.create` is not registered and cannot open in the native history.
The panel stays attached to its supplied session when the native app switches
to another conversation.

### Stable control IDs

Use `window:Get(id)` to access a declared control when your host needs to:

| IDs | Purpose |
| --- | --- |
| `prompt`, `send`, `stop`, `status`, `reply` | Request draft, actions, and latest-response display |
| `open-client`, `providers` | Open the full app or provider setup |
| `workbench-title`, `workbench-enabled`, `workbench-batch` | Editable host settings |
| `workbench-state`, `workbench-apply`, `workbench-refresh` | Applied summary and explicit form actions |
| `theme`, `reduced-motion` | This window's appearance preferences |

The prompt, status, response, and applied-state summary are excluded from window
configuration with `Persist = false`. The example does not automatically save or
load a profile. If your host adds profile loading, remember that imports are
silent: explicitly refresh/apply derived appearance or domain state as needed.

## Host model and tools

The example model starts with:

```lua
local state = { title = "My workbench", enabled = true, batchSize = 5 }
```

It changes only local example settings. It does not inspect inventory, execute
game code, modify the server, or write its settings to a file.

| Method | Contract |
| --- | --- |
| `model.read()` | Returns a fresh snapshot of applied state |
| `model.update(patch)` | Returns `true, snapshot` or `false, reason`; validates before applying |
| `model.subscribe(callback)` | Delivers applied snapshots; returns an unsubscribe function |

Title must contain 1–80 bytes and non-whitespace text. `enabled` must be boolean.
`batchSize` must be an integer from 1 to 20. Unknown fields are rejected. Omitted
fields keep their previous values. Validation lives in the model so both manual
UI actions and tool handlers use the same boundary.

| Tool | Group/risk | Behavior |
| --- | --- | --- |
| `workbench_status` | `workbench` / read | Returns a readable summary and structured state |
| `workbench_configure` | `workbench` / write | Applies a validated patch through the model |

`workbench_configure` checks cancellation before applying. A model-generated
write goes through UAI's normal dispatcher and permission system. In the default
Ask first mode, the agent's write needs approval. Manual Apply is a user action
that calls the model directly; the domain validation still runs.

The installer stores its model in `uai.env.context.workbenchExample`. This is an
example-owned namespace, not a built-in UAI context option. Reinstallation on the
same live client returns that model; tool names are not registered twice. If
another integration already owns those tool names, installation reports a
collision. Choose your own prefix and context namespace for a derivative host.
Its SDK scope owns both tools and model cleanup. `model.destroy()` removes them
and makes later updates fail; a later install can create a fresh model. Close
dependent views before replacing the model so they can bind the replacement.

## Drafts, events, and rendering

The prompt publishes valid edits live and is bounded to 8,000 bytes. Send reads
the draft, checks session acceptance, and clears it only if accepted and still
unchanged. A rejected send leaves the draft available. Provider failures after
acceptance are reported in the latest-response view.

The panel subscribes to its session before replaying retained state. It displays
one latest response, bounded to 6,000 bytes with UTF-8-aware truncation, plus
transient previews. It coalesces event-driven paints into at most one pending
60 ms delayed task. It does not build a second full chat transcript or append
one GUI row per token. **Open UAI** shows the retained native history.

Ready/turn-end events may precede busy release. The panel also observes
`sessions.listChanged`, and its completion callback refreshes admission state.
Stop is cooperative and does not immediately free a busy session.

Workbench fields are drafts. A tool/model update refreshes **Applied state**
without overwriting what the user is editing. **Refresh** explicitly copies the
current model into the fields. **Apply** validates the complete form and writes
it to the model. The model itself is shared even when no workbench window is
visible.

## Ownership

Rerunning the launcher replaces `embedding-workbench`, releases its listeners
and pending paint, and reuses the model and same-build client without toggling
the standard app. Different builds follow the client's guarded reload policy.

Minimize and Hide retain the view/model subscriptions. Closing the custom window
destroys only that view. The conversation remains in UAI, including any accepted
turn. Unloading the supplied client closes the dependent window, clears the
model's subscriptions, and makes model writes fail.
The view uses a separate SDK scope for client-unload cleanup. Its subscriptions
and paint task stay in `window:Give`, while the model's tools outlive that view.

```lua
integration.window:Destroy() -- Close this view.
-- Only when your application intends to unload the entire shared client:
-- integration.client.unload()
```

The fixed `Project UAI | UI LIB.` attribution, text actions, sidebar profile,
responsive layout, and transitions are all supplied by the library.

## Try the behavior

1. Launch with no active client. Open Providers, configure a real supported
   model, and select the provider through the standard UI.
2. Read `workbench_status` in a request. Ask to change the batch size and respond
   to the normal permission prompt for the write.
3. Type a different title into the Workbench form, then update the model through
   a tool. Applied state should change while the form draft remains.
4. Use Refresh, change several values, and Apply. Invalid domain values should
   report an error without partially replacing model state.
5. Send, minimize the panel, and reopen it. The conversation should remain
   attached, with a usable latest-response view and a working Stop action.
6. Rerun the launcher. The previous view should close without duplicate tool
   registration or an extra conversation. Close the new panel; UAI should stay
   alive. Unload UAI explicitly to end the full integration.

These are optional real-host scenarios, separate from offline verification.
They do not require image uploads or browser automation.

## Offline verification

Finish and manually review all changes before building. Generate the UI guide,
client bundle, and site catalog in the order documented in
[Distribution and verification](../../docs/EMBEDDING.md#distribution-and-verification),
then inspect the generated outputs. Run:

```powershell
luajit test/embedding_examples.lua
luajit test/embedding_sdk.lua
luajit test/embedding_sessions.lua
luajit test/ui_library_agent.lua
```

The fixtures load the real example modules and distributed bundles with local
downloads and a simulated provider. They require no network or provider key.
The broader UI library suite is `luajit test/ui_library.lua`. Offline checks do
not verify native Roblox rendering, IME, touch/gamepad input, or executor-specific
native behavior. This example supplies no image attachment UI or browser widget.
