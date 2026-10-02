return function(env)
	local tokens = env.require("theme")
	local M = { services = env.services, tokens = tokens }
	local unpackValues = table.unpack or unpack
	local Scope = {}
	Scope.__index = Scope

	local function dispose(resource)
		local kind = typeof(resource)
		if type(resource) == "function" then resource()
		elseif kind == "RBXScriptConnection" or (type(resource) == "table" and resource.Disconnect) then resource:Disconnect()
		elseif kind == "Instance" or (type(resource) == "table" and resource.Destroy) then resource:Destroy()
		elseif type(resource) == "thread" and task.cancel then pcall(task.cancel, resource)
		end
	end
	function M.scope(parent)
		local scope = setmetatable({ alive = true, items = {} }, Scope)
		if parent then scope.release = parent:Add(function() scope:Destroy() end) end
		return scope
	end
	function Scope:Add(resource)
		assert(resource ~= nil, "Give expects a cleanup function, connection, instance, or task")
		if not self.alive then pcall(dispose, resource); return function() end end
		local key = {}
		self.items[key] = resource
		return function(clean)
			local value = self.items[key]
			self.items[key] = nil
			if value ~= nil and clean ~= false then pcall(dispose, value) end
		end
	end
	function Scope:Connect(signal, callback)
		local connection = signal:Connect(function(...)
			if self.alive then callback(...) end
		end)
		self:Add(connection)
		return connection
	end
	function Scope:Delay(seconds, callback)
		local release, finished
		local thread = task.delay(seconds, function()
			finished = true
			if release then release(false) end
			if self.alive then callback() end
		end)
		if not finished then release = self:Add(thread) end
		return function() if release then release(); release = nil end end
	end
	function Scope:Spawn(callback)
		local release, finished
		local thread = task.spawn(function()
			if self.alive then callback() end
			finished = true
			if release then release(false) end
		end)
		if not finished then release = self:Add(thread) end
		return thread
	end
	function Scope:Destroy()
		if not self.alive then return end
		self.alive = false
		local items = self.items
		self.items = {}
		for _, resource in pairs(items) do
			local ok, why = pcall(dispose, resource)
			if not ok then warn("UI LIB cleanup: " .. tostring(why)) end
		end
		if self.release then self.release(false); self.release = nil end
	end

	function M.clamp(value, low, high) return math.max(low, math.min(high, value)) end
	function M.finite(value) return type(value) == "number" and value == value and value > -math.huge and value < math.huge end
	function M.number(value, fallback, low, high)
		if not M.finite(value) then value = fallback end
		return M.clamp(value, low, high)
	end
	function M.truncate(value, limit)
		if #value <= limit then return value end
		local cut = limit + 1
		while cut > 1 do
			local byte = value:byte(cut)
			if not byte or byte < 128 or byte >= 192 then break end
			cut = cut - 1
		end
		return value:sub(1, cut - 1)
	end
	function M.copy(value)
		if typeof(value) ~= "table" then return value end
		local result = {}
		for key, item in pairs(value) do result[key] = M.copy(item) end
		return result
	end
	function M.equal(a, b)
		if a == b then return true end
		if typeof(a) ~= "table" or typeof(b) ~= "table" then return false end
		for key, value in pairs(a) do if not M.equal(value, b[key]) then return false end end
		for key in pairs(b) do if a[key] == nil then return false end end
		return true
	end
	function M.call(window, callback, ...)
		if type(callback) ~= "function" then return true end
		local result = { pcall(callback, ...) }
		if not result[1] then
			warn("Project UAI UI LIB: " .. tostring(result[2]))
			if window and window.Alive and window.Notify then
				window:Notify({ Title = "Action failed", Content = tostring(result[2]), Kind = "Danger" })
			end
		end
		return unpackValues(result)
	end
	function M.owner(window, parentScope)
		return { _window = window, _scope = M.scope(parentScope or window._scope) }
	end
	function M.bind(owner, instance, properties)
		local window = owner._window
		local binding = window._paintNodes[instance]
		if not binding then
			binding = { node = instance, owner = owner, properties = {} }
			window._paint[binding], window._paintNodes[instance] = true, binding
			owner._scope:Add(function()
				window._paint[binding] = nil
				if window._paintNodes[instance] == binding then window._paintNodes[instance] = nil end
			end)
		end
		for key, value in pairs(properties) do
			binding.properties[key] = value
			if type(value) == "function" then instance[key] = value(window.Theme)
			else instance[key] = window.Theme[value] end
		end
		return instance
	end
	function M.node(owner, class, parent, props, colors)
		local instance = Instance.new(class)
		if instance:IsA("GuiObject") then instance.BorderSizePixel = 0 end
		if class == "TextButton" or class == "ImageButton" then
			instance.AutoButtonColor = false
			instance.Selectable = true
			if class == "TextButton" then instance.Text = "" end
		end
		for key, value in pairs(props or {}) do instance[key] = value end
		if colors then M.bind(owner, instance, colors) end
		instance.Parent = parent
		return instance
	end
	function M.corner(parent, radius)
		local node = Instance.new("UICorner")
		node.CornerRadius = UDim.new(0, radius or tokens.Size.FieldRadius)
		node.Parent = parent
		return node
	end
	function M.stroke(owner, parent, color)
		local node = M.node(owner, "UIStroke", parent, { Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, { Color = color or "Border" })
		return node
	end
	function M.fieldBorder(owner, field, invalid)
		local editing = false
		local border = M.stroke(owner, field, "Edge")
		local function color(theme)
			if invalid and invalid() then return theme.Danger end
			return editing and theme.Accent or theme.Edge
		end
		M.bind(owner, border, { Color = color })
		local function refresh()
			if not owner._scope.alive then return end
			border.Thickness = editing and 2 or 1
			env.require("motion").to(owner, border, { Color = color(owner._window.Theme) })
		end
		owner._scope:Connect(field.Focused, function() editing = true; refresh() end)
		owner._scope:Connect(field.FocusLost, function() editing = false; refresh() end)
		return border, refresh
	end
	function M.pad(parent, x, y)
		local node = Instance.new("UIPadding")
		node.PaddingLeft, node.PaddingRight = UDim.new(0, x), UDim.new(0, x)
		node.PaddingTop, node.PaddingBottom = UDim.new(0, y or x), UDim.new(0, y or x)
		node.Parent = parent
		return node
	end
	function M.list(parent, horizontal, gap)
		local node = Instance.new("UIListLayout")
		node.SortOrder = Enum.SortOrder.LayoutOrder
		node.FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
		node.Padding = UDim.new(0, gap or 0)
		node.Parent = parent
		return node
	end
	local font, strong, display = Enum.Font.Gotham, Enum.Font.GothamMedium, Enum.Font.GothamBold
	pcall(function() font, strong, display = Enum.Font.BuilderSans, Enum.Font.BuilderSansMedium, Enum.Font.BuilderSansBold end)
	M.Font = font
	function M.text(owner, parent, text, role, color, props)
		local config = {
			BackgroundTransparency = 1, Text = tostring(text or ""), RichText = false,
			Font = role == "Display" and display or (role == "Title" or role == "Heading" or role == "Eyebrow") and strong or font,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
			TextWrapped = true, TextSize = tokens.Type[role or "Body"] or tokens.Type.Body,
			Size = UDim2.new(1, 0, 0, 20),
		}
		for key, value in pairs(props or {}) do config[key] = value end
		local node = M.node(owner, "TextLabel", parent, config, {
			TextColor3 = color or "Text",
			TextSize = function() return math.floor((tokens.Type[role or "Body"] or tokens.Type.Body) * owner._window.TextScale + 0.5) end,
		})
		pcall(function()
			local base = Font.fromEnum(config.Font)
			node.FontFace = Font.new(base.Family, role == "Display" and Enum.FontWeight.Bold or (role == "Title" or role == "Heading" or role == "Eyebrow") and Enum.FontWeight.Medium or Enum.FontWeight.Regular)
		end)
		return node
	end
	function M.measure(text, size, width, textFont)
		width = math.max(1, width)
		local ok, bounds = pcall(function()
			return env.services.TextService:GetTextSize(tostring(text), size, textFont or font, Vector2.new(width, 100000))
		end)
		return ok and math.ceil(bounds.Y) or math.ceil(math.max(1, #tostring(text) * size * 0.55 / width)) * math.ceil(size * 1.3)
	end
	function M.reflow(owner, callback)
		local window = owner._window
		window._reflow[callback] = true
		owner._scope:Add(function() window._reflow[callback] = nil end)
		callback()
	end
	function M.scroll(owner, parent, name)
		return M.node(owner, "ScrollingFrame", parent, {
			Name = name, BackgroundTransparency = 1, BorderSizePixel = 0,
			CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = tokens.Size.Scrollbar, ScrollingDirection = Enum.ScrollingDirection.Y,
			ClipsDescendants = true, Size = UDim2.fromScale(1, 1),
		}, { ScrollBarImageColor3 = "Muted" })
	end
	local ICONS = {
		close = { { 4, 4, 16, 16 }, { 16, 4, 4, 16 } },
		minus = { { 4, 10, 16, 10 } },
		chevron = { { 5, 8, 10, 13 }, { 10, 13, 15, 8 } },
		check = { { 4, 10, 8, 14 }, { 8, 14, 16, 5 } },
		arrow = { { 4, 10, 16, 10 }, { 11, 5, 16, 10 }, { 16, 10, 11, 15 } },
		sliders = { { 3, 5, 17, 5 }, { 3, 10, 17, 10 }, { 3, 15, 17, 15 }, { 7, 3, 7, 7 }, { 13, 8, 13, 12 }, { 8, 13, 8, 17 } },
		grid = { { 4, 4, 8, 4 }, { 12, 4, 16, 4 }, { 4, 10, 8, 10 }, { 12, 10, 16, 10 }, { 4, 16, 8, 16 }, { 12, 16, 16, 16 } },
		code = { { 6, 5, 2, 10 }, { 2, 10, 6, 15 }, { 14, 5, 18, 10 }, { 18, 10, 14, 15 }, { 12, 3, 8, 17 } },
	}
	function M.icon(owner, parent, name, color, size)
		size = size or 18
		local frame = M.node(owner, "Frame", parent, { Name = name, BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size) })
		for _, points in ipairs(ICONS[name] or ICONS.grid) do
			local dx, dy = points[3] - points[1], points[4] - points[2]
			local line = M.node(owner, "Frame", frame, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale((points[1] + points[3]) / 40, (points[2] + points[4]) / 40),
				Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) * size / 20, 1.5),
				Rotation = math.deg(math.atan2(dy, dx)),
			}, { BackgroundColor3 = color or "Secondary" })
			M.corner(line, 1)
		end
		return frame
	end
	-- The Project UAI mark. Same eleven uneven rays, open gaps and softly cut
	-- ends as the application brand, drawn from frames so the library still
	-- needs no uploaded image and no logo download. Color binds like any other
	-- node, so a theme or accent change repaints it with everything else.
	local RAYS = {
		{ -8, 0.440, 0.086 }, { 24, 0.365, 0.105 }, { 58, 0.425, 0.080 },
		{ 91, 0.390, 0.096 }, { 126, 0.445, 0.078 }, { 158, 0.380, 0.106 },
		{ 192, 0.435, 0.088 }, { 225, 0.370, 0.105 }, { 257, 0.445, 0.079 },
		{ 291, 0.390, 0.096 }, { 325, 0.430, 0.082 },
	}
	function M.mark(owner, parent, size, color)
		local frame = M.node(owner, "Frame", parent, { Name = "Brand", BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size) })
		for index, ray in ipairs(RAYS) do
			local radians = math.rad(ray[1])
			local overlap = 0.055
			local centre = (ray[2] - overlap) * 0.5
			local piece = M.node(owner, "Frame", frame, {
				Name = "Ray" .. index,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.49 + math.cos(radians) * centre, 0.51 + math.sin(radians) * centre),
				Size = UDim2.fromScale(ray[2] + overlap, ray[3]),
				Rotation = ray[1],
			}, { BackgroundColor3 = color or "Accent" })
			M.corner(piece, math.max(1, math.floor(size * 0.05)))
		end
		return frame
	end
	function M.feedback(owner, button, style, enabled)
		local window, hovered, selected, pressed = owner._window, false, false, false
		local motion = env.require("motion")
		local stroke = M.node(owner, "UIStroke", button, { Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
		local function paint(theme)
			local active = not enabled or enabled()
			stroke.Color = (hovered or selected) and active and theme.Accent or theme.Edge
			stroke.Thickness = selected and 2 or 1
			stroke.Transparency = (style == "Primary" or style == "Danger") and not selected and not hovered and 1 or 0
			if style == "Primary" or style == "Danger" then
				if not active then return theme.Raised end
				local base = style == "Primary" and theme.Primary or theme.Danger
				if pressed then return base:Lerp(theme.OnPrimary, 0.16) end
				if hovered then return base:Lerp(style == "Primary" and theme.Accent or theme.Text, 0.1) end
				return base
			end
			return active and pressed and theme.Pressed or active and hovered and theme.Hover or style == "Field" and theme.Input or theme.Raised
		end
		M.bind(owner, button, { BackgroundColor3 = paint })
		local function refresh()
			if owner._scope.alive then motion.to(owner, button, { BackgroundColor3 = paint(window.Theme) }) end
		end
		local function release() if pressed then pressed = false; refresh() end end
		window._presses[release] = true
		owner._scope:Add(function() window._presses[release] = nil end)
		owner._scope:Connect(button.MouseEnter, function() hovered = true; refresh() end)
		owner._scope:Connect(button.MouseLeave, function() hovered, pressed = false, false; refresh() end)
		owner._scope:Connect(button.SelectionGained, function() selected = true; refresh() end)
		owner._scope:Connect(button.SelectionLost, function() selected, pressed = false, false; refresh() end)
		owner._scope:Connect(button.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
				or input.KeyCode == Enum.KeyCode.ButtonA or input.KeyCode == Enum.KeyCode.Return then pressed = true; refresh() end
		end)
		return refresh
	end
	-- Choice rows share a stateful focus/hover treatment without changing values.
	function M.selection(owner, button, chosen, enabled)
		local hovered, focused = false, false
		local edge = M.stroke(owner, button, "Accent")
		local function background(theme)
			if chosen() then return theme.Selected end
			return hovered and (not enabled or enabled()) and theme.Hover or theme.Input
		end
		local function opacity()
			return focused and 0 or chosen() and 0.6 or 1
		end
		M.bind(owner, button, { BackgroundColor3 = background })
		M.bind(owner, edge, { Transparency = opacity })
		local function refresh()
			local motion = env.require("motion")
			motion.to(owner, button, { BackgroundColor3 = background(owner._window.Theme) })
			motion.to(owner, edge, { Transparency = opacity() })
		end
		owner._scope:Connect(button.MouseEnter, function() hovered = true; refresh() end)
		owner._scope:Connect(button.MouseLeave, function() hovered = false; refresh() end)
		owner._scope:Connect(button.SelectionGained, function() focused = true; refresh() end)
		owner._scope:Connect(button.SelectionLost, function() focused = false; refresh() end)
		return refresh
	end
	function M.releaseFocus(window, root)
		local focused = env.services.UserInputService:GetFocusedTextBox()
		if focused and focused:IsDescendantOf(root or window.ScreenGui) then
			pcall(function() focused:ReleaseFocus() end)
		end
	end
	function M.cancelGesture(window, owner)
		local gesture = window._gesture
		if not gesture or (owner and gesture.owner ~= owner) then return end
		window._gesture = nil
		if gesture.release then gesture.release() end
	end
	function M.pointer(owner, target, began, moved, ended, options)
		-- One window-level router; an initiating touch owns the whole gesture.
		local window = owner._window
		owner._scope:Connect(target.InputBegan, function(input)
			local kind = input.UserInputType
			if window._gesture or not window.Alive then return end
			if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then return end
			if options and options.CanStart and not options.CanStart() then return end
			local touch = kind == Enum.UserInputType.Touch
			local pending = touch and options and options.TouchAxis == "X"
			local origin, scrolls = input.Position, {}
			local gesture = { input = input, owner = owner }
			function gesture.release()
				for scroll, enabled in pairs(scrolls) do
					if scroll.Parent then scroll.ScrollingEnabled = enabled end
				end
				scrolls = {}
			end
			local function start(current)
				if began(current) == false or not owner._scope.alive or not window.Alive or window._gesture ~= gesture then
					if window._gesture == gesture then M.cancelGesture(window) end
					return false
				end
				pending = false
				if touch and options and (options.TouchAxis or options.LockScroll) then
					local ancestor = target.Parent
					while ancestor and ancestor ~= window.ScreenGui do
						if ancestor:IsA("ScrollingFrame") then
							scrolls[ancestor] = ancestor.ScrollingEnabled
							ancestor.ScrollingEnabled = false
						end
						ancestor = ancestor.Parent
					end
				end
				return true
			end
			function gesture.move(current)
				if pending then
					local delta = current.Position - origin
					if math.max(math.abs(delta.X), math.abs(delta.Y)) < tokens.Size.TouchSlop then return end
					-- A vertical swipe belongs to the native scroll container. Only
					-- a tap or a horizontal drag may change a horizontal value.
					if math.abs(delta.Y) >= math.abs(delta.X) then M.cancelGesture(window); return end
					if not start(current) then return end
				end
				if moved then moved(current) end
			end
			function gesture.finish(current)
				if pending then gesture.move(current) end
				if window._gesture ~= gesture then return end
				if pending and not start(current) then return end
				if ended then ended(current) end
			end
			window._gesture = gesture
			if not pending then start(input) end
		end)
		owner._scope:Add(function()
			M.cancelGesture(window, owner)
		end)
	end
	function M.isInside(node, x, y)
		local origin, size = node.AbsolutePosition, node.AbsoluteSize
		return x >= origin.X and y >= origin.Y and x <= origin.X + size.X and y <= origin.Y + size.Y
	end
	function M.footer(owner, parent)
		local footer = M.node(owner, "Frame", parent, {
			Name = "ProjectUAI_Footer", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, tokens.Size.Footer),
		}, { BackgroundColor3 = "Chrome" })
		M.text(owner, footer, env.metadata.footer, "Small", "Muted", {
			Name = "Attribution", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
		})
		return footer
	end
	return M
end
