-- Complete executor entry point. Replace main with one reviewed commit SHA in
-- production so the runtime, UI library and example modules stay on one revision.
local revision = "main"
local root = "https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/" .. revision .. "/"
local function loadModule(path)
	local ok, source = pcall(function() return game:HttpGet(root .. path) end)
	assert(ok and type(source) == "string", "Could not download " .. path .. ": " .. tostring(source))
	local chunk, why = loadstring(source, "@" .. path)
	assert(chunk, "Could not compile " .. path .. ": " .. tostring(why))
	return chunk
end

local globals = type(getgenv) == "function" and getgenv() or nil
local uai = globals and globals.UAI
if not (type(uai) == "table" and uai.alive) then
	uai = loadModule("dist/uai.lua")({
		prompt = "This host provides workbench_status and workbench_configure for its local example settings. Use those tools for workbench requests.",
	})
end
assert(uai and uai.alive, "UAI did not start; read its console error")

local UI = loadModule("dist/uai-ui.lua")()
local installModel = loadModule("examples/embedding/host_tools.lua")()
local createPanel = loadModule("examples/embedding/assistant_panel.lua")()
local model = installModel(uai)
local window, session = createPanel(uai, UI, { Model = model })
return { client = uai, UI = UI, model = model, window = window, session = session }
