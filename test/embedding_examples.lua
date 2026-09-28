-- Execute the published examples with local downloads and the real bundles.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock = require("env")
local passed = 0
local function check(label, value) assert(value, label); passed = passed + 1; print("ok " .. label) end
local function read(path)
	local file = assert(io.open(path, "rb")); local source = file:read("*a"); file:close(); return source
end
local function fixture()
	local h = envMock.new()
	h.sandbox.game.HttpGet = function(_, url)
		local path = assert(url:match("ProjectUAI/main/(.+)$"), "unexpected example download")
		return read(path)
	end
	local function run(path) return assert(h.sandbox.loadstring(read(path), "@" .. path))() end
	return h, run
end
local h, run = fixture()
local integration = run("examples/embedding/sdk.lua")
check("SDK example boots without UI or automatic inference", integration.client.alive and not integration.client.uiMounted and #h.coreGui:GetChildren() == 0)
check("SDK example installs only its named tool and isolated conversation", integration.session.ephemeral and integration.session.toolFilter.sdk_example_status and integration.client.tools.get("sdk_example_status"))
local missing = assert(integration.ask("Read host status"))
check("example exposes request failures for unconfigured providers", missing.await(5).status == "failed")
integration.destroy()
check("destroying the SDK example removes its tool but retains the client and conversation", not integration.client.tools.get("sdk_example_status") and integration.client.alive and integration.client.sessions.get(integration.session.id) == integration.session)
check("destroyed example cannot send more requests", integration.ask("after") == nil)
local repeated = run("examples/embedding/sdk.lua")
check("destroyed SDK integration can reuse its existing conversation", repeated.client == integration.client and repeated.session == integration.session and not repeated.created)
repeated.client.unload(); h.settle(1)
check("SDK example finishes without uncaught errors", #h.errors() == 0)

local viewHarness, launch = fixture()
local workbench = launch("examples/embedding/launcher.lua")
local client, window, model = workbench.client, workbench.window, workbench.model
viewHarness.settle(0.2)
check("workbench mounts library controls and the normal app", client.uiMounted and window.Alive and window:Get("workbench-apply") ~= nil)
local form = window:Get("workbench-title")
form:Set("Unsaved draft", true)
assert(model.update({ title = "Agent setting", batchSize = 8 }))
check("model notifications preserve the editable draft", form:Get() == "Unsaved draft" and model.read().title == "Agent setting")
window:SelectTab("workbench"); viewHarness.settle(0.2)
window:Get("workbench-refresh"):Press(); viewHarness.settle(0.2)
check("explicit Refresh copies model values into controls", form:Get() == "Agent setting" and window:Get("workbench-batch"):Get() == 8)
form:Set("Applied form", true)
window:Get("workbench-apply"):Press(); viewHarness.settle(0.2)
check("Apply commits through model validation", model.read().title == "Applied form")
local ok = model.update({ batchSize = 100, title = "Invalid atomic patch" })
check("invalid model patch preserves all previous settings", not ok and model.read().title == "Applied form" and model.read().batchSize == 8)
local replacement = launch("examples/embedding/launcher.lua")
viewHarness.settle(0.2)
check("rerun replaces the window and reuses client, model and conversation", not window.Alive and replacement.window.Alive and replacement.client == client and replacement.model == model and replacement.session == workbench.session)
replacement.window:Destroy()
check("closing a view preserves model tools and the shared client", client.alive and client.tools.get("workbench_status") and model.update({ enabled = false }))
model.destroy()
check("model teardown unregisters both tools and releases its namespace", not client.tools.get("workbench_status") and not client.tools.get("workbench_configure") and client.env.context.workbenchExample == nil)
local latest = launch("examples/embedding/launcher.lua")
check("explicit model teardown allows a clean reinstall", latest.model ~= model and latest.window.Alive)
client.unload(); viewHarness.settle(1)
check("client unload closes the dependent example window", not latest.window.Alive and not latest.model.update({ enabled = true }))
check("workbench examples leave no asynchronous errors", #viewHarness.errors() == 0)
print("Embedding examples: " .. passed .. " checks passed")
