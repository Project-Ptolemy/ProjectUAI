-- Exact, provider-scoped catalog lookup. Model names are not price aliases.
return function(env)
	local data = env.require("provider/model_data")
	local urls = env.require("net/url")
	local M = { updated = data.updated }
	local HOSTS = {
		["api.openai.com"] = "openai", ["api.anthropic.com"] = "anthropic",
		["generativelanguage.googleapis.com"] = "google", ["api.deepseek.com"] = "deepseek",
		["openrouter.ai"] = "openrouter", ["api.groq.com"] = "groq",
		["api.together.xyz"] = "together", ["api.together.ai"] = "together",
		["api.mistral.ai"] = "mistral", ["api.x.ai"] = "xai",
		["api.fireworks.ai"] = "fireworks", ["api.cerebras.ai"] = "cerebras",
	}
	local PRESETS = {
		["anthropic-messages"] = "anthropic", zen = "opencode", ["fireworks-ai"] = "fireworks",
	}
	local ROUTES = {
		openai = { ["/v1"] = true }, anthropic = { ["/v1"] = true },
		google = { ["/v1"] = true, ["/v1beta"] = true, ["/v1beta/openai"] = true },
		deepseek = { ["/v1"] = true, ["/beta"] = true }, openrouter = { ["/api/v1"] = true },
		groq = { ["/openai/v1"] = true }, together = { ["/v1"] = true },
		mistral = { ["/v1"] = true }, xai = { ["/v1"] = true },
		fireworks = { ["/inference/v1"] = true }, cerebras = { ["/v1"] = true },
	}
	local DIRECT = { "openai", "anthropic", "google", "deepseek", "mistral", "xai" }
	local DEFAULTS = {}
	for _, provider in ipairs(DIRECT) do
		for id, row in pairs(data.providers[provider] or {}) do
			if not DEFAULTS[id] then DEFAULTS[id] = row end
			DEFAULTS[provider .. "/" .. id] = row
		end
	end
	-- Exact reseller ids have meaning only on that reseller, or as a model-only
	-- estimate when the caller has no provider record. Never strip a :free suffix.
	for _, provider in ipairs({ "opencode", "openrouter" }) do
		for id, row in pairs(data.providers[provider] or {}) do
			if not DEFAULTS[id] then DEFAULTS[id] = row end
		end
	end

	function M.provider(record)
		if type(record) ~= "table" then return nil end
		local raw = tostring(record.baseUrl or "")
		if raw ~= "" then
			local parsed = urls.parse(urls.normaliseBase(raw))
			if not parsed then return nil end
			if parsed.scheme ~= "https" or parsed.authority:lower() ~= parsed.host and parsed.authority:lower() ~= parsed.host .. ":443" then return nil end
			if parsed.scheme == "https" and (parsed.host == "api.kilo.ai" or parsed.host == "ai-gateway.kilo.ai") then
				local authority = parsed.authority:lower()
				if authority ~= parsed.host and authority ~= parsed.host .. ":443" then return nil end
				local path = parsed.path:gsub("/+$", "")
				for _, route in ipairs({ "/api/gateway", "/api/gateway/v1", "/api/v1" }) do
					if path == route or path == route .. "/chat/completions" or path == route .. "/responses" or path == route .. "/messages" then return "kilo" end
				end
				return nil
			end
			if env.require("net/tunnel_route").isClineBase(raw) then return "cline" end
			if parsed.host == "opencode.ai" then
				local path = parsed.path:lower():gsub("/+$", "")
				for _, route in ipairs({ "/inference/go/v1", "/zen/go/v1" }) do
					if path == route or path:sub(1, #route + 1) == route .. "/" then return "opencode-go" end
				end
				for _, route in ipairs({ "/zen/v1", "/inference/v1", "/inference/openai/v1" }) do
					if path == route or path:sub(1, #route + 1) == route .. "/" then return "opencode" end
				end
				return nil
			end
			local provider = HOSTS[parsed.host]
			local route = parsed.path:gsub("/+$", "")
			route = route:match("^(.*)/models/[^/]+:generateContent$") or route:match("^(.*)/models/[^/]+:streamGenerateContent$")
				or route:match("^(.*)/chat/completions$") or route:match("^(.*)/messages$")
				or route:match("^(.*)/responses$") or route:match("^(.*)/models$") or route
			return provider and ROUTES[provider] and ROUTES[provider][route] and provider or nil
		end
		local preset = tostring(record.preset or "")
		return PRESETS[preset] or (data.providers[preset] and preset or nil)
	end

	function M.lookup(model, record)
		local id = tostring(model or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
		if record then
			local provider = M.provider(record)
			return provider and (data.providers[provider] or {})[id] or nil
		end
		return DEFAULTS[id]
	end

	-- Capabilities can still use the documented underlying model for a custom
	-- gateway. Pricing deliberately cannot: that gateway sets its own rates.
	function M.capabilities(model, record)
		return M.lookup(model, record) or M.lookup(model)
	end
	return M
end
