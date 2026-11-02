-- Measure long lines in bounded UTF-8 chunks and reuse their prefix widths.
return function(env)
	local text = env.require("runtime/code_text")
	local P = env.require("ui/primitives")
	local M = {}
	-- Native calibration is optional; hosts may refuse extra inputs or their
	-- metric properties. The existing text measurement remains the fallback.
	function M.probe(parent, name, value, role)
		local node
		local ok = pcall(function()
			node = Instance.new("TextBox", parent)
			node.Name, node.Text, node.TextTransparency, node.BackgroundTransparency = name, value, 1, 1
			node.Active, node.Selectable, node.TextEditable = false, false, false
			node.BorderSizePixel, node.ClearTextOnFocus = 0, false
			node.MultiLine, node.TextWrapped, node.RichText = true, false, false
			node.Font, node.TextSize, node.LineHeight = role.font, role.size, role.line
			if role.face then pcall(function() node.FontFace = role.face end) end
			node.Position, node.Size = UDim2.fromOffset(-2000, 0), UDim2.fromOffset(1000, 2000)
		end)
		if ok then return node end
		if node then pcall(function() node:Destroy() end) end
	end
	function M.nativeAdvance(single, multiple, size)
		if not single or not multiple then return nil end
		local ok, advance = pcall(function() return (multiple.TextBounds.Y - single.TextBounds.Y) / 32 end)
		if ok and type(advance) == "number" and advance >= size * 0.5 and advance <= size * 4 then return advance end
	end
	function M.watchProbe(node, callback)
		if not node then return nil end
		local ok, connection = pcall(function() return node:GetPropertyChangedSignal("TextBounds"):Connect(callback) end)
		return ok and connection or nil
	end
	function M.line(value)
		local metric = { width = 0, chunks = {} }
		local at = 1
		while at <= #value do
			local after = text.clamp(value, at + 2048)
			local width = P.measureText(value:sub(at, after - 1), { role = "mono" }).X
			metric.chunks[#metric.chunks + 1] = { first = at, after = after, x = metric.width, width = width }
			metric.width, at = metric.width + width, after
		end
		return metric
	end
	function M.at(metric, value, offset)
		offset = text.clamp(value, offset)
		local low, high = 1, #metric.chunks
		while low < high do local mid = math.ceil((low + high) / 2); if metric.chunks[mid].first <= offset then low = mid else high = mid - 1 end end
		local chunk = metric.chunks[low]
		if not chunk then return 0 end
		if offset >= chunk.after then return chunk.x + chunk.width end
		return chunk.x + P.measureText(value:sub(chunk.first, offset - 1), { role = "mono" }).X
	end
	function M.window(metric, value, left, width)
		if #value <= 2048 then return 0, 1, #value + 1 end
		local low, high = 1, #metric.chunks
		while low < high do local mid = math.ceil((low + high) / 2); if metric.chunks[mid].x <= left then low = mid else high = mid - 1 end end
		local first = metric.chunks[low]
		local after = first.after
		for i = low + 1, math.min(#metric.chunks, low + 3) do
			local chunk = metric.chunks[i]
			if chunk.x > left + width then break end
			after = chunk.after
		end
		return first.x, first.first, after
	end
	return M
end
