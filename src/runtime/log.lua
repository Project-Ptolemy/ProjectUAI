-- Structured log with a bounded history.
--
-- Two audiences: the developer, who wants the last hundred lines including HTTP
-- detail, and the user, who occasionally needs to see why a provider rejected
-- them. Both read the same ring buffer through the Logs panel, so nothing is
-- printed to the console by default -- an in-game script that spams output is
-- indistinguishable from a broken one.
return function(env)
	local util = env.require("runtime/util")
	local signal = env.require("runtime/signal")
	local search = env.require("runtime/search")

	local LIMIT = 400

	local M = {
		entries = {},
		changed = signal.new("log"),
		mirror = false,
		minLevel = 1,
	}

	local LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }

	-- Published so a settings surface can set the floor by name rather than by
	-- guessing which integer "warn" is.
	M.LEVELS = LEVELS

	function M.setLevel(level)
		M.minLevel = LEVELS[tostring(level)] or 2
		return M.minLevel
	end

	-- An API key must never reach the buffer in full: the panel is screenshot and
	-- pasted into bug reports. Anything key-shaped keeps a four-character tail so
	-- a user can still tell two keys apart.
	local function redact(text)
		text = tostring(text)
		local function masked(value)
			return #value > 4 and ("..." .. value:sub(-4)) or "..."
		end
		local function secretField(key)
			key = key:lower():gsub("[_%-]", "")
			return key == "key" or key == "apikey" or key == "xapikey" or key == "token"
				or key == "accesstoken" or key == "refreshtoken" or key == "password"
				or key == "secret" or key == "clientsecret" or key == "authorization"
		end
		text = text:gsub('("([%w_%-]+)"%s*:%s*")([^"]*)(")', function(open, key, value, close)
			return open .. (secretField(key) and masked(value) or value) .. close
		end)
		text = text:gsub("([?&]([%w_%-]+)=)([^&#%s]+)", function(open, key, value)
			return open .. (secretField(key) and masked(value) or value)
		end)
		text = text:gsub("([%w_%-]+)(%s*[:=]%s*)([^%s,;]+)", function(key, separator, value)
			if secretField(key) and value:lower() ~= "bearer" then return key .. separator .. masked(value) end
			return key .. separator .. value
		end)
		text = text:gsub("(sk%-[%w%-_]*)([%w%-_][%w%-_][%w%-_][%w%-_])", function(_, tail)
			return "sk-..." .. tail
		end)
		for _, prefix in ipairs({ "oc_sk_", "ghp_", "gho_", "ghu_", "ghs_", "ghr_", "github_pat_", "xox[baprs]%-", "AKIA" }) do
			text = text:gsub(prefix .. "[%w_%-]+", function(value) return masked(value) end)
		end
		text = text:gsub("eyJ[%w_%-]+%.eyJ[%w_%-]+%.[%w_%-]+", masked)
		text = text:gsub("([Bb]earer%s+)[%w%.%-_]+([%w%.%-_][%w%.%-_][%w%.%-_][%w%.%-_])", "%1...%2")
		text = text:gsub('("api[_%-]?key"%s*:%s*")[^"]*([^"][^"][^"][^"])(")', "%1...%2%3")
		return text
	end
	M.redact = redact
	local function bounded(value, limit)
		local text = redact(value)
		return util.truncate(text, limit)
	end

	local function push(level, source, message, detail)
		if (LEVELS[level] or 2) < M.minLevel then return end
		if level == "warn" or level == "error" then message = env.require("runtime/support").error(message) end
		local entry = {
			at = env.require("runtime/clock").ms(),
			stamp = env.require("runtime/clock").stamp(),
			level = level,
			source = bounded(source or "app", 256),
			message = bounded(message, 8192),
			detail = detail ~= nil and bounded(type(detail) == "table" and util.concatKeys(detail) or tostring(detail), 16384) or nil,
		}
		M.entries[#M.entries + 1] = entry
		if #M.entries > LIMIT then
			-- Drop in blocks rather than one per push: table.remove(1) on a 400
			-- entry list on every log line is a copy each time.
			local kept = {}
			for index = math.floor(LIMIT * 0.25) + 1, #M.entries do kept[#kept + 1] = M.entries[index] end
			M.entries = kept
		end
		if M.mirror then
			local line = string.format("[uai:%s] %s: %s", entry.level, entry.source, entry.message)
			if level == "error" or level == "warn" then pcall(warn, line) else pcall(print, line) end
		end
		M.changed:fire(entry)
		return entry
	end

	function M.debug(source, message, detail) return push("debug", source, message, detail) end
	function M.info(source, message, detail) return push("info", source, message, detail) end
	function M.warn(source, message, detail) return push("warn", source, message, detail) end
	function M.error(source, message, detail) return push("error", source, message, detail) end

	function M.tail(count)
		local from = math.max(#M.entries - (count or 50) + 1, 1)
		return util.slice(M.entries, from, #M.entries)
	end

	function M.filter(level, text)
		local wanted = LEVELS[level] or 1
		local match = search.compile(text)
		local out = {}
		for _, entry in ipairs(M.entries) do
			if (LEVELS[entry.level] or 2) >= wanted then
				if match(entry.source, entry.message, entry.detail, entry.level) then
					out[#out + 1] = entry
				end
			end
		end
		return out
	end

	function M.clear()
		M.entries = {}
		M.changed:fire(nil)
	end

	function M.export()
		local lines = {}
		for _, entry in ipairs(M.entries) do
			lines[#lines + 1] = string.format("%s %-5s %-14s %s%s",
				entry.stamp, entry.level:upper(), entry.source, entry.message,
				entry.detail and ("  " .. entry.detail) or "")
		end
		return table.concat(lines, "\n")
	end

	return M
end
