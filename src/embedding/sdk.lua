-- The versioned host surface. Legacy runtime APIs remain available on the handle.
return function(env)
	local clock = env.require("runtime/clock")
	local dispose = env.require("runtime/dispose")
	local signal = env.require("runtime/signal")
	local scopes = env.require("embedding/scope")
	local log = env.require("runtime/log")
	local M = {}

	function M.attach(handle)
		local sdk = { version = "1.0.0", features = {
			uiFreeBoot = true, resourceScopes = true, requests = true, sessionLookup = true,
		} }
		local pending = {}
		function sdk.createScope(id) return scopes.create(handle, id) end

		-- Subscriptions are installed before send, including for hosts whose task
		-- scheduler can complete the entire turn before send returns.
		function sdk.request(session, text, options)
			if not handle.alive then return nil, "client is unloaded" end
			if type(session) ~= "table" or handle.sessions.get(session.id) ~= session then
				return nil, "a tracked conversation from this client is required"
			end
			if type(text) ~= "string" then return nil, "request text must be a string" end
			if options ~= nil and type(options) ~= "table" then return nil, "request options must be a table" end
			options = options or {}
			for key in pairs(options) do
				if key ~= "onEvent" and key ~= "onComplete" and key ~= "files" and key ~= "images" then
					return nil, "unknown request option: " .. tostring(key)
				end
			end
			if (options.onEvent ~= nil and type(options.onEvent) ~= "function")
				or (options.onComplete ~= nil and type(options.onComplete) ~= "function") then
				return nil, "request callbacks must be functions"
			end
			if pending[session] or session.busy or session.preparing then return nil, "already working" end
			local request = { status = "running", sessionId = session.id }
			local completion = signal.new("sdk:completion")
			local done, admitted, epoch, turn, cancelled, aborted, failure = false, false, nil, nil, false, false, nil
			local result, disconnect, unwatch, release, eventCallback
			local delivered = false
			eventCallback = options.onEvent
			local function notify(fn, value)
				local ok, why = pcall(fn, value)
				if not ok then log.warn("embedding", "request callback failed", why) end
			end
			local function cleanup()
				if disconnect then disconnect(); disconnect = nil end
				if unwatch then unwatch(); unwatch = nil end
				if release then local remove = release; release = nil; remove() end
				eventCallback = nil
				if pending[session] == request then pending[session] = nil end
			end
			local function deliver()
				if delivered or not admitted or not done then return end
				delivered = true
				completion:fire(result)
				completion:clear()
			end
			local function finish(status, reply, why)
				if done then return end
				done = true
				result = { ok = status == "succeeded", status = status, text = tostring(reply or ""),
					error = why, sessionId = session.id }
				request.status, request.result = status, result
				cleanup()
				deliver()
			end
			function request.onComplete(fn)
				if type(fn) ~= "function" then return nil, "callback must be a function" end
				if done then notify(fn, result); return function() end end
				return completion:connect(function(value) notify(fn, value) end)
			end
			function request.cancel()
				if done or cancelled then return false end
				if not session.busy and not session.preparing then return false end
				-- Never abort a subsequent legacy send that started before our onDone.
				if epoch and session.toolEpoch ~= epoch then return false end
				cancelled = true
				return session.abort()
			end
			function request.await(timeoutSeconds)
				if timeoutSeconds ~= nil and (type(timeoutSeconds) ~= "number" or timeoutSeconds ~= timeoutSeconds
					or timeoutSeconds < 0 or timeoutSeconds == math.huge) then
					return nil, "timeout must be a finite nonnegative number"
				end
				local deadline = timeoutSeconds and (clock.ms() + timeoutSeconds * 1000)
				while not done do
					if deadline and clock.ms() >= deadline then return nil, "timeout" end
					clock.wait(0.03)
				end
				return result
			end
			if options.onComplete then request.onComplete(options.onComplete) end
			pending[session] = request
			disconnect = session.events:connect(function(event)
				if done then return end
				if not epoch and event.kind == "user" then epoch, turn, admitted = session.toolEpoch, session.turns, true end
				if not epoch or session.turns ~= turn then return end
				if event.kind == "abort" then aborted = true
				elseif event.kind == "error" then failure = tostring(event.message or "request failed")
				elseif event.kind == "turn:end" and event.failed then failure = failure or tostring(event.text or "request failed") end
				if eventCallback then notify(eventCallback, event) end
			end)
			unwatch = handle.sessions.listChanged:connect(function()
				if handle.sessions.get(session.id) ~= session then finish("cancelled", "", "conversation removed") end
			end)
			release = dispose.add(function()
				if not done then session.abort(); finish("cancelled", "", "client unloaded") end
			end, "embedding request")
			local called, accepted, why = pcall(session.send, text, function(reply)
				if done then return end
				if cancelled or aborted then finish("cancelled", reply, "aborted")
				elseif failure then finish("failed", reply, failure)
				elseif session.turns == turn and session.abortFlag then finish("cancelled", reply, "aborted")
				else finish("succeeded", reply) end
			end, options.files, options.images)
			if not called or not accepted then
				done = true
				cleanup(); completion:clear()
				return nil, called and why or tostring(accepted)
			end
			admitted = true
			deliver()
			return request
		end
		return sdk
	end
	return M
end
