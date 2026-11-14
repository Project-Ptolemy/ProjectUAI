-- The same declarative panels serve inert reviews and the active mod workspace.
-- Source reviews compile only; script execution belongs to the application controller.
return function(env)
	local util = env.require("runtime/util")
	local document = env.require("runtime/ui_mod_document")
	local mods = env.require("runtime/ui_mods")
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local M = {}
	local appearanceOrder = { "theme", "accent", "density", "fontScale", "interfaceFont", "codeFont", "codeTheme", "transcriptWidth" }
	local function label(parent, name, text, order, role, color)
		return P.text(parent, { name = name, text = text or "", role = role or "small", color = color,
			wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = order })
	end
	local function owned(parent, name, props)
		local root = P.column(parent, { name = name, auto = "Y", size = UDim2.new(1, 0, 0, 0),
			gap = theme.space.sm, layoutOrder = props and props.layoutOrder })
		local handle = { root = root, alive = true }
		root.Destroying:Connect(function() handle.alive = false end)
		function handle.destroy()
			if not handle.alive then return end
			handle.alive = false; root:Destroy()
		end
		return handle
	end
	local function metricText(value)
		if type(value) == "number" then
			if value ~= value or math.abs(value) > 9007199254740991 then return "Unavailable" end
			return util.formatNumber(value)
		end
		if type(value) ~= "string" or not util.validUtf8(value) then return "Unavailable" end
		return util.ellipsis(util.sanitise(value), 160)
	end
	function M.renderVisual(parent, spec, props)
		props = props or {}
		local handle = owned(parent, "UiModPanels", props)
		local clean, why = document.validate(spec)
		if not clean or clean.kind ~= "visual" then
			label(handle.root, "UiModPanelsError", why or "This mod does not declare visual panels.", 1, "small", theme.color.warn)
			function handle.refresh() end
			return handle
		end
		handle.spec, handle.panels = clean, {}
		local metrics, preview = {}, props.preview == true
		for order, panel in ipairs(clean.panels) do
			if not props.panelId or props.panelId == panel.id then
				local card = P.card(handle.root, { name = "UiModPanel_" .. panel.id, layoutOrder = order,
					gap = theme.space.sm, padding = theme.space.md })
				handle.panels[panel.id] = card
				label(card, "UiModPanelTitle_" .. panel.id, panel.title, 1, "bodyStrong")
				if panel.description ~= "" then label(card, "UiModPanelDescription_" .. panel.id, panel.description, 2, "caption", theme.color.textSecondary) end
				for index, widget in ipairs(panel.widgets) do
					local itemOrder = index + 2
					if widget.type == "text" then
						label(card, "UiModText_" .. widget.id, widget.body, itemOrder)
					elseif widget.type == "metric" then
						local group = P.column(card, { name = "UiModMetric_" .. widget.id, size = UDim2.new(1, 0, 0, 0),
							auto = "Y", gap = theme.space.hair, layoutOrder = itemOrder })
						label(group, "UiModMetricLabel_" .. widget.id, widget.label, 1, "caption", theme.color.textSecondary)
						local value = label(group, "UiModMetricValue_" .. widget.id,
							preview and ("Live " .. widget.selector .. " value when applied") or "Unavailable", 2, "monoSmall")
						metrics[#metrics + 1] = { selector = widget.selector, label = value }
					elseif widget.type == "action" then
						local action = widget.action
						P.button(card, { name = "UiModAction_" .. widget.id, text = widget.label, variant = "secondary",
							size = "sm", fill = true, layoutOrder = itemOrder, enabled = not preview and type(props.navigate) == "function",
							onClick = function()
								if handle.alive and not preview and type(props.navigate) == "function" then props.navigate(action) end
							end })
					end
				end
			end
		end
		function handle.refresh()
			if not handle.alive or preview then return end
			for _, item in ipairs(metrics) do
				local ok, value = false, nil
				if type(props.metric) == "function" then ok, value = pcall(props.metric, item.selector) end
				item.label.Text = ok and metricText(value) or "Unavailable"
			end
		end
		handle.refresh()
		return handle
	end
	function M.render(parent, record, props)
		props = props or {}
		local handle = owned(parent, "UiModPreview", props)
		handle.reviewComplete = false
		local clean, why = document.validate(type(record) == "table" and (record.spec or record) or nil)
		if not clean then
			handle.reviewReason = why or "This mod definition could not be displayed."
			label(handle.root, "UiModPreviewError", tostring(why), 1, "small", theme.color.warn)
			return handle
		end
		handle.reviewComplete = true
		handle.spec = clean
		local savedVersion = record.spec and record.version
		label(handle.root, "UiModPreviewIdentity", clean.name .. " / " .. clean.id
			.. (savedVersion and (" / saved version " .. tostring(savedVersion)) or " / draft"), 1, "bodyStrong")
		if clean.description ~= "" then label(handle.root, "UiModPreviewDescription", clean.description, 2) end
		local sources = { "Source: " .. tostring(props.sourceLabel or "Portable UI mod definition") }
		if clean.author then sources[#sources + 1] = "Author: " .. clean.author end
		for _, source in ipairs(clean.sources) do sources[#sources + 1] = source.label .. (source.url and (" / " .. source.url) or "") end
		label(handle.root, "UiModPreviewSources", table.concat(sources, "\n"), 3, "caption", theme.color.textSecondary)
		if clean.kind == "script" then
			label(handle.root, "UiModPreviewScope", "This Lua source runs with the executor's permissions. It receives the full client environment and an owned scope, and can access the game, client, files and network. Disable releases registered resources and supplied cleanup; external changes and native work may remain.", 4)
			local called, compiled, reason, diagnostic = pcall(mods.checkScript, clean)
			local check = type(diagnostic) == "table" and util.copy(diagnostic) or { compilerAvailable = false, executed = false }
			check.ok = called and compiled == true
			check.error = reason or check.error or (not called and "The compile check stopped unexpectedly." or nil)
			handle.check = check
			local result = check.ok and "Compile check passed. Source has not run."
				or (check.compilerAvailable == false and "Compile check unavailable: " or "Compile check failed: ") .. tostring(check.error or "Unknown compiler result")
			label(handle.root, "UiModCompileResult", result, 5, "caption", check.ok and theme.color.textSecondary or theme.color.warn)
			local sourceLabel = label(handle.root, "UiModSourceLabel", "Complete Lua source / " .. tostring(#clean.source) .. " bytes", 6, "label")
			handle.source = P.field(handle.root, { name = "UiModPreviewSource", text = clean.source, multiline = true,
				height = theme.size.controlLarge * 6, role = "mono", syntax = false, readOnly = true, layoutOrder = 7 })
			local retained, shown = pcall(handle.source.get)
			handle.reviewComplete = retained and shown == clean.source
			if not handle.reviewComplete then
				handle.reviewReason = "This host changed or shortened the displayed source. Export the complete Lua source for inspection; Apply uses the exact saved revision."
				sourceLabel.Text = "Lua source / " .. tostring(#clean.source) .. " original bytes / incomplete native display"
				label(handle.root, "UiModReviewIncomplete", handle.reviewReason, 9, "caption", theme.color.warn)
			end
			P.button(handle.root, { name = "UiModSelectSource", text = "Select source", variant = "ghost", size = "sm",
				layoutOrder = 8, onClick = function() if handle.alive then handle.source.selectAll() end end })
		else
			label(handle.root, "UiModPreviewScope", "Preview only. Appearance preferences apply inside Project UAI. Panel actions open the named client pages after Apply.", 4, "caption", theme.color.textSecondary)
			local appearance = {}
			for _, key in ipairs(appearanceOrder) do if clean.appearance[key] ~= nil then appearance[#appearance + 1] = key .. ": " .. tostring(clean.appearance[key]) end end
			label(handle.root, "UiModPreviewAppearance", #appearance > 0 and ("Requested appearance\n" .. table.concat(appearance, "\n")) or "No appearance overrides.", 5, "caption", theme.color.textSecondary)
			handle.visual = M.renderVisual(handle.root, clean, { preview = true, layoutOrder = 6 })
		end
		return handle
	end
	return M
end
