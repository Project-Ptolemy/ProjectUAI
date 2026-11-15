-- Device identity stays independent of layout and optional mouse capabilities.
-- Some phone executors expose MouseEnabled even though the host is handheld.
return function(env)
	local M = {}
	local platformSampled, mobilePlatform = false, false
	local function samplePlatform()
		if platformSampled then return end
		platformSampled = true
		local ok, name = pcall(function() return env.uis:GetPlatform().Name end)
		mobilePlatform = ok and (name == "IOS" or name == "Android") or false
	end
	function M.input()
		samplePlatform()
		local result = { touch = false, pointer = true, keyboard = true, gamepad = false, console = false }
		pcall(function()
			result.touch = env.uis.TouchEnabled == true
			result.pointer = env.uis.MouseEnabled == true
			result.keyboard = env.uis.KeyboardEnabled == true
			result.gamepad = env.uis.GamepadEnabled == true
		end)
		pcall(function() result.console = env.guisvc:IsTenFootInterface() == true end)
		result.handheld = result.touch and not result.console and (mobilePlatform or not result.pointer or not result.keyboard)
		return result
	end
	function M.isHandheld() return M.input().handheld end
	return M
end
