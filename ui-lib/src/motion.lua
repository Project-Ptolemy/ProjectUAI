-- Owned transitions reverse from the current value and always settle exactly.
return function(env)
	local T = env.require("theme")
	local M = {}
	local function assign(node, properties)
		for key, value in pairs(properties) do node[key] = value end
	end
	function M.stop(window, node, settle)
		local entry = window._motions and window._motions[node]
		if not entry then return end
		window._motions[node] = nil
		if entry.connection then entry.connection:Disconnect() end
		if entry.tween then pcall(function() entry.tween:Cancel() end) end
		if entry.release then entry.release(false) end
		if settle and node.Parent then assign(node, entry.goals) end
	end
	function M.stopAll(window, settle)
		local nodes = {}
		for node in pairs(window._motions or {}) do nodes[#nodes + 1] = node end
		for _, node in ipairs(nodes) do M.stop(window, node, settle) end
	end
	function M.to(owner, node, properties, seconds)
		local window = owner._window
		if not owner._scope.alive or not window.Alive or not node.Parent then return end
		local goals = {}
		local previous = window._motions[node]
		if previous then
			local same = true
			for key, value in pairs(properties) do if previous.goals[key] ~= value then same = false; break end end
			if same then return end
		end
		if previous then for key, value in pairs(previous.goals) do goals[key] = value end end
		for key, value in pairs(properties) do goals[key] = value end
		M.stop(window, node, false)
		local changed = false
		for key, value in pairs(goals) do if node[key] ~= value then changed = true; break end end
		if not changed then return end
		local launcher = window._launcher
		local shown = window.Visible or (launcher and launcher.Visible and (node == launcher or node:IsDescendantOf(launcher)))
		if window.ReducedMotion or not shown or seconds == 0 then assign(node, goals); return end
		local ok, tween = pcall(function()
			return env.services.TweenService:Create(node, TweenInfo.new(seconds or T.Motion.Fast, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), goals)
		end)
		if not ok or not tween then assign(node, goals); return end
		local entry = { goals = goals, tween = tween }
		window._motions[node] = entry
		entry.release = owner._scope:Add(function() M.stop(window, node, true) end)
		entry.connection = tween.Completed:Connect(function()
			if window._motions[node] ~= entry then return end
			window._motions[node] = nil
			entry.connection:Disconnect(); entry.release(false)
			if owner._scope.alive and node.Parent then assign(node, goals) end
		end)
		local played = pcall(function() tween:Play() end)
		if not played then M.stop(window, node, true) end
	end
	function M.reveal(owner, node)
		local window = owner._window
		local scale = node:FindFirstChild("EntranceScale")
		if not scale then scale = Instance.new("UIScale"); scale.Name = "EntranceScale"; scale.Parent = node end
		M.stop(window, scale, false)
		scale.Scale = window.ReducedMotion and 1 or T.Motion.EntranceScale
		M.to(owner, scale, { Scale = 1 }, T.Motion.Enter)
	end
	return M
end
