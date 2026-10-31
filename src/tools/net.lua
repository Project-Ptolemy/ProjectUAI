-- HTTP from inside the agent: fetch a URL, call a JSON API.
--
-- These carry the Claude Code identity like every other request, because that is
-- the client's identity and there is no reason for a tool call to present a
-- different one. The web tools next door are the exception, and they say why.
return function(env)
	local util = env.require("runtime/util")
	local http = env.require("net/http")
	local H = env.require("tools/helpers")
	local N = env.require("tools/native_helpers").forGroup("net")

	local BODY_CAP = 5000

	local function headerTable(input)
		local out = {}
		for key, value in pairs(input or {}) do
			if type(key) == "string" and value ~= nil then out[key] = tostring(value) end
		end
		return out
	end
	local function timeout(args)
		return H.limit(args.timeout, 20, 120)
	end
	local function response(res, args)
		local body = tostring(res.body or "")
		local limit = math.min(H.limit(args.limit, BODY_CAP, 64000), math.max(128, H.resultBudget() - 480))
		local last = math.min(#body, limit)
		while last > 0 and body:byte(last + 1) and body:byte(last + 1) >= 128 and body:byte(last + 1) < 192 do last = last - 1 end
		local text, trimmed = body:sub(1, last), last < #body
		local data = { ok = res.ok == true, status = res.status, totalBytes = #body, truncated = trimmed == true }
		if trimmed then
			local key = N.retain({ body = body, status = res.status, ok = res.ok == true }, body, "net")
			data.resultId, data.readTool = key, key and "http_result_read" or nil
			data.detailsUnavailable = not key and "Response exceeded the retained-detail budget" or nil
			data.nextOffset = key and #text + 1 or nil
		end
		return { ok = data.ok, text = string.format("HTTP %s (%d bytes%s)\n%s", tostring(res.status), #body,
			data.resultId and "; use http_result_read section=text for the complete response" or trimmed and "; remaining response exceeded detail retention" or "", text), data = data }
	end

	local tools = {
		{
			name = "http_get",
			examples = { { title = "Read the published UI LIB guide", arguments = { url = "https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/main/docs/UI_LIBRARY.md", limit = 4000 },
				note = "The offline ui_library_docs reference is usually faster; this example is an explicit network read." } },
			risk = "read",
			needs = { "http" },
			description = "GET a URL. HTTP errors fail the call. Large bodies retain a five-minute result reference for http_result_read without another request.",
			timeout = function(args) return timeout(args) + 1 end,
			parameters = {
				type = "object",
				properties = {
					url = { type = "string" },
					timeout = { type = "integer", minimum = 1, maximum = 120, description = "Total request deadline in seconds, default 20." },
					headers = { type = "object", description = "Extra request headers." },
					limit = { type = "integer", description = "Maximum UTF-8 body bytes in this page; bounded by result budget. Default 5000.", minimum = 200, maximum = 64000 },
				},
				required = { "url" },
			},
			run = function(args, ctx)
				local res, err = http.send({
					url = args.url,
					method = "GET",
					headers = headerTable(args.headers),
					attempts = 2,
					timeout = timeout(args), aborted = ctx and ctx.aborted,
					tag = "tool:http_get",
				})
				if not res then return H.fail(err) end
				return response(res, args)
			end,
		},
		{
			name = "http_request",
			risk = "write",
			needs = { "http" },
			description = "Send one HTTP request with method and body. Writes are never retried. HTTP errors fail the call; large responses remain readable through http_result_read.",
			timeout = function(args) return timeout(args) + 1 end,
			parameters = {
				type = "object",
				properties = {
					url = { type = "string" },
					method = { type = "string", enum = { "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD" } },
					timeout = { type = "integer", minimum = 1, maximum = 120, description = "Total request deadline in seconds, default 20." },
					headers = { type = "object" },
					body = { type = "string", description = "Request body. JSON should be sent as a string." },
					limit = { type = "integer", minimum = 200, maximum = 64000 },
				},
				required = { "url", "method" },
			},
			run = function(args, ctx)
				local res, err = http.send({
					url = args.url,
					method = args.method,
					headers = headerTable(args.headers),
					body = args.body,
					attempts = 1,
					timeout = timeout(args), aborted = ctx and ctx.aborted,
					tag = "tool:http_request",
				})
				if not res then return H.fail(err) end
				return response(res, args)
			end,
		},
		{
			name = "json_api",
			risk = "read",
			needs = { "http" },
			description = "GET JSON and read a field by dotted path or exact keys (including keys containing dots). Large values retain a reference for http_result_read; false is a valid value and HTTP errors fail.",
			timeout = function(args) return timeout(args) + 1 end,
			parameters = {
				type = "object",
				properties = {
					url = { type = "string" },
					path = { type = "string", description = "Dotted path into the response. Array indexes are 1-based. Omit for the whole document." },
					keys = { type = "array", items = { type = "string" }, maxItems = 32, description = "Exact keys; array indexes as strings. Use instead of path for keys containing dots." },
					timeout = { type = "integer", minimum = 1, maximum = 120, description = "Total request deadline in seconds, default 20." },
					headers = { type = "object" },
				},
				required = { "url" },
			},
			run = function(args, ctx)
				if args.keys and args.path then return H.fail("use either keys or path, not both") end
				local decoded, err, res = http.json({
					url = args.url,
					method = "GET",
					headers = headerTable(args.headers),
					attempts = 2,
					timeout = timeout(args), aborted = ctx and ctx.aborted,
					tag = "tool:json_api",
				})
				if res and not res.ok then return response(res, args) end
				if decoded == nil then
					return H.fail(string.format("%s%s", tostring(err),
						res and (" (status " .. tostring(res.status) .. ")") or ""))
				end

				local target = decoded
				if args.keys or (args.path and util.trim(args.path) ~= "") then
					for _, part in ipairs(args.keys or util.split(args.path, ".")) do
						if type(target) ~= "table" then
							return H.fail("requested path does not exist in the response")
						end
						local value = target[part]
						if value == nil and tonumber(part) then value = target[tonumber(part)] end
						target = value
					end
					if target == nil then
						return H.fail("requested path is not present in the response")
					end
				end

				return N.result({ value = target, status = res and res.status }, "JSON response value")
			end,
		},
	}
	N.addReader(tools, "net")
	return tools
end
