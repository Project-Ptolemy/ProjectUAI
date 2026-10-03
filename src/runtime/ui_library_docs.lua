-- Generated from docs/UI_LIBRARY.md by tools/build_ui_lib.js; edit the Markdown.
return function(env)
	return {
		version = "1.2.1",
		url = "https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/main/dist/uai-ui.lua",
		repository = "https://github.com/Project-Ptolemy/ProjectUAI",
		sections = {
			["quickstart"] = [=[
## Quickstart

Load the library once in each standalone script. The returned API is independent
of the Project UAI client. The library does not download fonts, icons, or third-party scripts. Roblox
services resolve the local headshot and experience name asynchronously; a readable
initial and "Current experience" remain until those lookups finish.

```lua
local UI = loadstring(game:HttpGet(
	"https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/main/dist/uai-ui.lua"
))()

local window = UI:CreateWindow({
	Id = "my-session-tools",
	Title = "Session tools",
	Subtitle = "Everything you need for this session",
})
local main = window:Tab({ Title = "Main" })
local actions = main:Section({ Title = "Actions" })
local amount = actions:Slider({
	Id = "amount", Text = "Amount", Min = 1, Max = 20, Step = 1, Default = 5,
})
actions:Button({
	Text = "Process selection", ActionText = "Run", Style = "Primary",
	Callback = function()
		-- Your application logic belongs here.
		print("Process", amount:Get())
		window:Notify({ Title = "Finished", Content = "Selection processed.", Kind = "Success" })
	end,
})
return window
```

Use a stable, script-specific window `Id`. Rerunning a script with that same Id
destroys its previous window and calls its registered cleanup functions, even
when it loads a fresh copy of the library. Different Ids coexist. No unrelated
ScreenGui is deleted.

Agents: read `ui_library_docs` sections `quickstart`, `controls`, and `lifecycle`
before writing a script UI. Use declarative tabs, sections, and controls plus
domain logic. Do not create GUI instances, styles, layout arithmetic, drag
handlers, third-party UI loaders, or replacement attribution in scripts. Extend
the shared library when a missing reusable component is required. Respect an
explicit user request to work on an existing custom interface.

The `main` URL follows compatible updates to the v1 API. For reproducible releases,
replace `main` with the reviewed Git commit SHA in the raw URL. HTTP and loadstring
must be available in the host; surface their errors instead of silently fetching
a different UI library. In Studio, the bundle can be placed in a ModuleScript
and loaded with `require` from a LocalScript.
]=],
			["embedding"] = [=[
## Embedding

### Choose the right bundle

| Need | Entry point |
| --- | --- |
| Script-owned controls without an AI client | `dist/uai-ui.lua` |
| UAI's existing assistant application | `dist/uai.lua` |
| Your controls backed by UAI sessions/tools | Load both, then pass the live client and UI API into a view factory |
| Local Studio UI | Place the UI bundle in a ModuleScript and require it from a LocalScript |
| Browser UI | Use the web bridge; this Roblox library is not a JavaScript package |

Loading UI LIB returns the API without mounting a window. `CreateWindow` mounts
one. It does not depend on `getgenv().UAI`, configure providers, change tool
permissions, or create agent sessions. The full client mounts its standard
application by default. Pass `{ ui = false, reuse = true }` to its loader for a
runtime without a mounted app, then use `uai.sdk` for owned integrations and
request handles. `uai.show(...)` mounts the standard app on demand. There is no
alternate client `Parent` option. See [the embedding SDK guide](EMBEDDING.md).

### Keep downloads at the entry point

Load one UI API in your entry script and pass it to your application modules.
Modules should declare controls and callbacks, not download a second library.
Keep production URLs on one reviewed commit SHA when you need reproducibility.

```lua
local revision = "main" -- Replace with a reviewed commit SHA for a pinned release.
local url = "https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/"
	.. revision .. "/dist/uai-ui.lua"
local ok, source = pcall(function() return game:HttpGet(url) end)
assert(ok and type(source) == "string", "UI library download failed: " .. tostring(source))
local chunk, why = loadstring(source, "@uai-ui")
assert(chunk, "UI library compilation failed: " .. tostring(why))
local UI = chunk()
```

The library's metadata (`UI.Version`, `UI.URL`, `UI.Repository`) identifies its
release and canonical location. `UI.URL` is canonical metadata; it does not
become your commit-pinned download URL automatically. Keep the selected revision
in your host's own release metadata.

### Local ModuleScript setup

Place the **contents** of `dist/uai-ui.lua` in
`ReplicatedStorage/UAIUI` as a ModuleScript, then use a LocalScript:

```lua
local UI = require(game:GetService("ReplicatedStorage"):WaitForChild("UAIUI"))
local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
local window = UI:CreateWindow({
	Id = "my-game-workbench", Title = "Workbench", Parent = playerGui,
	ToggleKey = false,
})
local main = window:Tab({ Id = "main", Title = "Main" })
main:Section({ Title = "Actions" }):Button({
	Id = "inspect", Text = "Inspect selection", ActionText = "Inspect",
	Callback = function() print("Call your validated application operation here") end,
})
```

This UI path needs no runtime HTTP or `loadstring`. File-backed `SaveConfig` and
`LoadConfig` still require executor filesystem capabilities. A Studio game can
use JSON import/export with its own storage flow. Server-owned effects still
belong behind the game's own validated server APIs.

### Parent means ScreenGui parent

`Parent` chooses where the library creates its ScreenGui. Supply a
PlayerGui/CoreGui-compatible parent. It does not mount controls in an existing
Frame, inherit that Frame's layout rectangle, or create a dockable component.
The library still owns its screen, safe-area layout, overlays, and restore pill.

`window.ScreenGui`, `window.Frame`, and `control.Frame` are exposed for inspection
and tests. Do not reparent, restyle, replace, or use them as custom-content slots
in consumer scripts. There is no public arbitrary-content or docking API.

### Identity and replacement

Use one stable window Id per logical application, such as `myhost-workbench`.
Controls need unique stable Ids **within that window**, even across different
tabs. Two tabs cannot both use `Id = "enabled"` for different controls. Prefix
control IDs by feature (`scan-enabled`, `export-enabled`) when composing modules.

Creating a new window with an existing Id releases the previous one and its
registered resources. Different window IDs coexist. `UI:GetWindow(id)` finds a
live registered window. Use the supplied handles instead of enumerating
ScreenGuis by title or deleting GUI objects by a broad name match.

For a supplied full-client handle, use `uai.show(...)` and `session.send(...)`
with dots. UI LIB uses `window:Show()` and `control:Set(...)` with colons. See
[Runtime integration](#runtime-integration) for the connection between them.
]=],
			["controls"] = [=[
## Controls

Create controls with `section:ControlName({ ... })`. Common options:

| Option | Meaning |
| --- | --- |
| `Id` | Unique string within the window; required for configuration persistence and `window:Get(id)`. |
| `Text` | Visible label. Use short, concrete wording. |
| `Description` | Supporting text that wraps at the available width. |
| `Default` | Initial value. Construction never invokes a callback. |
| `Callback` | Called on a changed value or button press. Errors produce a notification and do not break other controls. |
| `Disabled` / `Visible` | Initial enabled/visible state. |
| `Persist = false` | Exclude this value from exported configuration; use for transient or sensitive inputs. |

All controls have `Get()`, `Set(value, silent?)`, `Reset(silent?)`,
`SetText(text)`, `SetDescription(text)`, `SetDisabled(boolean)`,
`SetVisible(boolean)`, `OnChanged(callback)`, and `Destroy()`.
`OnChanged` returns an unsubscribe function. Setters return the control.
`Set` invokes value callbacks only when the value changes; `silent = true`
suppresses them. Returned arrays are copies. A disabled control can be updated
programmatically. `Get/Set/Reset/OnChanged` are useful on value controls; use
`Press` for buttons and `SetText/SetDescription` for display-only text.

| Constructor | Options and behavior |
| --- | --- |
| `Button` | `ActionText = "Run"`, `Style = "Primary" / "Danger"` (otherwise secondary), `LoadingText`. `Callback()` runs in an owned task; repeated presses are ignored while it runs. `Press()` returns whether it started; `SetLoading(bool)` controls a loading indicator. |
| `Toggle` | Boolean `Default`; `Callback(enabled)`. Full-size touch target around a compact switch. |
| `Checkbox` | Same boolean API, with explicit On/Off text. |
| `Slider` | `Min = 0`, `Max = 100`, `Step = 1`, `Default`, `Suffix`. `Callback(number)` on changes, `OnCommit(number)` once at gesture end. Values are clamped and rounded relative to Min; Max is reachable even when the step does not divide the range. Arrow/D-pad left/right changes one step; Home/End reaches the endpoints. |
| `Input` | String `Default`, `Placeholder`, `MaxLength = 4096` UTF-8 bytes, `MultiLine`, `Lines = 3`, `Live = false`. Commits on focus loss; Live publishes valid edits while preserving the draft/caret until focus loss. `Numeric = true` uses finite numbers and optional `Min/Max`. Invalid drafts show an error while preserving the last valid value. `OnCommit(value)` and `Focus()` are available. |
| `Dropdown` | `Options`, `Default`, `Multi = false`, `Searchable = true`, `Placeholder`. Option records accept `Image`, shown as a round profile image at the start of the row and in the closed field for the current selection. `SetOptions(array, silent?)` replaces choices and retains still-valid selections. `Open()` opens the picker. Empty options show an empty state. |
| `Segmented` | Single selection among 1–8 `Options`. Same selection and `SetOptions` API as Dropdown; wraps into rows at narrow widths. |
| `Keybind` | `Default = Enum.KeyCode.K` (or `"K"`), `Mode = "Press" / "Hold" / "Toggle"`, `ActiveWhenHidden = false`. `Callback(active, key)` handles activation; `OnChanged(key)` handles rebinding. Hold calls true on press and false on release/cancellation; Toggle alternates until canceled. Click to capture, Escape cancels, Backspace/Delete clears. `Set(nil)` unbinds. Window's toggle key is reserved. |
| `ColorPicker` | `Default = Color3.fromRGB(...)`, optional `Alpha = 1` or `ShowAlpha = true`. HSV square, hue bar, hex and RGB inputs, preview, Apply/Cancel. Color components must be within 0–1; alpha is clamped to that range. `Callback(color, alpha)` fires on Apply or a changed Set. `Get()` returns color, alpha; `GetAlpha()` and `SetAlpha(alpha, silent?)` are available. |
| `Label` | A wrapping `Text` and optional `Description`. |
| `Paragraph` | `Text` is the title; `Content` (or Description) is the wrapping body. |
| `Divider` | A small section label and separator. Use `Text = ""` for a plain separator. |
| `Badge` | `Default` or `Value` is a status string. `Kind = "Success" / "Warning" / "Danger" / "Secondary"`. Change the string with `Set`. |
| `Progress` | `Min = 0`, `Max = 100`, `Default` or `Value`. `Set(number)` updates a bounded track and percentage. |

Dropdown/Segmented options are primitive strings, finite numbers, or booleans,
or records such as `{ Label = "Balanced", Value = "balanced", Disabled = false }`.
A record may also carry `Image`, a URL rendered as a round avatar at the start of
a dropdown row and in the closed field for the current selection. Player
headshots work with the built-in
`rbxthumb://type=AvatarHeadShot&id=<UserId>&w=150&h=150` scheme, which the client
resolves without an upload or an HTTP request; a readable initial stays visible
behind the image until it loads. Values must be unique. Dropdowns support up to
500 choices with literal search.
Single-select `Default` and `Get` use one value (or nil for no selection);
multi-select uses an array. Multi-select changes are immediate; Done closes the
picker. A disabled option is displayed but cannot be selected interactively.

Keybinds work across tabs while the window is open. They ignore processed input,
text editing, and open dialogs. Hiding or destroying a window releases active
Hold/Toggle actions. No initialization or configuration import simulates a key
press. A keybind's `Set` updates the binding, not its active state.
]=],
			["layout"] = [=[
## Layout

`UI:CreateWindow(options)` accepts `Id`, `Title`, `Subtitle`, optional
`Width = 780` / `Height = 580`, `Search = true`, `Theme = "Dark" / "Light"`,
`Accent = Color3`, `TextScale = 1` (0.85–1.5), `ToggleKey = Enum.KeyCode.RightShift`
(false disables it), `DisplayOrder = 80`, `Parent`, `OnDestroy`, optional
`GameName`, and optional `ReducedMotion`.
Supply a PlayerGui/CoreGui-compatible parent only when embedding.
The default parent is gethui, CoreGui, then PlayerGui, with capability detection.
When Height is omitted, narrow touch windows use the available screen height;
an explicit Height retains the requested size within the safe viewport.

The library handles safe insets, viewport/camera replacement, device rotation,
keyboard obstruction, touch targets of at least 44 pixels, mouse dragging,
desktop resizing, wrapped descriptions, independently scrolling tabs, and scroll
reveal for focused fields. It reflows at compact widths rather than shrinking
the interface with UIScale. Navigation becomes a horizontal scrolling tab strip.
On desktop, controls use a 40-pixel target, increasing with text scale.
Rows stack their value below the label when space is tight.

The visual refresh keeps the v1 constructors, methods, callbacks and configuration
format compatible. Existing scripts receive the new appearance without changing
their declarations. Each tab has a heading and a live control/section count; these
scroll with the content so they do not take space from short keyboard layouts.
Search updates the count and keeps its empty state clear. Sections use rounded
surfaces, fields use inset backgrounds, and selected choices have an accent edge.
Focus and validation states survive theme changes. Text remains native at its
final size throughout transitions; opening a view never scales its contents.

`window:Tab({ Id?, Title })` creates a text-only tab. Legacy `Icon` options
are ignored, and consumer scripts must not supply new icons. `tab:Select()`, `tab:SetVisible(bool)`,
and `tab:Destroy()` manage it.

`tab:Section({ Title, Description?, Collapsible?, Collapsed? })` creates a
group. Sections support `SetCollapsed(bool)`, `SetVisible(bool)`, and `Destroy()`.
Search filters the active tab's labels, descriptions, and section titles,
reveals matching collapsed sections, and displays a clear empty state.

Window methods: `Show()`, `Hide()`, `Minimize()`, `Toggle()`, `Destroy()`,
`SelectTab(idOrTab)`, `SetTitle(title, subtitle?)`,
`SetTheme("Dark"|"Light", accent?)`, `SetTextScale(number)`,
`SetReducedMotion(boolean)`, `Get(controlId)`.
Minimize keeps a branded restore pill on screen: it shows the mark, title,
subtitle and
attribution, can be dragged anywhere in the safe viewport, and restores on a click
that was not a drag. Hide removes that pill too, and a notification that arrives
while minimized updates its status. The top-right close button destroys the window. The
Minimize and Close glyphs have no resting fill;
hover brightens them and gamepad selection adds a focus outline. The desktop
resize grip stays in the bottom-right corner. Each window has independent theme and state. The footer
remains pinned outside scrolling content. The sidebar profile stays below the
scrolling tabs; compact and short layouts use the horizontal tabs and omit the
profile to preserve room for controls. The profile places the game name on its
own full-width line. `GameName` overrides the automatic game
lookup when the script already knows its display name.

Windows, tabs, pickers, and notifications reveal their contents with a brief
fade at fixed geometry. Tab switches preserve scroll positions and update only
the affected navigation states; rapid selections continue the active fade.
Hover, focus, and toggle transitions reverse from their current value. Hidden
controls settle immediately, and transitions release their resources on completion,
hide, focus loss, replacement, and destruction. With no explicit
`ReducedMotion` option the library follows Roblox's reduced-motion preference
when available. `SetReducedMotion(true)` immediately finishes active transitions.
Dragging only moves the window; it does not remeasure the control list.
]=],
			["lifecycle"] = [=[
## Lifecycle

Register logic resources with `window:Give(resource)`: an RBXScriptConnection,
Instance, task thread, or cleanup function. It returns an early-release function.
`window:OnDestroy(function)` is an alias for registering cleanup. Resources
are released when the window is closed, its ScreenGui is removed, its Id is
replaced, or `UI:DestroyAll()` is called. Cleanup is idempotent.

```lua
local players = game:GetService("Players")
window:Give(players.PlayerAdded:Connect(function(player)
	window:Notify({ Title = "Player joined", Content = player.DisplayName })
end))
window:OnDestroy(function()
	-- Restore temporary application state and stop any domain-level worker.
end)
```

Use event-driven logic. Do not start an unowned infinite task inside a callback.
When run through UAI's managed `run_luau`, tool-owned tasks have the execution
tool's deadline; use owned event connections for UI logic that should continue
after the initial script returns. Dynamic library loading does not extend that
deadline or undo application side effects. A callback should check its own
domain object's lifetime after yielding.

`UI:GetWindow(id)` returns a live handle, `UI:DestroyAll()` closes only library
windows, and `UI.Version` / `UI.URL` / `UI.Repository` identify the release.
GUI instance handles are exposed as `window.ScreenGui`, `window.Frame`, and
`control.Frame` for inspection and testing. Do not style or reparent these in
consumer scripts; doing so breaks the layout and ownership contract.

### Pick an owner for every resource

| Resource | Register | Lifetime |
| --- | --- | --- |
| Roblox service connection | `window:Give(signal:Connect(fn))` | Window |
| Host-model or UAI unsubscribe function | `window:Give(unsubscribe)` | Window |
| Short scheduled debounce/paint | `window:Give(thread)`; unregister when it completes | Window or completion |
| Temporary domain state | One `window:OnDestroy(cleanup)` | Window |
| Shared model or UAI client | Host-owned cleanup outside the view | Host/client, which can outlive the window |

Hide and Minimize retain your subscriptions and application state. Destroy
releases them. The library releases active key holds/toggles when hidden, but
that does not stop an unrelated agent turn or your own domain operation.

The early-release function returned by `Give` normally disposes the resource.
`release(false)` unregisters without disposing. Use the latter when a task has
already completed. Releasing twice is harmless. Cleanup order across independent
resources is not guaranteed; combine dependent teardown steps in one function.

### Own a delayed update

This helper schedules one pending paint, uses the most recent model state when
it runs, and removes completed tasks from the window's cleanup registry:

```lua
local function makeQueuedRefresh(window, refresh)
	local queued = false
	return function()
		if queued or not window.Alive then return end
		queued = true
		local release, finished
		local thread = task.delay(0.06, function()
			finished, queued = true, false
			if release then release(false) end
			if window.Alive then refresh() end
		end)
		if not finished then release = window:Give(thread) end
	end
end
```

`refresh` is your synchronous, bounded view update. Subscribe a model's change
signal to the returned function and register that subscription with the window.
The example uses a 60 ms delay; choose a rate suited to the domain, and display
final state immediately when the interaction requires it.

### Guard asynchronous results

A request can finish after the window closes or after a newer request starts.
Keep a generation counter in the view and check it plus `window.Alive` before
applying a result. This is necessary even when the visible initiating button
has been disabled: another model update or teardown can still make work stale.

Do not force-cancel a coroutine suspended inside a native API that may resume it
later. For that kind of work, invalidate the result and let the native call
settle. Short library-owned tasks and a host operation with its own cancellation
contract have different lifetimes. Buttons already run their callbacks in owned
tasks; avoid putting an indefinite polling loop inside one.

Never use closing a view as an implicit command to destroy a shared UAI client
or delete a saved conversation. If your application offers those actions, give
them explicit names and callbacks separate from view cleanup.
]=],
			["configuration"] = [=[
## Configuration

Give stateful controls stable Ids. `window:ExportConfig()` returns versioned JSON;
`window:ImportConfig(json, options?)` returns `true, count` or `false, error`.
Imports require the same window Id, validate every known value before changing
any, ignore removed/unknown control Ids, and reject changed control types.
Configuration JSON is limited to 256 KiB. Values marked `Persist = false` are
neither exported nor imported.

Imports are silent by default: they update controls without starting application
actions. `{ Silent = false }` invokes value callbacks after all values have been
restored. Active Hold/Toggle bindings receive a release (`false`) after the
complete state is restored; imports never send an activation (`true`). Release
callbacks may clean up or destroy their window. Read initial control values
explicitly when your application needs them.

`window:SaveConfig("profile-name")` saves under `ProjectUAI/UI/` and returns
`true, path` or `false, error`. `window:LoadConfig("profile-name", options?)`
reads and imports. Names allow 1–48 letters, digits, underscores, and hyphens.
Files are namespaced per window; paths cannot traverse directories.
Missing executor filesystem functions return a clear error; JSON export/import
works with Roblox HttpService and does not require executor storage.
No configuration is read, saved, or applied automatically.

### Control values versus application state

Configuration restores the values declared by the window. It does not call your
model's API, set UAI provider options, or validate game-level relationships.
Keep an explicit function that reads a complete form, validates it, and applies
it to your application. Call that function at your chosen boundary: an Apply
button, or a deliberate load-and-apply action.

For example, given existing `title`, `enabled`, and `batch` controls and a model
with `update(patch)`:

```lua
local function applyForm()
	local ok, why = model.update({
		title = title:Get(), enabled = enabled:Get(), batchSize = batch:Get(),
	})
	if not ok then
		window:Notify({ Title = "Settings kept", Content = tostring(why), Kind = "Warning" })
	end
	return ok
end
```

After a silent import, call any derived-view refresh function yourself. For
example, an imported mode might require showing a detail section or disabling an
irrelevant field. Silent imports do not invoke the `OnChanged` subscriber that
normally handles that work.

Use `Persist = false` for prompts, temporary status, and sensitive inputs. UI
configurations are ordinary JSON, not encrypted storage. An API-key field should
not be included in a shareable window profile.

### Evolve a saved configuration

Keep control Ids and types stable when only labels or tab layout change. A
renamed label keeps its saved value; a new Id creates a new setting. A removed
control's old entry is ignored. Reusing an Id for a different control type is
rejected on import, so give a replacement setting a new Id or implement a
deliberate migration before passing the JSON to `ImportConfig`.

Known values are validated before changes are applied. That protects the form
from partial invalid imports; it does not make subsequent application callbacks
a transaction or roll back their effects. Prefer silent import followed by one
validated domain operation for settings that must be applied together.
]=],
			["application_patterns"] = [=[
## Application patterns

### Start with a model contract

A small application normally needs three operations:

| Host operation | Meaning |
| --- | --- |
| `model.read()` | Return a snapshot of current applied state |
| `model.update(patch)` | Validate and apply a domain change; return true/snapshot or false/reason |
| `model.subscribe(callback)` | Notify views of applied changes; return an unsubscribe function |

These names are an example contract, not built-in UI LIB methods. The complete
[workbench model](../examples/embedding/host_tools.lua) supplies one. A different
application can adapt an existing controller to this shape.

### Immediate settings and silent reflection

This factory expects that model contract with `enabled` and `batchSize` fields.
It declares controls, sends user changes into the model, and reflects model
changes without triggering another write:

```lua
return function(window, model)
	local tab = window:Tab({ Id = "settings", Title = "Settings" })
	local section = tab:Section({ Title = "Processing" })
	local initial = model.read()
	local controls = {}
	local function reflect(value)
		if not window.Alive then return end
		controls.enabled:Set(value.enabled, true)
		controls.batch:Set(value.batchSize, true)
		controls.batch:SetDisabled(not value.enabled)
	end
	local function apply(patch)
		local ok, why = model.update(patch)
		if not ok then
			reflect(model.read())
			window:Notify({ Title = "Change kept", Content = tostring(why), Kind = "Warning" })
		end
	end
	controls.enabled = section:Toggle({
		Id = "processing-enabled", Text = "Enable processing", Default = initial.enabled,
		Callback = function(value) apply({ enabled = value }) end,
	})
	controls.batch = section:Slider({
		Id = "processing-batch", Text = "Batch size", Min = 1, Max = 20, Step = 1,
		Default = initial.batchSize,
		OnCommit = function(value) apply({ batchSize = value }) end,
	})
	window:Give(model.subscribe(reflect))
	reflect(model.read())
	return controls
end
```

The slider's `OnCommit` applies at gesture end. Use `Callback` for a cheap
immediate preview and `OnCommit` for the corresponding final operation. A
programmatic `Set` uses value callbacks; do not assume it simulates a slider
gesture and invokes `OnCommit`.

### Editable forms and applied state

An Input has a draft while focused and a last valid value. With `Live = false`,
ordinary edits commit on focus loss. With `Live = true`, valid edits publish
while the field retains its caret and draft. Invalid numeric input remains
visible as an error; `Get()` still returns the last valid value.

For several settings that form one operation, initialize controls from a
snapshot and provide an Apply button. Let external model changes refresh an
**Applied state** summary. Provide a separate Refresh action to replace form
values. This prevents an agent or background event from erasing a user's
unfinished input.

The [assistant panel example](../examples/embedding/assistant_panel.lua) implements
this pattern. Its Workbench tab applies all three settings through one model
call. Your domain operation should report conflicts or stale target revisions
when overwriting a changed object would be inappropriate.

### Dependent controls

Derived visibility and enabled state belong in one refresh function:

```lua
local mode = section:Segmented({
	Id = "export-mode", Text = "Export mode", Options = { "Summary", "Detailed" },
	Default = "Summary",
})
local detail = section:Input({
	Id = "export-note", Text = "Detail note", Default = "", MaxLength = 200,
})
local function refreshMode()
	detail:SetVisible(mode:Get() == "Detailed")
end
window:Give(mode:OnChanged(refreshMode))
refreshMode()
```

A hidden or disabled control keeps its value and can still be updated through
`Set`. Those are presentation states, not authorization. Read and validate only
the fields applicable to the selected mode when executing an operation.

### Dynamic choices and stable values

Use stable IDs as option `Value` and human-readable names as `Label`. A player
can change their display name without changing `UserId`; use that identity for
selection. Do not use a list index as the durable value if options can reorder.
`SetOptions` retains still-valid choices and normalizes removed selections.
Handle nil or an empty array as a normal no-selection state.

Search is literal. Keep Dropdown collections within the 500-choice bound and
use a domain search/filtered collection for larger datasets. A disabled option
cannot be selected interactively; check domain eligibility again when running
the operation because a target can change after selection.

### Split a growing interface into modules

One entry point loads UI LIB and creates the window. Feature factories receive
that window (or a tab) and their model/controller. Each feature owns its
subscriptions through the supplied window. Return the controls or an explicit
refresh method when the entry point needs them.

```text
my-host/
  launcher.lua          loads UI once and composes the application
  model.lua             state, validation, and domain operations
  processing_tab.lua    declares processing controls against the model
  history_tab.lua       declares a bounded history view
```

In Studio, those modules can be ModuleScripts required by a LocalScript. In an
executor host, load your reviewed source modules at the entry point. A source
module can `return function(window, model) ... end`, as above. Do not duplicate
window creation, styles, fonts, padding, drag systems, or helper ScreenGuis in
each feature module.

### Communicate state with text

Use short action verbs: Run, Apply, Stop, Refresh, Export. Pair an action with a
clear field label and a description when the result needs explanation. Use a
Badge or Progress for status, a Paragraph for a bounded explanation, and a
notification for a transient outcome. Color should support readable status text.

The library owns typography, spacing, touch targets, and focus presentation.
Set Title/Subtitle, choose Dark/Light, adjust TextScale through the window API,
and offer reduced motion where useful. Do not add icon-only buttons, Unicode
symbols as replacement icons, or decorative marks to navigation. A subject's
avatar in a player choice is content, not an action icon.

The sidebar profile is automatic. `GameName` supplies an already-known name;
there is no need to fetch a logo or player avatar yourself. Compact and short
layouts omit the profile while keeping the controls reachable.
]=],
			["runtime_integration"] = [=[
## Runtime integration

UI LIB can be the presentation layer for a host model and a UAI session. The
complete [embedding guide](EMBEDDING.md) documents the runtime APIs; this section
provides the essential view contract for script authors reading `ui_library_docs`.

### Attach a companion panel

Given an existing live `uai` handle and loaded `UI` API:

```lua
local createPanel = loadstring(game:HttpGet(
	"https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/main/examples/embedding/assistant_panel.lua"
))()
local window, session = createPanel(uai, UI, {
	Id = "my-assistant-panel",
	Session = uai.sessions.current(),
})
```

The example returns a factory; the first call evaluates the source module and
the second constructs the view. It accepts `Id`, `Session`, optional `Parent`,
and an optional `Model` with the read/update/subscribe contract described above.
Use the [launcher](../examples/embedding/launcher.lua) for checked downloads and
installation of the example model/tools. Pin all modules to the same reviewed
revision in a distributed host script.

The panel stays attached to the supplied registered conversation. It does not
follow active-thread changes automatically. Use `uai.sessions.newThread(...)`
for a dedicated thread; `sessions.create(...)` is untracked and is not accepted
by this companion example.

### Send is an admission result

`session.send(text, onDone, files, images)` returns `true` or `false, reason`.
Clear a draft only after true, and only if the current draft still matches what
was submitted. The callback runs after the busy state is released and receives
reply text, which may describe a failure. Observe `error` and `turn:end.failed`
for failure state. Check `window.Alive` before a delayed callback updates controls.

`status = "Ready"` and `turn:end` can arrive before `session.busy` becomes false.
Subscribe to `uai.sessions.listChanged` or use `onDone` to refresh admission
controls after the worker releases busy. Also respect `session.preparing` and
`session.removed`. Stop calls `session.abort()`; it is cooperative, so keep a
stopping state until the session finishes.

### Signals and replay

```lua
window:Give(session.events:connect(function(event)
	if event.kind == "assistant:text" then
		reply:SetDescription(event.text or "")
	elseif event.kind == "error" then
		window:Notify({ Title = "Request failed", Content = event.message, Kind = "Warning" })
	end
end))
```

Here `reply` is an existing Paragraph. Its body setter is `SetDescription`,
not `SetContent`. This small example illustrates the binding; production panels
should bound the displayed text and coalesce frequent updates as the complete
companion panel does.

UAI signals use lowercase `:connect` and return an unsubscribe function, unlike
Roblox's `:Connect` returning an RBXScriptConnection. `window:Give` accepts both.
For initial state, read `session.transcript.snapshot()` after subscribing and
read `session.livePreview` for a running response. `assistant:preview` contains
the accumulated current preview; replace it instead of appending it as a delta.
Clear previews on completion, abort, error, and reset. Full transcript views
must reconcile retained IDs and omissions; a latest-response view can replace
one bounded Paragraph.

### Keep host and view lifetimes distinct

Register a client-lifetime cleanup that closes the dependent view:

```lua
local scope = assert(uai.sdk.createScope("my-assistant-view"))
scope.give(function() window:Destroy() end)
window:OnDestroy(function() scope.destroy() end)
```

Closing the panel then unregisters that runtime cleanup. It does not call
`uai.unload()`, abort the turn, or delete its conversation. Put those actions
behind explicit application commands if the host owns them.

Custom agent tools should call a stable host model, not a control or a captured
window. `scope.registerTool(definition)` refuses duplicate names and unregisters
owned tools when the scope closes. Both those tools
and manual UI actions can call the same validated domain operations.

Keep access to the standard app for provider setup and approvals:
`uai.show("providers")` opens setup; `uai.openSession(session.id)` opens the
conversation. A custom window does not grant new
capabilities or bypass existing permission rules.
]=],
			["recipes"] = [=[
## Recipes

Notifications:

```lua
window:Notify({
	Title = "Saved", Content = "Your preferences are ready.",
	Kind = "Success", Duration = 5,
	Action = { Text = "Open settings", Callback = function() settingsTab:Select() end },
})
```

`Kind` is Info/Success/Warning/Danger. Up to three notifications are retained;
the newest ones that fit are visible. Older notices reappear as space becomes
available or newer ones close. Long text is bounded and truncated.
`Duration = 0` keeps one visible until dismissed; otherwise 0–60 seconds.
The returned handle has `Close()`.

Dialogs:

```lua
window:Confirm({
	Title = "Reset preferences?", Content = "This restores the defaults for this tool.",
	ConfirmText = "Reset", Danger = true,
	Callback = function() amount:Reset() end,
})
window:Dialog({
	Title = "About this tool", Content = "A focused workspace for your current session.",
	Buttons = { { Text = "Done", Style = "Primary" } },
})
```

`Dialog` accepts 1–4 buttons, each with `Text`, optional `Style` and `Callback`.
Choosing a button closes the dialog, then runs the callback in the window's scope.
`Dismissible = false` disables backdrop/Escape dismissal and the close button.
Dialogs return a `Close()` handle and restore previous gamepad selection.
Only one dialog or picker is open per window. Pickers clamp to the safe viewport,
move above their anchor when needed, and use a centered sheet on compact layouts.

Dynamic choices:

```lua
local target = actions:Dropdown({
	Id = "target", Text = "Target", Options = {}, Placeholder = "No players yet",
})
-- Each player is their headshot followed by their display name. The rbxthumb
-- scheme resolves inside the client, so no upload or HTTP request is needed.
local function playerChoice(player)
	return {
		Label = player.DisplayName,
		Value = player.UserId,
		Image = string.format("rbxthumb://type=AvatarHeadShot&id=%.0f&w=150&h=150", player.UserId),
	}
end
local function refreshPlayers()
	local choices = {}
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		choices[#choices + 1] = playerChoice(player)
	end
	target:SetOptions(choices)
end
refreshPlayers()
window:Give(game:GetService("Players").PlayerAdded:Connect(refreshPlayers))
window:Give(game:GetService("Players").PlayerRemoving:Connect(function(leaving)
	local choices = {}
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		if player ~= leaving then choices[#choices + 1] = playerChoice(player) end
	end
	target:SetOptions(choices)
end))
```

Full examples: [starter.lua](../ui-lib/examples/starter.lua) and
[showcase.lua](../ui-lib/examples/showcase.lua). They load the same public bundle
as production scripts and contain no GUI instance construction.

For a complete model, tool registration, and custom assistant panel, use
[examples/embedding](../examples/embedding/README.md).
]=],
			["performance"] = [=[
## Performance

### Keep work proportional to what the view needs

| Work | Recommended pattern |
| --- | --- |
| A setting changes | Update the affected controls, using silent setters for reflection |
| Many state events arrive | Queue one bounded refresh that reads the newest state |
| A slider moves | Cheap preview through Callback; expensive operation on OnCommit |
| A player list changes | Replace a bounded options list by stable identity |
| An assistant response grows | Replace a bounded latest-response preview; open UAI for full history |
| A window is rerun | Stable Id replacement and owned cleanup |
| A native operation completes late | Generation/lifetime checks before publishing the result |

Do not recreate the window for each settings change, poll every frame for state
that already has an event, or build one control for every log line. The window
already owns layout and reflow. Changing Frame positions or sizes in consumer
code competes with that system.

Dropdowns support at most 500 choices. Segmented controls are for 1–8 choices.
Paragraphs wrap plain text and are not Markdown renderers, code editors, or
virtualized transcripts. Bound your data first; add a shared paginated or
virtualized component under `ui-lib/src` when the product needs one.

### Hidden views still have state

Hide/Minimize stop the window's visible presentation and release active input
actions, while your subscriptions remain owned and active. Destroy is the
resource-release boundary. A host event can still arrive while minimized; it
must update state without assuming a visible measured rectangle.

The companion example keeps one bounded response and schedules at most one
pending paint. It does not implement a separate virtual transcript. For a
larger reusable view, retain state separately from mounted rows, preserve a
reading anchor, treat zero measurements during hiding as temporary, and refresh
from retained state on restore. Viewport chunking must never delete the model's
conversation or lose a user's draft.

There is no public window visibility-change signal in 1.2.1. Do not invent
`OnShow`/`OnHide` options or patch a window's methods to simulate them. Simple
bounded views can remain subscribed. A reusable view that needs dedicated
visibility lifecycle support should add that capability to the library first.

### Motion and responsiveness

Mobile layouts use smaller content insets, wrapped section headings, and dialog
action rows sized for touch. Dropdown search stays above the scrolling choices
when the keyboard leaves enough space for a complete option row; in shorter
views it joins the scroll body. Dialog actions likewise join the body when space
is too short to pin them. Open pickers reflow their fields and actions after
rotation or text-scale changes without replacing drafts.

On touch screens, horizontal sliders and color bars wait for a tap release or
horizontal movement before changing values. Vertical swipes remain scroll gestures
and do not invoke slider `OnCommit`. Active horizontal drags temporarily hold their
scrolling ancestors; release, cancellation, hide, rotation, replacement, and
destruction restore scrolling. Multiline fields reveal the editing line when a
keyboard makes the entire field too tall to display. Hiding a window, tab, or
control releases its text focus.

Use the library's owned transitions and `SetReducedMotion` API. Do not add
per-frame entrance tweens, custom drag motion, or artificial typewriter loops to
consumer scripts. `SetReducedMotion(true)` settles active transitions, and
window destruction/replacement releases their resources.

Choose preferred Width/Height, then let the library fit the safe viewport.
Long descriptions wrap, value rows stack, and tabs switch to a horizontal strip
when space is limited. Avoid treating a desktop pixel width as an invariant in
application code. Preserve useful text at larger TextScale values and provide
readable statuses alongside color.
]=],
			["troubleshooting"] = [=[
## Troubleshooting

| Problem | Resolution |
| --- | --- |
| A callback does not run when the control is created | Constructors deliberately do not invoke callbacks; read initial values or call a domain initializer |
| Programmatic updates call the model repeatedly | Use `Set(value, true)` when reflecting model state |
| Import changes a value but not dependent controls | Silent import suppresses callbacks; call your derived-view refresh afterward |
| Import rejects a formerly valid setting | Check window Id, control type, and current value bounds; migrate intentionally |
| Filesystem save fails | Use ExportConfig/ImportConfig or supply the host's storage flow; Studio has no executor files |
| Text body does not update | Paragraph body uses `SetDescription`, while `SetText` changes its title |
| Numeric input shows an error but Get returns an older value | Invalid drafts preserve the last valid value; do not treat that value as the raw draft |
| A slider callback is too expensive | Keep value-change previews cheap and commit expensive work at gesture end |
| Set does not trigger OnCommit | A setter is not a user gesture; invoke the domain operation explicitly when needed |
| Player selection changes after list refresh | Use stable UserId values, not list indices or mutable display names |
| A keybind does not fire while typing/in a dialog | Input capture protects editing and overlays; choose another interaction |
| A keybind conflicts with the window toggle | The window toggle key is reserved; disable/change it through CreateWindow options |
| Two scripts replace each other's windows | Give different applications different stable window Ids |
| Two controls collide across tabs | Control Ids are unique across the whole window |
| The sidebar profile disappears on a compact window | The layout prioritizes control space; horizontal tabs remain available |
| An Icon option does nothing | Navigation and actions are text-only; legacy Icon options are ignored |
| A Frame Parent does not behave like docking | Parent is for the owned ScreenGui; arbitrary Frame embedding is unsupported |
| A closed view still handles model events | Register the returned unsubscribe/connection with window:Give |
| Work continues after Minimize | Minimize retains the application; use an explicit Stop command for domain work |
| A delayed task updates a replaced window | Guard with window.Alive and generation tokens; own/unregister scheduled tasks |
| Full UAI settings do not change after a window import | Window configuration and UAI client configuration are separate systems |
| A custom send button stays disabled | Refresh actual session.busy after sessions.listChanged/onDone |
| A large reply makes the panel slow | Bound the response view and coalesce updates; use a proper shared transcript component for history |

Read the implementation and add a reusable capability when a requirement falls
outside the public API. Do not solve an API gap by editing private Frames or
copying a second UI library into the script.
]=],
			["extending"] = [=[
## Extending

This section is for repository contributors. Consumer scripts use the public
API; new reusable controls and lifecycle capabilities belong in `ui-lib/src`.

### Source map

| Module | Responsibility |
| --- | --- |
| `library.lua` | Public UI object, window lookup, configuration method composition |
| `window.lua` | Window creation, input, safe layout, visibility, lifetime |
| `containers.lua` | Tabs, sections, control constructor exposure, search/layout |
| `controls.lua` | Base control contract and common control implementations |
| `choice.lua` | Choice-based controls and pickers |
| `color.lua` | Color picker behavior |
| `config.lua` | Typed state serialization, validation, import/export, file profiles |
| `core.lua` | Resource scopes, instance helpers, layout/measurement, callbacks |
| `theme.lua` | Shared visual tokens and theme values |
| `motion.lua` | Owned reversible transitions and reduced-motion handling |
| `overlays.lua` | Dialogs, notifications, and overlay ownership |
| `profile.lua` | Local player profile and experience information |

`ui-lib/loader.lua` creates the independent factory environment. Each source
module returns `function(env) ... end` and uses that environment's memoized
loader. These modules do not use the client `src/ui` module environment.

### Add a control as a shared capability

1. Define the consumer API: constructor, valid values, methods, callbacks,
   defaults, disabled/hidden states, and persistence behavior.
2. Implement the control using the shared base/ownership helpers. Keep stable
   values independent from visible labels and validate before changing state.
3. Wire it into control dispatch and the constructor exposure in
   `containers.lua`. There is no consumer `UI:RegisterControl` hook.
4. Define configuration serialization/validation if it is stateful. Invalid
   imports must not partially apply, and imports remain silent by default.
5. Handle pointer, touch, keyboard/gamepad selection, overlay dismissal, hide,
   replacement, and destruction. Use shared motion/theme primitives.
6. Document the API in Controls and add a focused usage example. Add meaningful
   behavioral coverage for its distinct state/input/lifecycle cases.
7. Finish and manually audit all source, documentation, example, and test edits
   before building or testing.

For a capability such as virtualization or docking, first define its lifetime,
measurement, accessibility, and data ownership contracts. A control that happens
to fit one script is not yet a stable shared interface. Keep the permanent
attribution and text navigation in the design.

### Keep the agent reference discoverable

Every H2 section in this file becomes a lowercase underscore key in the generated
`runtime/ui_library_docs` module. `src/tools/gui.lua` advertises those keys in the
`ui_library_docs` schema. Add new keys there whenever adding a section here.
Do not edit `src/runtime/ui_library_docs.lua` directly.

`test/ui_library_agent.lua` checks that the tool's advertised sections match the
generated guide and that pagination reconstructs every section exactly. The
tool returns bounded UTF-8 pages; agents must follow `nextOffset` until it is
absent to read a long section completely.
]=],
			["development"] = [=[
## Development

Library source is separate from `src/ui`, which remains the existing client UI.
Modules in `ui-lib/src` are `return function(env) ... end` factories, using the
repository's Lua 5.1-compatible Luau dialect. Keep visual tokens in `theme.lua`.
Add reusable controls here; consumer scripts should only declare controls and
implement application behavior.

Manually audit every change before automated tests, including the test code.
After reviewing build inputs, generate and inspect the outputs before running
the suites. Review each subsequent fix manually before retesting.

```bash
node tools/build_ui_lib.js
luajit tools/bundle.lua --native
node tools/build_site.js
# Manually inspect the generated bundles, manifests, guide, and catalog here.
luajit test/ui_library.lua
luajit test/ui_library_agent.lua
luajit test/embedding_examples.lua
node tools/build_ui_lib.js --check
luajit tools/bundle.lua --native --check
node tools/build_site.js --check
```

These are the focused guide/library/example checks. For broader client/runtime
changes, follow the [native verification sequence](CODE_WORKSPACE_TESTING.md)
with `node tools/test_native.js`. Its `--skip-images` flag omits the dedicated
image-input suite when image verification is
out of scope; the verification report lists that omission. The bridge scenario
runner accepts the same flag and suppresses screenshots and image-specific suites.

The UI build emits `dist/uai-ui.lua`, a SHA-256 manifest, and
`src/runtime/ui_library_docs.lua` generated from this guide. The generated guide
backs the offline `ui_library_docs` tool, so agents can read the exact API without
network access. Never hand-edit generated artifacts. Rebuild the main client
after changing the guide or agent instructions.

The behavioral tests execute the actual distributed library with the repository's
Roblox mock, including mouse/touch ownership, value validation, config round-trips,
callback failures, replay, and cleanup. Native Roblox rendering, OS keyboard
behavior, and actual gamepad focus still require in-client validation.
]=],
		},
	}
end
