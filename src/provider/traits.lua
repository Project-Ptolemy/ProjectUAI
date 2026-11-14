-- What a model accepts, and how much it can hold.
--
-- Every gateway claims to be OpenAI-compatible and none of them publishes
-- capabilities: /models returns ids, not limits. So the facts that change how a
-- request must be built live here, in one table, rather than being rediscovered
-- from a 400 at each call site.
--
-- Current limits come from the reviewed provider catalog. The small hand-written
-- table retains protocol facts: a generic reasoning flag cannot establish which
-- wire-level thinking parameters an endpoint accepts.
return function(env)
	local config = env.require("runtime/config")
	local info = env.require("provider/model_info")

	local M = {}

	-- context  the input window, in tokens.
	-- output   the ceiling on a single reply, in tokens.
	-- sampling false where temperature/top_p/top_k are rejected or documented as
	--          unsupported. Absent means "send them", which is what every other model
	--          in this client has always had.
	-- effort   the levels `output_config.effort` accepts, cheapest first, or absent
	--          where the model has no effort control.
	-- thinking "adaptive" for models that reason without a token budget and take
	--          `{ type = "adaptive" }`; "budget" for the older shape that requires
	--          `budget_tokens`. Absent means the model does not expose reasoning.
	-- default  the effort level the API itself uses when none is sent, so the
	--          interface can mark it rather than implying the client picked it.
	local FIVE = { "low", "medium", "high", "xhigh", "max" }
	local FOUR = { "low", "medium", "high", "max" }
	local SIX = { "none", "low", "medium", "high", "xhigh", "max" }

	local TRAITS = {
		-- Explicit Responses effort scales from the official model references.
		-- Context and reply limits continue to come from provider-scoped metadata.
		["gpt-6.1-sol"] = { sampling = false, effort = FIVE, default = "medium", exact = true },
		["gpt-6-astra"] = { sampling = false, effort = FIVE, exact = true },
		["gpt-6.1-terra"] = { effort = SIX, default = "medium", exact = true },
		["gpt-6-sol"] = { effort = SIX, default = "medium", exact = true },
		["gpt-6-luna"] = { effort = SIX, default = "medium", exact = true },
		["gpt-5.6-sol"] = { effort = SIX, default = "medium", exact = true },
		["gpt-5.6"] = { effort = SIX, default = "medium", exact = true },
		["gemini-2.5-pro"] = { effort = { "low", "medium", "high" }, thinking = "gemini-budget", thinkingMax = 32768 },
		["gemini-2.5-flash"] = { effort = { "low", "medium", "high" }, thinking = "gemini-budget", thinkingMax = 24576 },
		["gemini-2.5-flash-image"] = {},
		["gemini-3-pro"] = { effort = { "low", "high" }, thinking = "gemini-level", default = "high" },
		["gemini-3-pro-image"] = {},
		["gemini-3.1-pro"] = { effort = { "low", "medium", "high" }, thinking = "gemini-level", default = "high" },
		["gemini-3-flash"] = { effort = { "minimal", "low", "medium", "high" }, thinking = "gemini-level", default = "high" },
		["gemini-3.1-flash-lite"] = { effort = { "minimal", "low", "medium", "high" }, thinking = "gemini-level", default = "minimal" },
		-- Google's native API reference explicitly retires sampling on 3.6 Flash
		-- and newer Flash models. Unknown future families retain default handling.
		["gemini-3.6-flash"] = { sampling = false, effort = { "low", "medium", "high" }, thinking = "gemini-level" },
		["gemini-3.7-flash"] = { sampling = false, effort = { "low", "medium", "high" }, thinking = "gemini-level" },
		["gemini-3.8-flash"] = { sampling = false, effort = { "low", "medium", "high" }, thinking = "gemini-level", default = "medium" },
		-- Gemini 4 shares input/thinking/output in one window. Its 64K streaming
		-- ceiling does not raise Carbon/Argon's separate 32K non-streaming hop.
		["gemini-4-carbon"] = { sampling = false, effort = { "low", "medium", "high" }, thinking = "gemini-level",
			default = "medium", nonStreamingOutput = 32768, exact = true },
		["gemini-4-argon"] = { sampling = false, effort = { "low", "medium", "high" }, thinking = "gemini-level",
			default = "medium", nonStreamingOutput = 32768, exact = true },
		["gemini-4-hydrogen"] = { sampling = false, effort = { "low", "medium", "high", "xhigh" },
			thinking = "gemini-level", default = "high", exact = true },
		["claude-fable-5-2"] = { sampling = false, effort = FIVE, thinking = "adaptive", default = "high", alwaysThinks = true, exact = true },
		["claude-mythos-5-2"] = { sampling = false, effort = FIVE, thinking = "adaptive", default = "high", alwaysThinks = true, exact = true },
		["claude-fable-5.2"] = { sampling = false, effort = FIVE, thinking = "adaptive", default = "high", alwaysThinks = true, exact = true },
		["claude-mythos-5.2"] = { sampling = false, effort = FIVE, thinking = "adaptive", default = "high", alwaysThinks = true, exact = true },
		["claude-fable-5-1"] = { context = 1000000, output = 128000, sampling = false,
			effort = FIVE, thinking = "adaptive", default = "high", alwaysThinks = true },
		["claude-mythos-5-1"] = { context = 1000000, output = 128000, sampling = false,
			effort = FIVE, thinking = "adaptive", default = "high", alwaysThinks = true },
		["claude-fable-5"] = { context = 1000000, output = 128000, sampling = false,
			effort = FIVE, thinking = "adaptive", default = "high", alwaysThinks = true },
		-- Opus 5 thinks by default, unlike 4.8 and 4.7, and refuses a disabled
		-- thinking block above effort "high".
		["claude-opus-5"] = { context = 1000000, output = 128000, sampling = false,
			effort = FIVE, thinking = "adaptive", default = "high" },
		["claude-opus-4-8"] = { context = 1000000, output = 128000, sampling = false,
			effort = FIVE, thinking = "adaptive", default = "high" },
		["claude-opus-4-7"] = { context = 1000000, output = 128000, sampling = false,
			effort = FIVE, thinking = "adaptive", default = "high" },
		-- 4.6 is the last generation that still takes sampling parameters, and its
		-- effort scale has no "xhigh".
		["claude-opus-4-6"] = { context = 1000000, output = 128000,
			effort = FOUR, thinking = "adaptive", default = "high" },
		["claude-sonnet-5"] = { context = 1000000, output = 128000, sampling = false,
			effort = FIVE, thinking = "adaptive", default = "high" },
		["claude-sonnet-4-6"] = { context = 1000000, output = 128000,
			effort = FOUR, thinking = "adaptive", default = "high" },
		["claude-haiku-4-5"] = { context = 200000 },
		["cat-jam"] = { context = 262144, maxTools = 128, thinking = "adaptive", default = "high" },
	}

	local EMPTY = {}

	-- What the user has told this client to assume about a model id, in place of
	-- what this table documents. Gateways relay ids this table has never heard of
	-- -- "openrouter/qwen3-235b", a relay's own spelling of a frontier model -- and
	-- the honest answer to those used to be "no reasoning, no badge", when the user
	-- knows perfectly well the model behind the id thinks and holds a million tokens.
	-- `agent.forceReasoning` / `agent.forceContext` are those two claims, keyed by
	-- the lowercased model id. A forced context also feeds what the sliders clamp
	-- against, which is what makes a 1M setting real rather than decorative.
	local function forced(model)
		local id = tostring(model or ""):lower()
		if id == "" then return nil end
		local reasoning = config.get("agent.forceReasoning", {}) or {}
		local contexts = config.get("agent.forceContext", {}) or {}
		return {
			thinking = reasoning[id] == true and "adaptive" or nil,
			context = tonumber(contexts[id]) or nil,
		}
	end

	function M.of(model, record)
		local id = tostring(model or ""):lower()
		if id == "" then return EMPTY end
		local best, bestLength = EMPTY, 0
		for prefix, traits in pairs(TRAITS) do
			local matches = id:find(prefix, 1, true)
			if traits.exact then matches = id == prefix or id:sub(-#prefix - 1) == "/" .. prefix end
			if matches and #prefix > bestLength then
				best, bestLength = traits, #prefix
			end
		end
		local documented = info.capabilities(id, record)
		if not documented then return best end
		local merged = {}
		for key, value in pairs(best) do merged[key] = value end
		merged.context = documented.context or merged.context
		merged.input = documented.input
		merged.output = documented.output or merged.output
		merged.tools = documented.tools
		merged.reasoning = documented.reasoning
		return merged
	end

	function M.contextWindow(model, record)
		local id = tostring(model or ""):lower()
		local over = tonumber((config.get("agent.forceContext", {}) or {})[id])
		if over and over >= 1 and over < math.huge then return math.floor(over) end
		local row = M.of(model, record)
		return row.input and row.context and math.min(row.input, row.context) or row.input or row.context
	end

	function M.maxOutput(model, record)
		return M.of(model, record).output
	end

	function M.maxTools(model)
		return M.of(model).maxTools
	end

	-- True unless the model is documented to reject them. Withholding a parameter a
	-- model would have accepted changes behaviour for every gateway this client
	-- talks to, so silence is not the safe default here -- only a known refusal is.
	function M.allowsSampling(model)
		return M.of(model).sampling ~= false
	end

	function M.effortLevels(model)
		return M.of(model).effort
	end

	function M.defaultEffort(model)
		return M.of(model).default
	end

	-- The nearest level this model actually has, never rounding up: asking for
	-- "xhigh" on a scale that stops at "high" must land on "high" rather than
	-- spending "max", because the setting is a ceiling the user chose.
	local RANK = { none = -1, minimal = 0, low = 1, medium = 2, high = 3, xhigh = 4, max = 5 }

	function M.nearestEffort(model, wanted)
		local levels = M.effortLevels(model)
		-- A model with no documented scale but a manual reasoning claim has no
		-- levels to clamp against, so the wanted level passes through: the user
		-- said it reasons, and this client has no basis to round them down.
		if not levels then
			if M.thinkingStyle(model) then return tostring(wanted or "") ~= "" and wanted or nil end
			return nil
		end
		local target = RANK[tostring(wanted or ""):lower()]
		if not target then return nil end
		local best
		for _, level in ipairs(levels) do
			local rank = RANK[level]
			if rank == target then return level end
			if rank and rank < target and (not best or RANK[best] < rank) then best = level end
		end
		-- Every level this model has sits above what was asked for, so the cheapest
		-- of them is the closest thing to it.
		return best or levels[1]
	end

	function M.thinkingStyle(model)
		local id = tostring(model or ""):lower()
		if (config.get("agent.forceReasoning", {}) or {})[id] == true then
			return "adaptive"
		end
		return M.of(model).thinking
	end

	function M.alwaysThinks(model)
		return M.of(model).alwaysThinks == true
	end

	-- A short badge for the model pickers: "1M", "200K". Nil when unknown, so a
	-- row for an id this table has never heard of simply has no badge. A manually
	-- declared context is a fact the user stated, so it earns the same badge.
	function M.badge(model, record)
		local context = M.contextWindow(model, record)
		if not context then return nil end
		if context >= 1000000 then
			local millions = context / 1000000
			return (millions % 1 == 0) and string.format("%dM", millions)
				or string.format("%.1fM", millions)
		end
		if context >= 1000 then return string.format("%dK", math.floor(context / 1000)) end
		return tostring(context)
	end

	M.TRAITS = TRAITS

	return M
end
