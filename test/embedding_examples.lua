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
check("SDK example opens required password entry with the normal app hidden", integration.client.alive
	and integration.client.uiMounted and not integration.client.app.window.visible
	and not integration.client.config.vaultStatus().ready)
check("SDK example cannot request before password entry", integration.ask("Read host status") == nil)
check("SDK example installs only its named tool and isolated conversation", integration.session.ephemeral and integration.session.toolFilter.sdk_example_status and integration.client.tools.get("sdk_example_status"))
require("password_fixture")(h, integration.client)
check("SDK starts with no automatic provider", #integration.client.providers.list() == 0)
local missing, missingWhy = integration.ask("Read host status")
check("example directs unconfigured hosts to setup before starting work", missing == nil and missingWhy:find("configureProvider", 1, true))
check("provider setup is an explicit navigation action", integration.configureProvider() and integration.client.app.panel == "providers")
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
check("tool and manual updates reject multiline titles", not model.update({ title = "first\nsecond" }))
check("tool and manual updates reject invalid UTF-8", not model.update({ title = "bad\255" }))
check("invalid title preserves applied state", model.read().title == "Applied form")
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

local failedHarness, failedLaunch = fixture()
local download = failedHarness.sandbox.game.HttpGet
failedHarness.sandbox.game.HttpGet = function(self, url)
	if url:find("examples/embedding/assistant_panel.lua", 1, true) then
		return [[return function(uai, UI)
			getgenv().__partialExample = UI:CreateWindow({ Id = "embedding-workbench", Title = "Partial example" })
			error("Synthetic construction failure")
		end]]
	end
	return download(self, url)
end
local launched = pcall(failedLaunch, "examples/embedding/launcher.lua")
local failedClient = failedHarness.sandbox.getgenv().UAI
check("failed construction keeps the shared client available", not launched and failedClient and failedClient.alive)
check("failed construction removes newly owned model tools", not failedClient.tools.get("workbench_status") and not failedClient.env.context.workbenchExample)
local partialWindow = failedHarness.sandbox.getgenv().__partialExample
check("failed construction closes its partial library window", partialWindow and not partialWindow.Alive and partialWindow.ScreenGui.Parent == nil)
failedClient.unload(); failedHarness.settle(0.3)
check("failed launch leaves no asynchronous errors", #failedHarness.errors() == 0)
print("Embedding examples: " .. passed .. " checks passed")
