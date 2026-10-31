-- Named shapes offer predictable corners without requiring pixel choices.
-- Explicit CornerRadius remains an optional, bounded advanced preference.
return function(env)
	local M = { Names = { "Rounded", "Soft", "Square" } }
	local radii = { Rounded = 8, Soft = 14, Square = 0 }
	function M.valid(name) return radii[name] ~= nil end
	function M.radius(name)
		local radius = radii[name or "Rounded"]
		assert(radius ~= nil, "Unknown shape: " .. tostring(name))
		return radius
	end
	function M.infer(radius)
		for _, name in ipairs(M.Names) do if radii[name] == radius then return name end end
		return "Custom"
	end
	return M
end
