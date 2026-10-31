-- Cowork: the browser-shared conversation.
--
-- The mode switch in the sidebar offers "Cowork" beside "Code", and in the client
-- this is modelled on that means real-time pairing. There is exactly one thing here
-- that genuinely is two people in one conversation -- the local web bridge -- so that
-- is what this panel is: its live state, its switch, and the two values it needs.
--
-- A Roblox client cannot accept a connection, so both sides dial out to a small
-- process on the same machine. That is why this panel is mostly about whether that
-- process is reachable, and why it says so in those words rather than showing a
-- spinner.
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

	-- The live state and the two values it needs, as cards a caller drops into its own
	-- column. Both the Cowork panel and the settings dialog's Cowork pane use this, so
	-- there is one description of the bridge rather than two that can disagree.
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
		-- its own actions rather than being folded into the manual bridge below.
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

		local desktopCard
		local autoToggle
		if not mobile then
			desktopCard = P.card(container, { name = "DesktopBridge", layoutOrder = nextOrder(), gap = theme.space.sm })
			P.text(desktopCard, { text = "UAI Bridge desktop app", role = "label", layoutOrder = 1 })
			P.text(desktopCard, { text = "Click Start Cowork in UAI Bridge.exe. This script finds it on port 28791 and reconnects when the app restarts. No token copying is needed. Manual connections below take priority when enabled.",
				role = "caption", wrap = true, auto = "Y", layoutOrder = 2 })
			local autoRow = P.row(desktopCard, { size = UDim2.new(1, 0, 0, 0), auto = "Y", gap = theme.space.sm, layoutOrder = 3 })
			P.text(autoRow, { text = "Find desktop app automatically", role = "small", flex = "Fill", layoutOrder = 1 })
			autoToggle = C.switch(autoRow, { value = config.get("bridge.autoDiscover", true) == true,
				onChange = function(value) config.set("bridge.autoDiscover", value) end })
			autoToggle.instance.Name = "AutoDiscoverDesktop"
			autoToggle.instance.LayoutOrder = 2
		end

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
		local runtimeText
		local function describe()
			local status = bridge.status()
			local shared = sessions.current()
			if runtimeText then runtimeText.Text = status.online and "Web runtime · Connected" or "Game runtime · No bridge connection" end
			if not status.running then
				dot.BackgroundColor3 = theme.color.textTertiary
				statusText.Text = status.searching and "Looking for UAI Bridge. Click Start Cowork in the desktop app."
					or "Not connected. Enable automatic discovery or configure a manual bridge below."
				detail.Text = string.format("%s\nwould share: %s", status.url, shared.title)
				return
			end
			if status.online then
				dot.BackgroundColor3 = theme.color.success
				statusText.Text = status.source == "desktop" and "Desktop app connected automatically. Cowork is ready."
					or "Connected. Open the browser link and start chatting."
				detail.Text = string.format("%s\nsharing: %s\nqueued: %d", status.url, shared.title, status.queued or 0)
				if status.kilo then detail.Text = detail.Text .. "\nKilo: " .. status.kilo.state .. " - " .. status.kilo.message end
				if status.cline then detail.Text = detail.Text .. "\nCline: " .. status.cline.state .. " - " .. status.cline.message end
				return
			end
			dot.BackgroundColor3 = theme.color.warn
			statusText.Text = status.source == "desktop" and "Desktop app found. Connecting to Cowork..."
				or "Waiting for the manual bridge. Check its token and port."
			detail.Text = string.format("%s\n%s", status.url, tostring(status.error or "no answer yet"))
		end

		local switchRow = P.row(statusCard, {
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			gap = theme.space.sm,
			layoutOrder = 3,
		})
		local switchText = P.column(switchRow, {
			size = UDim2.new(0, 0, 0, 0),
			auto = "Y",
			flex = "Fill",
			gap = 0,
			layoutOrder = 1,
		})
		P.text(switchText, { text = "Manual bridge enabled", role = "small" })
		P.text(switchText, {
			text = "Use this for terminal-based setup. Turn it off to use desktop discovery.",
			role = "caption",
			color = theme.color.textTertiary,
			wrap = true,
			auto = "Y",
		})
		local toggle = C.switch(switchRow, {
			value = config.get("bridge.enabled", false) == true,
			onChange = function(value) config.set("bridge.enabled", value) end,
		})
		toggle.instance.LayoutOrder = 2

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

		-- Every row in here states its order.
		--
		-- All six were LayoutOrder 0, so the label above the port field, the field, the
		-- label above the token field, that field, the hint and the button row were sorted
		-- by whatever the tie-break happened to produce -- which is a card whose two
		-- labels can end up over the wrong two fields.
		-- The Node installer is desktop setup; on a phone it is noise.
		if not mobile then
			local installerCard = P.card(container, { layoutOrder = nextOrder(), gap = theme.space.sm })
			P.text(installerCard, { text = "Manual setup: download and start", role = "label", layoutOrder = 1 })
			local installStatus = P.text(installerCard, { name = "BridgeDownloadStatus",
				text = "Install Node.js 18+ on this computer. Download the files, then open a terminal in your executor workspace (the folder containing UAI). Run: node UAI/bridge/start.txt",
				role = "caption", wrap = true, auto = "Y", layoutOrder = 2 })
			P.button(installerCard, { name = "DownloadBridge", text = "Download bridge files", icon = "folder",
				variant = "secondary", size = "sm", fill = true, layoutOrder = 3,
				onClick = function(button)
					button.setEnabled(false)
					button.setText("Downloading…")
					task.spawn(function()
						local ok, message = env.require("runtime/bridge_install").download(function(text)
							if installStatus.Parent then installStatus.Text = text end
						end)
						if not installerCard.Parent then return end
						installStatus.Text = message
						button.setText(ok and "Download again" or "Retry download")
						button.setEnabled(true)
						overlay.toast(ok and "Bridge files downloaded" or message, ok and "good" or "warn", 4)
					end)
				end })
			if caps.clipboard then
				P.button(installerCard, { name = "CopyBridgeStart", text = "Copy start command", variant = "ghost", size = "sm", fill = true, layoutOrder = 4,
					onClick = function()
						local ok = env.require("runtime/clipboard").write("node " .. env.require("runtime/fsx").root .. "/bridge/start.txt")
						overlay.toast(ok and "Start command copied" or "Could not reach the clipboard", ok and "good" or "warn", 2)
					end })
			end
			P.text(installerCard, { text = "No npm install or file renaming needed. Keep the terminal and Roblox open. From a Git checkout, run node bridge/server.js instead.",
				role = "caption", wrap = true, auto = "Y", layoutOrder = 5 })
		end
		local settings = P.card(container, { layoutOrder = nextOrder(), gap = theme.space.sm })
		P.text(settings, { text = "Manual connection", role = "label", layoutOrder = 0 })
		local runtimeCard = P.card(container, { layoutOrder = nextOrder(), gap = theme.space.sm })
		P.text(runtimeCard, { text = "Automatic runtime", role = "label", layoutOrder = 1 })
		P.text(runtimeCard, { text = "Connecting to Cowork automatically selects Web for live replies. Disconnecting returns new requests to Game. Tools and permissions stay in Roblox. Open the browser link to start chatting.",
			role = "caption", wrap = true, auto = "Y", layoutOrder = 2 })
		runtimeText = P.text(runtimeCard, { name = "BridgeRuntimeStatus", text = "", role = "small", wrap = true, auto = "Y", layoutOrder = 3 })
		P.text(runtimeCard, { text = "Bridge replies have no time limit. Use Stop to cancel a reply.", role = "caption", wrap = true, auto = "Y", layoutOrder = 4 })
		P.text(settings, { text = "Port", role = "small", layoutOrder = 1 })
		P.field(settings, {
			name = "BridgePort",
			text = tostring(config.get("bridge.port", 8790)),
			placeholder = "8790",
			layoutOrder = 2,
			onBlur = function(text)
				local port = tonumber(util.trim(text))
				config.set("bridge.port", (port and port > 0 and port < 65536) and math.floor(port) or 8790)
			end,
		})
		P.text(settings, { text = "Token", role = "small", layoutOrder = 3 })
		P.field(settings, {
			name = "BridgeToken",
			text = tostring(config.get("bridge.token", "")),
			placeholder = "paste the Token from your terminal",
			layoutOrder = 4,
			onBlur = function(text) config.set("bridge.token", util.trim(text)) end,
		})
		local tokenHint = P.text(settings, {
			text = "Match the port printed in the terminal, paste its Token, then turn Enabled on above. After restarting the bridge, paste the new token and reopen its browser link.",
			role = "caption",
			color = theme.color.textTertiary,
			wrap = true,
			auto = "Y",
			layoutOrder = 5,
		})
		tokenHint.Size = UDim2.new(1, 0, 0, 0)

		local buttons = P.row(settings, {
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			wrap = true,
			gap = theme.space.sm,
			layoutOrder = 6,
		})
		if caps.clipboard then
			P.button(buttons, {
				name = "CopyBridgeUrl",
				text = "Copy address",
				variant = "secondary",
				size = "sm",
				layoutOrder = 1,
				onClick = function()
					local ok = env.require("runtime/clipboard").write(bridge.status().url)
					overlay.toast(ok and "Address copied" or "Could not reach the clipboard",
						ok and "good" or "warn", 2)
				end,
			})
		end
		P.button(buttons, {
			name = "Reconnect",
			text = "Reconnect",
			variant = "ghost",
			size = "sm",
			layoutOrder = 2,
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

		describe()
		describeRelay()
		local unsubscribeConfig = config.changed:connect(function(path)
			if autoToggle and (path == nil or path == "bridge" or path == "bridge.autoDiscover") then
				autoToggle.set(config.get("bridge.autoDiscover", true) == true, true)
			end
			if path == nil or path == "bridge" or path == "bridge.enabled" then
				toggle.set(config.get("bridge.enabled", false) == true, true)
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
