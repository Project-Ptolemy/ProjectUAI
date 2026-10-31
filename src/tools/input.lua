-- Virtual input: keyboard and mouse simulation.
--
-- Supports VirtualInputManager (standard engine input injector), executor globals
-- (keypress, mouse1click, etc.) and VirtualUser as fallbacks.
return function(env)
	local util = env.require("runtime/util")
	local clock = env.require("runtime/clock")
	local H = env.require("tools/helpers")

	local KEY_ALIASES = {
		["0"] = "Zero",
		["1"] = "One",
		["2"] = "Two",
		["3"] = "Three",
		["4"] = "Four",
		["5"] = "Five",
		["6"] = "Six",
		["7"] = "Seven",
		["8"] = "Eight",
		["9"] = "Nine",
		enter = "Return",
		space = "Space",
		esc = "Escape",
		escape = "Escape",
		tab = "Tab",
		backspace = "Backspace",
		shift = "LeftShift",
		lshift = "LeftShift",
		rshift = "RightShift",
		ctrl = "LeftControl",
		control = "LeftControl",
		lctrl = "LeftControl",
		rctrl = "RightControl",
		alt = "LeftAlt",
		lalt = "LeftAlt",
		ralt = "RightAlt",
		up = "Up",
		down = "Down",
		left = "Left",
		right = "Right",
	}

	local validKeyCodes = nil
	local function getValidKeyCodes()
		if validKeyCodes then return validKeyCodes end
		validKeyCodes = {}
		local ok, items = pcall(function() return Enum.KeyCode:GetEnumItems() end)
		if ok and type(items) == "table" then
			for _, item in ipairs(items) do
				validKeyCodes[item.Name:lower()] = item
			end
		end
		return validKeyCodes
	end

	local function resolveKeyCode(rawName)
		local cleaned = util.trim(rawName or "")
		if cleaned == "" then return nil, "no key specified" end

		local lower = cleaned:lower()
		local targetName = KEY_ALIASES[lower] or cleaned

		local codes = getValidKeyCodes()
		if codes[targetName:lower()] then
			return codes[targetName:lower()]
		end

		if #cleaned == 1 then
			local upper = cleaned:upper()
			if codes[upper:lower()] then
				return codes[upper:lower()]
			end
		end

		return nil, "unrecognised KeyCode: '" .. cleaned .. "'"
	end

	local function getVim()
		local ok, vim = pcall(function() return game:GetService("VirtualInputManager") end)
		return (ok and vim) or nil
	end

	local function getVu()
		local ok, vu = pcall(function() return game:GetService("VirtualUser") end)
		return (ok and vu) or nil
	end

	local function getMousePos(customX, customY)
		local x = tonumber(customX)
		local y = tonumber(customY)
		if x and y then return x, y end

		if env.uis and env.uis.GetMouseLocation then
			local ok, loc = pcall(function() return env.uis:GetMouseLocation() end)
			if ok and loc then
				x = x or loc.X
				y = y or loc.Y
			end
		end

		if not x or not y then
			local camera = env.services.Workspace and env.services.Workspace.CurrentCamera
			if camera and camera.ViewportSize then
				x = x or math.floor(camera.ViewportSize.X / 2)
				y = y or math.floor(camera.ViewportSize.Y / 2)
			end
		end

		return x or 0, y or 0
	end

	local held, alive, watching = {}, true, false
	local function stopped(ctx)
		if not alive then return true end
		if not ctx or not ctx.aborted then return false end
		local ok, value = pcall(ctx.aborted)
		return not ok or value == true
	end
	local function release(entry)
		entry.releaseRequested = true
		if entry.released then return true end
		if entry.releasing then return false end
		entry.releasing = true
		while true do
			local beganPending = entry.pendingDown
			local ok, value = pcall(entry.route.up)
			-- Up itself can yield across the late down. Only an up dispatched
			-- after down completed can clear ownership; this repeats at most once.
			if not beganPending or entry.pendingDown then
				entry.releasing = false
				if ok and value ~= false then
					if entry.pendingDown then return true end
					entry.released = true
					if held[entry.id] == entry then held[entry.id] = nil end
					return true
				end
				return false
			end
		end
	end
	local function watch()
		if watching or not alive then return end
		watching = true
		clock.delay(0.1, function()
			if not alive then watching = false; return end
			for _, entry in pairs(held) do
				if not entry.cleanupAttempted then
					if stopped(entry.ctx) then
						entry.cleanupAttempted = true
						local owned = entry
						clock.spawn(function() release(owned) end)
					end
				end
			end
			watching = false
			for _, entry in pairs(held) do if not entry.cleanupAttempted then watch(); break end end
		end)
	end
	local function outcome(ok, text, route, id, status)
		return { ok = ok, text = text, data = { status = status, provider = route and route.name,
			held = held[id] ~= nil } }
	end
	-- A known false return allows another provider. An exception after entering
	-- input injection has an unknown outcome: release through that same provider
	-- and stop, rather than issuing a second key-down or click elsewhere.
	local function inject(id, action, duration, routes, ctx, label)
		if stopped(ctx) then return H.fail("input was cancelled before dispatch") end
		local prior = held[id]
		if prior then
			if prior.ctx and prior.ctx.session ~= (ctx and ctx.session) then return H.fail("this input is held by another conversation") end
			if action ~= "up" then return H.fail("this input is already held; release it before pressing again") end
			local ok = release(prior)
			local pending = ok and prior.pendingDown
			return outcome(ok, pending and (label .. ": release requested; native down is pending and will be released again")
				or (ok and (label .. ": released") or (label .. ": release failed; the input may still be held. Retry only an explicit up action.")),
				prior.route, id, pending and "release_pending" or (ok and "released" or "release_failed"))
		end
		if util.count(held) >= 32 and action ~= "up" then return H.fail("held-input limit reached; release existing inputs first") end
		for _, route in ipairs(routes) do
			if stopped(ctx) then return H.fail("input was cancelled before dispatch") end
			local prepared, accepted = true, true
			if route.prepare then prepared, accepted = pcall(route.prepare) end
			if prepared and accepted ~= false then
				if stopped(ctx) then return H.fail("input was cancelled before dispatch") end
				if held[id] then return H.fail("this input became owned by another pending action; no input was sent") end
				if action == "up" and route.up then
					local ok, value = pcall(route.up)
					if ok and value ~= false then return outcome(true, label .. ": released", route, id, "released") end
				elseif action ~= "up" and route.down and route.up then
					if util.count(held) >= 32 then return H.fail("held-input limit reached; release existing inputs first") end
					local entry = { id = id, route = route, ctx = ctx, pendingDown = true }
					held[id] = entry
					watch()
					local ok, value = pcall(route.down)
					entry.pendingDown = false
					if ok and value == false then
						if entry.releaseRequested then
							local released = release(entry)
							return outcome(false, label .. ": provider refused down after release was requested; "
								.. (released and "cleanup completed" or "cleanup remains pending or failed; retry only an explicit up action"),
								route, id, released and "cancelled" or (entry.releasing and "release_pending" or "release_failed"))
						end
						if held[id] == entry then held[id] = nil end
					elseif not ok then
						release(entry)
						return outcome(false, label .. ": input outcome unknown; release attempted through the same provider. Do not repeat the press or click.",
							route, id, "unknown")
					else
						if action == "down" and not stopped(ctx) and not entry.releaseRequested then return outcome(true, label .. ": held until up, cancellation or unload", route, id, "held") end
						local deadline = clock.ms() + duration * 1000
						while not stopped(ctx) and not entry.releaseRequested and clock.ms() < deadline do clock.wait(math.min(0.05, (deadline - clock.ms()) / 1000)) end
						local cancelled = stopped(ctx) or entry.releaseRequested == true
						local released = release(entry)
						if not released then
							return outcome(false, label .. ": down was sent but release failed; the input may still be held. Retry only an explicit up action.", route, id, "release_failed")
						end
						return outcome(not cancelled, label .. (cancelled and ": cancelled and released" or ": completed"),
							route, id, cancelled and "cancelled" or "completed")
					end
				elseif action ~= "down" and action ~= "up" and route.tap then
					local ok, value = pcall(route.tap)
					if not ok then return outcome(false, label .. ": input outcome unknown; do not repeat this action.", route, id, "unknown") end
					if value ~= false then return outcome(true, label .. ": completed", route, id, "completed") end
				end
			end
		end
		return H.fail("no input provider accepted this action; no accepted down or click was retried")
	end
	env.require("runtime/dispose").add(function()
		alive = false
		for _, entry in pairs(held) do
			local owned = entry
			clock.spawn(function() release(owned) end)
		end
	end, "owned virtual input")

	local function keyRoutes(keyCode)
		local routes, vim, vu = {}, getVim(), getVu()
		if vim and type(vim.SendKeyEvent) == "function" then
			routes[#routes + 1] = { name = "VirtualInputManager",
				down = function() return vim:SendKeyEvent(true, keyCode, false, game) end,
				up = function() return vim:SendKeyEvent(false, keyCode, false, game) end }
		end
		if type(keypress) == "function" and type(keyrelease) == "function" then
			local press, up = keypress, keyrelease
			routes[#routes + 1] = { name = "executor", down = function() return press(keyCode.Value) end, up = function() return up(keyCode.Value) end }
		end
		if vu and type(vu.SetKeyDown) == "function" and type(vu.SetKeyUp) == "function" then
			routes[#routes + 1] = { name = "VirtualUser", prepare = function() return vu:CaptureController() end,
				down = function() return vu:SetKeyDown(keyCode.Name) end, up = function() return vu:SetKeyUp(keyCode.Name) end }
		end
		return routes
	end

	local function mouseRoutes(button, action, x, y, positioned)
		local routes, vim, vu = {}, getVim(), getVu()
		local index = button == "right" and 1 or button == "middle" and 2 or 0
		if action == "move" then
			if vim and type(vim.SendMouseMoveEvent) == "function" then routes[#routes + 1] = { name = "VirtualInputManager", tap = function() return vim:SendMouseMoveEvent(x, y, game) end } end
			if type(mousemoveabs) == "function" then local move = mousemoveabs; routes[#routes + 1] = { name = "executor", tap = function() return move(x, y) end } end
			return routes
		end
		if vim and type(vim.SendMouseButtonEvent) == "function" then
			routes[#routes + 1] = { name = "VirtualInputManager",
				down = function() return vim:SendMouseButtonEvent(x, y, index, true, game, 0) end,
				up = function() return vim:SendMouseButtonEvent(x, y, index, false, game, 0) end }
		end
		local click = button == "left" and mouse1click or button == "right" and mouse2click
		if type(click) == "function" and (not positioned or type(mousemoveabs) == "function") then
			local move = mousemoveabs
			routes[#routes + 1] = { name = "executor", tap = function()
				if positioned and move(x, y) == false then return false end
				return click()
			end }
		end
		if vu and button ~= "middle" then
			local down, up
			if button == "right" then down, up = vu.Button2Down, vu.Button2Up
			else down, up = vu.Button1Down, vu.Button1Up end
			if type(down) == "function" and type(up) == "function" then
				local pos = Vector2.new(x, y)
				routes[#routes + 1] = { name = "VirtualUser", prepare = function() return vu:CaptureController() end,
					down = function() return down(vu, pos) end, up = function() return up(vu, pos) end }
			end
		end
		return routes
	end
	return {
		{
			name = "key_press",
			examples = { { title = "Tap an interaction key", arguments = { key = "E", action = "press", duration = 0.05 },
				note = "Use only for an intended interaction. An uncertain press must not be automatically repeated." } },
			risk = "write",
			description = "Press, hold or release a keyboard key. Holds belong to this conversation and release on up, cancellation or unload. Accepted/uncertain presses are never repeated through a fallback; after a release failure, use only action=up.",
			parameters = {
				type = "object",
				properties = {
					key = {
						type = "string",
						description = "Key name or character, e.g. 'E', 'Space', 'Return', 'W', '1', 'LeftShift'.",
					},
					action = {
						type = "string",
						enum = { "press", "down", "up" },
						description = "'press' taps key down and up. 'down' holds key. 'up' releases key. Default 'press'.",
					},
					duration = {
						type = "number",
						description = "Hold duration in seconds if action is 'press' (0.01 - 2.0, default 0.05).",
						minimum = 0.01,
						maximum = 2.0,
					},
				},
				required = { "key" },
			},
			run = function(args, ctx)
				local keyCode, keyErr = resolveKeyCode(args.key)
				if not keyCode then return H.fail(keyErr) end
				local action = args.action or "press"
				if action ~= "press" and action ~= "down" and action ~= "up" then return H.fail("unknown keyboard action") end
				local duration = util.clamp(tonumber(args.duration) or 0.05, 0.01, 2.0)
				return inject("key:" .. keyCode.Name, action, duration, keyRoutes(keyCode), ctx, "Key " .. keyCode.Name)
			end,
		},
		{
			name = "mouse_click",
			risk = "write",
			description = "Click, hold, release or move the mouse at screen coordinates. Held buttons release on up, cancellation or unload. Unknown or partial input outcomes are reported without repeating clicks; retry only an explicit up after release failure.",
			parameters = {
				type = "object",
				properties = {
					button = {
						type = "string",
						enum = { "left", "right", "middle" },
						description = "Mouse button to click. Default 'left'.",
					},
					action = {
						type = "string",
						enum = { "click", "down", "up", "move" },
						description = "'click' clicks down and up. 'down' holds button. 'up' releases button. 'move' positions cursor. Default 'click'.",
					},
					x = {
						type = "number",
						description = "Screen X coordinate in pixels. Defaults to current mouse location or viewport center.",
					},
					y = {
						type = "number",
						description = "Screen Y coordinate in pixels. Defaults to current mouse location or viewport center.",
					},
				},
				required = {},
			},
			run = function(args, ctx)
				local button, action = args.button or "left", args.action or "click"
				if button ~= "left" and button ~= "right" and button ~= "middle" then return H.fail("unknown mouse button") end
				if action ~= "click" and action ~= "down" and action ~= "up" and action ~= "move" then return H.fail("unknown mouse action") end
				local x, y = getMousePos(args.x, args.y)
				local label = string.format("Mouse %s %s at (%.0f, %.0f)", button, action, x, y)
				return inject(action == "move" and "pointer" or ("mouse:" .. button), action, 0.05,
					mouseRoutes(button, action, x, y, args.x ~= nil or args.y ~= nil), ctx, label)
			end,
		},
	}
end
