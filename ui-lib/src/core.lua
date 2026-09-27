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
	local font, strong = Enum.Font.Gotham, Enum.Font.GothamMedium
	pcall(function() font, strong = Enum.Font.BuilderSans, Enum.Font.BuilderSansMedium end)
	M.Font = font
	function M.text(owner, parent, text, role, color, props)
		local config = {
			BackgroundTransparency = 1, Text = tostring(text or ""), RichText = false,
			Font = (role == "Title" or role == "Heading") and strong or font,
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
			node.FontFace = Font.new(base.Family, (role == "Title" or role == "Heading") and Enum.FontWeight.Medium or Enum.FontWeight.Regular)
		end)
		return node
	end
	function M.measure(text, size, width)
		width = math.max(1, width)
		local ok, bounds = pcall(function()
			return env.services.TextService:GetTextSize(tostring(text), size, font, Vector2.new(width, 100000))
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
	function M.feedback(owner, button, style, enabled)
		local window, hovered, selected, pressed = owner._window, false, false, false
		local motion = env.require("motion")
		local stroke = M.node(owner, "UIStroke", button, { Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
		local function paint(theme)
			local active = not enabled or enabled()
			stroke.Color = (hovered or selected) and active and theme.Accent or theme.Subtle
			stroke.Thickness = selected and 2 or 1
			if style == "Primary" then return active and theme.Primary or theme.Raised end
			if style == "Danger" then return active and theme.Danger or theme.Raised end
			return active and pressed and theme.Pressed or active and hovered and theme.Hover or theme.Raised
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
	function M.pointer(owner, target, began, moved, ended)
		-- One window-level router; an initiating touch owns the whole gesture.
		local window = owner._window
		owner._scope:Connect(target.InputBegan, function(input)
			local kind = input.UserInputType
			if window._gesture or not window.Alive then return end
			if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then return end
			if began(input) == false or not owner._scope.alive or not window.Alive then return end
			window._gesture = { input = input, owner = owner, move = moved, finish = ended }
		end)
		owner._scope:Add(function()
			if window._gesture and window._gesture.owner == owner then window._gesture = nil end
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
		}, { BackgroundColor3 = "Sidebar" })
		M.node(owner, "Frame", footer, { Size = UDim2.new(1, 0, 0, 1) }, { BackgroundColor3 = "Subtle" })
		M.text(owner, footer, env.metadata.footer, "Small", "Muted", {
			Name = "Attribution", Size = UDim2.new(1, parent == owner._window.Frame and -64 or 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center,
		})
		return footer
	end
	return M
end
