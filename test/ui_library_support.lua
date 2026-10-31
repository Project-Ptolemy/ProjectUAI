-- Shared setup for focused checks against the built public UI bundle.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock = require("env")
local M = {}
function M.new(id, options)
	local h = envMock.new(options)
	local UI = assert(h.boot("dist/uai-ui.lua"))
	local window = UI:CreateWindow({ Id = id, ReducedMotion = true })
	local section = window:Tab({ Id = "main", Title = "Main" }):Section({ Title = "Form" })
	local checks = 0
	local function check(label, value)
		assert(value, label)
		checks = checks + 1
		print("ok " .. label)
	end
	local function done()
		UI:DestroyAll(); h.settle(0.3)
		check("no asynchronous or Roblox property errors", #h.errors() == 0 and #h.instanceState.typeErrors == 0)
		print(id .. ": " .. checks .. " checks passed")
	end
	return h, UI, window, section, check, done
end
return M
