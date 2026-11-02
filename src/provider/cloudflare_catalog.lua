-- Workers AI lists models outside its OpenAI-compatible inference prefix.
return function(env)
	local urls = env.require("net/url")
	local util = env.require("runtime/util")
	local M = {}
	local function catalogPath(url)
		local parsed = urls.parse(url)
		if not parsed or parsed.scheme ~= "https" or parsed.authority:lower() ~= "api.cloudflare.com" then return nil end
		return parsed, parsed.path:match("^(/client/v4/accounts/[%w_-]+/ai)/v1/models$")
	end
	function M.endpoint(url)
		local parsed, path = catalogPath(url)
		if not path then return url, false end
		local base = parsed.scheme .. "://" .. parsed.authority .. path .. (parsed.query and ("?" .. parsed.query) or "")
		return urls.endpoint(base, "/models/search", { page = 1, per_page = 100 }), true
	end
	function M.page(url, page)
		local parsed = urls.parse(url)
		local base = parsed.scheme .. "://" .. parsed.authority .. parsed.path:gsub("/models/search$", "") .. (parsed.query and ("?" .. parsed.query) or "")
		return urls.endpoint(base, "/models/search", { page = page })
	end
	function M.rows(decoded)
		if type(decoded) ~= "table" or decoded.success == false or not util.isArray(decoded.result) then return nil end
		return decoded.result
	end
	function M.nextPage(decoded, page)
		local rows = M.rows(decoded)
		if not rows or #rows == 0 then return nil end
		local info = type(decoded.result_info) == "table" and decoded.result_info or {}
		if type(info.total_pages) == "number" and info.total_pages >= 0 then return info.total_pages > page and page + 1 or nil end
		if type(info.total_count) == "number" and type(info.per_page) == "number" and info.per_page > 0 and info.total_count <= page * info.per_page then return nil end
		if type(info.per_page) == "number" and info.per_page > 0 and #rows < info.per_page then return nil end
		-- The official SDK continues until an empty result when totals are absent.
		return page + 1
	end
	function M.id(row)
		-- id identifies the catalog record; name is the model sent to inference.
		return type(row) == "table" and row.name or type(row) == "string" and row or nil
	end
	function M.accepts(row)
		local task = type(row) == "table" and row.task
		local name = type(task) == "table" and task.name or nil
		return type(name) ~= "string" or name == "" or name == "Text Generation"
	end
	return M
end
