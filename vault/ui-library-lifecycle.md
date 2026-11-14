---
uai_vault: 1
title: "Build a UI LIB tool with owned cleanup"
description: "Use stable declarative controls and attach domain cleanup to the library window."
kind: recipe
scope: global
tags: ["ui", "ui-lib", "lifecycle"]
sources: [{"label":"UI LIB Quickstart and Controls","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/UI_LIBRARY.md"},{"label":"Owned view work","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/UI_LIBRARY_LIFECYCLE.md"}]
status: verified
verification: "API recipe reviewed against UI LIB 1.6.0 documentation for Project UAI 4.0.0; native rendering and input are unverified."
---
# Build a UI LIB tool with owned cleanup

Read the library's Quickstart, Controls and Lifecycle before writing a new
script-owned interface. Load the published bundle once at the entry point and
pass the API into other modules. Scripts declare values and domain callbacks;
the library owns controls, layout, appearance, drag behavior and attribution.

```lua
local UI = loadstring(game:HttpGet(
	"https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/main/dist/uai-ui.lua"
))()
local window = UI:CreateWindow({
	Id = "my-project-observer", Title = "Project observer",
	Subtitle = "Inspect the current session",
})
local tab = window:Tab({ Id = "main", Title = "Main" })
local section = tab:Section({ Id = "actions", Title = "Actions" })
local enabled = section:Toggle({
	Id = "observer-enabled", Text = "Observe changes", Default = false,
})
local players = game:GetService("Players")
window:Give(players.PlayerAdded:Connect(function(player)
	if enabled:Get() then print("Player joined", player.Name) end
end))
window:OnDestroy(function()
	-- Release any additional domain state owned by this application.
end)
return window
```

Give different applications different stable window IDs; keep control IDs unique
within one window. Recreating the same window ID destroys the earlier view and
calls its cleanup. Keep navigation and action labels as plain text. Every library
window retains `Project UAI | UI LIB.` and the library-provided player profile.

For delayed work use owned `window:Delay`; for a trailing update after a burst,
use `window:Debounce`. Guard native asynchronous results with a request generation
and `window.Alive` after they return. Closing a view does not roll back domain
effects or destroy a shared client.

Review the source, build affected artifacts, inspect output, and run appropriate
offline checks. A mock preview establishes approximate layout; native rendering,
host input and side-effect behavior require their own evidence.
