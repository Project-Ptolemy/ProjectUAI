---
uai_vault: 1
title: "Own a script's resources"
description: "Keep connections and created Instances under an explicit, repeatable cleanup function."
kind: recipe
scope: global
tags: ["cleanup", "connections", "scripts"]
sources: [{"label":"Execution and cleanup","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/SCRIPT_DEVELOPMENT.md#execution-and-cleanup"},{"label":"UI LIB lifecycle","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/UI_LIBRARY.md#lifecycle"}]
status: verified
verification: "Documentation recipe reviewed for Project UAI 4.0.0; native engine callbacks and cleanup behavior still need host checks."
---
# Own a script's resources

Give each connection, delayed task and created Instance one owner. A source
restore cannot undo a running script's effects, and a tool timeout does not
automatically disconnect persistent engine callbacks.

For a small non-UI module, keep ownership in local state:

```lua
local M = {}
local alive = false
local connection
local ownedPart

function M.stop()
	alive = false
	if connection then connection:Disconnect(); connection = nil end
	if ownedPart then ownedPart:Destroy(); ownedPart = nil end
end

function M.start(runService, parent)
	M.stop()
	local part = Instance.new("Part")
	ownedPart = part
	local ok, why = pcall(function()
		part.Name = "OwnedPreview"
		part.Anchored = true
		part.CanCollide = false
		part.Parent = parent
		alive = true
		connection = runService.Heartbeat:Connect(function()
			if not alive or not part.Parent then return end
			-- Perform bounded work on this module's owned object.
		end)
	end)
	if not ok then M.stop(); error(why, 0) end
	return M.stop
end

return M
```

The caller supplies the service and parent, and retains the returned stop
function. Do not delete unrelated objects just because their names match. If a
setup fails after creating an object, clean up that exact object.

For a script-owned interface, register the returned cleanup and application
connections with `window:Give` or `window:OnDestroy`. Hide and Minimize retain
the view's resources; Destroy and same-Id replacement release them.

Check repeated Start/Stop, setup failure, late callbacks and the actual lifetime
the user requested. Managed task deadlines cover managed work only; dynamically
loaded code, native calls and persistent callbacks retain their documented limits.
