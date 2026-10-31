-- Saved-provider navigation for the model picker. Configuration stays in registry.
return function(env)
	local util = env.require("runtime/util")
	local search = env.require("runtime/search")
	local theme = env.require("ui/theme")
	local responsive = env.require("ui/responsive")
	local P = env.require("ui/primitives")
	local overlay = env.require("ui/overlay")
	local providers = env.require("provider/registry")
	local models = env.require("provider/models")
	local urls = env.require("net/url")
	local bridge = env.require("net/bridge")
	local community = env.require("provider/community_key")
	local M = {}
	local opened

	function M.target()
		return math.max(theme.size.control, responsive.minTarget(), responsive.isMobile() and 40 or 0)
	end

	function M.preferredHeight()
		-- The catalogue can use the screen's height while the app's compact
		-- placement, typography and other windows keep their normal metrics.
		return math.ceil(theme.size.modelPickerHeight / (responsive.isMobile() and theme.metricScale or 1))
	end

	function M.sizeButton(button, height)
		local size = button.instance.Size
		button.instance.Size = UDim2.new(size.X.Scale, size.X.Scale == 0 and math.max(size.X.Offset, height) or size.X.Offset, 0, height)
	end

	function M.describe(record)
		if not record then return { detail = "Add a provider to get started", route = "", tone = theme.color.textTertiary } end
		local known, free = models.list(record), 0
		for _, id in ipairs(known) do if models.isFree(record, id) then free = free + 1 end end
		local detail = util.pluralise(#known, "model") .. (free > 0 and (" / " .. free .. " free") or "")
		local route, tone = urls.display(record.baseUrl), theme.color.textTertiary
		if community.isApplied(record) then
			local availability = community.availability(record)
			local countdown = community.countdown(record)
			detail = "Community access / " .. (countdown and countdown.text or community.shortHours)
			route, tone = community.shortHours, availability.open and theme.color.success or theme.color.warn
		elseif record.preset == "hcnsec" then
			detail = "Personal HCNSEC / " .. detail
			if providers.keyPoolSize(record) == 0 then detail, tone = "API key required / " .. detail, theme.color.warn end
		elseif providers.isCline(record) then
			local state = bridge.clineStatus()
			local labels = { ready = "Desktop connected", ["auth-required"] = "Sign in on desktop", disabled = "Enable in Tunnels",
				missing = "Install Cline on desktop", starting = "Connecting on desktop", failed = "Check desktop connection",
				disconnected = "Connect the desktop bridge", unavailable = "Update the desktop bridge" }
			detail = (labels[state.state] or "Check desktop connection") .. (free > 0 and (" / " .. free .. " free") or "")
			route, tone = "Cline / Text models / Desktop only", state.available and theme.color.success or theme.color.textSecondary
		elseif providers.isOpencodeZen(record) and bridge.opencodeStatus().available then
			detail = "Desktop CLI connected" .. (free > 0 and (" / " .. free .. " free") or "")
		elseif record.authStyle == "none" then
			detail = "No API key / " .. detail
		elseif providers.keyPoolSize(record) == 0 then
			detail, tone = "API key required / " .. detail, theme.color.warn
		end
		if record.enabled == false then detail, tone = "Disabled / " .. detail, theme.color.textDisabled
		elseif providers.keyPoolSize(record) > 0 and #providers.requestKeys(record) == 0 then
			detail, tone = "No active API key / " .. detail, theme.color.warn
		elseif providers.cooling(record) then detail, tone = env.require("provider/health").message(record) .. " / " .. detail, theme.color.warn end
		local admission = env.require("provider/availability").describe(record)
		if not admission.ready and admission.state ~= "disabled" and admission.state ~= "key-required" then
			detail, tone = admission.message, theme.color.warn
		end
		return { detail = detail, route = route, tone = tone }
	end

	function M.open(owner, onChange)
		if opened and not opened.closed then return opened end
		local target = M.target()
		local modal = overlay.modal({ title = "Switch provider", width = theme.size.modelPicker,
			height = M.preferredHeight(), minTarget = target, scroll = true })
		if not modal then return end
		opened = modal
		local rows, filter = {}, ""
		local count
		local function filterRows()
			local matches, visible = search.compile(filter), 0
			for _, entry in ipairs(rows) do
				entry.button.instance.Visible = matches(entry.search) ~= nil
				if entry.button.instance.Visible then visible = visible + 1 end
			end
			if count then
				count.Text = visible == #rows and util.pluralise(#rows, "saved connection")
					or string.format("%d of %d connections", visible, #rows)
			end
			local empty = modal.content:FindFirstChild("NoSavedProviderMatch")
			if empty then empty.Visible = visible == 0 end
		end
		P.field(modal.content, { name = "ProviderSwitchSearch", placeholder = "Search saved providers...", role = "small", height = target,
			layoutOrder = 1, onChange = function(text) filter = text; filterRows() end })
		count = P.text(modal.content, { name = "SavedProviderCount", text = "Your saved connections", role = "caption", color = theme.color.textTertiary, layoutOrder = 2 })
		local function render()
			if modal.closed then return end
			local previous = {}
			for _, entry in ipairs(rows) do previous[entry.id] = entry end
			rows = {}
			local active = providers.active()
			for index, record in ipairs(providers.list()) do
				local info = M.describe(record)
				local entry = previous[record.id]
				previous[record.id] = nil
				if not entry then
					local button = P.rowButton(modal.content, { name = "Option_" .. record.id,
						height = theme.text.small.height + theme.text.caption.height * 2 + theme.space.sm * 2 + theme.space.hair * 2,
						selected = active and active.id == record.id, bgSelected = theme.color.surfaceActive,
						bg = theme.color.surface, radius = theme.radius.md,
						stroke = true, strokeColor = theme.color.borderSubtle, padding = { x = theme.space.md }, gap = theme.space.sm,
						layoutOrder = index + 2, onClick = function()
							local ok, why = providers.setActive(record.id)
							if not ok then overlay.toast(why or "This provider is no longer available.", "warn"); return end
							modal.close(); if onChange then onChange() end
						end })
					local text = P.column(button.row, { name = "ProviderInfo", size = UDim2.new(0, 0, 0, 0), auto = "Y", flex = "Fill", gap = theme.space.hair })
					local name = P.text(text, { name = "ProviderName", text = record.label, role = "label", truncate = true,
						size = UDim2.new(1, 0, 0, theme.text.small.height), layoutOrder = 1 })
					local status = P.text(text, { name = "ProviderAvailability", text = info.detail, role = "caption", color = info.tone, truncate = true,
						size = UDim2.new(1, 0, 0, theme.text.caption.height), layoutOrder = 2 })
					local route = P.text(text, { name = "ProviderRoute", text = info.route, role = "caption", color = theme.color.textTertiary, truncate = true,
						size = UDim2.new(1, 0, 0, theme.text.caption.height), layoutOrder = 3 })
					local mark = button.icon("check", 3, theme.color.accentHot)
					entry = { id = record.id, button = button, name = name, status = status, route = route, mark = mark }
				end
				entry.name.Text, entry.status.Text, entry.status.TextColor3, entry.route.Text = record.label, info.detail, info.tone, info.route
				entry.mark.Visible = active and active.id == record.id or false
				entry.button.setSelected(entry.mark.Visible)
				entry.button.instance.LayoutOrder = index + 2
				entry.search = (record.label .. " " .. info.route .. " " .. info.detail):lower()
				rows[#rows + 1] = entry
			end
			for _, entry in pairs(previous) do entry.button.instance:Destroy() end
			filterRows()
		end
		P.text(modal.content, { name = "NoSavedProviderMatch", text = "No matching providers. Add a connection in Manage providers.",
			role = "small", color = theme.color.textTertiary, wrap = true, auto = "Y", layoutOrder = 10000 })
		M.sizeButton(P.button(modal.footer, { name = "ManageSavedProviders", text = "Manage providers", variant = "secondary", size = "sm",
			onClick = function() modal.close(); owner.close(); env.require("ui/app").show("providers") end }), target)
		local unsubscribe = providers.changed:connect(render)
		local unsubscribeBridge = bridge.changed:connect(render)
		local unsubscribeModels = models.changed:connect(render)
		local ownerClosed = owner.scrim.Destroying:Connect(function() if not modal.closed then modal.close() end end)
		modal.scrim.Destroying:Connect(function() unsubscribe(); unsubscribeBridge(); unsubscribeModels(); ownerClosed:Disconnect() end)
		render()
		return modal
	end
	return M
end
