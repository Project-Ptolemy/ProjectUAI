-- The established client's startup surface, before theme/config and controls.
-- The small progress model and frame-drawn brand are its only dependencies.
return function(env)
	local progress = env.require("runtime/boot_progress")
	local M = {}
	local COLOR = {
		surface = Color3.fromRGB(35, 35, 33), raised = Color3.fromRGB(45, 45, 42),
		track = Color3.fromRGB(62, 62, 57), border = Color3.fromRGB(75, 74, 69),
		text = Color3.fromRGB(245, 244, 238), dim = Color3.fromRGB(179, 177, 167),
		accent = Color3.fromRGB(220, 126, 91), good = Color3.fromRGB(164, 190, 150),
		danger = Color3.fromRGB(240, 132, 124),
	}
	local connections, pulse, exitTween, exitTask, dropTask = {}, nil, nil, nil, nil
	local stages, state, ticks, layout, paint

	function M.container()
		if type(gethui) == "function" then
			local ok, container = pcall(gethui)
			if ok and typeof(container) == "Instance" then return container end
		end
		local ok, core = pcall(function() return game:GetService("CoreGui") end)
		if ok and core then return core end
		return env.plr and env.plr:FindFirstChild("PlayerGui") or nil
	end
	local function corner(instance, radius)
		local item = Instance.new("UICorner", instance)
		item.CornerRadius = UDim.new(0, radius)
	end
	local function frame(parent, name, color)
		local item = Instance.new("Frame", parent)
		item.Name, item.BorderSizePixel = name, 0
		item.BackgroundTransparency = color and 0 or 1
		if color then item.BackgroundColor3 = color end
		item.Active, item.Selectable = false, false
		return item
	end
	local function text(parent, name, size, color, font)
		local item = Instance.new("TextLabel", parent)
		item.Name, item.Text = name, ""
		item.BackgroundTransparency, item.BorderSizePixel = 1, 0
		item.TextColor3, item.TextSize = color or COLOR.text, size
		item.Font = font or Enum.Font.Gotham
		item.TextXAlignment, item.TextYAlignment = Enum.TextXAlignment.Left, Enum.TextYAlignment.Center
		return item
	end
	local function stopActive()
		if ticks then ticks:Disconnect(); ticks = nil end
		if pulse then pcall(function() pulse:Cancel() end); pulse = nil end
		if M.pulse then M.pulse.BackgroundTransparency = 0 end
	end
	local function release()
		stopActive()
		for _, connection in ipairs(connections) do connection:Disconnect() end
		connections = {}
		if exitTween then pcall(function() exitTween:Cancel() end); exitTween = nil end
		if exitTask then pcall(task.cancel, exitTask); exitTask = nil end
		if dropTask then pcall(task.cancel, dropTask); dropTask = nil end
	end
	function M.destroy()
		local screen = M.screen
		M.screen = nil
		release()
		if screen then pcall(function() screen:Destroy() end) end
		M.card, M.status, M.count, M.title, M.note, M.elapsed, M.pulse = nil, nil, nil, nil, nil, nil, nil
		M.close, stages, state, layout, paint = nil, nil, nil, nil, nil
	end

	function M.show()
		if M.screen and M.screen.Parent then return M end
		M.destroy()
		local container = M.container()
		if not container then return M end
		state = progress.new(os.clock())
		local screen = Instance.new("ScreenGui")
		screen.Name, screen.ResetOnSpawn = "UAI_Boot", false
		screen.DisplayOrder = 2147481000
		screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		pcall(function() screen.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
		screen.Parent = container
		M.screen = screen
		local bounds = frame(screen, "BootBounds")
		bounds.Size = UDim2.fromScale(1, 1)
		local card = Instance.new("CanvasGroup", bounds)
		card.Name, card.BorderSizePixel = "BootCard", 0
		card.BackgroundColor3 = COLOR.surface
		card.AnchorPoint, card.GroupTransparency = Vector2.new(0.5, 1), 0
		card.ClipsDescendants = true
		corner(card, 16)
		local outline = Instance.new("UIStroke", card)
		outline.Color, outline.Thickness = COLOR.border, 1
		M.card = card
		local accent = frame(card, "BootAccent", COLOR.accent)
		accent.Size = UDim2.new(1, 0, 0, 2)
		local mark = frame(card, "BootBrand")
		mark.Size, mark.Position = UDim2.fromOffset(32, 32), UDim2.fromOffset(18, 19)
		pcall(function() env.require("ui/brand").draw(mark, 32) end)
		local name = text(card, "BootName", 15, COLOR.text, Enum.Font.GothamBold)
		name.Text, name.Position = "Project UAI", UDim2.fromOffset(60, 18)
		name.Size = UDim2.new(1, -78, 0, 20)
		local version = text(card, "BootVersion", 11, COLOR.dim)
		version.Text = "Version " .. tostring(env.info and env.info.version or "")
		version.Position, version.Size = UDim2.fromOffset(60, 39), UDim2.new(1, -78, 0, 14)
		M.title = text(card, "BootTitle", 18, COLOR.text, Enum.Font.GothamMedium)
		M.title.Position, M.title.Size = UDim2.fromOffset(18, 69), UDim2.new(1, -36, 0, 25)
		M.title.TextWrapped = true
		M.status = text(card, "BootStatus", 12, COLOR.dim)
		M.status.Position, M.status.Size = UDim2.fromOffset(18, 99), UDim2.new(1, -36, 0, 40)
		M.status.TextWrapped, M.status.TextYAlignment = true, Enum.TextYAlignment.Top
		stages = {}
		for index = 1, 3 do
			local slot = frame(card, "BootStage" .. index)
			slot.Position, slot.Size = UDim2.new((index - 1) / 3, 18 - (index - 1) * 12, 0, 145), UDim2.new(1 / 3, -16, 0, 26)
			local bar = frame(slot, "StageTrack", COLOR.track)
			bar.Size = UDim2.new(1, 0, 0, 3); corner(bar, 2)
			local label = text(slot, "StageLabel", 11, COLOR.dim)
			label.Position, label.Size = UDim2.fromOffset(0, 9), UDim2.new(1, 0, 0, 15)
			stages[index] = { slot = slot, bar = bar, label = label }
		end
		local facts = frame(card, "BootFacts", COLOR.raised)
		facts.Position, facts.Size = UDim2.fromOffset(12, 183), UDim2.new(1, -24, 0, 32); corner(facts, 7)
		M.pulse = frame(facts, "BootActivity", COLOR.accent)
		M.pulse.Position, M.pulse.Size = UDim2.fromOffset(10, 13), UDim2.fromOffset(6, 6); corner(M.pulse, 3)
		M.count = text(facts, "BootCount", 11, COLOR.dim)
		M.count.Position, M.count.Size = UDim2.fromOffset(23, 0), UDim2.new(1, -88, 1, 0)
		M.elapsed = text(facts, "BootElapsed", 11, COLOR.dim)
		M.elapsed.Position, M.elapsed.Size = UDim2.new(1, -60, 0, 0), UDim2.new(0, 50, 1, 0)
		M.elapsed.TextXAlignment = Enum.TextXAlignment.Right
		M.note = text(card, "BootNote", 11, COLOR.dim)
		M.note.Position, M.note.Size = UDim2.fromOffset(18, 226), UDim2.new(1, -36, 0, 31)
		M.note.TextWrapped, M.note.TextYAlignment = true, Enum.TextYAlignment.Top
		local close = Instance.new("TextButton", card)
		close.Name, close.Text = "DismissBootError", "Close notice"
		close.Size, close.Position = UDim2.new(1, -36, 0, 36), UDim2.fromOffset(18, 268)
		close.BackgroundColor3, close.TextColor3 = COLOR.raised, COLOR.text
		close.Font, close.TextSize, close.BorderSizePixel = Enum.Font.GothamMedium, 12, 0
		close.Visible, close.Selectable = false, true
		corner(close, 7)
		close.Activated:Connect(M.destroy)
		M.close = close
		layout = function()
			if M.screen ~= screen then return end
			local width, height = bounds.AbsoluteSize.X, bounds.AbsoluteSize.Y
			if width <= 0 or height <= 0 then
				local camera = env.services.Workspace and env.services.Workspace.CurrentCamera
				local viewport = camera and camera.ViewportSize
				width, height = viewport and viewport.X or 800, viewport and viewport.Y or 600
			end
			local cardHeight = state.status == "failed" and 318 or 268
			local short = height < cardHeight + 24
			M.note.Visible = not short
			if short then cardHeight = state.status == "failed" and 224 or 184 end
			name.Position, version.Position = UDim2.fromOffset(60, short and 10 or 18), UDim2.fromOffset(60, short and 31 or 39)
			mark.Position = UDim2.fromOffset(18, short and 11 or 19)
			M.title.Position, M.status.Position = UDim2.fromOffset(18, short and 55 or 69), UDim2.fromOffset(18, short and 83 or 99)
			M.status.Size = UDim2.new(1, -36, 0, short and 30 or 40)
			M.status.TextSize = short and 11 or 12
			local cardWidth = math.max(1, math.min(368, width - 24))
			local segmentWidth = math.max(1, math.floor((cardWidth - 52) / 3))
			for index, stage in ipairs(stages) do
				stage.slot.Position = UDim2.fromOffset(18 + (index - 1) * (segmentWidth + 8), short and 117 or 145)
				stage.slot.Size = UDim2.fromOffset(index == 3 and math.max(1, cardWidth - 52 - segmentWidth * 2) or segmentWidth, 26)
			end
			facts.Position = UDim2.fromOffset(12, short and 149 or 183)
			close.Position = UDim2.fromOffset(18, short and 184 or 268)
			card.Size = UDim2.fromOffset(cardWidth, cardHeight)
			card.Position = UDim2.new(0.5, 0, 1, -math.min(24, math.max(8, height * 0.03)))
			M.title.TextSize, M.count.TextSize = width < 340 and 16 or 18, width < 340 and 10 or 11
		end
		paint = function()
			if M.screen ~= screen then return end
			local snapshot = state.snapshot(os.clock())
			M.title.Text, M.status.Text, M.note.Text = snapshot.title, snapshot.detail, snapshot.note
			M.title.TextColor3 = snapshot.status == "failed" and COLOR.danger or COLOR.text
			M.count.Text, M.elapsed.Text = string.format("%d components loaded", snapshot.count), string.format("%.1f s", snapshot.elapsed)
			M.note.TextColor3 = snapshot.slow and COLOR.accent or COLOR.dim
			M.pulse.BackgroundColor3 = snapshot.status == "ready" and COLOR.good or snapshot.status == "failed" and COLOR.danger or COLOR.accent
			for index, stage in ipairs(snapshot.stages) do
				stages[index].bar.BackgroundColor3 = stage.status == "done" and COLOR.good or stage.status == "failed" and COLOR.danger
					or stage.status == "loading" and COLOR.accent or COLOR.track
				stages[index].bar:SetAttribute("StageStatus", stage.status)
				stages[index].label.Text, stages[index].label.TextColor3 = stage.label, stage.status == "pending" and COLOR.dim or COLOR.text
			end
			close.Visible = snapshot.status == "failed"
		end
		connections[#connections + 1] = bounds:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
		connections[#connections + 1] = screen.Destroying:Connect(function()
			if M.screen == screen then M.screen = nil; release() end
		end)
		local ok, animation = pcall(function()
			return env.tween:Create(M.pulse, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ BackgroundTransparency = 0.65 })
		end)
		if ok and animation then pulse = animation; pulse:Play() end
		local elapsed = 0
		ticks = env.run.Heartbeat:Connect(function(delta)
			elapsed = elapsed + delta
			if elapsed >= 0.2 then elapsed = 0; paint() end
		end)
		state.module(env.moduleCount, env.moduleTotal, os.clock())
		layout(); paint()
		return M
	end

	function M.step(id, count, total)
		if not M.screen or not state then return end
		state.module(count, total, os.clock()); paint()
	end
	function M.stage(id, detail)
		if not M.screen or not state then return false end
		local changed = state.stage(id, detail, os.clock()); paint(); return changed
	end
	function M.phase(detail)
		if not M.screen or not state then return end
		state.phase(detail, os.clock()); paint()
	end
	function M.done(detail)
		if not M.screen or not state then return end
		state.module(env.moduleCount, env.moduleTotal, os.clock())
		if not state.finish(detail, os.clock()) then return end
		stopActive(); paint(); layout()
		local screen, card = M.screen, M.card
		exitTask = task.delay(0.65, function()
			exitTask = nil
			if M.screen ~= screen then return end
			local ok, animation = pcall(function()
				return env.tween:Create(card, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 1 })
			end)
			if ok and animation then exitTween = animation; animation:Play() end
			dropTask = task.delay(0.22, function() dropTask = nil; if M.screen == screen then M.destroy() end end)
		end)
	end
	function M.fail(why)
		if not M.screen or not state or not state.fail(os.clock()) then return end
		-- The bootstrap retains complete exceptions in the executor console. Raw
		-- exceptions can contain paths or credential-bearing host data.
		stopActive(); paint(); layout()
	end
	return M
end
