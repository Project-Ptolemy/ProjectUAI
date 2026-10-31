-- Reviewable project starters. Return source declarations; never write or execute.
return function(env)
	local util = env.require("runtime/util")
	local M = {}
	function M.files(directory, kind)
		local root, why = env.require("runtime/script_project").path(directory)
		if not root then return nil, why end
		kind = kind or "basic"
		if kind ~= "basic" and kind ~= "interface" then return nil, "Choose basic or interface" end
		local modules = { main = "main.lua", settings = "settings.lua", ["tests/settings"] = "tests/settings.lua" }
		local sources = {
			main = 'local settings = require("settings")\nreturn { name = settings.name, enabled = settings.enabled }\n',
			settings = 'return { name = "My script", enabled = true }\n',
			["tests/settings"] = 'local settings = require("settings")\nreturn {\n\tdefaults = function(t)\n\t\tt.equal(settings.name, "My script")\n\t\tt.truthy(settings.enabled)\n\tend,\n}\n',
		}
		local tests = { "tests/settings" }
		if kind == "interface" then
			modules.interface, modules.logic, modules["tests/logic"] = "interface.lua", "logic.lua", "tests/logic.lua"
			sources.main = [[local source = game:HttpGet("https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/main/dist/uai-ui.lua")
local chunk, why = loadstring(source, "@uai-ui")
assert(chunk, why)
local UI = chunk()
return require("interface")(UI, require("settings"), require("logic")())
]]
			sources.settings = 'return { name = "My script", enabled = true, id = "uai-' .. root:gsub("[^%w_-]", "-"):sub(-70) .. '" }\n'
			sources.logic = [[return function()
	local model = { count = 0, alive = true }
	function model.increment()
		if not model.alive then return false end
		model.count = model.count + 1; return true
	end
	function model.reset() if model.alive then model.count = 0 end end
	function model.stop() model.alive = false end
	return model
end
]]
			sources.interface = [[return function(UI, settings, model)
	local window = UI:CreateWindow({ Id = settings.id, Title = settings.name })
	local main = window:Tab({ Id = "main", Title = "Main" })
	local actions = main:Section({ Id = "actions", Title = "Actions" })
	local count = actions:Badge({ Id = "count", Text = "Count", Default = "0" })
	actions:Button({ Id = "increment", Text = "Increase count", Callback = function()
		if model.increment() then count:Set(tostring(model.count)) end
	end })
	actions:Button({ Id = "reset", Text = "Reset count", Callback = function()
		model.reset(); count:Set(tostring(model.count))
	end })
	window:OnDestroy(model.stop)
	return window
end
]]
			sources["tests/logic"] = [[local make = require("logic")
return {
	increments = function(t)
		local model = make()
		t.truthy(model.increment()); t.equal(model.count, 1)
		model.reset(); t.equal(model.count, 0)
	end,
	stops = function(t)
		local model = make()
		model.stop(); t.equal(model.increment(), false); t.equal(model.count, 0)
	end,
}
]]
			tests[#tests + 1] = "tests/logic"
		end
		local result = { { path = root .. "/uai.project.json", create = true,
			content = util.encode({ version = 1, entry = "main", modules = modules, tests = tests }) } }
		for _, id in ipairs(util.keys(modules, true)) do result[#result + 1] = { path = root .. "/" .. modules[id], create = true, content = sources[id] } end
		return result, root .. "/uai.project.json"
	end
	return M
end
