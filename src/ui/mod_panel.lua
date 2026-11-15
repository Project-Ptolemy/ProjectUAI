-- Native mod controls share the application's sections, fields and control rows.
-- The runtime model owns values/callbacks, so remounting retains domain state.
return function(env)
	local models = env.require("runtime/ui_mod_panels")
	local clock = env.require("runtime/clock")
	local P = env.require("ui/primitives")
	local C = env.require("ui/controls")
	local R = env.require("ui/settingsrows")
	local theme = env.require("ui/theme")
	local overlay = env.require("ui/overlay")
	local M = {}
	local function label(parent, name, value, role, order)
		return P.text(parent, { name = name, text = value or "", role = role or "small", wrap = true,
			auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = order })
	end
	function M.new(parent, key)
		local snapshot = models.snapshot(key)
		if not snapshot then return nil end
		local root = P.column(parent, { name = "UiModNativePanel_" .. snapshot.id, size = UDim2.new(1, 0, 0, 0), auto = "Y", gap = theme.space.md })
		local handle = { root = root, alive = true, revision = snapshot.revision }
		local controls, painting, visible = {}, false, true
		label(root, "UiModNativeTitle", snapshot.title, "heading", 1)
		if snapshot.description ~= "" then label(root, "UiModNativeDescription", snapshot.description, "caption", 2) end
		local function retainedValue(controlId)
			local current = models.snapshot(key)
			if not current then return nil end
			for _, section in ipairs(current.sections) do
				for _, item in ipairs(section.controls) do
					if item.id == controlId then return item.value end
				end
			end
		end
		local function trigger(controlId, value)
			if handle.alive and visible and not painting then
				-- Deferred TextChanged signals can arrive after a silent model repaint.
				local entry = controls[controlId]
				if entry and entry.kind == "input" and value == retainedValue(controlId) then return end
				local ok = models.trigger(key, controlId, value)
				if not ok and handle.refresh then handle.refresh() end
			end
		end
		for index, section in ipairs(snapshot.sections) do
			local card = R.section(root, { name = "UiModNativeSection_" .. section.id,
				title = section.title, description = section.description ~= "" and section.description or nil, layoutOrder = index + 2 })
			for position, item in ipairs(section.controls) do
				local controlId, itemKind = item.id, item.kind
				local entry = { kind = itemKind, retainedValue = item.value }
				controls[controlId] = entry
				if itemKind == "text" then
					entry.label = label(card, "UiModNativeText_" .. controlId, item.value, "small", position)
				elseif itemKind == "button" then
					entry.control = P.button(card, { name = "UiModNativeButton_" .. controlId, text = item.value,
						variant = "secondary", fill = true, size = "sm", layoutOrder = position, enabled = item.enabled,
						onClick = function() trigger(controlId) end })
				elseif itemKind == "toggle" then
					entry.control = R.toggle(card, { name = "UiModNativeToggleRow_" .. controlId, label = item.text,
						hint = item.hint ~= "" and item.hint or nil, value = item.value, layoutOrder = position,
						onChange = function(value) trigger(controlId, value) end })
					entry.control.instance.Name = "UiModNativeToggle_" .. controlId
				else
					local column = P.column(card, { name = "UiModNativeControl_" .. controlId,
						size = UDim2.new(1, 0, 0, 0), auto = "Y", gap = theme.space.xs, layoutOrder = position })
					label(column, "UiModNativeLabel_" .. controlId, item.text, "label", 1)
					if item.hint ~= "" then label(column, "UiModNativeHint_" .. controlId, item.hint, "caption", 2) end
					if itemKind == "input" then
						entry.control = P.field(column, { name = "UiModNativeInput_" .. controlId,
							text = item.value, placeholder = item.placeholder, multiline = item.multiline,
							height = item.multiline and theme.size.controlLarge * 3 or nil, syntax = false, layoutOrder = 3,
							onChange = function(value) trigger(controlId, value) end })
					elseif itemKind == "select" then
						entry.options = item.options
						local function choose(button)
							if not handle.alive or not visible then return end
							local current = models.snapshot(key)
							if not current then return end
							local options = {}
							for _, option in ipairs(entry.options) do
								options[#options + 1] = { label = option.label, value = option.value }
							end
							if entry.menu and entry.menu.close then entry.menu.close() end
							entry.menu = overlay.menu({ target = button.instance, options = options, onSelect = function(value)
								if handle.alive then trigger(controlId, value) end
							end })
						end
						entry.control = P.button(column, { name = "UiModNativeSelect_" .. controlId, text = item.value,
							variant = "secondary", fill = true, size = "sm", layoutOrder = 3, onClick = choose })
					elseif itemKind == "slider" then
						entry.value = label(column, "UiModNativeValue_" .. controlId, tostring(item.value), "monoSmall", 3)
						entry.control = C.slider(column, { name = "UiModNativeSlider_" .. controlId,
							min = item.min, max = item.max, step = item.step, value = item.value, layoutOrder = 4,
							onChange = function(value) if handle.alive then entry.value.Text = tostring(value) end end,
							onCommit = function(value) trigger(controlId, value) end })
					end
				end
			end
		end
		function handle.refresh(resetDrafts)
			if not handle.alive or not visible then return end
			local current = models.snapshot(key)
			if not current or current.revision ~= handle.revision then return end
			painting = true
			for _, section in ipairs(current.sections) do
				for _, item in ipairs(section.controls) do
					local entry = controls[item.id]
					if entry.label then entry.label.Text = item.value
					elseif entry.kind == "button" then entry.control.setText(item.value); entry.control.setBusy(item.busy == true)
					elseif entry.kind == "input" then if entry.control.get() ~= item.value then entry.control.set(item.value) end
					elseif entry.kind == "select" then
						for _, option in ipairs(entry.options) do if option.value == item.value then entry.control.setText(option.label); break end end
					elseif entry.kind == "slider" then
						-- A live gesture is a draft until commit; unrelated values do not reset it.
						if resetDrafts or entry.retainedValue ~= item.value then
							entry.control.set(item.value, true)
							entry.value.Text = tostring(item.value)
						end
						entry.retainedValue = item.value
					else
						entry.control.set(item.value, true)
					end
					if entry.control then entry.control.setEnabled(item.enabled and not item.busy) end
					if item.error and entry.error ~= item.error then overlay.toast(item.error, "warn", 5) end
					entry.error = item.error
				end
			end
			painting = false
		end
		local refresh, cancel = clock.debounce(handle.refresh, 0.05)
		local release = models.changed:connect(function(changedKey, kind)
			if changedKey == key and kind == "value" and handle.alive and visible then refresh() end
		end)
		function handle.setVisible(value)
			if not handle.alive then return end
			local reopening = value == true and not visible
			visible = value == true
			if visible then handle.refresh(reopening)
			else
				cancel()
				for _, entry in pairs(controls) do if entry.menu and entry.menu.close then entry.menu.close() end end
			end
		end
		function handle.destroy()
			if not handle.alive then return end
			handle.alive = false; release(); cancel()
			for _, entry in pairs(controls) do if entry.menu and entry.menu.close then entry.menu.close() end end
			root:Destroy()
		end
		root.Destroying:Connect(handle.destroy)
		handle.refresh()
		return handle
	end
	return M
end
