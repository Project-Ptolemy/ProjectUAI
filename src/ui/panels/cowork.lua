-- Cowork uses the automatically discovered desktop app. Mobile provider traffic
-- keeps the companion relay's independent pairing, status and controls.
return function(env)
	local util = env.require("runtime/util")
	local config = env.require("runtime/config")
	local caps = env.require("runtime/caps")
	local theme = env.require("ui/theme")
	local P = env.require("ui/primitives")
	local C = env.require("ui/controls")
	local overlay = env.require("ui/overlay")
	local bridge = env.require("net/bridge")
	local sessions = env.require("agent/session")
	local relayLink = env.require("net/relay_link")

	local M = {}

	function M.new(parent)
		local panel = {}
		local mobile = relayLink.mobile()
		local scroll = P.scroll(parent, {
			name = "Cowork",
			size = UDim2.new(1, 0, 1, 0),
			gap = theme.space.lg,
			padding = theme.space.lg,
		})

		P.sectionHeader(scroll.instance, {
			title = "Cowork",
			description = mobile
				and ("Start UAI Relay on this phone and the script pairs with it automatically, so long replies survive the "
					.. "executor's request limit. Messages, tools, and permissions stay connected to this Roblox session.")
				or ("Open UAI Bridge on this computer and click Start Cowork. The desktop app connects automatically. "
					.. "Messages, tools, and permissions stay connected to this Roblox session."),
			layoutOrder = 1,
		})

		M.rows(scroll.instance, { layoutOrder = 2 })

		panel.scroll = scroll
		return panel
	end

	-- Share live status and discovery controls between Cowork and Settings.
	function M.rows(container, props)
		props = props or {}
		local order = (props.layoutOrder or 1) - 1
		local function nextOrder()
			order = order + 1
			return order
		end
		local mobile = relayLink.mobile()

		-- The companion relay is the mobile answer to the executor's request limit. It
		-- is independent of the Cowork link, so it gets its own card, its own mode and
		-- its own actions rather than sharing the desktop connection's controls.
		local relayCard = P.card(container, { name = "RelayCompanion", layoutOrder = nextOrder(), gap = theme.space.sm })
		P.text(relayCard, { text = "Mobile relay (companion app)", role = "label", layoutOrder = 1 })
		P.text(relayCard, {
			text = "Start UAI Relay on this phone. The script hands long provider requests to it, so the executor's request limit "
				.. "cannot cut them off. Pairing is automatic; no token copying.",
			role = "caption", wrap = true, auto = "Y", layoutOrder = 2 })
		local relayRow = P.row(relayCard, { size = UDim2.new(1, 0, 0, 0), auto = "Y", gap = theme.space.sm, layoutOrder = 3 })
		local relayDot = P.statusDot(relayRow, { diameter = theme.size.dot, color = theme.color.textTertiary, layoutOrder = 1 })
		local relayText = P.text(relayRow, {
			name = "RelayStatusText", text = "", role = "small", color = theme.color.text, wrap = true,
			auto = "Y", size = UDim2.new(0, 0, 0, 0), flex = "Fill", layoutOrder = 2 })
		local relayDetail = P.text(relayCard, {
			name = "RelayStatusDetail", text = "", role = "monoSmall", color = theme.color.textSecondary,
			wrap = true, auto = "Y", layoutOrder = 4 })
		relayDetail.Size = UDim2.new(1, 0, 0, 0)
		local function describeRelay()
			local status = relayLink.status()
			local token = tostring(config.get("relay.token", ""))
			if status.state == "ready" then
				relayDot.BackgroundColor3 = theme.color.success
				relayText.Text = "Companion connected. Long replies are relayed through this phone."
			elseif status.mode == "off" then
				relayDot.BackgroundColor3 = theme.color.textTertiary
				relayText.Text = "Relay mode is off, so the script calls providers directly."
			elseif not caps.has("http") then
				relayDot.BackgroundColor3 = theme.color.warn
				relayText.Text = "This host has no HTTP transport, so the companion cannot be reached."
			else
				relayDot.BackgroundColor3 = theme.color.warn
				relayText.Text = status.state == "searching" and "Looking for the companion app…"
					or "Companion connection failed. Check the details below, then press Scan now."
			end
			local parts = { "port " .. tostring(status.port) }
			if status.server ~= "" then parts[#parts + 1] = "server " .. status.server end
			if #token > 10 then parts[#parts + 1] = "paired ···" .. token:sub(-4) end
			if (status.placeId or 0) > 0 then parts[#parts + 1] = "place " .. tostring(status.placeId) end
			if status.error then parts[#parts + 1] = tostring(status.error) end
			if status.kilo then parts[#parts + 1] = "Kilo: " .. status.kilo.state .. " - " .. status.kilo.message end
			relayDetail.Text = table.concat(parts, "  ·  ")
		end
		local relayMode = C.segmented(relayCard, {
			options = { { label = "Auto", value = "auto" }, { label = "Always", value = "always" }, { label = "Off", value = "off" } },
			value = config.get("relay.mode", "auto"), layoutOrder = 5,
			onChange = function(value) config.set("relay.mode", value) end })
		local relayButtons = P.row(relayCard, { size = UDim2.new(1, 0, 0, 0), auto = "Y", wrap = true, gap = theme.space.sm, layoutOrder = 6 })
		P.button(relayButtons, {
			name = "RelayScan", text = "Scan now", variant = "secondary", size = "sm", layoutOrder = 1,
			onClick = function(button)
				button.setEnabled(false)
				button.setText("Scanning…")
				local ok, err = relayLink.scan()
				if not relayCard.Parent then return end
				button.setEnabled(true)
				button.setText("Scan now")
				describeRelay()
				if not ok then overlay.toast(tostring(err or "No companion answered on that port"), "warn", 3) end
			end })
		P.button(relayButtons, {
			name = "RelayUnpair", text = "Reset pairing", variant = "ghost", size = "sm", layoutOrder = 2,
			onClick = function()
				relayLink.forget()
				describeRelay()
				overlay.toast("Pairing reset", "good", 2)
			end })

		if mobile then
			describeRelay()
			local unsubscribeConfig = config.changed:connect(function(path)
				if path == nil or path == "relay" or util.startsWith(tostring(path), "relay.") then
					relayMode.set(config.get("relay.mode", "auto")); describeRelay()
				end
			end)
			local unsubscribeRelay = relayLink.changed:connect(function()
				if relayCard.Parent then describeRelay() end
			end)
			relayCard.Destroying:Connect(function() unsubscribeConfig(); unsubscribeRelay() end)
			return relayCard
		end
		local desktopCard = P.card(container, { name = "DesktopBridge", layoutOrder = nextOrder(), gap = theme.space.sm })
		P.text(desktopCard, { text = "UAI Bridge desktop app", role = "label", layoutOrder = 1 })
		P.text(desktopCard, { text = "Click Start Cowork in UAI Bridge.exe. This script connects automatically and reconnects when the app restarts.",
			role = "caption", wrap = true, auto = "Y", layoutOrder = 2 })
		local autoRow = P.row(desktopCard, { size = UDim2.new(1, 0, 0, 0), auto = "Y", gap = theme.space.sm, layoutOrder = 3 })
		P.text(autoRow, { text = "Find desktop app automatically", role = "small", flex = "Fill", layoutOrder = 1 })
		local autoToggle = C.switch(autoRow, { value = config.get("bridge.autoDiscover", true) == true,
			onChange = function(value) config.set("bridge.autoDiscover", value) end })
		autoToggle.instance.Name = "AutoDiscoverDesktop"
		autoToggle.instance.LayoutOrder = 2

		local statusCard = P.card(container, { layoutOrder = nextOrder(), gap = theme.space.sm })

		local statusRow = P.row(statusCard, {
			name = "Status",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			gap = theme.space.sm,
			layoutOrder = 1,
		})
		local dot = P.statusDot(statusRow, {
			diameter = theme.size.dot,
			color = theme.color.textTertiary,
			layoutOrder = 1,
		})
		local statusText = P.text(statusRow, {
			name = "StatusText",
			text = "",
			role = "small",
			color = theme.color.text,
			wrap = true,
			auto = "Y",
			size = UDim2.new(0, 0, 0, 0),
			flex = "Fill",
			layoutOrder = 2,
		})

		local detail = P.text(statusCard, {
			name = "StatusDetail",
			text = "",
			role = "monoSmall",
			color = theme.color.textSecondary,
			wrap = true,
			auto = "Y",
			layoutOrder = 2,
		})
		detail.Size = UDim2.new(1, 0, 0, 0)

		-- Everything on this row is a fact about the running bridge rather than a
		-- control, which is why it is text and not a badge: three of the four values are
		-- only interesting when something is wrong.
		local runtimeText, reconnect, disconnect
		local function describe()
			local status = bridge.status()
			local shared = sessions.current()
			if reconnect then reconnect.setEnabled(caps.has("http") and config.get("bridge.autoDiscover", true) == true) end
			if disconnect then disconnect.setEnabled(status.running or status.searching) end
			if runtimeText then runtimeText.Text = status.online and "Web runtime · Connected" or "Game runtime · No bridge connection" end
			if not status.running then
				dot.BackgroundColor3 = theme.color.textTertiary
				statusText.Text = status.searching and "Looking for UAI Bridge. Click Start Cowork in the desktop app."
					or not caps.has("http") and "This host cannot connect to the desktop app because HTTP is unavailable."
					or config.get("bridge.autoDiscover", true) ~= true and "Automatic desktop connection is off. Enable Find desktop app automatically to connect."
					or "Cowork is disconnected. Choose Reconnect to look for the desktop app."
				detail.Text = string.format("%s\nwould share: %s", status.url, shared.title)
				return
			end
			if status.online then
				dot.BackgroundColor3 = theme.color.success
				statusText.Text = "Desktop app connected automatically. Cowork is ready."
				detail.Text = string.format("%s\nsharing: %s\nqueued: %d", status.url, shared.title, status.queued or 0)
				if status.kilo then detail.Text = detail.Text .. "\nKilo: " .. status.kilo.state .. " - " .. status.kilo.message end
				if status.cline then detail.Text = detail.Text .. "\nCline: " .. status.cline.state .. " - " .. status.cline.message end
				return
			end
			dot.BackgroundColor3 = theme.color.warn
			statusText.Text = "Desktop app found. Connecting to Cowork..."
			detail.Text = string.format("%s\n%s", status.url, tostring(status.error or "no answer yet"))
		end

		if not caps.has("http") then
			local warning = P.text(statusCard, {
				text = "This host has no HTTP transport, so the bridge cannot be reached from here at all.",
				role = "caption",
				color = theme.color.warn,
				wrap = true,
				auto = "Y",
				layoutOrder = 4,
			})
			warning.Size = UDim2.new(1, 0, 0, 0)
		end

		local runtimeCard = P.card(container, { layoutOrder = nextOrder(), gap = theme.space.sm })
		P.text(runtimeCard, { text = "Automatic runtime", role = "label", layoutOrder = 1 })
		P.text(runtimeCard, { text = "Connecting to Cowork automatically selects Web for live replies. Disconnecting returns new requests to Game. Tools and permissions stay in Roblox.",
			role = "caption", wrap = true, auto = "Y", layoutOrder = 2 })
		runtimeText = P.text(runtimeCard, { name = "BridgeRuntimeStatus", text = "", role = "small", wrap = true, auto = "Y", layoutOrder = 3 })
		P.text(runtimeCard, { text = "Bridge replies have no time limit. Use Stop to cancel a reply.", role = "caption", wrap = true, auto = "Y", layoutOrder = 4 })
		local buttons = P.row(statusCard, {
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			wrap = true,
			gap = theme.space.sm,
			layoutOrder = 3,
		})
		reconnect = P.button(buttons, {
			name = "Reconnect",
			text = "Reconnect",
			variant = "ghost",
			size = "sm",
			layoutOrder = 1,
			onClick = function()
				-- Stop then sync: the poller backs off up to ten seconds between
				-- attempts, and after starting the server on the other side nobody wants
				-- to wait out the backoff.
				bridge.stop()
				local ok, why = bridge.sync()
				if not ok and why then overlay.toast(tostring(why), "warn", 3) end
				describe()
			end,
		})
		disconnect = P.button(buttons, { name = "DisconnectCowork", text = "Disconnect", variant = "ghost", size = "sm", layoutOrder = 2,
			onClick = function() bridge.stop(); describe() end })

		describe()
		describeRelay()
		local unsubscribeConfig = config.changed:connect(function(path)
			if autoToggle and (path == nil or path == "bridge" or path == "bridge.autoDiscover") then
				autoToggle.set(config.get("bridge.autoDiscover", true) == true, true)
			end
			if path == nil or path == "relay" or util.startsWith(tostring(path), "relay.") then
				relayMode.set(config.get("relay.mode", "auto"))
				describeRelay()
			end
		end)
		local unsubscribeBridge = bridge.changed:connect(function()
			if not statusCard.Parent then return end
			describe()
		end)
		local unsubscribeRelay = relayLink.changed:connect(function()
			if not relayCard.Parent then return end
			describeRelay()
		end)
		local unsubscribeSessions = sessions.listChanged:connect(function()
			if not statusCard.Parent then return end
			describe()
		end)
		statusCard.Destroying:Connect(function()
			pcall(unsubscribeBridge)
			pcall(unsubscribeSessions)
			pcall(unsubscribeConfig)
			pcall(unsubscribeRelay)
		end)

		return statusCard
	end

	return M
end
