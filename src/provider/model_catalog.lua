-- Interpret documented catalog kinds only on their exact public API routes.
-- Unknown schemas and manually entered IDs remain the user's choice.
return function(env)
	local urls = env.require("net/url")
	local M = {}
	local schemas = {
		["https://api.aimlapi.com/v1/models"] = { field = "type", kind = "openai/chat-completions" },
		["https://ai-gateway.vercel.sh/v1/models"] = { field = "type", kind = "language" },
		["https://api.friendli.ai/serverless/v1/models"] = { field = "mode", kind = "chat" },
		["https://api.venice.ai/api/v1/models"] = { field = "type", kind = "text" },
	}
	function M.accepts(url, row)
		if type(row) ~= "table" then return true end
		local parsed = urls.parse(url)
		if not parsed then return true end
		local route = parsed.scheme .. "://" .. parsed.authority:lower() .. parsed.path
		local authority = parsed.authority:lower()
		if not tostring(url):find("[?#]") and parsed.scheme == "https" and (authority == "opencode.ai" or authority == "opencode.ai:443")
			and (parsed.path == "/zen/v1/models" or parsed.path == "/inference/v1/models" or parsed.path == "/inference/openai/v1/models") then
			local kind = row.type
			return type(kind) ~= "string" or kind == "" or kind == "chat" or kind == "language"
		end
		local schema = schemas[route]
		if not schema then return true end
		local kind = row[schema.field]
		return type(kind) ~= "string" or kind == "" or kind == schema.kind
	end
	return M
end
