-- Built-in Roblox fonts only. Each role retains its hierarchy when a window
-- changes family; explicit code surfaces always keep a monospace font.
return function(env)
	local M = { Names = { "Sans", "System", "Mono" } }
	local sans = { Enum.Font.Gotham, Enum.Font.GothamMedium, Enum.Font.GothamBold }
	pcall(function() sans = { Enum.Font.BuilderSans, Enum.Font.BuilderSansMedium, Enum.Font.BuilderSansBold } end)
	local families = {
		Sans = sans,
		System = { Enum.Font.SourceSans, Enum.Font.SourceSansSemibold, Enum.Font.SourceSansBold },
		Mono = { Enum.Font.Code, Enum.Font.Code, Enum.Font.Code },
	}
	function M.valid(name) return families[name] ~= nil end
	function M.font(name, role, code)
		local family = families[name or "Sans"]
		assert(family, "Unknown typography: " .. tostring(name))
		if code then return Enum.Font.Code end
		local weight = role == "Display" and 3 or (role == "Title" or role == "Heading" or role == "Eyebrow") and 2 or 1
		return family[weight]
	end
	function M.attach(core, owner, node, role, code)
		core.bind(owner, node, { Font = function() return M.font(owner._window.Typography, role, code) end })
	end
	return M
end
