-- Declarative native mod panels retain domain state independently of GUI mounts.
-- Presentation subscribes to changes; this module creates no Roblox instances.
return function(env)
	local util = env.require("runtime/util")
	local signal = env.require("runtime/signal")
	local dispose = env.require("runtime/dispose")
	local document = env.require("runtime/ui_mod_document")
	local M = { changed = signal.new("ui_mod_panels"), limits = { panels = 4, sections = 8, controls = 32, options = 32, text = 4000, input = 8000 } }
	local records, order, alive = {}, {}, true
	local function id(value)
		return document.validId(value)
	end
	local function text(value, maximum, required)
		if value == nil and not required then return "" end
		if type(value) ~= "string" or #value > maximum or not util.validUtf8(value)
			or value:find("[%z\1-\8\11\12\14-\31\127]") or required and util.trim(value) == "" then return nil end
		return value
	end
	local function finite(value)
		return type(value) == "number" and value == value and math.abs(value) <= 1000000000
	end
	local function fields(options, allowed)
		if type(options) ~= "table" then return false end
		for key in pairs(options) do if not allowed[key] then return false end end
		return true
	end
	local function array(value, maximum)
		if type(value) ~= "table" or #value > maximum then return false end
		local count = 0
		for key in pairs(value) do
			count = count + 1
			if count > maximum or type(key) ~= "number" or key ~= math.floor(key) or key < 1 or key > #value then return false end
		end
		return count == #value
	end
	local panelFields = { id = true, title = true, description = true }
	local controlFields = { id = true, text = true, hint = true, value = true, callback = true, enabled = true,
		placeholder = true, multiline = true, options = true, min = true, max = true, step = true }
	local function active(record)
		return alive and record.alive and (not record.gate or record.gate())
	end
	local function changed(record, kind, control)
		if record.alive then M.changed:fire(record.key, kind, control and control.id) end
	end
	local function validateValue(control, value)
		if control.kind == "text" then if type(value) == "string" then return text(value, M.limits.text) end; return nil end
		if control.kind == "button" then if document.validLabel(value, 100) then return value end; return nil end
		if control.kind == "toggle" then if type(value) == "boolean" then return value end; return nil end
		if control.kind == "input" then if type(value) == "string" then return text(value, M.limits.input) end; return nil end
		if control.kind == "select" then
			for _, item in ipairs(control.options) do if value == item.value then return value end end
			return nil
		end
		if control.kind == "slider" and finite(value) then
			value = util.clamp(value, control.min, control.max)
			if control.step then value = util.clamp(control.min + math.floor((value - control.min) / control.step + 0.5) * control.step, control.min, control.max) end
			return value
		end
	end
	local function invoke(record, control, value)
		if not active(record) or not control.enabled or control.busy then return nil, "This mod control is unavailable" end
		if not control.callback then return true end
		control.busy = true; changed(record, "value", control)
		local ok, why = pcall(record.invoke, control.callback, value, control.handle)
		control.busy = false
		if active(record) then
			control.error = not ok and "This action failed. Review the mod source before trying again." or nil
			changed(record, "value", control)
		end
		return ok or nil, not ok and tostring(why) or nil
	end
	local function controlHandle(record, control)
		local handle = { id = control.id }
		function handle:Get() return control.value end
		function handle:Set(value, notify)
			if not active(record) then return nil, "The mod panel is closed" end
			local clean = validateValue(control, value)
			if clean == nil then return nil, "This value is invalid for the control" end
			control.value = clean
			changed(record, "value", control)
			if notify == true then return invoke(record, control, clean) end
			return true
		end
		function handle:SetEnabled(value)
			if not active(record) then return nil, "The mod panel is closed" end
			if type(value) ~= "boolean" then return nil, "Enabled must be a boolean" end
			control.enabled = value; changed(record, "value", control); return true
		end
		function handle:Activate() return invoke(record, control, control.value) end
		control.handle = handle
		return handle
	end
	function M.create(options, owner)
		if not alive then return nil, "The client is unloaded" end
		if not fields(options, panelFields) or not id(options.id) then return nil, "A native panel needs a stable lowercase ASCII id, title and optional description" end
		local title, description = text(options.title, 100, true), text(options.description, 500)
		if not title or not description or not document.validLabel(title, 100) then return nil, "The native panel title or description is invalid" end
		if type(owner) ~= "table" or not id(owner.id) or type(owner.invoke) ~= "function" then return nil, "A live mod owner is required" end
		local key = owner.id .. ":" .. options.id
		if records[key] then return nil, "This mod panel id is already registered" end
		if #order >= M.limits.panels then return nil, "A mod can register at most four native panels" end
		local record = { key = key, id = options.id, ownerId = owner.id, title = title, description = description,
			sections = {}, controls = {}, ids = {}, count = 0, revision = 0, alive = true,
			gate = owner.gate, invoke = owner.invoke, show = owner.show }
		local panel = { id = options.id, key = key }
		record.handle = panel
		function panel:IsAlive() return active(record) end
		function panel:Get(controlId) return record.controls[controlId] and record.controls[controlId].handle end
		function panel:Show()
			if not active(record) or type(record.show) ~= "function" then return nil, "The native mod workspace is unavailable" end
			return record.show(key)
		end
		function panel:Destroy()
			if not record.alive then return end
			record.alive = false; records[key] = nil
			for index, item in ipairs(order) do if item == key then table.remove(order, index); break end end
			for _, control in pairs(record.controls) do control.callback = nil end
			record.gate, record.invoke, record.show = nil, nil, nil
			M.changed:fire(key, "structure")
		end
		panel.destroy = panel.Destroy
		function panel:Section(props)
			if not active(record) then return nil, "The mod panel is closed" end
			if not fields(props, panelFields) or not id(props.id) or record.ids[props.id] then return nil, "A section needs a unique stable id" end
			if #record.sections >= M.limits.sections then return nil, "A native panel can contain at most eight sections" end
			local sectionTitle, sectionDescription = text(props.title, 100, true), text(props.description, 500)
			if not sectionTitle or not sectionDescription or not document.validLabel(sectionTitle, 100) then return nil, "The section title or description is invalid" end
			local section = { id = props.id, title = sectionTitle, description = sectionDescription, controls = {} }
			local sectionHandle = { id = props.id }
			local function add(kind, controlOptions)
				if not active(record) then return nil, "The mod panel is closed" end
				if not fields(controlOptions, controlFields) or not id(controlOptions.id) or record.ids[controlOptions.id] then return nil, "A control needs a unique stable id and supported options" end
				if record.count >= M.limits.controls then return nil, "A native panel can contain at most 32 controls" end
				local caption = text(controlOptions.text, kind == "text" and M.limits.text or 100, kind ~= "text")
				local hint = text(controlOptions.hint, 500)
				if not caption or not hint or kind ~= "text" and not document.validLabel(caption, 100)
					or controlOptions.callback ~= nil and type(controlOptions.callback) ~= "function"
					or controlOptions.enabled ~= nil and type(controlOptions.enabled) ~= "boolean" then return nil, "The control text, callback or enabled state is invalid" end
				local control = { id = controlOptions.id, kind = kind, text = caption, hint = hint,
					callback = controlOptions.callback, enabled = controlOptions.enabled ~= false }
				if kind == "input" then
					control.placeholder = text(controlOptions.placeholder, 100)
					if not control.placeholder or controlOptions.multiline ~= nil and type(controlOptions.multiline) ~= "boolean" then return nil, "The input options are invalid" end
					control.multiline = controlOptions.multiline == true
				elseif kind == "select" then
					if not array(controlOptions.options, M.limits.options) or #controlOptions.options < 1 then return nil, "Select needs 1-32 options" end
					control.options = {}
					local values = {}
					for index, item in ipairs(controlOptions.options) do
						if not fields(item, { value = true, label = true }) then return nil, "Each select option needs a value and label" end
						local optionValue, optionLabel = text(item.value, 100, true), text(item.label, 100, true)
						if not optionValue or not optionLabel or not document.validLabel(optionLabel, 100) or values[optionValue] then return nil, "Select values must be distinct nonblank text" end
						values[optionValue] = true; control.options[index] = { value = optionValue, label = optionLabel }
					end
				elseif kind == "slider" then
					if not finite(controlOptions.min) or not finite(controlOptions.max) or controlOptions.max <= controlOptions.min
						or controlOptions.step ~= nil and (not finite(controlOptions.step) or controlOptions.step <= 0
							or controlOptions.step < (controlOptions.max - controlOptions.min) / 1000000000) then return nil, "Slider needs finite increasing bounds and an optional usable positive step" end
					control.min, control.max, control.step = controlOptions.min, controlOptions.max, controlOptions.step
				end
				local initial = controlOptions.value
				if initial == nil then
					if kind == "toggle" then initial = false
					elseif kind == "input" then initial = ""
					elseif kind == "select" then initial = control.options[1].value
					elseif kind == "slider" then initial = control.min
					else initial = caption end
				end
				control.value = validateValue(control, initial)
				if control.value == nil then return nil, "The initial control value is invalid" end
				local handle = controlHandle(record, control)
				record.ids[control.id], record.controls[control.id] = true, control
				section.controls[#section.controls + 1] = control
				record.count = record.count + 1; record.revision = record.revision + 1
				changed(record, "structure")
				return handle
			end
			function sectionHandle:Text(props) return add("text", props) end
			function sectionHandle:Button(props) return add("button", props) end
			function sectionHandle:Toggle(props) return add("toggle", props) end
			function sectionHandle:Input(props) return add("input", props) end
			function sectionHandle:Select(props) return add("select", props) end
			function sectionHandle:Slider(props) return add("slider", props) end
			record.sections[#record.sections + 1] = section; record.ids[section.id] = true
			record.revision = record.revision + 1; changed(record, "structure")
			return sectionHandle
		end
		records[key] = record; order[#order + 1] = key
		M.changed:fire(key, "structure")
		return panel
	end
	function M.list(ownerId)
		local items = {}
		for _, key in ipairs(order) do
			local record = records[key]
			if record and active(record) and (not ownerId or record.ownerId == ownerId) then
				items[#items + 1] = { key = key, id = record.id, title = record.title, revision = record.revision }
			end
		end
		return items
	end
	function M.snapshot(key)
		local record = records[key]
		if not record or not active(record) then return nil end
		local result = { key = key, id = record.id, title = record.title, description = record.description, revision = record.revision, sections = {} }
		for index, section in ipairs(record.sections) do
			local group = { id = section.id, title = section.title, description = section.description, controls = {} }
			for position, control in ipairs(section.controls) do
				local options
				if control.options then
					options = {}
					for optionIndex, option in ipairs(control.options) do options[optionIndex] = { value = option.value, label = option.label } end
				end
				group.controls[position] = { id = control.id, kind = control.kind, text = control.text, hint = control.hint,
					value = control.value, enabled = control.enabled, busy = control.busy, error = control.error,
					placeholder = control.placeholder, multiline = control.multiline,
					options = options, min = control.min, max = control.max, step = control.step }
			end
			result.sections[index] = group
		end
		return result
	end
	function M.trigger(key, controlId, value)
		local record = records[key]
		local control = record and record.controls[controlId]
		if not record or not control or not active(record) or not control.enabled or control.busy then return nil, "This mod control is unavailable" end
		if control.kind == "button" then return invoke(record, control, control.value) end
		return control.handle:Set(value, true)
	end
	dispose.add(function()
		alive = false
		local pending = {}; for _, key in ipairs(order) do pending[#pending + 1] = records[key].handle end
		for _, panel in ipairs(pending) do panel:Destroy() end
		M.changed:clear()
	end, "native mod panels")
	return M
end
