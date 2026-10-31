return function(env)
	local C = env.require("core")
	local M = {}
	local function array(value)
		if type(value) ~= "table" then return false end
		local count = 0
		for key in pairs(value) do
			if type(key) ~= "number" or key < 1 or key > #value or key ~= math.floor(key) then return false end
			count = count + 1
		end
		return count == #value
	end
	local function controls(window, options)
		assert(window.Alive, "Window is destroyed")
		options = options or {}
		assert(type(options) == "table", "Value options must be a table")
		for _, name in ipairs({ "PersistOnly", "Silent", "FocusInvalid" }) do
			assert(options[name] == nil or type(options[name]) == "boolean", name .. " must be a boolean")
		end
		local ids, seen, selected = options.Ids, {}, {}
		if ids ~= nil then
			assert(array(ids), "Ids must be an array")
			for _, id in ipairs(ids) do
				assert(type(id) == "string" and window.Controls[id] and window.Controls[id]._normalize, "Unknown value control Id: " .. tostring(id))
				assert(not seen[id], "Duplicate control Id: " .. id)
				seen[id] = true
			end
		end
		for id, control in pairs(window.Controls) do
			if control._normalize and id:sub(1, 17) ~= "__uai_appearance_" and (not ids or seen[id]) and (not options.PersistOnly or control.Persist) then
				selected[#selected + 1] = control
			end
		end
		table.sort(selected, function(a, b) return a.Id < b.Id end)
		return selected
	end
	M.controls = controls
	local function apply(window, pending, silent)
		local releases = {}
		for _, item in ipairs(pending) do
			if item.control._restore then
				local release = item.control._restore(C.copy(item.value))
				if release then releases[#releases + 1] = release end
			else
				item.control._value = C.copy(item.value)
				if item.control._render then item.control._render() end
			end
		end
		for _, release in ipairs(releases) do release() end
		if silent == false then
			for _, item in ipairs(pending) do if item.changed and item.control.Alive and window.Alive then item.control:_Emit() end end
		end
		return true, #pending
	end
	function M.GetValues(window, options)
		local result = {}
		for _, control in ipairs(controls(window, options)) do result[control.Id] = C.copy(control._value) end
		return result
	end
	function M.InspectValues(window, options)
		local result = {}
		for _, control in ipairs(controls(window, options)) do
			local valid, message = true, nil
			if control._validateValue then valid, message = control._validateValue(control._value) end
			result[#result + 1] = { Id = control.Id, Kind = control.Kind, Value = C.copy(control._value), Default = C.copy(control._default),
				Changed = not C.equal(control._value, control._default), Persist = control.Persist, Visible = control.Visible,
				Disabled = control.Disabled, Valid = valid, Message = message }
		end
		return result
	end
	function M.SetValues(window, values, options)
		if not window.Alive then return false, "Window is destroyed" end
		options = options or {}
		if type(values) ~= "table" or type(options) ~= "table" then return false, "Values and options must be tables" end
		if options.Silent ~= nil and type(options.Silent) ~= "boolean" then return false, "Silent must be a boolean" end
		local pending, included = {}, {}
		local function add(id, value)
			local control = window.Controls[id]
			if type(id) ~= "string" or not control or not control._normalize or id:sub(1, 17) == "__uai_appearance_" then return false, "Unknown value control: " .. tostring(id) end
			if included[id] then return false, "Value is both supplied and cleared: " .. id end
			local valid, normalized = pcall(function() return control._normalize(C.copy(value)) end)
			if not valid then return false, "Invalid value for " .. id .. ": " .. tostring(normalized) end
			pending[#pending + 1] = { control = control, value = normalized, changed = not C.equal(control._value, normalized) }
			included[id] = true
			return true
		end
		for id, value in pairs(values) do local ok, why = add(id, value); if not ok then return false, why end end
		if options.Clear ~= nil then
			if not array(options.Clear) then return false, "Clear must be an array of control Ids" end
			for _, id in ipairs(options.Clear) do local ok, why = add(id, nil); if not ok then return false, why end end
		end
		table.sort(pending, function(a, b) return a.control.Id < b.control.Id end)
		return apply(window, pending, options.Silent)
	end
	function M.ResetValues(window, options)
		if not window.Alive then return false, "Window is destroyed" end
		local ok, selected = pcall(controls, window, options)
		if not ok then return false, tostring(selected) end
		local pending = {}
		for _, control in ipairs(selected) do
			local valid, normalized = pcall(control._normalizeDefault or control._normalize, C.copy(control._default))
			if not valid then return false, "Default is no longer valid for " .. control.Id end
			pending[#pending + 1] = { control = control, value = normalized, changed = not C.equal(control._value, normalized) }
		end
		return apply(window, pending, not options or options.Silent ~= false)
	end
	function M.CommitInputs(window, options)
		if not window.Alive then return false, "Window is destroyed" end
		local ok, selected = pcall(controls, window, options)
		if not ok then return false, tostring(selected) end
		local values, errors, first = {}, {}, nil
		for _, control in ipairs(selected) do
			if control._readDraft then
				local valid, value = control:_readDraft()
				if valid then control:_showValidation(nil) else control:_showValidation(value) end
				if valid then values[control.Id] = value else errors[control.Id], first = value, first or control end
			end
		end
		if first then
			if options and options.FocusInvalid then window:Reveal(first.Id); first:Focus() end
			return false, errors
		end
		return M.SetValues(window, values, { Silent = not options or options.Silent ~= false })
	end
	return M
end
