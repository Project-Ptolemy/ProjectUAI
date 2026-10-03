-- Owned transitions reverse from the current value and always settle exactly.
return function(env)
	local T = env.require("theme")
	local M = {}
	local function assign(node, properties)
		for key, value in pairs(properties) do node[key] = value end
	end
	local function visible(window, node)
		local ancestor = node
		while ancestor and ancestor ~= window.ScreenGui do
			if ancestor:IsA("GuiObject") and not ancestor.Visible then return false end
			ancestor = ancestor.Parent
		end
		return ancestor ~= nil and window.ScreenGui.Enabled
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
		local immediate = window.ReducedMotion or seconds == 0 or not visible(window, node)
		if previous and not immediate then
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
		if immediate then assign(node, goals); return end
		local ok, tween = pcall(function()
			return env.services.TweenService:Create(node, TweenInfo.new(seconds or T.Motion.Fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals)
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
	-- Fade content at its final size. Scaling a scrolling page changes its
	-- canvas, text rasterization and hit geometry throughout the transition.
	function M.reveal(owner, node, color, radius)
		local window = owner._window
		local veil = node:FindFirstChild("Reveal")
		if window.ReducedMotion or not visible(window, node) then
			if veil then M.to(owner, veil, { BackgroundTransparency = 1 }, 0) end
			return
		end
		if not veil then
			local C = env.require("core")
			veil = C.node(owner, "Frame", node, {
				Name = "Reveal", Size = UDim2.fromScale(1, 1), Active = false, Selectable = false, ZIndex = 50,
			})
			local corner = node:FindFirstChildOfClass("UICorner")
			C.corner(veil, radius or (corner and corner.CornerRadius.Offset) or 0)
		end
		veil.BackgroundColor3 = color or node.BackgroundColor3
		-- A quick second selection continues the existing fade instead of
		-- flashing back to an opaque page. The host owns this single veil.
		if not window._motions[veil] then veil.BackgroundTransparency = 0 end
		M.to(owner, veil, { BackgroundTransparency = 1 }, T.Motion.Enter)
	end
	return M
end
