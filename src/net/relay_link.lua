-- Discovers and pairs with the local inference relay (the mobile companion).
--
-- A phone's executor cuts long HTTP calls off after a wall-clock limit that a
-- reasoning turn easily exceeds. The companion is a tiny foreground service that
-- owns the upstream connection and answers every executor call in milliseconds.
-- This module finds it on loopback, pairs once for a stable token, and reports
-- whether it can be used. It performs no long work and never blocks boot.
return function(env)
	local util = env.require("runtime/util")
	local clock = env.require("runtime/clock")
	local log = env.require("runtime/log")
	local config = env.require("runtime/config")
	local dispose = env.require("runtime/dispose")
	local caps = env.require("runtime/caps")
	local http = env.require("net/http")
	local signal = env.require("runtime/signal")
	local dataModel = env.require("net/relay_datamodel")
	local kiloStatus = env.require("net/kilo_status")
	local kilo

	local M = { changed = signal.new("relay") }
	local alive, started, nextProbe, epoch = true, false, 0, 0
	local activeProbe, failures = nil, 0
	local verifiedToken, verifiedInstance, unlimited = nil, nil, false
	local verifiedProfile
	local state, lastError, lastProbeAt = "off", nil, 0
	local PROBE_MS = 30000
	local EXCHANGE_SECONDS = 5

	local function mode()
		local value = config.get("relay.mode", "auto")
		if value ~= "auto" and value ~= "always" and value ~= "off" then return "auto" end
		return value
	end

	local function port()
		local value = tonumber(config.get("relay.port", 8790)) or 8790
		if value < 1 or value > 65535 or value % 1 ~= 0 then return 8790 end
		return value
	end

	local function token() return tostring(config.get("relay.token", "")) end
	local function base() return "http://127.0.0.1:" .. tostring(port()) end

	function M.mode() return mode() end

	-- Presentation and defaults only; the prober runs the same way everywhere.
	local function mobile()
		local ok, touch = pcall(function() return env.uis.TouchEnabled == true end)
		if not ok then return false end
		local okMouse, mouse = pcall(function() return env.uis.MouseEnabled end)
		return touch and (not okMouse or mouse ~= true)
	end
	function M.mobile() return mobile() end

	local function setState(next, note)
		if state == next and lastError == note then return end
		local previous = state
		state, lastError = next, note
		if next == "ready" then log.info("relay", "companion connected on port " .. tostring(port()))
		elseif next == "error" and previous == "ready" then log.warn("relay", "companion disconnected", note) end
		M.changed:fire()
	end

	local function remember(path, value)
		if config.get(path, "") ~= value then config.set(path, value, { quiet = true }) end
	end

	local function copyProfile(profile)
		if not profile then return nil end
		return { request = profile.request, name = profile.name,
			useTimeout = profile.useTimeout, omitEmptyHeaders = profile.omitEmptyHeaders }
	end

	local function profileLabel(profile)
		return profile.name .. (profile.useTimeout == false and " minimal" or " standard")
	end

	local function sameProfile(left, right)
		return left and right and left.request == right.request and left.useTimeout == right.useTimeout
			and left.omitEmptyHeaders == right.omitEmptyHeaders
	end

	function M.status()
		return { mode = mode(), state = state, port = port(), server = tostring(config.get("relay.server", "")),
			instance = tostring(config.get("relay.instance", "")), placeId = tonumber(config.get("relay.placeId", 0)) or 0,
			error = lastError, lastProbeAt = lastProbeAt, unlimited = unlimited,
			kilo = state == "ready" and kilo and util.copy(kilo) or nil,
			transport = verifiedProfile and profileLabel(verifiedProfile) or nil }
	end

	local function has(text, terms)
		for _, term in ipairs(terms) do if text:find(term, 1, true) then return true end end
		return false
	end

	local function optionFailure(text)
		return has(text, { "invalid option", "unknown option", "unsupported option", "unexpected option", "unrecognized option",
			"bad argument", "invalid argument", "argument #", "invalid parameter", "unknown field", "invalid field",
			"unexpected field", "unsupported field", "unrecognized field" })
	end

	local function timedOut(text)
		return has(text, { "deadline", "timeout", "timed out", "etimedout", "timedout" })
	end

	-- Native exceptions can include whole request or response objects, including
	-- a newly issued pairing token. Display only fixed categories, never excerpts.
	local function transportProblem(problem)
		local text = tostring(problem or ""):lower()
		if optionFailure(text) then
			return "The executor rejected a native request option or argument."
		end
		if timedOut(text) then
			return "The local relay exchange reached its deadline or timed out."
		end
		if has(text, { "aborted", "cancelled", "canceled" }) then
			return "The local relay exchange was cancelled."
		end
		if has(text, { "capacity:", "slots are busy", "request limit" }) then
			return "Native HTTP capacity is busy; wait for other requests, then scan again."
		end
		if has(text, { "connectfail", "connection refused", "econnrefused", "failed to connect", "connect failed", "connection failed", "could not connect", "unable to connect" }) then
			return "Connection refused or failed; check that UAI Relay is running on this port."
		end
		if has(text, { "cleartext", "https-only", "https only", "only https", "unsupported protocol", "protocol is not supported", "https required" }) then
			return "The executor rejected local HTTP; cleartext or this protocol is not supported."
		end
		if has(text, { "permission", "denied", "not permitted", "disallowed", "blocked" }) then
			return "The executor denied permission for this loopback request."
		end
		if has(text, { "malformed", "empty executor", "no response", "non-text", "body is not text", "response_limit:" }) then
			return "The executor returned an empty, malformed or oversized response."
		end
		return "The executor reported an unknown transport failure."
	end
	M.describeTransportProblem = transportProblem

	local function readReply(step, response, problem, probePort, limit, profile, failureKind)
		local label = "Companion " .. step .. " on port " .. tostring(probePort)
		if not response then
			local origin = failureKind == "transport" and "executor threw"
				or failureKind == "response" and "executor returned an unusable response" or "wait stopped"
			return nil, label .. " failed via " .. profileLabel(profile) .. " (" .. origin .. "): " .. transportProblem(problem)
		end
		if not response.ok then
			return nil, label .. " returned HTTP " .. tostring(response.status or 0) .. "."
		end
		if type(response.body) ~= "string" or #response.body > limit then
			return nil, label .. " returned an oversized or non-text reply."
		end
		local value, decodeError = util.decode(response.body)
		if decodeError then return nil, label .. " returned invalid JSON." end
		if type(value) ~= "table" then return nil, label .. " did not return a JSON object." end
		return value
	end

	local function validInstance(value)
		return type(value) == "string" and #value > 0 and #value <= 128
	end

	local function profiles()
		local out = {}
		local function add(profile)
			for _, prior in ipairs(out) do if sameProfile(prior, profile) then return end end
			out[#out + 1] = copyProfile(profile)
		end
		if verifiedProfile then add(verifiedProfile) end
		for index, alias in ipairs(caps.requestAliases()) do
			if index == 1 then add({ request = alias.fn, name = alias.name, useTimeout = true, omitEmptyHeaders = false }) end
			add({ request = alias.fn, name = alias.name, useTimeout = false, omitEmptyHeaders = true })
		end
		if dataModel.available() then
			add({ request = dataModel.request, name = "HttpGet/HttpPost", useTimeout = false, omitEmptyHeaders = true })
		end
		return out
	end

	-- Only a completed native throw can justify another unauthenticated hello.
	-- A returned response, timeout, cancellation or busy worker is conclusive for
	-- this scan. In particular, no unknown native work can accumulate across aliases.
	local function chooseHello(probeBase, probePort, stale)
		local candidates, attempts = profiles(), {}
		for index, profile in ipairs(candidates) do
			if stale() then return nil, nil, "cancelled" end
			local authenticated = sameProfile(profile, verifiedProfile) and token() == verifiedToken and token() ~= ""
			local rejectedToken = false
			local hello, helloError, _, failureKind = http.request({ url = probeBase .. "/api/hello", method = "GET",
				headers = authenticated and { Authorization = "Bearer " .. token() } or nil,
				identity = "none", silent = true, timeout = EXCHANGE_SECONDS, aborted = stale, executorProfile = profile })
			if stale() then return nil, nil, "cancelled" end
			-- The DataModel adapter authenticates hello through /api/executor. A
			-- replaced companion can explicitly reject that old token before we see
			-- its new instance. Read public metadata once, then let the existing
			-- authenticated status check decide whether pairing needs repair.
			if authenticated and hello and hello.status == 401 then
				rejectedToken = true
				hello, helloError, _, failureKind = http.request({ url = probeBase .. "/api/hello", method = "GET",
					identity = "none", silent = true, timeout = EXCHANGE_SECONDS, aborted = stale, executorProfile = profile })
				if stale() then return nil, nil, "cancelled" end
			end
			attempts[#attempts + 1] = profileLabel(profile)
			local info, problem = readReply("hello", hello, helloError, probePort, 4096, profile, failureKind)
			if info then
				-- Metadata is validated before this profile can carry any credential.
				if info.server ~= "uai-relay" then problem = "Port " .. tostring(probePort) .. " is used by another program"
				elseif info.protocol ~= 2 then problem = "The companion hello uses an incompatible protocol; protocol 2 is required."
				elseif not validInstance(info.instance) then problem = "The companion hello did not include a valid instance ID."
				elseif profile.request == dataModel.request and (type(info.capabilities) ~= "table"
					or type(info.capabilities.executorPost) ~= "table" or info.capabilities.executorPost.schema ~= 1) then
					problem = "The companion is reachable through HttpGet. Install UAI Relay 3.5.7 or newer for authenticated HttpPost support."
				else return info, profile, nil, rejectedToken end
			end
			local errorText = tostring(helloError or ""):lower()
			local stop = hello ~= nil or failureKind ~= "transport"
				or has(errorText, { "aborted", "cancelled", "canceled", "capacity:", "slots are busy", "request limit" })
				or (not optionFailure(errorText) and timedOut(errorText))
			if stop or index == #candidates then
				return nil, nil, problem .. " Attempts: " .. table.concat(attempts, ", ") .. "."
			end
		end
		return nil, nil, "No captured executor HTTP request function is available."
	end

	-- A periodic health check must not make a ready relay temporarily unusable or
	-- fill the log with an absent optional app. Settings and unload invalidate each
	-- request; a late hello/pair cannot restore credentials for an old endpoint.
	local function probe(mine, probeBase, probePort)
		local function stale() return config.accessProblem() ~= nil or not alive or epoch ~= mine or mode() == "off" end
		local info, profile, helloProblem, rejectedToken = chooseHello(probeBase, probePort, stale)
		if not info then return false, helloProblem end
		local pairedToken = token()
		if pairedToken ~= "" and (rejectedToken or pairedToken ~= verifiedToken or info.instance ~= verifiedInstance or not sameProfile(profile, verifiedProfile)) then
			local status, statusError, _, failureKind = http.request({ url = probeBase .. "/api/status", method = "GET",
				headers = { Authorization = "Bearer " .. pairedToken }, identity = "none", silent = true,
				timeout = EXCHANGE_SECONDS, aborted = stale, executorProfile = profile })
			if stale() then return false, "cancelled" end
			if status and status.status == 401 then pairedToken = ""
			else
				local checked, statusProblem = readReply("saved-pairing check", status, statusError, probePort, 8192, profile, failureKind)
				if not checked then return false, statusProblem end
				if checked.server ~= "uai-relay" then return false, "The saved-pairing check answered from another program." end
				if checked.protocol ~= 2 then return false, "The saved-pairing check uses an incompatible protocol; protocol 2 is required." end
				if not validInstance(checked.instance) then return false, "The saved-pairing check did not include a valid instance ID." end
				if checked.instance ~= info.instance then return false, "The companion instance changed during its saved-pairing check; scan again." end
				if checked.ok ~= true then return false, "The companion could not confirm its saved pairing." end
			end
		end
		if pairedToken == "" then
			local place = env.require("runtime/place")
			local body = util.encode({ client = "ProjectUAI-Mobile",
				version = (env.info and env.info.version) or "0.0.0", protocol = 2,
				placeId = place.id, gameId = place.gameId })
			local pair, pairError, _, failureKind = http.request({ url = probeBase .. "/api/pair", method = "POST", body = body,
				headers = { ["Content-Type"] = "application/json" }, identity = "none", silent = true,
				timeout = EXCHANGE_SECONDS, aborted = stale, executorProfile = profile })
			if stale() then return false, "cancelled" end
			local issued, pairProblem = readReply("pairing", pair, pairError, probePort, 4096, profile, failureKind)
			if not issued then return false, pairProblem end
			if issued.protocol ~= 2 then return false, "The pairing reply uses an incompatible protocol; protocol 2 is required." end
			if not validInstance(issued.instance) then return false, "The pairing reply did not include a valid instance ID." end
			if issued.instance ~= info.instance then return false, "The companion instance changed during pairing; scan again." end
			if issued.ok ~= true or type(issued.token) ~= "string" or #issued.token ~= 64 or not issued.token:match("^[a-f0-9]+$") then
				return false, "The companion did not issue a valid pairing token."
			end
			pairedToken = issued.token
			remember("relay.token", issued.token)
			remember("relay.server", "uai-relay")
			remember("relay.placeId", place.id)
		end
		verifiedToken, verifiedInstance = pairedToken, info.instance
		verifiedProfile = copyProfile(profile)
		local inference = type(info.capabilities) == "table" and info.capabilities.inference
		local nextKilo = kiloStatus.read(type(info.capabilities) == "table" and info.capabilities.kilo)
		local kiloChanged = util.encode(kilo) ~= util.encode(nextKilo)
		kilo = nextKilo
		unlimited = type(inference) == "table" and inference.schema == 1 and inference.unlimited == true
		remember("relay.instance", tostring(info.instance))
		if kiloChanged then M.changed:fire() end
		return true
	end

	function M.probe()
		if not alive then return false, "unloaded" end
		local access = config.accessProblem()
		if access then return false, access end
		if mode() == "off" then setState("off"); return false, "off" end
		if type(caps.fn.request) ~= "function" and not dataModel.available() then
			nextProbe = clock.ms() + PROBE_MS
			local reason = "The companion needs an executor HTTP request function or HttpGet/HttpPost; Roblox HttpService cannot reach this phone's loopback relay."
			setState("error", reason); return false, reason
		end
		if activeProbe then
			local pending = activeProbe
			while alive and pending == activeProbe and not pending.done do clock.wait(0.05) end
			if pending.done then return pending.ok == true, pending.reason end
			return false, not alive and "unloaded" or "cancelled"
		end
		local mine = epoch
		local pending = {}
		activeProbe = pending
		if state == "off" then setState("searching") end
		local ok, result, reason = pcall(probe, mine, base(), port())
		pending.ok, pending.reason, pending.done = ok and result == true, reason, true
		if not ok then pending.reason = "Companion probe failed" end
		if activeProbe == pending then activeProbe = nil end
		if not config.accessProblem() and alive and mine == epoch and mode() ~= "off" then
			lastProbeAt = clock.ms()
			failures = pending.ok and 0 or math.min(failures + 1, 3)
			nextProbe = lastProbeAt + PROBE_MS * 2 ^ math.max(0, failures - 1)
			setState(pending.ok and "ready" or "error", pending.reason)
		end
		return pending.ok, pending.reason
	end

	function M.usable()
		return alive and mode() ~= "off" and state == "ready" and token() ~= "" and verifiedProfile ~= nil
	end

	function M.endpoint(retain)
		if retain then
			if not alive or mode() == "off" or token() == "" then return nil end
		elseif not M.usable() then return nil end
		return { target = "companion", base = base(), token = token(),
			instance = tostring(config.get("relay.instance", "")), enabled = true, unlimited = unlimited,
			executorProfile = copyProfile(verifiedProfile) }
	end

	local function start()
		if config.accessProblem() or started or not alive then return end
		started = true
		clock.spawn(function()
			while alive do
				if not config.accessProblem() and mode() ~= "off" and clock.ms() >= nextProbe then
					M.probe()
				end
				clock.wait(0.25)
			end
		end)
	end

	function M.ensure()
		if config.accessProblem() or not alive then return end
		if mode() == "off" then setState("off"); return end
		start()
	end

	-- On-demand probe for a "Scan now" action.
	function M.scan()
		if mode() == "off" then return false, "off" end
		M.ensure()
		return M.probe()
	end

	-- Starting the app after Roblox should affect the next request, without
	-- waiting through discovery's two-minute idle backoff. One shared short scan
	-- is allowed per five seconds; absent apps cannot delay every provider retry.
	function M.prepare()
		if config.accessProblem() or not mobile() or not alive or mode() == "off" or M.usable() then return end
		M.ensure()
		if activeProbe or lastProbeAt == 0 or clock.since(lastProbeAt) >= 5000 then M.probe() end
	end

	function M.forget()
		epoch, failures = epoch + 1, 0
		verifiedToken, verifiedInstance, unlimited = nil, nil, false
		kilo = nil
		verifiedProfile = nil
		remember("relay.token", "")
		remember("relay.server", "")
		remember("relay.instance", "")
		nextProbe = 0
		setState("searching")
	end

	dispose.add(config.changed:connect(function(path)
		if path ~= nil and path ~= "relay" and not util.startsWith(tostring(path), "relay.") then return end
		epoch, failures = epoch + 1, 0
		nextProbe = 0
		verifiedToken, verifiedInstance, verifiedProfile, unlimited = nil, nil, nil, false
		kilo = nil
		if path == "relay.port" then
			remember("relay.token", "")
			remember("relay.server", "")
			remember("relay.instance", "")
		end
		setState(mode() == "off" and "off" or "searching")
		M.ensure()
		M.changed:fire()
	end), "relay settings")
	dispose.add(function() alive, epoch, kilo = false, epoch + 1, nil end, "relay prober")

	return M
end
