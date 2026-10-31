-- Background measurements for included Free access. Synthetic probes never carry
-- a conversation or execute a tool. User requests are never raced or replayed.
return function(env)
	local util = env.require("runtime/util")
	local config = env.require("runtime/config")
	local clock = env.require("runtime/clock")
	local registry = env.require("provider/registry")
	local community = env.require("provider/community_key")
	local transport = env.require("net/transport")
	local http = env.require("net/http")
	local sse = env.require("net/sse")
	local traits = env.require("provider/traits")
	local signal = env.require("runtime/signal")
	local M = { changed = signal.new("free route") }
	local states = setmetatable({}, { __mode = "k" })
	local owners = setmetatable({}, { __mode = "k" })
	local alive = true
	local TTL, TARGET, MAX_MODELS = 10 * 60 * 1000, 10000, 32
	local LESSONS = { "maxTokensCap", "toolsCap", "repairs", "repairScope" }

	local function eligibleRecord(record)
		return alive and community.isApplied(record) and record.model == "auto" and record.enabled ~= false
			and (record.api or "openai") == "openai" and util.trim(record.wsUrl) == ""
			and next(record.params or {}) == nil and next(record.query or {}) == nil
	end

	function M.eligible(record)
		return not config.accessProblem() and not config.vaultStatus().locked and config.get("agent.autoFreeRouting", true) ~= false and eligibleRecord(record)
			and community.problem(record) == nil and #registry.requestKeys(record) > 0
	end

	local function same(a, b)
		if type(a) ~= type(b) then return false end
		if type(a) ~= "table" then return a == b end
		for key, value in pairs(a) do if not same(value, b[key]) then return false end end
		for key in pairs(b) do if a[key] == nil then return false end end
		return true
	end

	local function scope(record)
		return { headers = record.headers or {}, claudeUa = record.claudeUa, relay = transport.endpoint() }
	end

	local function matches(record, state)
		-- Preference changes apply to future selection, never accepted requests.
		return eligibleRecord(record) and registry.get(record.id) == record
			and same(state.scope, scope(record))
	end

	local function current(record, state)
		return M.eligible(record) and states[record] == state and matches(record, state)
	end

	local function validState(record)
		local state = states[record]
		if state and current(record, state) and clock.since(state.at) < TTL then return state end
	end

	local function call(record, state, body)
		if not current(record, state) then return nil end
		local start = clock.ms()
		local headers = env.require("provider/chat").headers(record)
		local accounting = env.require("runtime/request_accounting").new(record)
		local key = record.apiKey
		local function aborted() return not current(record, state) or clock.since(start) >= TARGET end
		local response = http.send({ url = registry.endpoint(record, "/chat/completions"), method = "POST",
			requiresAccess = true,
			headers = headers, body = util.encode(body),
			onDispatch = function() accounting.dispatch(key, headers) end,
			identity = registry.identityFor(record), identityRequired = registry.requiresClaude(record),
			relay = state.scope.relay ~= nil, attempts = 1, timeout = TARGET / 1000, deadlineMs = start + TARGET,
			aborted = aborted, silent = true, tag = "free:probe" })
		if aborted() or not response or not response.ok then return nil end
		local parsed
		if sse.looksStreamed(response.body) then parsed = sse.parse(response.body)
		else
			local decoded = util.decode(response.body)
			if type(decoded) ~= "table" or decoded.error then return nil end
			parsed = sse.fromResponse(decoded)
		end
		accounting.attach(parsed)
		if parsed.streamError then return nil end
		return parsed, clock.since(start)
	end

	local function probe(record, state, model)
		local prompt = "Call uai_ping with nonce ok once. After its result, reply PONG."
		local tools = { { type = "function", ["function"] = { name = "uai_ping", description = "Connectivity check only.",
			parameters = { type = "object", properties = { nonce = { type = "string", enum = { "ok" } } },
				required = { "nonce" }, additionalProperties = false } } } }
		local first, firstMs = call(record, state, { model = model, stream = false, max_tokens = 128,
			messages = { { role = "user", content = prompt } }, tools = tools, tool_choice = "auto" })
		local calls = first and first.toolCalls or {}
		local tool = #calls == 1 and calls[1]
		local fn = tool and tool["function"]
		local args = fn and util.decode(fn.arguments or "")
		if not fn or fn.name ~= "uai_ping" or not args or args.nonce ~= "ok" or util.trim(tool.id) == "" then return end
		local assistant = { role = "assistant", content = first.content or "", tool_calls = calls }
		if util.trim(first.reasoning) ~= "" then assistant.reasoning_content = first.reasoning end
		local second, secondMs = call(record, state, { model = model, stream = false, max_tokens = 128,
			messages = { { role = "user", content = prompt },
				assistant,
				{ role = "tool", tool_call_id = tool.id, content = '{"ok":true}' } }, tools = tools, tool_choice = "auto" })
		if not second or util.trim(second.content) == "" or #(second.toolCalls or {}) > 0 then return end
		if current(record, state) then
			state.samples[model] = { model = model, ms = math.max(firstMs, secondMs), at = clock.ms() }
			M.changed:fire(record.id)
		end
	end

	-- Nonblocking, with two bounded probe workers. An expired native HTTP worker
	-- remains owned by net/http until the executor returns; no coroutine is killed.
	function M.refresh(record)
		if not M.eligible(record) then return end
		local state = validState(record)
		if state then return end
		state = { at = clock.ms(), scope = util.deepCopy(scope(record)), samples = {}, running = true }
		states[record] = state
		M.changed:fire(record.id)
		task.spawn(function()
			local ok, found = pcall(env.require("provider/models").discover, record,
				{ timeout = TARGET / 1000, aborted = function() return not current(record, state) end })
			if not ok or not current(record, state) then state.running = false; return end
			local index, workers = 0, 2
			for _ = 1, workers do
				task.spawn(function()
					while current(record, state) do
						index = index + 1
						local model = index <= MAX_MODELS and found[index]
						if not model then break end
						pcall(probe, record, state, model)
					end
					workers = workers - 1
					if workers == 0 then state.running = false; M.changed:fire(record.id) end
				end)
			end
		end)
	end

	local function winner(record, request)
		local state = validState(record)
		if not state then return nil end
		local usage = env.require("agent/usage")
		local input = request and (usage.estimateMessages(request.messages) + usage.estimateText(util.encode(request.tools or {}))) or 0
		local best
		for model, sample in pairs(state.samples) do
			local window = traits.contextWindow(model, record)
			local output = math.min(tonumber(request and request.maxTokens) or env.require("runtime/config").get("agent.maxTokens", 4096),
				traits.maxOutput(model, record) or math.huge)
			-- Unknown windows and images keep the provider's router. A tiny text
			-- probe establishes neither vision support nor arbitrary context size.
			local fits = model == "auto" or (window and input * 1.25 + output + 1024 <= window)
			if fits and sample.ms < TARGET and clock.since(sample.at) < TTL
				and (not best or sample.ms < best.ms or (sample.ms == best.ms and model < best.model)) then best = sample end
		end
		return best
	end

	function M.select(record, request)
		if config.get("agent.autoFreeRouting", true) == false then
			local owner = owners[record]
			return owner and matches(owner.record, owner.state) and owner.record or record
		end
		if not M.eligible(record) then return record end
		M.refresh(record)
		if next(request.extra or {}) ~= nil or env.require("runtime/images").hasReferences(request.messages) then return record end
		for _, message in ipairs(request.messages or {}) do
			for _, block in ipairs(type(message.content) == "table" and message.content or {}) do
				if block.type ~= "text" then return record end
			end
		end
		local best = winner(record, request)
		if not best or best.model == "auto" then return record end
		local snapshot = registry.requestSnapshot(record)
		snapshot.model = best.model
		local baseline = {}
		for _, key in ipairs(LESSONS) do baseline[key] = util.deepCopy(snapshot[key]) end
		owners[snapshot] = { record = record, state = states[record], baseline = baseline }
		return snapshot
	end

	-- A refusal or slow actual response removes that candidate for later requests.
	-- It never causes the current prompt to be resent to another measured model.
	function M.observe(record, result, ms)
		local owner = owners[record]
		if owner and matches(owner.record, owner.state) then
			local changed = false
			for _, key in ipairs(LESSONS) do
				if not same(owner.baseline[key], record[key]) then
					local value, existing = util.deepCopy(record[key]), owner.record[key]
					if (key == "maxTokensCap" or key == "toolsCap") and type(value) == "table" and type(existing) == "table"
						and value.model == existing.model and value.scope == existing.scope then
						local field = key == "maxTokensCap" and "tokens" or "limit"
						value[field] = math.min(tonumber(value[field]) or math.huge, tonumber(existing[field]) or math.huge)
					elseif key == "repairs" and owner.record.repairScope == record.repairScope and type(value) == "table" then
						for _, repair in ipairs(existing or {}) do
							if not util.find(value, function(item) return item == repair end) then value[#value + 1] = repair end
						end
					end
					if key == "repairs" and owner.record.repairScope ~= record.repairScope then
						owner.record.repairScope = record.repairScope; changed = true
					end
					if not same(existing, value) then owner.record[key] = value; changed = true end
				end
			end
			if changed then registry.save(owner.record, { force = true }) end
		else owner = { record = record, state = validState(record) } end
		if owner.state and current(owner.record, owner.state) and (not result or ms >= TARGET) then
			owner.state.samples[record.model] = nil; M.changed:fire(owner.record.id)
		end
	end

	function M.current(record)
		local owner = owners[record]
		-- Expiring latency measurements cannot abort an accepted long request.
		-- Lock clears the saved provider's live fields; the accepted snapshot may
		-- still finish its request while new work remains gated by M.eligible.
		if owner and (config.accessProblem() or config.vaultStatus().locked) then return alive and registry.get(owner.record.id) == owner.record end
		return alive and (not owner or matches(owner.record, owner.state))
	end

	function M.isRouted(record) return owners[record] ~= nil end

	function M.status(record)
		local state = validState(record)
		local best = state and winner(record)
		local availability = community.availability(record)
		local access = config.accessProblem()
		local supported = eligibleRecord(record)
		local locked = config.vaultStatus().locked
		local hasKey = #registry.requestKeys(record) > 0
		local problem = access or (locked and "Unlock credential storage")
			or (not availability.open and availability.message) or (not hasKey and "Resume an API key to use automatic routing")
		return { enabled = config.get("agent.autoFreeRouting", true) ~= false, supported = supported,
			available = supported and not problem, scheduleOpen = availability.open,
			availability = problem or availability.message,
			running = state and state.running or false, model = best and best.model,
			ms = best and best.ms, ready = state ~= nil }
	end

	local dispose = env.require("runtime/dispose")
	dispose.add(config.changed:connect(function(path)
		if path == nil or path == "agent" or path == "agent.autoFreeRouting" then
			if config.get("agent.autoFreeRouting", true) == false then states = setmetatable({}, { __mode = "k" }) end
			M.changed:fire()
		end
	end), "free routing preference")
	dispose.add(function() alive = false; states = {}; owners = {} end, "free model measurements")
	return M
end
