-- Connection checks own their cancellation without borrowing a conversation.
return function(env)
	local util = env.require("runtime/util")
	local config = env.require("runtime/config")
	local clock = env.require("runtime/clock")
	local log = env.require("runtime/log")
	local providers = env.require("provider/registry")
	local M = {}
	local alive, latest, active = true, {}, {}
	local MAX_ACTIVE, MAX_HISTORY = 16, 128
	local function validId(id)
		return type(id) == "string" and #id > 0 and #id <= 128 and id:match("^[%w_%-]+$") ~= nil
	end
	local function count(values)
		local total = 0
		for _ in pairs(values) do total = total + 1 end
		return total
	end
	local function bounded(value)
		return util.ellipsis(log.redact(tostring(value or "")), 240)
	end
	local function snapshot(test)
		if not test then return nil end
		return { id = test.id, state = test.state, text = test.text,
			startedAt = test.startedAt, elapsedMs = math.max(0, (test.finishedAt or clock.ms()) - test.startedAt),
			ms = test.ms }
	end
	local function retain(test)
		if not latest[test.providerId] and count(latest) >= MAX_HISTORY then
			local oldest
			for _, item in pairs(latest) do
				if not active[item.providerId] and (not oldest or item.startedAt < oldest.startedAt) then oldest = item end
			end
			if not oldest then return false end
			latest[oldest.providerId] = nil
		end
		latest[test.providerId], active[test.providerId] = test, test
		return true
	end
	local function begin(record, id)
		if not alive or config.accessProblem() or config.vaultStatus().busy then return nil, "Finish credential access before testing a connection." end
		if type(record) ~= "table" or providers.get(record.id) ~= record then return nil, "Choose a saved provider connection." end
		if not validId(id) then return nil, "Connection test id must be 1 to 128 letters, numbers, underscores or hyphens." end
		local previous = latest[record.id]
		if previous and previous.id == id then return previous, nil, false end
		if active[record.id] then return nil, "This connection is already being tested. Cancel its current test first." end
		if count(active) >= MAX_ACTIVE then return nil, "Too many connection tests are running. Cancel one before starting another." end
		local problem = providers.protocolProblem(record)
		if problem then return nil, problem end
		local test = { id = id, providerId = record.id, startedAt = clock.ms(), state = "running", text = "Testing connection" }
		local scope, rateLimit = providers.compatibilityKey(record), record.requestsPerMinute
		local connection = env.require("net/bridge_connection")
		local owner = connection.get(true)
		function test.aborted()
			local current = owner.enabled and connection.get(true)
			return not alive or test.cancelled or providers.get(record.id) ~= record
				or providers.compatibilityKey(record) ~= scope or record.requestsPerMinute ~= rateLimit
				or config.accessProblem() ~= nil
				or owner.enabled and (not current.enabled or current.token ~= owner.token or current.instance ~= owner.instance or current.port ~= owner.port)
		end
		if not retain(test) then return nil, "Connection test history is full. Finish a running test first." end
		return test, nil, true
	end
	local function perform(test, record)
		local called, result, problem = pcall(function()
			return env.require("provider/chat").complete(record, {
				messages = { { role = "user", content = "Reply with OK." } }, maxTokens = 12, attempts = 1,
				aborted = test.aborted,
				onRetry = function(info)
					if test.aborted() then return end
					if info.rateLimit and info.phase == "waiting" then test.state, test.text = "waiting", "Waiting for request rate limit"
					elseif info.rateLimit and info.phase == "admitted" then test.state, test.text = "running", "Testing connection" end
				end,
			})
		end)
		test.finishedAt = clock.ms()
		if active[test.providerId] == test then active[test.providerId] = nil end
		if test.aborted() or called and not result and problem == "aborted" then test.state, test.text = "cancelled", "Connection test cancelled"
		elseif not called then test.state, test.text = "failed", "Connection test could not complete"
		elseif not result then test.state, test.text = "failed", bounded(problem or "Connection test failed")
		else
			test.state, test.text = "succeeded", bounded("Connected: " .. tostring(result.content or ""))
			test.ms = type(result.ms) == "number" and result.ms == result.ms and math.abs(result.ms) < math.huge
				and math.max(0, result.ms) or math.max(0, test.finishedAt - test.startedAt)
		end
		-- Release captured connection credentials and policy after settlement.
		test.aborted = nil
		return snapshot(test)
	end
	function M.start(record, id)
		local test, problem, created = begin(record, id)
		if not test then return nil, problem end
		if created then
			local pendingRecord = record
			local scheduled = pcall(clock.spawn, function()
				if not pendingRecord then return end
				local ownedRecord = pendingRecord
				pendingRecord = nil
				perform(test, ownedRecord)
			end)
			if not scheduled and not test.finishedAt then
				pendingRecord = nil
				active[test.providerId] = nil
				test.finishedAt, test.state, test.text = clock.ms(), "failed", "Connection test could not start"
				test.aborted = nil
				return nil, test.text
			end
		end
		return snapshot(test)
	end
	function M.run(record)
		local id = "provider_test_" .. env.services.HttpService:GenerateGUID(false)
		local test, problem = begin(record, id)
		if not test then return nil, problem end
		local result = perform(test, record)
		if result.state ~= "succeeded" then return nil, result.text end
		return { text = result.text, ms = result.ms }
	end
	function M.cancel(providerId, id)
		if not validId(id) then return false, "Choose the current connection test." end
		local test = active[providerId]
		if not test or test.id ~= id then return true, false end
		test.cancelled, test.state, test.text = true, "cancelling", "Stopping connection test"
		return true, true
	end
	function M.state(providerId) return snapshot(latest[providerId]) end
	env.require("runtime/dispose").add(function()
		alive = false
		for _, test in pairs(active) do test.cancelled = true end
		latest = {}
	end, "connection tests")
	return M
end
