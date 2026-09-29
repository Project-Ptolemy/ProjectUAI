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
		local previousWidth, previousY
		local connections = {}
		local manager = { mounted = 0, created = 0, warm = 0 }
		local positions, tops
		local queue
		local function invalidate()
			positions, tops = nil, nil
		end
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
			item.remeasure = nil
			handle.root:Destroy()
			invalidate()
		end
		local function heightOf(node)
			local item = items[node]
			return item and item.height or math.max(node.AbsoluteSize.Y, node.Size.Y.Offset, 0)
		end
		-- Scrolling changes only the viewing range. Retain sibling order/offsets
		-- until content or geometry changes, rather than sorting the whole history
		-- on every wheel/touch tick. These offsets also work before native layout
		-- publishes AbsolutePosition after a hidden window returns.
		local function top(node)
			if not tops then positions, tops = {}, { [frame] = 0 } end
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
			local direction = previousY and y - previousY or 0
			previousY = y
			local margin = math.max(theme.space.huge, size.Y * 0.65)
			local ahead = math.max(margin, math.min(size.Y, math.abs(direction) * 2))
			local low, high = y - (direction < 0 and ahead or margin), y + size.Y + (direction > 0 and ahead or margin)
			local warmLow, warmHigh = y - size.Y * 3, y + size.Y * 4
			local candidates, warm, releases = {}, {}, {}
			local focused = env.uis and env.uis:GetFocusedTextBox()
			local selected = env.guisvc and env.guisvc.SelectedObject
			for root, item in pairs(items) do
				local offset = top(root)
				local wanted = offset ~= nil and offset + item.height >= low and offset <= high
				local held = item.handle and ((focused and focused:IsDescendantOf(root)) or (selected and selected:IsDescendantOf(root)))
				if wanted then
					item.distance = math.max(offset - (y + size.Y), y - offset - item.height, 0)
					item.visible = offset < y + size.Y and offset + item.height > y
					if not item.handle then candidates[#candidates + 1] = item end
				elseif item.handle and not held then
					if offset and offset + item.height >= warmLow and offset <= warmHigh then
						item.distance = math.max(offset - (y + size.Y), y - offset - item.height, 0)
						warm[#warm + 1] = item
					else releases[#releases + 1] = item end
				end
			end
			-- Keep a bounded band of previously drawn content ready for reversals.
			-- A small backtrack must not rebuild every paragraph and its connections.
			table.sort(warm, function(a, b) return a.distance < b.distance end)
			manager.warm = math.min(24, #warm)
			for index = 25, #warm do releases[#releases + 1] = warm[index] end
			for _, item in ipairs(releases) do unmount(item) end
			table.sort(candidates, function(a, b)
				if a.visible ~= b.visible then return a.visible end
				if a.distance == b.distance then return a.root.LayoutOrder < b.root.LayoutOrder end
				return a.distance < b.distance
			end)
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
							local previous = item.height
							if options.beforeMeasure then options.beforeMeasure(item.root, previous, height) end
							item.height = height; item.root.Size = UDim2.new(1, 0, 0, height)
							invalidate()
							if options.afterMeasure then options.afterMeasure(item.root, previous, height) end
							queue()
						end
					end
					item.measure = handle.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(measure)
					item.remeasure = measure
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
			invalidate()
			item.root.Destroying:Connect(function() items[item.root] = nil; unmount(item); invalidate() end)
			function item.resize()
				if not item.root.Parent or type(spec.estimate) ~= "function" then return end
				local available = parent.AbsoluteSize.X > 0 and parent.AbsoluteSize.X or scroll.viewportSize().X
				item.height = math.ceil(math.max(1, spec.estimate(math.max(1, available))))
				item.root.Size = UDim2.new(1, 0, 0, item.height)
				invalidate()
			end
			function item.update(method, ...)
				if item.handle and item.handle[method] then item.handle[method](...)
				elseif method ~= "setModel" then item.resize() end
				invalidate()
				queue()
			end
			queue()
			return item
		end
		-- The view keeps this finer anchor only while its spacers exist. Its saved
		-- transcript-id anchor still covers refresh, session switches and pruning.
		function manager.anchor()
			if not alive or not enabled then return nil end
			local y, height = frame.CanvasPosition.Y, scroll.viewportSize().Y
			local best, distance
			for root, item in pairs(items) do
				local offset = top(root)
				if offset and offset < y + height and offset + item.height > y then
					local gap = math.max(0, offset - y)
					if not best or gap < distance or (gap == distance and root:IsDescendantOf(best.root)) then
						best, distance = { root = root, offset = offset - y }, gap
					end
				end
			end
			return best
		end
		function manager.restoreAnchor(anchor)
			if not alive or not anchor or not items[anchor.root] then return nil end
			local offset = top(anchor.root)
			return offset and math.max(0, offset - anchor.offset) or nil
		end
		function manager.wake() invalidate(); queue() end
		function manager.setVisible(value)
			enabled = value == true
			invalidate(); previousY = nil
			-- Minimize and Settings suspend drawing without throwing away the
			-- bounded set the reader just paid to render. Remeasure it on return in
			-- case hidden window geometry changed; destruction still releases it.
			if enabled then
				for _, item in pairs(items) do if item.remeasure then item.remeasure() end end
				queue()
			end
		end
		function manager.destroy()
			if not alive then return end
			alive = false
			for _, connection in ipairs(connections) do connection:Disconnect() end
			for _, item in pairs(items) do unmount(item) end
			items = {}; manager.warm = 0; invalidate()
		end
		connect(frame:GetPropertyChangedSignal("CanvasPosition"), queue)
		connect(frame:GetPropertyChangedSignal("AbsoluteSize"), manager.wake)
		connect(frame:GetPropertyChangedSignal("AbsoluteWindowSize"), manager.wake)
		connect(scroll.layout:GetPropertyChangedSignal("AbsoluteContentSize"), manager.wake)
		connect(frame.Destroying, manager.destroy)
		return manager
	end
	return M
end
