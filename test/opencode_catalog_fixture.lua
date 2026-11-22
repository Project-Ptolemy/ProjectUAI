-- Explicit synthetic Zen facts. Model names never imply price or protocol.
local M = {}
function M.row(id, opts)
	opts = opts or {}
	return { id = id, object = "model", type = opts.kind or "chat",
		cost = opts.cost or { text = { input = { price = 0, cache = { read = 0, write = 0 } }, output = { price = 0 } } },
		api = opts.api or { ["chat-completions"] = { base_url = "https://opencode.ai/inference/openai/v1" } },
		recommended_api = opts.protocol or "chat-completions", capabilities = { tools = { supported = true } } }
end
function M.observe(f, record, rows)
	local url = f.env.require("provider/registry").endpoint(record, "/models")
	assert(f.env.require("provider/opencode_public").observe(record, url, { data = rows or { M.row(record.model) } }))
end
function M.responses(f, record, chat)
	local api = { responses = { base_url = "https://opencode.ai/inference/openai/v1" } }
	if chat then api["chat-completions"] = { base_url = "https://opencode.ai/inference/openai/v1" } end
	M.observe(f, record, { M.row(record.model, { api = api, protocol = chat and "chat-completions" or "responses" }) })
end
return M
