-- A host's tools, hooks and subscriptions share one explicit client lifetime.
return function(env)
	local util = env.require("runtime/util")
	local log = env.require("runtime/log")
	local dispose = env.require("runtime/dispose")
	local tools = env.require("agent/registry")
	local hooks = env.require("agent/hooks")
	local M = {}
	local owners = setmetatable({}, { __mode = "k" })
	local TYPES = { object = true, array = true, string = true, number = true, integer = true, boolean = true, null = true }

	local function finite(value)
		return type(value) == "number" and value == value and math.abs(value) ~= math.huge
	end

	local function identifier(value)
		return type(value) == "string" and #value > 0 and #value <= 64 and value:match("^[%w_%-]+$") ~= nil
	end

	local function array(value, strings)
		if type(value) ~= "table" then return false end
		local count = 0
		for key, item in pairs(value) do
			if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then return false end
			if strings and (type(item) ~= "string" or util.trim(item) == "") then return false end
			count = count + 1
		end
		return count == #value
	end

	-- Copy JSON-shaped data without metatables, cycles or arbitrary host objects.
	-- Bounds also keep a malformed schema from overflowing the Lua stack.
	local function copyData(value, ancestors, state, depth)
		local kind = type(value)
		if kind ~= "table" then
			if kind == "string" or kind == "boolean" or (kind == "number" and finite(value)) then return value end
			error("parameters must contain only finite JSON data", 0)
		end
		if depth > 32 or state.nodes >= 8192 then error("parameters exceed the schema size/depth limit", 0) end
		if ancestors[value] then error("parameters must not contain cycles", 0) end
		ancestors[value] = true
		local out = {}
		for key, child in pairs(value) do
			state.nodes = state.nodes + 1
			if state.nodes > 8192 then error("parameters exceed the schema size/depth limit", 0) end
			if type(key) ~= "string" and not (finite(key) and key >= 1 and key == math.floor(key)) then
				error("parameters contain an invalid table key", 0)
			end
			out[key] = copyData(child, ancestors, state, depth + 1)
		end
		ancestors[value] = nil
		return out
	end

	local function validateSchema(schema)
		if type(schema) ~= "table" then return false, "each parameter schema must be a table" end
		if schema.type ~= nil then
			if type(schema.type) == "table" then
				if not array(schema.type, true) or #schema.type == 0 then return false, "schema type must name supported JSON types" end
				for _, kind in ipairs(schema.type) do if not TYPES[kind] then return false, "unsupported schema type" end end
			elseif not TYPES[schema.type] then return false, "unsupported schema type" end
		end
		if schema.required ~= nil and not array(schema.required, true) then return false, "schema required must be an array of names" end
		if schema.enum ~= nil and not array(schema.enum) then return false, "schema enum must be an array" end
		for _, key in ipairs({ "minimum", "maximum", "minLength", "maxLength", "minItems", "maxItems" }) do
			if schema[key] ~= nil and not finite(schema[key]) then return false, "schema " .. key .. " must be a finite number" end
		end
		if schema.properties ~= nil then
			if type(schema.properties) ~= "table" then return false, "schema properties must be a table" end
			if not util.isEmptyObject(schema.properties) then
				for key, child in pairs(schema.properties) do
					if type(key) ~= "string" then return false, "schema property names must be strings" end
					local ok, why = validateSchema(child)
					if not ok then return false, why end
				end
			end
		end
		if schema.items ~= nil then return validateSchema(schema.items) end
		return true
	end

	local function definition(input)
		if type(input) ~= "table" then return nil, "tool definition must be a table" end
		if not identifier(input.name) then return nil, "tool name must use 1-64 letters, digits, underscores or hyphens" end
		if input.group ~= nil and not identifier(input.group) then return nil, "tool group must use 1-64 letters, digits, underscores or hyphens" end
		if input.risk ~= nil and input.risk ~= "read" and input.risk ~= "write" and input.risk ~= "danger" then return nil, "tool risk must be read, write or danger" end
		if type(input.description) ~= "string" or util.trim(input.description) == "" then return nil, "tool description must be a nonempty string" end
		if type(input.run) ~= "function" then return nil, "tool run must be a function" end
		if input.prepare ~= nil and type(input.prepare) ~= "function" then return nil, "tool prepare must be a function" end
		if input.timeout ~= nil and type(input.timeout) ~= "function" and not (finite(input.timeout) and input.timeout > 0) then return nil, "tool timeout must be a positive finite number or function" end
		if input.needs ~= nil and not array(input.needs, true) then return nil, "tool needs must be an array of capability names" end
		local parameters = input.parameters
		if parameters == nil then parameters = { type = "object", properties = {}, required = {} } end
		if type(parameters) ~= "table" or parameters.type ~= "object" then return nil, "tool parameters must be an object schema" end
		local copied, schema = pcall(copyData, parameters, {}, { nodes = 0 }, 0)
		if not copied then return nil, tostring(schema) end
		local valid, why = validateSchema(schema)
		if not valid then return nil, why end
		local needs = {}
		for index, key in ipairs(input.needs or {}) do needs[index] = key end
		return {
			name = input.name, group = input.group or "misc", risk = input.risk or "write",
			description = input.description, parameters = schema, needs = needs,
			run = input.run, prepare = input.prepare, timeout = input.timeout,
		}
	end

	local function member(object, key)
		local ok, value = pcall(function() return object[key] end)
		if ok and type(value) == "function" then return value end
		return nil
	end

	function M.create(handle, id)
		if type(handle) ~= "table" or handle.alive ~= true then return nil, "client is unloaded" end
		if type(id) ~= "string" or util.trim(id) == "" or #id > 128 then return nil, "scope id must be a nonempty string of at most 128 bytes" end
		if dispose.draining then return nil, "client is unloading" end
		local owned = owners[handle]
		if not owned then owned = {}; owners[handle] = owned end
		if owned[id] then return nil, "scope id is already in use: " .. id end
		local scope = { id = id, alive = true }
		local entries, closed, removeFromClient = {}, false, nil
		owned[id] = scope

		local function active()
			return not closed and handle.alive == true and not dispose.draining
		end

		local function invoke(fn)
			local ok, err = pcall(fn)
			if not ok then log.warn("embedding", "scope " .. id .. " cleanup failed", err) end
		end

		function scope.give(fn)
			if type(fn) ~= "function" then return nil, "cleanup must be a function" end
			if not active() then invoke(fn); return nil, "scope is destroyed or client is unloaded" end
			local entry = { fn = fn }
			local function release()
				local cleanup = entry.fn
				if not cleanup then return false end
				entry.fn = nil
				for index, candidate in ipairs(entries) do
					if candidate == entry then table.remove(entries, index); break end
				end
				invoke(cleanup)
				return true
			end
			entry.release = release
			entries[#entries + 1] = entry
			return release
		end

		function scope.connect(signal, fn)
			if not active() then return nil, "scope is destroyed or client is unloaded" end
			if type(fn) ~= "function" then return nil, "signal callback must be a function" end
			local connect = member(signal, "Connect") or member(signal, "connect")
			if not connect then return nil, "signal must provide Connect or connect" end
			local callback = fn
			local ok, connection = pcall(connect, signal, function(...)
				if not active() or not callback then return end
				local called, err = pcall(callback, ...)
				if not called then log.warn("embedding", "scope " .. id .. " signal callback failed", err) end
			end)
			if not ok then callback = nil; return nil, tostring(connection) end
			local disconnect
			if type(connection) == "function" then disconnect = connection
			else
				local method = member(connection, "Disconnect") or member(connection, "disconnect")
				if method then disconnect = function() method(connection) end end
			end
			if not disconnect then callback = nil; return nil, "signal did not return an unsubscribe function or connection" end
			return scope.give(function() callback = nil; disconnect() end)
		end

		function scope.hook(kind, fn, opts)
			if not active() then return nil, "scope is destroyed or client is unloaded" end
			local ok, off, why = pcall(hooks.register, kind, fn, opts)
			if not ok then return nil, tostring(off) end
			if why then return nil, why end
			return scope.give(off)
		end

		function scope.registerTool(input)
			if not active() then return false, "scope is destroyed or client is unloaded" end
			local checked, tool, why = pcall(definition, input)
			if not checked then return false, tostring(tool) end
			if not tool then return false, why end
			tools.load()
			if not tools.register(tool) then return false, "tool name is already registered: " .. tool.name end
			local release, reason = scope.give(function() tools.unregister(tool.name, tool) end)
			if not release then return false, reason end
			return true, release
		end

		function scope.destroy()
			if closed then return 0 end
			closed, scope.alive = true, false
			owned[id] = nil
			local cleanup = removeFromClient
			removeFromClient = nil
			if cleanup then cleanup() end
			local pending = entries
			entries = {}
			local count = 0
			for index = #pending, 1, -1 do
				if pending[index].release() then count = count + 1 end
			end
			return count
		end

		removeFromClient = dispose.add(scope.destroy, "embedding scope " .. id)
		return scope
	end

	return M
end
