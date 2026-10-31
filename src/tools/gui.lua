-- On-screen interfaces: read them, press them, mark things up, and tell the user
-- something.
return function(env)
	local util = env.require("runtime/util")
	local caps = env.require("runtime/caps")
	local clock = env.require("runtime/clock")
	local H = env.require("tools/helpers")
	local scan = env.require("runtime/instance_scan")
	local function aborted(ctx)
		if not ctx or not ctx.aborted then return false end
		local ok, value = pcall(ctx.aborted); return not ok or value == true
	end
	local function hold(beginHold, endHold, seconds, ctx, label)
		if aborted(ctx) then return H.fail(label .. " cancelled before dispatch") end
		local pending, stopped, releasing, requested = true, false, false, false
		local released, releaseResult = false, nil
		local function finish()
			requested = true
			if releasing then return end
			repeat
				requested, releasing = false, true
				local wasPending = pending
				released, releaseResult = pcall(endHold)
				releasing = false
				if wasPending and not pending then requested = true end
			until not requested
		end
		local stopWatch
		local disposer = env.require("runtime/dispose")
		local release = disposer.add(function()
			stopped = true
			if stopWatch then stopWatch() end
			-- A native end may yield. Unload must still release unrelated resources;
			-- ordinary completion waits for its end result before reporting success.
			if disposer.draining then clock.spawn(finish) else finish() end
		end, "tool " .. label)
		if stopped then pending = false; return H.fail(label .. " cancelled before dispatch") end
		stopWatch = clock.interval(0.05, function() if aborted(ctx) then release() end end)
		local began, result = pcall(beginHold)
		pending = false
		if stopped or aborted(ctx) or not began or result == false then
			if stopped then finish() else release() end
			return H.fail(label .. " interrupted or rejected; release attempted and begin effects may have occurred")
		end
		local start = clock.ms()
		local waited, why = pcall(function()
			while not stopped and clock.since(start) < seconds * 1000 and not aborted(ctx) do clock.wait(0.05) end
		end)
		local cancelled = stopped or aborted(ctx)
		release()
		if not waited or releasing or not released or releaseResult == false then return H.fail(label .. " release was not confirmed: " .. tostring(why or releaseResult)) end
		if cancelled then return { ok = false, text = label .. " cancelled and released; begin effects may have occurred.", data = { status = "aborted" } } end
		return { text = label .. " completed and released.", data = { status = "completed", localObservation = true } }
	end

	local function guiRoots()
		local roots = {}
		local playerGui = env.plr and env.plr:FindFirstChild("PlayerGui")
		if playerGui then roots[#roots + 1] = playerGui end
		local okCore, coreGui = pcall(function() return env.services.CoreGui end)
		if okCore and coreGui then roots[#roots + 1] = coreGui end
		return roots
	end

	return {
		{
			name = "ui_library_docs",
			examples = { { title = "Read UI LIB setup", arguments = { section = "quickstart", limit = 4000 },
				note = "Follow nextOffset, then read controls and lifecycle for the interface you need." } },
			risk = "read",
			description = "Read the bundled Project UAI UI LIB reference before creating a script UI. Covers responsive windows, controls, configuration, cleanup, embedding, application patterns, runtime integration and extending the shared library. Start with quickstart, controls and lifecycle; follow continuation offsets. No network or execution required.",
			parameters = {
				type = "object",
				properties = {
					section = { type = "string", enum = { "index", "quickstart", "embedding", "controls", "layout", "lifecycle", "configuration", "application_patterns", "runtime_integration", "recipes", "performance", "troubleshooting", "extending", "development" }, description = "Reference section; index lists the sections and release URL." },
					offset = { type = "integer", minimum = 1, description = "Continuation byte offset from the previous result." },
					limit = { type = "integer", minimum = 256, maximum = 16000, description = "Bytes to read; also bounded by the conversation's result budget." },
				},
				required = {},
			},
			run = function(args)
				local docs = env.require("runtime/ui_library_docs")
				local section = args.section or "index"
				if section == "index" then
					local names = {}
					for name in pairs(docs.sections) do names[#names + 1] = name end
					table.sort(names)
					return "Project UAI UI LIB v" .. docs.version .. "\nLoader: " .. docs.url
						.. "\nGuide: " .. docs.repository .. "/blob/main/docs/UI_LIBRARY.md"
						.. "\nSections: " .. table.concat(names, ", ")
						.. "\nRead quickstart, controls and lifecycle before authoring. Continue every paginated section to its end."
				end
				local body = docs.sections[section]
				if not body then return H.fail("unknown UI library section; request index") end
				return H.readSlice("Project UAI UI LIB / " .. section, body, args, 6000)
			end,
		},
		{
			name = "gui_tree",
			risk = "read",
			description = "Page top-level interfaces in PlayerGui and CoreGui, with enabled state and direct child counts. Does not enumerate every GUI descendant.",
			parameters = {
				type = "object",
				properties = {
					limit = { type = "integer", minimum = 1, maximum = 80 },
					offset = { type = "integer", minimum = 1 },
				},
				required = {},
			},
			run = function(args)
				local found, unreadable = {}, 0
				for _, root in ipairs(guiRoots()) do
					local readable, children = pcall(function() return root:GetChildren() end)
					if not readable then unreadable = unreadable + 1; children = {} end
					for _, child in ipairs(children) do
						local ok, isGui = pcall(function() return child:IsA("LayerCollector") end)
						if ok and isGui then found[#found + 1] = child end
					end
				end
				local result = H.page(found, args, tostring(#found) .. " interface(s):", function(gui)
						local okCount, descendants = pcall(function() return #gui:GetChildren() end)
						return string.format("%s [%s] %s, %s",
							H.pathOf(gui), gui.ClassName,
							gui.Enabled and "enabled" or "disabled",
							okCount and util.pluralise(descendants, "direct child") or "unknown size")
					end, 40, 80)
				if result.data then result.data.unreadableRoots, result.data.complete = unreadable, unreadable == 0 end
				return result
			end,
		},
		{
			name = "gui_text",
			risk = "read",
			description = "Read visible text under GUI roots using bounded cooperative traversal. Checks ancestor visibility and ScreenGui.Enabled; include_hidden opts into hidden text. Traversal order is not visual stacking order. Continue with the returned offset and identical filters.",
			parameters = {
				type = "object",
				properties = {
					path = { type = "string", description = "Dotted path to a ScreenGui or frame. Defaults to every screen interface." },
					limit = { type = "integer", minimum = 1, maximum = 120 },
					offset = { type = "integer", minimum = 1, maximum = 20001 },
					include_hidden = { type = "boolean", description = "Include text beneath hidden frames or disabled screens; default false." },
					text = { type = "string", description = "Case-insensitive literal text filter." },
				},
				required = {},
			},
			run = function(args, ctx)
				local targets = {}
				if args.path and util.trim(args.path) ~= "" then
					local instance, err = H.resolve(args.path)
					if not instance then return H.fail(err) end
					targets[1] = instance
				else
					targets = guiRoots()
				end

				local rows, scanned, unreadable, complete, nextOffset, reason = {}, 0, 0, true, nil, nil
				local limit, offset = H.limit(args.limit, 50, 120), H.limit(args.offset, 1, 20001)
				local budget, used = H.resultBudget() - 500, 0
				if budget < 128 then return H.fail("increase the result budget to at least 628 bytes") end
				local needle = tostring(args.text or ""):lower()
				local function inspect(node, index)
					if index < offset then return end
					local readable, value, visible = pcall(function()
						if not (node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox")) then return nil end
						local ancestor, depth = node, 0
						while ancestor and depth < 128 do
							if (ancestor:IsA("GuiObject") and not ancestor.Visible) or (ancestor:IsA("LayerCollector") and not ancestor.Enabled) then return node.Text, false end
							ancestor, depth = ancestor.Parent, depth + 1
						end
						return node.Text, ancestor == nil
					end)
					if not readable then unreadable = unreadable + 1; return end
					if type(value) ~= "string" or not value:find("%S") or (not visible and not args.include_hidden) or not value:lower():find(needle, 1, true) then return end
					local line = string.format("%q %s[%s] %s", util.ellipsis(value, 160), visible and "" or "(hidden) ", node.ClassName, H.pathOf(node))
					if used + #line + 1 > budget then nextOffset = index; return false end
					rows[#rows + 1] = line; used = used + #line + 1
					if #rows >= limit then nextOffset = index + 1; return false end
				end
				for rootIndex, root in ipairs(targets) do
					if ctx and ctx.aborted and ctx.aborted() then return { ok = false, text = "GUI text scan cancelled.", data = { status = "aborted" } } end
					scanned = scanned + 1
					if inspect(root, scanned) == false then complete = false; break end
					local base = scanned
					local stats = scan.descendants(root, ctx, function(node, index) return inspect(node, base + index) end, math.max(0, 20000 - scanned))
					scanned, unreadable = scanned + stats.scanned, unreadable + stats.unreadable
					if not stats.complete then complete = false; reason = stats.reason end
					if scanned >= 20000 and rootIndex < #targets then complete, reason = false, "scan limit" end
					if nextOffset or scanned >= 20000 or stats.reason == "aborted" then break end
				end
				if #rows == 0 and nextOffset then return H.fail("one GUI row exceeds the result budget; narrow the root or increase the budget") end
				complete = complete and unreadable == 0
				return { ok = reason ~= "aborted", text = string.format("%d text element(s); %d nodes scanned%s.\n%s", #rows, scanned, complete and "" or "; incomplete traversal", table.concat(rows, "\n")),
					data = { count = #rows, scanned = scanned, unreadable = unreadable, complete = complete, nextOffset = nextOffset, reason = reason } }
			end,
		},
		{
			name = "gui_click",
			risk = "write",
			needs = { "hooks" },
			description = "Press a GUI button by firing the handlers connected to it. Needs a host that exposes signal introspection.",
			parameters = {
				type = "object",
				properties = {
					path = { type = "string", description = "Dotted path to a TextButton or ImageButton." },
					signal = {
						type = "string",
						enum = { "Activated", "MouseButton1Click", "MouseButton1Down" },
						description = "Which signal to fire. Default Activated, which most modern interfaces use.",
					},
				},
				required = { "path" },
			},
			run = function(args, ctx)
				local button, err = H.resolve(args.path)
				if not button then return H.fail(err) end
				local okA, isButton = pcall(function() return button:IsA("GuiButton") end)
				if not okA or not isButton then
					return H.fail(button.ClassName .. " is not a button")
				end

				local signalName = args.signal or "Activated"
				local okSignal, signal = pcall(function() return button[signalName] end)
				if not okSignal or not signal then return H.fail("no signal named " .. signalName) end

				local okConn, connections = pcall(caps.fn.getconnections, signal)
				if not okConn or type(connections) ~= "table" then
					return H.fail("could not read the connections on that signal")
				end
				if #connections == 0 then
					return H.fail(string.format("%s has no %s handlers; nothing was fired", H.pathOf(button), signalName))
				end
				if #connections > 256 then return H.fail("more than 256 handlers; select a more specific button or signal") end

				local fired = 0
				for _, connection in ipairs(connections) do
					if ctx and ctx.aborted and ctx.aborted() then break end
					local okFire, value = pcall(function() return connection:Fire() end)
					if okFire and value ~= false then fired = fired + 1 end
				end
				return { ok = fired == #connections, text = string.format("Fired %d of %d %s handler(s) on %s", fired, #connections, signalName, H.pathOf(button)),
					data = { fired = fired, total = #connections, status = fired == #connections and "dispatched" or "partial" } }
			end,
		},
		{
			name = "click_detector_fire",
			risk = "danger",
			description = "Submit a ClickDetector, ProximityPrompt hold, or part touch interaction. Prompt/touch holds are released on cancellation or unload; host acceptance does not prove a server response.",
			parameters = {
				type = "object",
				properties = {
					path = { type = "string", description = "Path to the ClickDetector, or to a part containing one." },
					distance = { type = "number", minimum = 0, maximum = 10000, description = "Reported click distance. Default 0." },
				},
				required = { "path" },
			},
			run = function(args, ctx)
				local instance, err = H.resolve(args.path)
				if not instance then return H.fail(err) end

				if aborted(ctx) then return H.fail("interaction cancelled before dispatch") end
				local detector = instance
				local okA, isDetector = pcall(function() return instance:IsA("ClickDetector") end)
				if not (okA and isDetector) then
					detector = instance:FindFirstChildOfClass("ClickDetector")
				end

				if detector and caps.fn.fireclickdetector then
					local ok, fireErr = pcall(caps.fn.fireclickdetector, detector, tonumber(args.distance) or 0)
					if not ok or fireErr == false then return H.fail("click was rejected: " .. tostring(fireErr)) end
					return "Clicked " .. H.pathOf(detector)
				end

				local prompt = instance:IsA("ProximityPrompt") and instance or instance:FindFirstChildOfClass("ProximityPrompt")
				if prompt then
					local duration = tonumber(prompt.HoldDuration) or 0
					if duration ~= duration or duration < 0 or duration > 20 then return H.fail("prompt hold duration is outside the supported 0–20 second range") end
					return hold(function() return prompt:InputHoldBegin() end, function() return prompt:InputHoldEnd() end,
						duration + 0.05, ctx, "Prompt hold on " .. H.pathOf(prompt))
				end

				if caps.fn.firetouchinterest then
					local root = env.plr and env.plr.Character
						and (env.plr.Character:FindFirstChild("HumanoidRootPart") or env.plr.Character.PrimaryPart)
					local okPart, isPart = pcall(function() return instance:IsA("BasePart") end)
					if root and okPart and isPart then
						return hold(function() return caps.fn.firetouchinterest(root, instance, 0) end,
							function() return caps.fn.firetouchinterest(root, instance, 1) end, 0.05, ctx, "Touch on " .. H.pathOf(instance))
					end
				end

				return H.fail("nothing interactable found at that path, or the host lacks the function to trigger it")
			end,
		},
		{
			name = "highlight",
			risk = "write",
			description = "Outline an instance on screen for a few seconds so the user can see which one you mean.",
			parameters = {
				type = "object",
				properties = {
					path = { type = "string" },
					seconds = { type = "number", description = "1-30. Default 6.", minimum = 1, maximum = 30 },
					colour = { type = "string", description = "Outline colour as 'r, g, b' or '#rrggbb'." },
				},
				required = { "path" },
			},
			run = function(args)
				local instance, err = H.resolve(args.path)
				if not instance then return H.fail(err) end

				local colour = Color3.fromRGB(0, 225, 190)
				if args.colour and util.trim(args.colour) ~= "" then
					local parsed = H.coerce(args.colour, colour)
					if not parsed then return H.fail("colour must be valid RGB or #rrggbb") end
					colour = parsed
				end
				local okNew, highlight = pcall(function() return Instance.new("Highlight") end)
				if not okNew or not highlight then return H.fail("this host has no Highlight class") end
				local release = env.require("runtime/dispose").add(function() highlight:Destroy() end, "tool highlight")

				local configured, problem = pcall(function()
					highlight.Name = "UAI_Highlight"
					highlight.FillColor = colour
					highlight.OutlineColor = colour
					highlight.FillTransparency = 0.65
					highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					highlight.Adornee = instance
					highlight.Parent = instance
				end)
				if not configured then release(); return H.fail("highlight could not be configured: " .. tostring(problem)) end

				local seconds = util.clamp(tonumber(args.seconds) or 6, 1, 30)
				clock.delay(seconds, release)
				return string.format("Highlighted %s for %.0f seconds", H.pathOf(instance), seconds)
			end,
		},
		{
			name = "notify",
			risk = "read",
			description = "Show a short message to the user as a toast in the agent's own interface. Use it for something worth noticing, not for your reply.",
			parameters = {
				type = "object",
				properties = {
					text = { type = "string", description = "One line, under about 90 characters." },
					tone = { type = "string", enum = { "info", "good", "warn", "bad" } },
				},
				required = { "text" },
			},
			run = function(args)
				local overlay = env.require("ui/overlay")
				local text = util.ellipsis(args.text, 140)
				if not overlay.toast(text, args.tone or "info") then return H.fail("the client interface is not mounted; notification was not shown") end
				return "Shown to the user: " .. text
			end,
		},
		{
			name = "clipboard_set",
			risk = "write",
			needs = { "clipboard" },
			description = "Put text on the user's clipboard.",
			parameters = {
				type = "object",
				properties = { text = { type = "string" } },
				required = { "text" },
			},
			run = function(args)
				local text = tostring(args.text or "")
				if text == "" then return "Nothing to copy." end
				local ok, err = pcall(caps.fn.clipboard, text)
				if not ok or err == false then return H.fail("clipboard write was rejected: " .. tostring(err)) end
				return string.format("Copied %d bytes to the clipboard.", #text)
			end,
		},
	}
end
