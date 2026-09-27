-- Lightweight spacers keep the transcript's geometry; only nearby content owns
-- text, syntax highlighting and input connections. No conversation data lives here.
return function(env)
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local clock = env.require("runtime/clock")
	local M = {}

	function M.estimate(text, width, extra)
		local role = theme.textRole("body")
		local columns = math.max(12, math.floor(math.max(1, width) / (role.size * 0.55)))
		local lines = 0
		for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
			lines = lines + math.max(1, math.ceil(#line / columns))
		end
		return math.max(role.height, lines * role.height + (extra or 0))
	end

	function M.new(scroll, options)
		options = options or {}
		local frame = scroll.instance
		local items, alive, enabled, queued = {}, true, true, false
		local previousWidth
		local connections = {}
		local manager = { mounted = 0, created = 0 }
		local queue
		local function connect(signal, fn)
			local connection = signal:Connect(fn)
			connections[#connections + 1] = connection
		end
		local function unmount(item)
			local handle = item.handle
			if not handle then return end
			item.handle = nil
			manager.mounted = math.max(0, manager.mounted - 1)
			if item.measure then item.measure:Disconnect(); item.measure = nil end
			handle.root:Destroy()
		end
		local function heightOf(node)
			local item = items[node]
			return item and item.height or math.max(node.AbsoluteSize.Y, node.Size.Y.Offset, 0)
		end
		local function pass()
			queued = false
			if not alive or not enabled or not frame.Parent then return end
			if options.defer and options.defer() then queue(0.05); return end
			local size = scroll.viewportSize()
			if size.X <= 0 or size.Y <= 0 then return end
			if previousWidth and math.abs(previousWidth - size.X) >= 1 then
				for _, item in pairs(items) do if not item.handle then item.resize() end end
			end
			previousWidth = size.X
			local y = frame.CanvasPosition.Y
			local margin = math.max(theme.space.huge, size.Y * 0.65)
			local low, high = y - margin, y + size.Y + margin
			-- Cache sibling offsets once per layout container. This also works before
			-- AbsolutePosition has settled after a hidden window becomes visible.
			local positions, tops = {}, { [frame] = 0 }
			local function top(node)
				if tops[node] ~= nil then return tops[node] end
				local parent = node.Parent
				if not parent or (parent ~= frame and not parent:IsDescendantOf(frame)) then return nil end
				if not node.Visible or (parent ~= frame and parent:IsA("GuiObject") and not parent.Visible) then return nil end
				local parentTop = top(parent)
				if parentTop == nil then return nil end
				local offsets = positions[parent]
				if not offsets then
					offsets = {}; positions[parent] = offsets
					local layout = parent:FindFirstChildOfClass("UIListLayout")
					if layout and layout.FillDirection == Enum.FillDirection.Vertical then
						local children = {}
						for index, child in ipairs(parent:GetChildren()) do
							if child:IsA("GuiObject") and child.Visible then children[#children + 1] = { node = child, index = index } end
						end
						table.sort(children, function(a, b)
							if a.node.LayoutOrder == b.node.LayoutOrder then return a.index < b.index end
							return a.node.LayoutOrder < b.node.LayoutOrder
						end)
						local padding = parent:FindFirstChildOfClass("UIPadding")
						local offset = padding and padding.PaddingTop.Offset or 0
						for _, child in ipairs(children) do
							offsets[child.node] = offset
							offset = offset + heightOf(child.node) + layout.Padding.Offset
						end
					end
				end
				local offset = offsets[node]
				if offset == nil then offset = node.Position.Y.Offset + node.Position.Y.Scale * parent.AbsoluteSize.Y - node.AnchorPoint.Y * heightOf(node) end
				tops[node] = parentTop + offset
				return tops[node]
			end
			local candidates = {}
			local focused = env.uis and env.uis:GetFocusedTextBox()
			local selected = env.guisvc and env.guisvc.SelectedObject
			for root, item in pairs(items) do
				local offset = top(root)
				local wanted = offset ~= nil and offset + item.height >= low and offset <= high
				local held = item.handle and ((focused and focused:IsDescendantOf(root)) or (selected and selected:IsDescendantOf(root)))
				if not wanted and not held then unmount(item)
				elseif not item.handle then
					candidates[#candidates + 1] = item
					item.distance = math.abs((offset or y) - y - size.Y / 2)
				end
			end
			table.sort(candidates, function(a, b) return a.distance < b.distance end)
			local started, count = clock.ms(), 0
			for _, item in ipairs(candidates) do
				if count >= 4 or (count > 0 and clock.since(started) >= 6) then queue(); break end
				if items[item.root] == item and item.root.Parent then
					local ok, handle = pcall(item.build, item.root)
					if not ok or not handle or not handle.root then
						for _, child in ipairs(item.root:GetChildren()) do child:Destroy() end
						handle = { root = P.text(item.root, { text = item.fallback or "This content could not be displayed. Refresh the conversation to retry.",
							role = "body", wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0) }) }
						env.require("runtime/log").warn("ui", "Transcript chunk could not be rendered")
					end
					if not alive or not item.root.Parent then handle.root:Destroy(); return end
					handle.root.Name = "Content"
					item.handle = handle
					manager.mounted, manager.created = manager.mounted + 1, manager.created + 1
					local function measure()
						if item.handle ~= handle or not enabled then return end
						local height = math.ceil(handle.root.AbsoluteSize.Y)
						if height > 0 and height ~= item.height then
							item.height = height; item.root.Size = UDim2.new(1, 0, 0, height)
							queue()
						end
					end
					item.measure = handle.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(measure)
					measure(); count = count + 1
				end
			end
		end
		queue = function(delay)
			if not alive or not enabled or queued then return end
			queued = true
			clock.delay(delay or 0.016, pass)
		end
		function manager.add(parent, spec)
			local width = math.max(1, parent.AbsoluteSize.X > 0 and parent.AbsoluteSize.X or frame.AbsoluteSize.X)
			local estimate = type(spec.estimate) == "function" and spec.estimate(width) or spec.estimate
			local item = { height = math.ceil(math.max(1, estimate or theme.text.body.height)), build = spec.build, fallback = spec.fallback }
			item.root = P.frame(parent, { name = spec.name or "TranscriptChunk", size = UDim2.new(1, 0, 0, item.height), layoutOrder = spec.order or 0 })
			items[item.root] = item
			item.root.Destroying:Connect(function() items[item.root] = nil; unmount(item) end)
			function item.resize()
				if not item.root.Parent or type(spec.estimate) ~= "function" then return end
				local available = parent.AbsoluteSize.X > 0 and parent.AbsoluteSize.X or scroll.viewportSize().X
				item.height = math.ceil(math.max(1, spec.estimate(math.max(1, available))))
				item.root.Size = UDim2.new(1, 0, 0, item.height)
			end
			function item.update(method, ...)
				if item.handle and item.handle[method] then item.handle[method](...)
				elseif method ~= "setModel" then item.resize() end
				queue()
			end
			queue()
			return item
		end
		function manager.wake() queue() end
		function manager.setVisible(value)
			enabled = value == true
			if enabled then queue() else for _, item in pairs(items) do unmount(item) end end
		end
		function manager.destroy()
			if not alive then return end
			alive = false
			for _, connection in ipairs(connections) do connection:Disconnect() end
			for _, item in pairs(items) do unmount(item) end
			items = {}
		end
		connect(frame:GetPropertyChangedSignal("CanvasPosition"), queue)
		connect(frame:GetPropertyChangedSignal("AbsoluteSize"), queue)
		connect(scroll.layout:GetPropertyChangedSignal("AbsoluteContentSize"), queue)
		connect(frame.Destroying, manager.destroy)
		return manager
	end
	return M
end
