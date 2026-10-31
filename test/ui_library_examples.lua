-- Execute consumer examples against the generated library, with local downloads.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock = require("env")
local function read(path)
	local file = assert(io.open(path, "rb")); local value = file:read("*a"); file:close(); return value
end
for _, name in ipairs({ "starter", "showcase", "forms", "profiles", "debounce", "activity", "workspace" }) do
	local h = envMock.new()
	h.sandbox.game.HttpGet = function(_, url)
		assert(url == "https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/main/dist/uai-ui.lua", "unexpected example download")
		return read("dist/uai-ui.lua")
	end
	local source = read("ui-lib/examples/" .. name .. ".lua")
	local window = assert(h.sandbox.loadstring(source, "@example-" .. name))()
	assert(window.Alive and h.byName("Attribution", window.Frame).Text == "Project UAI | UI LIB.")
	if name == "forms" then
		window:Get("batch-name"):Set("Reviewed batch", true)
		window:Get("batch-apply"):Press(); h.settle(0.1)
		assert(window:Get("batch-status"):Get() == "Applied")
	elseif name == "profiles" then
		window:Get("profile-save"):Press(); h.settle(0.1)
		assert(window:Get("profile-selected"):Get() == "default")
		window:Get("enabled"):Set(false)
		window:Get("profile-load"):Press(); h.settle(0.1)
		assert(window:Get("enabled"):Get())
	elseif name == "debounce" then
		window:Get("query"):Set("does-not-exist")
		h.settle(0.3)
		assert(#window:Get("player"):GetOptions() == 0)
	elseif name == "activity" then
		h.services.RunService.Heartbeat:Fire(2); h.settle(0.3)
		assert(tonumber(window:Get("elapsed"):Get()) >= 2)
	elseif name == "workspace" then
		window:Get("tasks"):Set("lighting")
		window:Get("actions"):Press("complete"); h.settle(0.1)
		assert(window:Get("details"):Get()[2].Value == "1")
		assert(window:Get("preview"):Get():find("interior", 1, true))
	end
	local replacement = assert(h.sandbox.loadstring(source, "@example-rerun-" .. name))()
	assert(not window.Alive and replacement.Alive, "example rerun must replace its own window")
	replacement:Destroy(); h.settle(0.5)
	assert(#h.errors() == 0 and #h.instanceState.typeErrors == 0, "example leaked errors: " .. name)
	print("ok example " .. name .. " loads, runs, replaces and cleans up")
end
