-- Shared syntax overlay for native selectable code fields, including read-only previews.
return function(env)
	local lexer = env.require("ui/code/highlight")
	local text = env.require("runtime/code_text")
	local metrics = env.require("ui/code/metrics")
	local theme = env.require("ui/theme")
	local clock = env.require("runtime/clock")
	local M = {}
	function M.attach(box, language)
		local P = env.require("ui/primitives")
		-- Keep the full-document native renderer behind a stable presentation.
		-- A selection changes only these bounded fills, never the visible source.
		local layer = P.frame(box, { name = "CodeSyntax", size = UDim2.fromScale(1, 1), bg = theme.color.codeSurface, zIndex = box.ZIndex + 1 })
		layer.Active, layer.Selectable = false, false
		local probes = P.frame(box, { name = "PreviewMetrics", size = UDim2.fromOffset(0, 0), clip = true })
		local role = { font = box.Font, size = box.TextSize, line = box.LineHeight }
		pcall(function() role.face = box.FontFace end)
		local singleProbe = metrics.probe(probes, "PreviewSingleLineMetrics", "Mg", role)
		local linesProbe = metrics.probe(probes, "PreviewLineMetrics", "Mg" .. string.rep("\nMg", 32), role)
		local alive, pending, focused, cache, rows, connections = true, false, false, nil, {}, {}
		local measured, caretAt, lineHeight = {}, clock.ms(), theme.text.mono.height
		local handle = { lineHeight = lineHeight }
		local caret = P.frame(layer, { name = "PreviewCaret", bg = theme.color.codeText, size = UDim2.fromOffset(2, theme.text.mono.height), zIndex = layer.ZIndex + 2, visible = false })
		caret.Active, caret.Selectable = false, false
		local palette = {}; for _, key in ipairs({ "keyword", "string", "number", "comment", "call" }) do palette[key] = "#" .. theme.code[key]:ToHex() end
		local scroll, ancestor = nil, box.Parent
		while ancestor do if ancestor:IsA("ScrollingFrame") then scroll = ancestor; break end; ancestor = ancestor.Parent end
		local function blinkCaret()
			local selecting = box.SelectionStart > 0 and box.CursorPosition ~= box.SelectionStart
			local visible = focused and not selecting and box.CursorPosition > 0 and (clock.ms() - caretAt) % 1000 < 550
			if caret.Visible ~= visible then caret.Visible = visible end
		end
		local function drawCaret()
			blinkCaret()
			if not focused or box.CursorPosition < 1 or not cache then return end
			local cursor = text.clamp(box.Text, box.CursorPosition)
			local index = text.lineAt(cache.starts, cursor)
			local value = cache.lines[index]
			measured[value] = measured[value] or metrics.line(value)
			caret.Position = UDim2.fromOffset(metrics.at(measured[value], value, cursor - cache.starts[index] + 1), (index - 1) * lineHeight)
			caret.Size = UDim2.fromOffset(2, lineHeight)
		end
		local function draw()
			if not alive then return end
			local previous = cache
			cache = lexer.scan(box.Text, cache)
			if previous ~= cache then
				measured = {}
			end
			local nativeAdvance = metrics.nativeAdvance(singleProbe, linesProbe, box.TextSize)
			local measuredAdvance = P.measureText("Mg\nMg", { role = "mono", line = 1 }).Y - P.measureText("Mg", { role = "mono", line = 1 }).Y
			local height = nativeAdvance or math.max(1, measuredAdvance * box.LineHeight)
			if lineHeight ~= height then
				lineHeight, handle.lineHeight = height, height
				if handle.onLineHeight then handle.onLineHeight(height) end
			end
			local viewport = scroll and scroll.AbsoluteSize.Y or box.AbsoluteSize.Y
			local y = scroll and math.max(0, scroll.AbsolutePosition.Y - box.AbsolutePosition.Y) or 0
			local first, count = math.max(1, math.floor(y / height) - 2), math.min(160, math.ceil(math.max(height, viewport) / height) + 6)
			local cursor, anchor = box.CursorPosition, box.SelectionStart
			local selecting = focused and cursor > 0 and anchor > 0 and cursor ~= anchor
			local a, b = math.min(cursor, anchor), math.max(cursor, anchor)
			for slot = 1, count do
				local row = rows[slot]
				if not row then
					row = { label = P.text(layer, { name = "SyntaxPreviewLine", role = "mono", rich = true, color = theme.color.codeText, zIndex = layer.ZIndex + 1 }),
						selection = P.frame(layer, { name = "PreviewSelection", bg = theme.color.codeSelection, zIndex = layer.ZIndex }) }
					row.label.Active, row.selection.Active = false, false; rows[slot] = row
				end
				local index, value = first + slot - 1, cache.lines[first + slot - 1]
				row.label.Visible, row.selection.Visible = value ~= nil, false
				if value then
					measured[value] = measured[value] or metrics.line(value)
					local left = scroll and math.max(0, scroll.AbsolutePosition.X - box.AbsolutePosition.X) or 0
					local x, firstByte, afterByte = metrics.window(measured[value], value, left, scroll and scroll.AbsoluteSize.X or box.AbsoluteSize.X)
					row.label.Position, row.label.Size = UDim2.fromOffset(x, (index - 1) * height), UDim2.new(1, -x, 0, height)
					row.label.TextYAlignment = Enum.TextYAlignment.Top
					if row.value ~= value or row.spans ~= cache.spans[index] or row.first ~= firstByte or row.after ~= afterByte then
						row.label.Text = language and language ~= "lua" and language ~= "luau" and env.require("ui/markdown").highlight(value:sub(firstByte, afterByte - 1), language)
							or lexer.richWindow(value, cache.spans[index], palette, firstByte, afterByte - 1)
						row.value, row.spans, row.first, row.after = value, cache.spans[index], firstByte, afterByte
					end
					local start, finish = cache.starts[index], cache.starts[index] + #value
					if selecting and a <= finish and b > start then
						local left = metrics.at(measured[value], value, math.max(1, a - start + 1))
						local right = metrics.at(measured[value], value, math.min(#value + 1, b - start + 1))
						row.selection.Position, row.selection.Size, row.selection.Visible = UDim2.fromOffset(left, (index - 1) * height), UDim2.fromOffset(math.max(theme.space.xs, right - left + (b > finish and theme.space.sm or 0)), height), true
					end
				end
			end
			for i = count + 1, #rows do rows[i].label.Visible, rows[i].selection.Visible = false, false end
			local transparency = #box.Text == 0 and 0 or 1
			layer.Visible = #box.Text > 0
			if box.TextTransparency ~= transparency then box.TextTransparency = transparency end
			drawCaret()
		end
		local function queue()
			if pending or not alive then return end; pending = true
			clock.delay(0.015, function() pending = false; if alive then draw() end end)
		end
		local function own(connection) if connection then connections[#connections + 1] = connection end end
		own(metrics.watchProbe(singleProbe, queue))
		own(metrics.watchProbe(linesProbe, queue))
		for _, property in ipairs({ "Text", "AbsoluteSize", "AbsolutePosition", "LineHeight", "CursorPosition", "SelectionStart", "TextTransparency", "TextWrapped" }) do connections[#connections + 1] = box:GetPropertyChangedSignal(property):Connect(queue) end
		connections[#connections + 1] = box.Focused:Connect(function() focused = true; caretAt = clock.ms(); queue() end)
		connections[#connections + 1] = box.FocusLost:Connect(function() focused = false; queue() end)
		connections[#connections + 1] = box:GetPropertyChangedSignal("CursorPosition"):Connect(function() caretAt = clock.ms(); queue() end)
		-- Blinking changes only visibility; source, selection and geometry events
		-- own syntax work and caret measurements.
		connections[#connections + 1] = env.run.Heartbeat:Connect(function() if alive and focused then blinkCaret() end end)
		if scroll then
			connections[#connections + 1] = scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(queue)
			connections[#connections + 1] = scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(queue)
		end
		function handle.destroy()
			if not alive then return end; alive = false
			for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
			handle.onLineHeight = nil
			layer:Destroy(); probes:Destroy()
		end
		connections[#connections + 1] = box.Destroying:Connect(handle.destroy)
		queue(); return handle
	end
	return M
end
