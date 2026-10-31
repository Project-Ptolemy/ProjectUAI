-- Delegation may narrow the caller's available original tools, never widen them.
return function(env)
	local registry = env.require("agent/registry")
	local M = {}
	function M.intersect(current, parent, requestNames)
		if not parent and requestNames == nil then return current end
		local parentNames = {}
		for _, tool in ipairs(registry.available(parent and { only = parent.toolFilter, groups = parent.toolGroups, exclude = parent.toolExclude } or {})) do
			parentNames[tool.name] = true
		end
		local out = {}
		for name in pairs(parentNames) do
			if (not current or current[name] == true) and (requestNames == nil or type(requestNames) == "table" and requestNames[name] == true) then
				out[name] = true
			end
		end
		return out
	end
	return M
end
