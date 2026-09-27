-- A custom task panel backed by a supplied client and a supplied UI library.
-- The panel owns its view; the client owns the conversation and running turn.
return function(uai, UI, options)
	options = options or {}
	assert(type(uai) == "table" and uai.alive, "A live UAI handle is required")
	local session = options.Session or uai.sessions.current()
	assert(session and not session.removed, "The conversation is unavailable")
	assert(uai.sessions.threads[session.id] == session, "Use a tracked conversation from current() or newThread()")
	local window = UI:CreateWindow({
		Id = options.Id or "embedding-workbench",
		Title = "My assistant workbench",
		Subtitle = "Your controls, UAI's conversation and tools",
		ToggleKey = false,
		Parent = options.Parent,
	})
	local main = window:Tab({ Id = "assistant", Title = "Assistant" })
	local taskSection = main:Section({ Title = "Task" })
	local status = taskSection:Badge({ Id = "status", Text = "Conversation", Default = "Ready", Persist = false })
	local prompt = taskSection:Input({
		Id = "prompt", Text = "Your request", MultiLine = true, Lines = 3, Live = true,
		MaxLength = 8000, Persist = false, Placeholder = "Ask about this place or the example workbench",
	})
	local submit, stop
	local reply = main:Section({ Title = "Latest response" }):Paragraph({
		Id = "reply", Text = "Assistant", Content = "Send a request to begin.", Persist = false,
	})
	local latest, preview, lastError = "", "", nil
	local queued, cancelPaint = false, nil
	local function paint()
		if not window.Alive then return end
		status:Set(session.removed and "Conversation removed" or session.preparing and "Preparing"
			or session.busy and session.status or "Ready", true)
		if submit then submit:SetDisabled(session.busy or session.preparing ~= nil or session.removed == true) end
		if stop then stop:SetDisabled(not session.busy and not session.preparing) end
		local text = lastError or (preview ~= "" and preview or latest)
		if text == "" then text = "Send a request to begin." end
		-- This is a latest-response panel. Full retained history stays in UAI.
		local bounded = uai.env.require("runtime/util").truncate(text, 6000)
		reply:SetDescription(bounded)
	end
	local function queuePaint()
		if queued or not window.Alive then return end
		queued = true
		local completed, release = false, nil
		local thread = task.delay(0.06, function()
			completed, queued = true, false
			if release then release(false) end
			cancelPaint = nil
			paint()
		end)
		if not completed then release = window:Give(thread); cancelPaint = release end
	end
	local function remember(event)
		if event.kind == "assistant:text" then
			latest, preview, lastError = event.text or "", "", nil
		elseif event.kind == "assistant:preview" then
			preview = event.text or ""
		elseif event.kind == "assistant:complete" or event.kind == "abort" then
			preview = ""
		elseif event.kind == "user" then
			preview, lastError = "", nil
		elseif event.kind == "request:start" then
			preview = ""
		elseif event.kind == "error" then
			preview, lastError = "", event.message
		elseif event.kind == "turn:end" and event.failed then
			preview, lastError = "", event.text or lastError
		elseif event.kind == "cleared" then
			latest, preview, lastError = "", "", nil
		end
	end
	-- Subscribe before reading retained state. Rendering replaces one bounded
	-- paragraph, so replay never creates a second copy of a message.
	window:Give(session.events:connect(function(event) remember(event); queuePaint() end))
	window:Give(uai.sessions.listChanged:connect(queuePaint))
	for _, event in ipairs(session.transcript.snapshot()) do
		remember(event)
	end
	if session.livePreview then preview = session.livePreview.text or "" end

	submit = taskSection:Button({
		Id = "send", Text = "Send request", ActionText = "Send", Style = "Primary",
		Callback = function()
			local submitted = prompt:Get()
			local accepted, why = session.send(submitted, function()
				-- onDone runs after the session releases busy; Ready events can arrive earlier.
				if window.Alive then paint() end
			end)
			if not window.Alive then return end
			if accepted then
				if prompt:Get() == submitted then prompt:Set("", true) end
			else window:Notify({ Title = "Request kept", Content = tostring(why), Kind = "Warning" }) end
			paint()
		end,
	})
	stop = taskSection:Button({ Id = "stop", Text = "Stop this conversation", ActionText = "Stop",
		Callback = function() session.abort(); paint() end })
	taskSection:Button({ Id = "open-client", Text = "Full history, permissions and tools", ActionText = "Open UAI",
		Callback = function() uai.app.openSession(session.id); uai.show("chat") end })
	taskSection:Button({ Id = "providers", Text = "Configure a provider and model", ActionText = "Providers",
		Callback = function() uai.show("providers") end })

	local model = options.Model
	if model then
		local settings = window:Tab({ Id = "workbench", Title = "Workbench" }):Section({ Title = "Host settings" })
		local current = model.read()
		local title = settings:Input({ Id = "workbench-title", Text = "Title", Default = current.title, MaxLength = 80 })
		local enabled = settings:Toggle({ Id = "workbench-enabled", Text = "Enable workbench", Default = current.enabled })
		local batch = settings:Slider({ Id = "workbench-batch", Text = "Batch size", Min = 1, Max = 20, Step = 1, Default = current.batchSize })
		local summary = settings:Paragraph({ Id = "workbench-state", Text = "Applied state", Persist = false })
		local function reflect(value)
			if not window.Alive then return end
			summary:SetDescription(string.format("%s / %s / batch %d", value.title, value.enabled and "enabled" or "disabled", value.batchSize))
		end
		window:Give(model.subscribe(reflect))
		reflect(current)
		settings:Button({ Id = "workbench-apply", Text = "Apply these form values", ActionText = "Apply",
			Callback = function()
				local ok, why = model.update({ title = title:Get(), enabled = enabled:Get(), batchSize = batch:Get() })
				window:Notify({ Title = ok and "Settings applied" or "Settings kept", Content = ok and "The host model now uses these values." or tostring(why), Kind = ok and "Success" or "Warning" })
			end })
		settings:Button({ Id = "workbench-refresh", Text = "Load the current host values into the form", ActionText = "Refresh",
			Callback = function()
				local value = model.read()
				title:Set(value.title, true); enabled:Set(value.enabled, true); batch:Set(value.batchSize, true)
			end })
	end

	local appearance = window:Tab({ Id = "appearance", Title = "Appearance" }):Section({ Title = "This window" })
	appearance:Segmented({ Id = "theme", Text = "Theme", Options = { "Dark", "Light" }, Default = "Dark",
		Callback = function(value) window:SetTheme(value) end })
	appearance:Toggle({ Id = "reduced-motion", Text = "Reduce motion", Default = window.ReducedMotion,
		Callback = function(value) window:SetReducedMotion(value) end })
	-- Unloading the supplied runtime closes its dependent view. Closing just this
	-- view unregisters the runtime cleanup; it never destroys the shared client.
	window:Give(uai.env.require("runtime/dispose").add(function() window:Destroy() end, "embedding workbench window"))
	window:OnDestroy(function() if cancelPaint then cancelPaint(); cancelPaint = nil end end)
	paint()
	return window, session
end
