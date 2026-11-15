-- One place decides which transport carries an inference request, so providers,
-- the relay and the UI cannot drift: Cowork's web bridge, the local companion
-- relay, or the executor directly. Precedence is Cowork, then companion, then
-- direct, exactly as the transport contract requires.
return function(env)
	local config = env.require("runtime/config")
	local connection = env.require("net/bridge_connection")
	local relayLink = env.require("net/relay_link")

	local M = {}

	-- Today's rule for the Cowork web runtime.
	function M.coworkWeb()
		return connection.enabled() and config.get("bridge.runtime", "game") == "web"
	end

	function M.companionReady()
		return relayLink.usable()
	end

	function M.target()
		if M.coworkWeb() then return "cowork" end
		if M.companionReady() then return "companion" end
		return nil
	end

	-- The companion must advertise this before the client sends timeout=0. Older
	-- companions interpret zero as ten seconds. Explicit request budgets remain
	-- finite; the normal unlimited setting applies only to default inference.
	function M.unlimited(request, endpoint)
		endpoint = endpoint or M.endpoint()
		if not endpoint then return false end
		request = request or {}
		if request.relayUnlimited == false then return false end
		if endpoint.target == "cowork" then return true end
		if endpoint.unlimited ~= true then return false end
		if request.relayUnlimited == true then return true end
		return request.timeout == nil and request.deadlineMs == nil and config.get("agent.requestUnlimited", true) == true
	end

	function M.prepare()
		if not M.coworkWeb() then relayLink.prepare() end
	end

	-- Always mode requires a relay even while discovery is unavailable. Let the
	-- relay report that failure rather than opening a long native provider call.
	function M.shouldRelay(imageRequest)
		return imageRequest == true or M.coworkWeb() or M.companionReady() or relayLink.mode() == "always"
	end

	-- Streaming is forced only for Cowork; the companion returns the whole body.
	function M.streamForced()
		return M.coworkWeb()
	end

	-- New requests prefer a connected Cowork bridge, then a healthy companion.
	-- Running jobs can retain their configured endpoint through a failed probe.
	function M.endpoint(retainTarget)
		if retainTarget == "cowork" or not retainTarget and M.coworkWeb() then
			local current = connection.get(retainTarget == "cowork")
			if current.enabled then
				return { target = "cowork", base = "http://127.0.0.1:" .. tostring(current.port),
					token = current.token, instance = current.instance, enabled = current.enabled }
			end
		end
		if retainTarget == "cowork" then return nil end
		return relayLink.endpoint(retainTarget == "companion")
	end

	return M
end
