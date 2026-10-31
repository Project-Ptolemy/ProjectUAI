-- Offline protocol contracts. Every response is synthetic; no model or key is used.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Provider compatibility")
local case, check = suite.case, suite.check
local function has(text, part) return tostring(text):find(part, 1, true) ~= nil end
local function recordFor(f, preset)
	local record = f.env.require("provider/registry").blank(preset or "custom")
	record.id, record.label, record.model = "fixture-" .. (preset or "custom"), "Fixture provider", "fixture/model:instruct"
	record.models = { record.model }
	if record.baseUrl == "" then record.baseUrl = "https://fixture.test/proxy/v1" end
	if preset ~= "projectuai-free" then record.apiKey = record.authStyle == "none" and "" or "fixture-key" end
	return record
end
local function jsonReply(f, text)
	return { StatusCode = 200, Body = f.h.json.encode({ choices = { { message = { role = "assistant", content = text or "ok" }, finish_reason = "stop" } } }) }
end
local function complete(f, record, request)
	return f.run(function() return f.env.require("provider/chat").complete(record, request or { messages = { { role = "user", content = "hello" } }, stream = false }) end)
end
local TOOLS = { { type = "function", ["function"] = { name = "fixture_tool", description = "Synthetic tool",
	parameters = { type = "object", properties = { value = { type = "string" } }, required = { "value" } } } } }

-- Expected routes are intentionally independent of registry.endpoint(). Catalog
-- additions must add a row here; the suite cannot quietly skip a new preset.
local MATRIX = {
	{ "agentrouter", "https://agentrouter.org/v1", "anthropic", "x-api-key" },
	{ "hcnsec", "https://api.hcnsec.cn/v1", "openai", "bearer" },
	{ "projectuai-free", "https://api.hcnsec.cn/v1", "openai", "bearer" },
	{ "kilo", "https://api.kilo.ai/api/gateway", "openai", "none" },
	{ "vercel", "https://ai-gateway.vercel.sh/v1", "openai", "bearer" },
	{ "perplexity", "https://api.perplexity.ai/orchestrator/v1", "openai", "bearer" },
	{ "friendli", "https://api.friendli.ai/serverless/v1", "openai", "bearer" },
	{ "venice", "https://api.venice.ai/api/v1", "openai", "bearer" },
	{ "nscale", "https://inference.api.nscale.com/v1", "openai", "bearer" },
	{ "arcee", "https://api.arcee.ai/api/v1", "openai", "bearer" },
	{ "aimlapi", "https://api.aimlapi.com/v1", "openai", "bearer" },
	{ "ovh", "https://oai.endpoints.kepler.ai.cloud.ovh.net/v1", "openai", "none" },
	{ "google", "https://generativelanguage.googleapis.com/v1beta", "gemini", "x-goog-api-key" },
	{ "groq", "https://api.groq.com/openai/v1", "openai", "bearer" },
	{ "cerebras", "https://api.cerebras.ai/v1", "openai", "bearer" },
	{ "mistral", "https://api.mistral.ai/v1", "openai", "bearer" },
	{ "modelscope", "https://api-inference.modelscope.cn/v1", "openai", "bearer" },
	{ "zai", "https://api.z.ai/api/paas/v4", "openai", "bearer" },
	{ "nvidia", "https://integrate.api.nvidia.com/v1", "openai", "bearer" },
	{ "cloudflare", "https://api.cloudflare.com/client/v4/accounts/YOUR-ACCOUNT-ID/ai/v1", "openai", "bearer" },
	{ "aionlabs", "https://api.aionlabs.ai/v1", "openai", "bearer" },
	{ "openai", "https://api.openai.com/v1", "openai", "bearer" },
	{ "anthropic-messages", "https://api.anthropic.com/v1", "anthropic", "x-api-key" },
	{ "anthropic", "https://api.anthropic.com/v1", "openai", "x-api-key" },
	{ "openrouter", "https://openrouter.ai/api/v1", "openai", "bearer" },
	{ "deepseek", "https://api.deepseek.com/v1", "openai", "bearer" },
	{ "xai", "https://api.x.ai/v1", "openai", "bearer" },
	{ "together", "https://api.together.xyz/v1", "openai", "bearer" },
	{ "fireworks", "https://api.fireworks.ai/inference/v1", "openai", "bearer" },
	{ "deepinfra", "https://api.deepinfra.com/v1/openai", "openai", "bearer" },
	{ "hyperbolic", "https://api.hyperbolic.xyz/v1", "openai", "bearer" },
	{ "nebius", "https://api.studio.nebius.com/v1", "openai", "bearer" },
	{ "novita", "https://api.novita.ai/v3/openai", "openai", "bearer" },
	{ "sambanova", "https://api.sambanova.ai/v1", "openai", "bearer" },
	{ "moonshot", "https://api.moonshot.ai/v1", "openai", "bearer" },
	{ "dashscope", "https://dashscope-intl.aliyuncs.com/compatible-mode/v1", "openai", "bearer" },
	{ "siliconflow", "https://api.siliconflow.cn/v1", "openai", "bearer" },
	{ "volcengine", "https://ark.cn-beijing.volces.com/api/v3", "openai", "bearer" },
	{ "hunyuan", "https://api.hunyuan.cloud.tencent.com/v1", "openai", "bearer" },
	{ "qianfan", "https://qianfan.baidubce.com/v2", "openai", "bearer" },
	{ "stepfun", "https://api.stepfun.com/v1", "openai", "bearer" },
	{ "yi", "https://api.lingyiwanwu.com/v1", "openai", "bearer" },
	{ "baichuan", "https://api.baichuan-ai.com/v1", "openai", "bearer" },
	{ "spark", "https://spark-api-open.xf-yun.com/v1", "openai", "bearer" },
	{ "upstage", "https://api.upstage.ai/v1/solar", "openai", "bearer" },
	{ "reka", "https://api.reka.ai/v1", "openai", "bearer" },
	{ "ai21", "https://api.ai21.com/studio/v1", "openai", "bearer" },
	{ "cohere", "https://api.cohere.ai/compatibility/v1", "openai", "bearer" },
	{ "huggingface", "https://router.huggingface.co/v1", "openai", "bearer" },
	{ "ollama-cloud", "https://ollama.com/v1", "openai", "bearer" },
	{ "baseten", "https://inference.baseten.co/v1", "openai", "bearer" },
	{ "kluster", "https://api.kluster.ai/v1", "openai", "bearer" },
	{ "chutes", "https://llm.chutes.ai/v1", "openai", "bearer" },
	{ "featherless", "https://api.featherless.ai/v1", "openai", "bearer" },
	{ "nano-gpt", "https://nano-gpt.com/api/v1", "openai", "bearer" },
	{ "requesty", "https://router.requesty.ai/v1", "openai", "bearer" },
	{ "scaleway", "https://api.scaleway.ai/v1", "openai", "bearer" },
	{ "runpod", "https://api.runpod.ai/v2/YOUR-ENDPOINT-ID/openai/v1", "openai", "bearer" },
	{ "azure-foundry", "https://YOUR-RESOURCE.openai.azure.com/openai/v1", "openai", "api-key" },
	{ "azure", "https://YOUR-RESOURCE.openai.azure.com/openai/deployments/YOUR-DEPLOYMENT", "openai", "api-key", "?api-version=2024-10-21" },
	{ "zen", "https://opencode.ai/zen/v1", "openai", "bearer" },
	{ "opencode-go", "https://opencode.ai/inference/go/v1", "openai", "bearer" },
	{ "ollama", "http://127.0.0.1:11434/v1", "openai", "none" },
	{ "lmstudio", "http://127.0.0.1:1234/v1", "openai", "none" },
	{ "vllm", "http://127.0.0.1:8000/v1", "openai", "none" },
	{ "llamacpp", "http://127.0.0.1:8080/v1", "openai", "none" },
	{ "sglang", "http://127.0.0.1:30000/v1", "openai", "none" },
	{ "localai", "http://127.0.0.1:8080/v1", "openai", "none" },
	{ "koboldcpp", "http://127.0.0.1:5001/v1", "openai", "none" },
	{ "textgen", "http://127.0.0.1:5000/v1", "openai", "none" },
	{ "jan", "http://127.0.0.1:1337/v1", "openai", "none" },
	{ "litellm", "http://127.0.0.1:4000/v1", "openai", "none" },
	{ "openwebui", "http://127.0.0.1:3000/api", "openai", "bearer" },
	{ "custom", "https://fixture.test/proxy/v1", "openai", "bearer" },
}

case("the protocol matrix covers every advertised preset", function()
	local f = F.new(); local wanted = {}
	for _, row in ipairs(MATRIX) do wanted[row[1]] = true end
	-- Cline is deliberately not a direct HTTP adapter. Its transport, identity,
	-- discovery and cancellation coverage lives in test/cline.lua.
	wanted.cline = true
	local presets = f.env.require("provider/catalog").presets
	check("matrix/catalog count agrees", #presets == #MATRIX + 1)
	for _, preset in ipairs(presets) do check("coverage for " .. preset.id, wanted[preset.id] == true) end
	local cline = f.env.require("provider/registry").blank("cline")
	check("Cline keeps its independent virtual route and no-auth contract", cline.baseUrl == "https://uai-tunnel.invalid/cline/v1"
		and cline.api == "openai" and cline.authStyle == "none" and cline.claudeUa == false)
	f.healthy(); f.close()
end)

for _, row in ipairs(MATRIX) do
	case(row[1] .. " discovers, calls tools and replays results over JSON/SSE", function()
		local f = F.new(); local record = recordFor(f, row[1]); local native = row[3] == "anthropic"
		if row[1] == "projectuai-free" then
			f.env.require("runtime/clock").ms = function() return 1767268800000 + f.h.sched.now * 1000 end
		end
		local gemini = row[3] == "gemini"
		if gemini then record.model = "fixture-model" end
		local posts, seenBodies = 0, {}
		check("preset wire/auth", record.api == row[3] and record.authStyle == row[4])
		f.h.http.handler = function(entry)
			local header = f.env.require("net/headers").get
			if row[4] == "none" then
				check("no unsolicited local credentials/identity", not header(entry.headers, "Authorization") and not header(entry.headers, "x-api-key") and not header(entry.headers, "x-app"))
			elseif row[4] == "bearer" then check("Bearer auth", header(entry.headers, "Authorization") == "Bearer " .. record.apiKey)
			else check("named auth header", header(entry.headers, row[4]) == "fixture-key") end
			if native then check("Messages version header", header(entry.headers, "anthropic-version") == "2023-06-01") end
			if entry.method == "GET" then
				check("model discovery route", entry.url == row[2] .. "/models" .. (row[5] or ""))
				return { StatusCode = 200, Body = f.h.json.encode({ data = { { id = record.model }, { id = "embedding-fixture" } } }) }
			end
			local route = gemini and ("/models/fixture-model:" .. (posts == 0 and "generateContent?alt=json" or "streamGenerateContent?alt=sse"))
				or native and "/messages" or "/chat/completions"
			check("completion route", entry.url == row[2] .. route .. (row[5] or ""))
			posts = posts + 1
			local body = f.h.json.decode(entry.body); seenBodies[posts] = body
			check("model/deployment selection", (row[1] == "azure" or gemini) and body.model == nil or row[1] ~= "azure" and body.model == record.model)
			check("effective Accept header", header(entry.headers, "Accept") == ((row[1] == "zen" or row[1] == "opencode-go") and "*/*" or ((body.stream or gemini and posts > 1) and "text/event-stream" or "application/json")))
			check("tools reach the server", type(body.tools) == "table" and #body.tools > 0)
			if row[1] == "ollama" then check("Ollama avoids unsupported defaults", body.tool_choice == nil and body.parallel_tool_calls == nil) end
			if posts == 1 then
				if gemini then return { StatusCode = 200, Body = f.h.json.encode({ modelVersion = record.model, candidates = { {
					content = { role = "model", parts = { { text = "using a tool" }, { functionCall = { id = "call-fixture", name = "fixture_tool", args = { value = row[1] } }, thoughtSignature = "fixture-signature" } } },
					finishReason = "STOP" } }, usageMetadata = { promptTokenCount = 17, candidatesTokenCount = 8 } }) } end
				if native then
					return { StatusCode = 200, Body = f.h.json.encode({ type = "message", role = "assistant", id = "fixture-message", model = record.model,
						content = { { type = "text", text = "using a tool" }, { type = "tool_use", id = "call-fixture", name = "fixture_tool", input = { value = row[1] } } },
						stop_reason = "tool_use", usage = { input_tokens = 17, output_tokens = 8 } }) }
				end
				local args = row[4] == "none" and { value = row[1] } or f.h.json.encode({ value = row[1] })
				return { StatusCode = 200, Body = f.h.json.encode({ id = "fixture-message", model = record.model,
					choices = { { message = { role = "assistant", content = "using a tool", tool_calls = {
						{ id = "call-fixture", type = "function", ["function"] = { name = "fixture_tool", arguments = args } } } }, finish_reason = "tool_calls" } },
					usage = { prompt_tokens = 17, completion_tokens = 8 } }) }
			end
			check("tool result retained on the next request", has(entry.body, "fixture result") and has(entry.body, "call-fixture"))
			local chunks = {}
			local function event(value) chunks[#chunks + 1] = "data: " .. f.h.json.encode(value) .. "\r\n\r\n" end
			if gemini then
				event({ candidates = { { content = { parts = { { text = "fixture reasoning", thought = true }, { text = "finished " .. row[1] } } }, finishReason = "STOP" } },
					usageMetadata = { promptTokenCount = 20, candidatesTokenCount = 9 } })
			elseif native then
				event({ type = "message_start", message = { id = "final", model = record.model, usage = { input_tokens = 20, output_tokens = 0 } } })
				event({ type = "content_block_start", index = 0, content_block = { type = "text", text = "" } })
				event({ type = "content_block_delta", index = 0, delta = { type = "text_delta", text = "finished " .. row[1] } })
				event({ type = "content_block_stop", index = 0 })
				event({ type = "message_delta", delta = { stop_reason = "end_turn" }, usage = { output_tokens = 9 } })
				event({ type = "message_stop" })
			else
				event({ choices = { { delta = { content = "finished " .. row[1], reasoning_content = "fixture reasoning" }, finish_reason = "stop" } } })
				event({ choices = {}, usage = { prompt_tokens = 20, completion_tokens = 9 } })
				chunks[#chunks + 1] = "data: [DONE]\r\n\r\n"
			end
			return { StatusCode = 200, Body = ": fixture heartbeat\r\n\r\n" .. table.concat(chunks), Headers = { ["Content-Type"] = "text/event-stream" } }
		end
		local found = f.run(function() return f.env.require("provider/models").discover(record) end)
		check("discovery keeps all model ids", #found == 2 and found[1] == "embedding-fixture")
		local first, why = complete(f, record, { messages = { { role = "system", content = "fixture instructions" }, { role = "user", content = "use tool" } }, tools = TOOLS, stream = false, maxTokens = 256 })
		check("JSON completion succeeded: " .. tostring(why), first ~= nil and #first.toolCalls == 1)
		local call = first.toolCalls[1]
		check("tool name/id/arguments survive", call.id == "call-fixture" and call["function"].name == "fixture_tool" and f.h.json.decode(call["function"].arguments).value == row[1])
		local final, finalError = complete(f, record, { messages = { { role = "user", content = "use tool" },
			{ role = "assistant", content = first.content, toolCalls = first.toolCalls, geminiParts = first.geminiParts, geminiScope = first.geminiScope },
			{ role = "tool", tool_call_id = call.id, content = "fixture result" } },
			tools = TOOLS, stream = true, maxTokens = 256 })
		check("SSE completion succeeded: " .. tostring(finalError), final ~= nil and final.content == "finished " .. row[1] and final.finish == "stop")
		check("usage and streaming retained", final.streamed and final.usage.completion_tokens == 9)
		if not native then check("reasoning retained", final.reasoning == "fixture reasoning") end
		check("only discovery and two intended requests", f.h.http.requestCount == 3 and posts == 2)
		f.healthy(); f.close()
	end)
end

case("URL normalization handles public, local, LAN, IPv6 and prefixes", function()
	local f = F.new(); local registry = f.env.require("provider/registry")
	local examples = {
		{ "api.example.com", "https://api.example.com/v1" },
		{ "localhost:11434", "http://localhost:11434/v1" },
		{ "host.local:8000/", "http://host.local:8000/v1" },
		{ "inference-box:8000/proxy/v1/", "http://inference-box:8000/proxy/v1" },
		{ "192.168.1.20:1234", "http://192.168.1.20:1234/v1" },
		{ "10.42.1.2:8000", "http://10.42.1.2:8000/v1" },
		{ "172.20.1.2:8000", "http://172.20.1.2:8000/v1" },
		{ "[::1]:8080", "http://[::1]:8080/v1" },
		{ "[fd12::1]:8000/v1", "http://[fd12::1]:8000/v1" },
		{ "[2001:db8::1]:8000/v1", "https://[2001:db8::1]:8000/v1" },
		{ "HTTPS://localhost:1234/v1/", "https://localhost:1234/v1" },
		{ "https://example.com?token=fixture#ignored", "https://example.com/v1?token=fixture" },
		{ "https://example.com/proxy/v1/?token=fixture", "https://example.com/proxy/v1?token=fixture" },
	}
	for _, example in ipairs(examples) do check(example[1], registry.normaliseBaseUrl(example[1]) == example[2]) end
	local record = recordFor(f); record.baseUrl = "https://example.com/prefix/v1/chat/completions?token=fixture&api-version=old"
	record.query = { ["api-version"] = "new", tag = "a b" }
	check("suffix precedes query and overrides are not duplicated", registry.endpoint(record, "/models") == "https://example.com/prefix/v1/models?token=fixture&api-version=new&tag=a%20b")
	record.baseUrl = "https://example.com/prefix/v1/messages/?token=fixture"; record.query = {}
	check("full Messages discovery", registry.endpoint(record, "/models") == "https://example.com/prefix/v1/models?token=fixture")
	check("full Messages inference", f.env.require("provider/anthropic").endpoint(record) == "https://example.com/prefix/v1/messages?token=fixture")
	check("full endpoint recognition with query", registry.isFullEndpoint(record.baseUrl))
	for _, bad in ipairs({ "ftp://example.com/v1", "ws://example.com/v1", "https://", "https://user:pass@example.com/v1", "https://example.com:99999", "https://bad host/v1" }) do
		record.baseUrl = bad; local valid = registry.validate(record); check("invalid base " .. bad, not valid)
	end
	f.healthy(); f.close()
end)

case("local reachability follows actual addresses and native paths fail before inference", function()
	local f = F.new(); local registry = f.env.require("provider/registry"); local record = recordFor(f)
	f.env.require("runtime/caps").http = "roblox"
	for _, base in ipairs({ "localhost:11434", "http://127.0.0.2:8000", "http://192.168.1.10:1234", "http://[::ffff:127.0.0.1]:8000" }) do
		record.baseUrl = base; local ok, problems = registry.validate(record)
		check("custom local address needs executor", not ok and has(table.concat(problems, " "), "executor HTTP"))
	end
	record.preset, record.requires, record.baseUrl = "vllm", "executor", "https://public.example.com/v1"
	check("public address in old local preset is accepted", registry.validate(record))
	record.baseUrl = "http://localhost:11434/api/chat"
	local result, why = complete(f, record)
	check("native Ollama route has an actionable diagnostic", not result and has(why, "/v1"))
	record.baseUrl, record.api = "https://fixture.test/v1", "unimplemented"
	result, why = complete(f, record)
	check("unknown protocol is not silently routed", not result and has(why, "not implemented"))
	check("protocol failures made no requests", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("key pools and explicit Messages auth select one credential", function()
	local f = F.new(); local registry = f.env.require("provider/registry"); local record = recordFor(f)
	record.apiKey = " key-one\nkey-two, key-three\nkey-one "
	registry.cooldownKey(record, "key-one", 30); registry.cooldownKey(record, "key-two", 10); registry.cooldownKey(record, "key-three", 20)
	check("all cooling selects the earliest key string", registry.nextKey(record) == "key-two")
	check("discovery headers contain one credential", f.env.require("provider/chat").headers(record).Authorization == "Bearer key-two")
	record.api = "anthropic"
	local headers = f.env.require("provider/chat").headers(record)
	check("Messages honors explicit Bearer", headers.Authorization == "Bearer key-two" and headers["x-api-key"] == nil)
	record.authStyle = "both"; headers = f.env.require("provider/chat").headers(record)
	check("both uses the same selected credential", headers.Authorization == "Bearer key-two" and headers["x-api-key"] == "key-two")
	record.authStyle = "none"; headers = f.env.require("provider/chat").headers(record)
	check("none sends no auth but retains Messages version", not headers.Authorization and not headers["x-api-key"] and headers["anthropic-version"])
	f.healthy(); f.close()
end)

case("header overrides are case insensitive and identity is host scoped", function()
	local f = F.new(); local http = f.env.require("net/http"); local record = recordFor(f)
	record.headers = { authorization = "Bearer override", ["content-TYPE"] = "application/custom", ["user-agent"] = "custom-client" }
	local headers = http.headersFor({ url = "https://fixture.test/openrouter.ai?host=openrouter.ai", identity = "none", body = "{}", headers = f.env.require("provider/chat").headers(record) })
	check("custom auth replaces default", headers.authorization == "Bearer override" and headers.Authorization == nil)
	check("no duplicate content type or user-agent", headers["content-TYPE"] == "application/custom" and headers["Content-Type"] == nil and headers["user-agent"] == "custom-client" and headers["User-Agent"] == nil)
	check("substring does not select OpenRouter identity", headers["HTTP-Referer"] == nil)
	headers = http.headersFor({ url = "HTTPS://OPENROUTER.AI.:443/api/v1/chat/completions", headers = { ["x-stainless-lang"] = "bad", ["X-App"] = "bad" } })
	check("official host receives attribution", headers["X-OpenRouter-Title"] == "Project UAI")
	check("case variants of competing identity are removed", headers["x-stainless-lang"] == nil and headers["X-App"] == nil)
	f.healthy(); f.close()
end)

case("the retired OpenRouter attribution URL migrates in saved records", function()
	local f = F.new(); local registry = f.env.require("provider/registry")
	-- A record saved before the repository move: its copied preset headers still
	-- carry the retired referer, which overrides the built-in default.
	local legacy = recordFor(f, "openrouter")
	legacy.headers["HTTP-Referer"] = "https://carldv.github.io/ProjectUAI/"
	check("legacy record saves", registry.save(legacy))
	local custom = recordFor(f, "custom")
	custom.headers = { ["HTTP-Referer"] = "https://example.test/keep-me/" }
	check("custom record saves", registry.save(custom))
	local near = recordFor(f, "custom")
	near.id, near.label = "fixture-near", "Near miss"
	near.headers = { ["http-referer"] = "https://carldv.github.io/ProjectUAI/archive" }
	check("near-miss record saves", registry.save(near))

	check("one saved record migrates", registry.migrate() == 1)
	check("referer points at the repository", registry.get("fixture-openrouter").headers["HTTP-Referer"]
		== "https://github.com/Project-Ptolemy/ProjectUAI")
	check("a user-set referer is untouched", registry.get("fixture-custom").headers["HTTP-Referer"]
		== "https://example.test/keep-me/")
	check("a similar URL is untouched", registry.get("fixture-near").headers["http-referer"]
		== "https://carldv.github.io/ProjectUAI/archive")
	check("a second boot changes nothing", registry.migrate() == 0)
	f.healthy(); f.close()
end)

case("discovery separates drafts and changes in connection/auth", function()
	local f = F.new(); local models = f.env.require("provider/models"); local a, b = recordFor(f), recordFor(f)
	a.id, b.id = "", ""; a.baseUrl, b.baseUrl = "http://localhost:1234/v1", "http://localhost:8000/v1"
	local serial = 0
	f.h.http.handler = function() serial = serial + 1; return { StatusCode = 200, Body = f.h.json.encode({ models = { { name = "model-" .. serial }, { name = " model-" .. serial .. " " } } }) } end
	local function fetch(record) return f.run(function() return models.discover(record) end) end
	check("first draft list is deduplicated after trim", #fetch(a) == 1 and models.discovered(a)[1] == "model-1")
	check("second draft uses its own endpoint", fetch(b)[1] == "model-2")
	check("unchanged connection is cached", fetch(a)[1] == "model-1" and serial == 2)
	a.apiKey = "different-key"; check("auth changes invalidate cached models", fetch(a)[1] == "model-3")
	a.baseUrl = "http://localhost:9000/v1"; check("endpoint changes invalidate cached models", fetch(a)[1] == "model-4")
	a.headers = { ["X-Tenant"] = "second" }; check("header changes invalidate cached models", fetch(a)[1] == "model-5")
	a.query = { tenant = "third" }; check("query changes invalidate cached models", fetch(a)[1] == "model-6")
	check("other draft remains cached", fetch(b)[1] == "model-2" and serial == 6)
	f.healthy(); f.close()
end)

case("failed discovery is never cached as an empty success", function()
	local f = F.new(); local models = f.env.require("provider/models"); local record = recordFor(f)
	local status = 401
	f.h.http.handler = function() return { StatusCode = status, Body = f.h.json.encode({ error = { message = "fixture refusal" } }) } end
	for _, code in ipairs({ 401, 403, 404, 422, 200 }) do
		status = code
		local found, note = f.run(function() return models.discover(record, { force = true }) end)
		check("error status is not an empty success: " .. code, #found == 0 and not has(note, "empty list"))
		if code == 401 then check("auth diagnostic", has(note, "key was rejected")) end
		if code == 403 then check("permission diagnostic", has(note, "not allowed")) end
		if code == 404 then check("manual entry diagnostic", has(note, "by hand")) end
		check("no failed cache entry", models.cached(record) == nil)
		check("manual model remains available", models.list(record)[1] == record.model)
	end
	f.healthy(); f.close()
end)

case("discovery rejects out-of-order, changed and invalidated requests", function()
	local f = F.new(); local models = f.env.require("provider/models"); local record = recordFor(f)
	f.h.http.handler = function(entry) return { StatusCode = 200, delay = entry.index == 1 and 0.3 or 0.05,
		Body = f.h.json.encode({ data = { { id = "response-" .. entry.index } } }) } end
	local first, second
	f.h.sched.spawn(function() first = { models.discover(record, { force = true }) } end)
	f.h.sched.spawn(function() second = { models.discover(record, { force = true }) } end)
	f.h.sched.advance(0.5)
	check("newest response owns cache", second[1][1] == "response-2" and models.discovered(record)[1] == "response-2")
	check("older response is suppressed", #first[1] == 0 and has(first[2], "superseded"))
	f.h.sched.spawn(function() first = { models.discover(record, { force = true }) } end)
	record.apiKey = "changed-during-request"; f.h.sched.advance(0.2)
	check("in-flight setting change is suppressed", #first[1] == 0 and #models.discovered(record) == 0)
	f.h.sched.spawn(function() first = { models.discover(record, { force = true }) } end)
	models.invalidate(record); f.h.sched.advance(0.2)
	check("invalidation cannot be undone by old response", #first[1] == 0 and models.cached(record) == nil)
	f.healthy(); f.close()
end)

case("FastAPI parameter errors are repairable without echoing input", function()
	local f = F.new(); local adapter = f.env.require("provider/openai"); local record = recordFor(f)
	local errorBody = f.h.json.encode({ detail = { { loc = { "body", "tool_choice" }, msg = "Extra inputs are not permitted", type = "extra_forbidden", input = "never-echo-this-prompt" } } })
	local message = adapter.errorText({ status = 422, body = errorBody })
	check("field path retained", has(message, "body.tool_choice"))
	check("input omitted", not has(message, "never-echo"))
	local bodies = {}
	f.h.http.handler = function(entry)
		bodies[#bodies + 1] = f.h.json.decode(entry.body)
		if #bodies == 1 then return { StatusCode = 422, Body = errorBody } end
		return jsonReply(f)
	end
	local result = complete(f, record, { messages = { { role = "user", content = "hi" } }, tools = TOOLS, stream = false })
	check("one field refusal is repaired", result and #bodies == 2 and bodies[1].tool_choice == "auto" and bodies[2].tool_choice == nil and #bodies[2].tools > 0)
	f.healthy(); f.close()
end)

case("learned repairs and output caps stay with their model and endpoint", function()
	local f = F.new(); local adapter = f.env.require("provider/openai"); local record = recordFor(f)
	local bodies = {}
	f.h.http.handler = function(entry)
		bodies[#bodies + 1] = f.h.json.decode(entry.body)
		if #bodies == 1 then return { StatusCode = 400, Body = f.h.json.encode({ error = { message = "Unsupported parameter: temperature" } }) } end
		return jsonReply(f)
	end
	check("initial request repairs", complete(f, record) ~= nil)
	check("repair is reused", complete(f, record) ~= nil and bodies[3].temperature == nil)
	record.model = "other-model"; check("different model is not stripped", complete(f, record) ~= nil and bodies[4].temperature ~= nil)
	adapter.rememberMaxTokens(record, 2048)
	check("learned cap applies on same endpoint/model", adapter.cappedMaxTokens(record, 10000) == 2048)
	record.baseUrl = "https://another.test/v1"
	check("same model on another endpoint gets its own cap", adapter.cappedMaxTokens(record, 10000) == 10000)
	record.maxTokensCap = { model = record.model, tokens = 1024 }
	check("legacy cap adopts current scope", adapter.cappedMaxTokens(record, 10000) == 1024)
	record.baseUrl = "https://third.test/v1"
	check("adopted legacy cap is then scoped", adapter.cappedMaxTokens(record, 10000) == 10000)
	f.healthy(); f.close()
end)

case("small local contexts and explicit output bounds are recognized", function()
	local f = F.new(); local adapter = f.env.require("provider/openai"); local record = recordFor(f)
	for _, limit in ipairs({ 512, 2048, 4096 }) do
		local text = "This model's maximum context length is " .. limit .. " tokens; requested 9000 including max_tokens 8192"
		check("small named window " .. limit, adapter.contextWindowFromMessage(text) == limit)
		local body = { max_tokens = 8192 }; check("context refusal never teaches output limit", adapter.repairForTest(body, text) == nil and body.max_tokens == 8192)
	end
	adapter.rememberContextWindow(record, 2048)
	check("small learned window reaches context traits", f.env.require("provider/traits").contextWindow(record.model) == 2048)
	check("explicit 512 output bound", adapter.ceilingFromMessage("max_tokens must be less than or equal to 512 (400)", 4096) == 512)
	local body = { max_completion_tokens = 4096 }
	check("renamed token field can learn a small bound", adapter.repairForTest(body, "max_completion_tokens must be less than or equal to 512") ~= nil and body.max_completion_tokens == 512)
	body = { max_tokens = 8192 }
	check("unnumbered context errors cannot teach output caps", adapter.repairForTest(body, "context_length_exceeded: reduce max_tokens or the prompt") == nil and body.max_tokens == 8192)
	f.healthy(); f.close()
end)

-- HCNSEC words the refusal in its host language ("field MaxTokens invalid"), and
-- the dispatch compares plain lowercase text: without camel humps put back the
-- field reads as "maxtokens", no repair fires, and every later turn pays for the
-- same refusal because the ceiling is never lowered or remembered.
case("camelCase field names in a refusal are repaired and remembered", function()
	local f = F.new(); local adapter = f.env.require("provider/openai"); local record = recordFor(f, "hcnsec")
	local text = "the provider rejected the request (400): field MaxTokens invalid, should be in [1, 65536]"
	local body = { max_tokens = 128000 }
	local note, key = adapter.repairForTest(body, text)
	check("the refusal is recognized", note ~= nil and key == "max_tokens")
	check("the bound is read from the range wording", body.max_tokens == 65536)

	local bodies = {}
	f.h.http.handler = function(entry)
		bodies[#bodies + 1] = f.h.json.decode(entry.body)
		if (bodies[#bodies].max_tokens or 0) > 65536 then
			return { StatusCode = 400, Body = f.h.json.encode({ error = {
				message = "field MaxTokens invalid, should be in [1, 65536]",
				type = "invalid_request_error", param = "max_tokens", code = "3" } }) }
		end
		return jsonReply(f)
	end
	check("the turn recovers on the retried request", complete(f, record) ~= nil and #bodies == 2)
	check("first attempt sent the configured ceiling", bodies[1].max_tokens == 128000)
	check("retried at the gateway's bound", bodies[2].max_tokens == 65536)
	check("the bound was learned", record.maxTokensCap and record.maxTokensCap.tokens == 65536)
	check("so the next turn opens with it", complete(f, record) ~= nil and #bodies == 3 and bodies[3].max_tokens == 65536)
	f.healthy(); f.close()
end)

case("a refusal cannot teach or resend through a connection changed in flight", function()
	for _, protocol in ipairs({ "openai", "anthropic" }) do
		local f = F.new(); local record = recordFor(f); record.api = protocol
		f.h.http.handler = function() return { StatusCode = 400, delay = 0.1, Body = f.h.json.encode({ error = { message = "max_tokens must be less than or equal to 512" } }) } end
		f.h.sched.delay(0.05, function() record.baseUrl, record.model = "https://new-connection.test/v1", "new-model" end)
		local result, why = complete(f, record)
		check(protocol .. " old request stops before another dispatch", not result and why == "aborted" and f.h.http.requestCount == 1)
		check(protocol .. " new selection inherits no old cap", record.maxTokensCap == nil)
		f.healthy(); f.close()
	end
end)

-- Zen serves some models only on the Responses lane: /chat/completions answers
-- ModelProtocolUnsupported and /inference/openai/v1/responses answers normally.
-- The adapter must switch lanes, assemble the streamed text exactly once, and
-- surface Responses function calls in the shared tool-call shape.
case("a model that only speaks Responses switches lanes and assembles once", function()
	local f = F.new(); local record = recordFor(f, "zen")
	local chatBodies, responsesBodies = {}, {}
	local stream = table.concat({
		"event: response.created",
		'data: {"type":"response.created","response":{"id":"resp_1","model":"' .. record.model .. '"}}',
		"",
		"event: response.output_text.delta",
		'data: {"type":"response.output_text.delta","item_id":"msg_1","delta":"Hello"}',
		"",
		"event: response.output_text.delta",
		'data: {"type":"response.output_text.delta","item_id":"msg_1","delta":" there"}',
		"",
		"event: response.completed",
		'data: {"type":"response.completed","response":{"id":"resp_1","model":"' .. record.model .. '","status":"completed",'
			.. '"output":[{"type":"message","id":"msg_1","content":[{"type":"output_text","text":"Hello there"}]}],'
			.. '"usage":{"input_tokens":10,"output_tokens":5,"total_tokens":15}}}',
		"",
	}, "\n")
	f.h.http.handler = function(entry)
		if entry.url:find("/responses", 1, true) then
			responsesBodies[#responsesBodies + 1] = f.h.json.decode(entry.body)
			return { StatusCode = 200, Body = stream }
		end
		chatBodies[#chatBodies + 1] = f.h.json.decode(entry.body)
		return { StatusCode = 400, Body = f.h.json.encode({ error = { type = "ModelProtocolUnsupported", message = "Model does not support this protocol." } }) }
	end
	local result = complete(f, record, { messages = { { role = "user", content = "hi" } }, tools = TOOLS, stream = true })
	check("the turn recovers on the Responses lane", result ~= nil and #chatBodies == 1 and #responsesBodies == 1)
	check("the retry carries Responses input, not chat messages", responsesBodies[1].input ~= nil and responsesBodies[1].messages == nil)
	check("tools are flattened to the Responses shape", responsesBodies[1].tools[1].name == "fixture_tool" and responsesBodies[1].tools[1]["function"] == nil)
	local declared = false
	for _, tool in ipairs(responsesBodies[1].tools) do
		if tool.name == "bash" and tool["function"] == nil then declared = true end
	end
	check("the standard declarations travel with it", declared)
	check("no reasoning_effort is sent on this lane", responsesBodies[1].reasoning_effort == nil)
	check("streamed text is assembled exactly once", result and result.content == "Hello there")
	check("usage is read from the completed payload", result and result.usage and result.usage.output_tokens == 5)
	check("the lane is remembered", record.repairs ~= nil and f.env.require("provider/responses").remembered(record))
	check("the next turn skips chat entirely", complete(f, record, { messages = { { role = "user", content = "again" } }, stream = true }) ~= nil and #chatBodies == 1 and #responsesBodies == 2)
	f.healthy(); f.close()
end)

-- On the direct route the free-tier gate answers 403 before protocol validation
-- runs, so a muse-spark record would never reach the reactive switch. Known
-- Responses-only models skip chat from the first turn.
case("verified Responses-only models skip chat proactively", function()
	local f = F.new(); local record = recordFor(f, "zen"); record.model = "muse-spark-1.3-contributor-free"
	local chatBodies, responsesBodies = {}, {}
	f.h.http.handler = function(entry)
		if entry.url:find("/responses", 1, true) then
			responsesBodies[#responsesBodies + 1] = f.h.json.decode(entry.body)
			return { StatusCode = 200, Body = f.h.json.encode({ id = "resp_1", object = "response", status = "completed",
				model = record.model, output = { { type = "message", id = "msg_1", content = { { type = "output_text", text = "hi" } } } },
				usage = { input_tokens = 2, output_tokens = 1 } }) }
		end
		chatBodies[#chatBodies + 1] = f.h.json.decode(entry.body)
		return { StatusCode = 403, Body = f.h.json.encode({ error = { type = "FreeTierError", message = "OpenCode's free tier can only be used from within OpenCode" } }) }
	end
	local result = complete(f, record, { messages = { { role = "user", content = "hi" } }, stream = true })
	check("no chat request is sent at all", result ~= nil and #chatBodies == 0 and #responsesBodies == 1)
	check("the reply arrives in chat shape", result and result.content == "hi")
	f.healthy(); f.close()
end)

-- A 403 free-tier refusal on an unlisted model still deserves one lane attempt:
-- the direct route fires the gate before protocol validation, so without this
-- the reactive switch would never see those models.
case("a free-tier refusal also tries the Responses lane once", function()
	local f = F.new(); local record = recordFor(f, "zen")
	local chatBodies, responsesBodies = {}, {}
	f.h.http.handler = function(entry)
		if entry.url:find("/responses", 1, true) then
			responsesBodies[#responsesBodies + 1] = f.h.json.decode(entry.body)
			return { StatusCode = 200, Body = f.h.json.encode({ id = "resp_1", object = "response", status = "completed",
				model = record.model, output = { { type = "message", id = "msg_1", content = { { type = "output_text", text = "recovered" } } } } }) }
		end
		chatBodies[#chatBodies + 1] = f.h.json.decode(entry.body)
		return { StatusCode = 403, Body = f.h.json.encode({ error = { type = "FreeTierError", message = "OpenCode's free tier can only be used from within OpenCode" } }) }
	end
	local result = complete(f, record, { messages = { { role = "user", content = "hi" } }, stream = true })
	check("the turn recovers on the Responses lane", result ~= nil and #chatBodies == 1 and #responsesBodies == 1)
	check("with the recovered text", result and result.content == "recovered")
	check("the lane is remembered only after answering", f.env.require("provider/responses").remembered(record))
	check("the next turn skips chat entirely", complete(f, record, { messages = { { role = "user", content = "again" } }, stream = true }) ~= nil and #chatBodies == 1 and #responsesBodies == 2)
	f.healthy(); f.close()
end)

-- A failed lane attempt must not pin the record: the next turn tries chat
-- again instead of repeating a lane known only to fail.
case("a failed Responses attempt never pins the lane", function()
	local f = F.new(); local record = recordFor(f, "zen")
	local chatBodies, responsesBodies = {}, {}
	f.h.http.handler = function(entry)
		if entry.url:find("/responses", 1, true) then
			responsesBodies[#responsesBodies + 1] = f.h.json.decode(entry.body)
			return { StatusCode = 400, Body = f.h.json.encode({ error = { message = "bad request" } }) }
		end
		chatBodies[#chatBodies + 1] = f.h.json.decode(entry.body)
		if #chatBodies == 1 then
			return { StatusCode = 400, Body = f.h.json.encode({ error = { type = "ModelProtocolUnsupported", message = "Model does not support this protocol." } }) }
		end
		return jsonReply(f)
	end
	local _, why = complete(f, record, { messages = { { role = "user", content = "hi" } }, stream = true })
	check("the terminal error names the protocol", why and has(why, "does not support this protocol"))
	check("the lane was attempted once", #responsesBodies == 1)
	check("and was not remembered", not f.env.require("provider/responses").remembered(record))
	check("so the next turn tries chat again", complete(f, record, { messages = { { role = "user", content = "again" } }, stream = true }) ~= nil and #chatBodies == 2 and #responsesBodies == 1)
	f.healthy(); f.close()
end)

case("the Responses lane uses the documented Console endpoint", function()
	local f = F.new(); local responses = f.env.require("provider/responses")
	local direct = recordFor(f, "zen")
	check("direct records use the Console responses URL", responses.endpointFor(direct) == "https://opencode.ai/inference/v1/responses")
	f.healthy(); f.close()
end)

case("Responses function calls surface as normal tool calls", function()
	local f = F.new(); local adapter = f.env.require("provider/responses")
	local body = table.concat({
		"event: response.completed",
		'data: {"type":"response.completed","response":{"id":"resp_2","model":"m","status":"completed","output":['
			.. '{"type":"function_call","call_id":"call_1","name":"fixture_tool","arguments":"{\\"value\\":\\"x\\"}"}]}}',
		"",
	}, "\n")
	local parsed = adapter.parse(body)
	check("the call is parsed", parsed.toolCalls and #parsed.toolCalls == 1)
	check("with its id, name and arguments", parsed.toolCalls[1].id == "call_1" and parsed.toolCalls[1]["function"].name == "fixture_tool" and parsed.toolCalls[1]["function"].arguments == '{"value":"x"}')
	check("and no stream error", parsed.streamError == nil)
	f.healthy(); f.close()
end)

case("optional body controls respect explicit stream and tool choices", function()
	local f = F.new(); local adapter = f.env.require("provider/openai"); local record = recordFor(f, "ollama")
	local body = adapter.buildBody(record, { tools = TOOLS, stream = true, parallelToolCalls = false, toolChoice = "required" })
	check("explicit options are literal", body.parallel_tool_calls == false and body.tool_choice == "required")
	record.params = { stream = false }
	body = adapter.buildBody(record, { stream = true })
	check("nonstreaming override removes stream-only options", body.stream == false and body.stream_options == nil)
	f.healthy(); f.close()
end)

case("OpenCode session and request IDs encode monotonic timestamps", function()
	local f = F.new(); local registry = f.env.require("provider/registry"); local clock = f.env.require("runtime/clock")
	local ses = registry.opencodeId("ses_")
	local req = registry.opencodeId("req_")
	check("session ID starts with ses_", ses:sub(1, 4) == "ses_")
	check("request ID starts with req_", req:sub(1, 4) == "req_")
	check("session ID length is 30", #ses == 30)
	check("request ID length is 30", #req == 30)
	local sesHex = ses:sub(5, 16)
	local reqHex = req:sub(5, 16)
	check("session hex is 12 hex characters", sesHex:match("^%x+$") ~= nil)
	check("request hex is 12 hex characters", reqHex:match("^%x+$") ~= nil)
	local recovered = 0
	for i = 1, 12, 2 do
		local b = 255 - tonumber(sesHex:sub(i, i + 1), 16)
		recovered = recovered * 256 + b
	end
	local sesMs = math.floor(recovered / 4096)
	local expectedMs = math.floor(clock.ms()) % (2 ^ 36)
	check("recovered session timestamp matches clock.ms() modulo 2^36", math.abs(sesMs - expectedMs) < 5000)
	f.healthy(); f.close()
end)

case("cat-jam traits and tool capping preserve OpenCode compatibility", function()
	local f = F.new()
	local traits = f.env.require("provider/traits")
	local adapter = f.env.require("provider/openai")
	local record = recordFor(f, "zen")
	record.model = "cat-jam-free"
	check("cat-jam documents 128 max tools", traits.maxTools("cat-jam-free") == 128)
	check("cat-jam uses its refreshed catalog context window", traits.contextWindow("cat-jam-free") == 1048576)
	-- A stale public CLI catalog used to advertise these free models at 1M while
	-- OpenCode's server rejected anything above 200K. Compaction now starts from
	-- the window the provider actually enforces.
	check("DeepSeek V4.1 Flash Free keeps its 200K server window", traits.contextWindow("deepseek-v4.1-flash-free") == 200000)
	check("GLM-5.3-Flash Free keeps its 200K server window", traits.contextWindow("glm-5.3-flash-free") == 200000)

	local bigTools = {}
	for i = 1, 174 do
		bigTools[#bigTools + 1] = { type = "function", ["function"] = { name = "tool_" .. i, description = "tool", parameters = { type = "object" } } }
	end

	local body = adapter.buildBody(record, { tools = bigTools, stream = true })
	check("body tools are capped to 128", #body.tools == 128)
	local names = {}
	for _, t in ipairs(body.tools) do names[t["function"].name] = true end
	for _, std in ipairs(adapter.opencodeTools) do
		check("OpenCode standard tool " .. std["function"].name .. " is preserved", names[std["function"].name] == true)
	end

	local msg = "Upstream request failed: [invalid_value] Invalid value for 'tools': maximum number of items is 128."
	check("extracts ceiling from message", adapter.toolCeilingFromMessage(msg) == 128)
	local otherRecord = recordFor(f, "zen")
	otherRecord.model = "unlisted-model"
	local testBody = { tools = bigTools }
	local note, key = adapter.repairForTest(testBody, msg)
	check("repair detects cap_tools", key == "cap_tools")
	check("repair capped tools to 128", #testBody.tools == 128)
	f.healthy(); f.close()
end)

case("tool capping preserves supplied declarations and fills the exact ceiling", function()
	local f = F.new(); local adapter = f.env.require("provider/openai")
	for _, flat in ipairs({ false, true }) do
		local tools = {}
		for _, tool in ipairs(adapter.opencodeTools) do tools[#tools + 1] = flat and tool["function"] or tool end
		for index = 1, 174 do
			local fn = { name = "tool_" .. index, parameters = { type = "object" } }
			tools[#tools + 1] = flat and fn or { type = "function", ["function"] = fn }
		end
		local capped = adapter.capTools(tools, 128, true)
		check("standard declarations at the front still fill the ceiling", #capped == 128)
		check("input order and schema survive beside the overflow catalogue", capped[1] == tools[1] and capped[127] == tools[127]
			and (capped[128]["function"] or capped[128]).name == "uai_tool_catalog")
		check("a small ceiling is never exceeded", #adapter.capTools(tools, 2, true) == 2)
	end
	local generic = { tools = {} }
	for index = 1, 140 do generic.tools[index] = { type = "function", ["function"] = { name = "custom_" .. index } } end
	adapter.repairForTest(generic, "Invalid tools: maximum number of items is 128")
	check("generic repair caps the declared tools", #generic.tools == 128)
	for index = 1, 127 do check("generic repair preserves native declarations", generic.tools[index]["function"].name == "custom_" .. index) end
	check("generic repair exposes omitted names through the catalogue", generic.tools[128]["function"].name == "uai_tool_catalog"
		and generic.tools[128]["function"].parameters.properties.name.enum[1] == "custom_128")
	local record = recordFor(f, "zen"); record.model = "cat-jam-free"
	record.toolsCap = { model = record.model, limit = 256 }
	check("a saved cap cannot exceed the model ceiling", adapter.toolCeiling(record) == 128)
	f.healthy(); f.close()
end)

case("OpenCode session validator migrates legacy sessions and connection tests stream", function()
	local f = F.new()
	local registry = f.env.require("provider/registry")
	local chat = f.env.require("provider/chat")
	local record = recordFor(f, "zen")
	record.opencodeSession = "ses_a1b2c3d4e5f6abcdefghijklmn"

	check("legacy random hex session fails validation", not registry.validOpencodeSession(record.opencodeSession))
	local refreshed = registry.opencodeSessionFor(record, {})
	check("opencodeSessionFor refreshes legacy session", registry.validOpencodeSession(refreshed))
	check("record.opencodeSession is updated", record.opencodeSession == refreshed)
	local corrupt = refreshed:sub(1, -2) .. "!"
	check("valid timestamp cannot hide a malformed Base62 suffix", not registry.validOpencodeSession(corrupt))
	record.opencodeSession = corrupt
	check("malformed saved suffix is migrated", registry.validOpencodeSession(registry.opencodeSessionFor(record, {})))

	local intercepted
	f.h.http.handler = function(spec)
		intercepted = spec
		return {
			StatusCode = 200,
			Headers = { ["content-type"] = "text/event-stream" },
			Body = 'data: {"choices":[{"delta":{"content":"ready"}}]}' .. "\n\n" .. 'data: [DONE]' .. "\n\n",
		}
	end

	local result = f.run(function()
		return chat.complete(record, {
			messages = { { role = "user", content = "ready" } },
			stream = false,
			maxTokens = 12,
		})
	end)
	check("connection test with stream=false is forced to streaming for OpenCode", result and result.content == "ready")
	check("body.stream is true", f.h.json.decode(intercepted.body).stream == true)
	check("header Accept matches the verified desktop fingerprint", f.env.require("net/headers").get(intercepted.headers, "accept") == "*/*")
	check("session header is valid inverted timestamp", registry.validOpencodeSession(intercepted.headers["x-opencode-session"]))
	check("Chat uses the verified desktop identity", intercepted.headers["x-opencode-client"] == "desktop"
		and intercepted.headers["User-Agent"] == "opencode/latest/2.0.27/desktop")
	for _, name in ipairs({ "x-opencode-session-id", "x-session-affinity", "X-Session-Id" }) do
		check("desktop session headers retain one affinity", intercepted.headers[name] == intercepted.headers["x-opencode-session"])
	end
	check("CLI project/request headers stay absent", intercepted.headers["x-opencode-project"] == nil and intercepted.headers["x-opencode-request"] == nil)
	f.healthy(); f.close()
end)

case("OpenCode saved identity overrides remain explicit on both protocol lanes", function()
	local f = F.new(); local registry = f.env.require("provider/registry")
	local record = recordFor(f, "zen")
	record.opencode = { version = "1.0.118-test", client = "custom-client" }
	local defaults = registry.opencodeHeaders(record)
	check("explicit numeric version retains its prior format", defaults["User-Agent"] == "opencode/stable/1.0.118-test/custom-client")
	check("explicit client is retained", defaults["x-opencode-client"] == "custom-client")
	record.opencode.version = "opencode/custom/verified-client"
	check("explicit complete user agent is unchanged", registry.opencodeHeaders(record)["User-Agent"] == "opencode/custom/verified-client")
	record.model = "muse-spark-fixture"
	local intercepted
	f.h.http.handler = function(spec)
		intercepted = spec
		return { StatusCode = 200, Body = f.h.json.encode({ object = "response", status = "completed", output = {
			{ type = "message", content = { { type = "output_text", text = "ready" } } },
		} }) }
	end
	local result = complete(f, record)
	check("Responses shares explicit saved overrides", result and intercepted.headers["User-Agent"] == "opencode/custom/verified-client"
		and intercepted.headers["x-opencode-client"] == "custom-client")
	f.healthy(); f.close()
end)

case("Responses connection tests retain OpenCode identity on Game and Web routes", function()
	for _, route in ipairs({ "game", "web", "image" }) do
		local f = F.new(); local record = recordFor(f, "zen")
		record.model = "muse-spark-fixture"
		record.baseUrl = record.baseUrl .. "?tenant=one"
		record.query = { mode = "a b" }
		local captured, relayed
		f.loaded["net/transport"] = { streamForced = function() return route == "web" end,
			prepare = function() end, unlimited = function() return route ~= "game" end,
			coworkWeb = function() return route ~= "game" end,
			endpoint = function() return route ~= "game" and { target = "cowork", base = "http://127.0.0.1:8790", token = "fixture" } or nil end,
			shouldRelay = function(images) return route == "web" or images end }
		local function answer(spec, headers, via)
			captured, relayed = { url = spec.url, headers = headers, body = f.h.json.decode(spec.body), sessionId = spec.sessionId }, via
			local raw = f.h.json.encode({ type = "response.completed", response = { status = "completed", output = {
				{ type = "message", content = { { type = "output_text", text = "ready" } } },
			} } })
			return "data: " .. raw .. "\n\n"
		end
		f.loaded["net/relay"] = { request = function(spec, headers)
			return { status = 200, headers = { ["content-type"] = "text/event-stream" }, body = answer(spec, headers, true), via = "web", inferenceId = "response-preview" }
		end }
		f.h.http.handler = function(spec)
			return { StatusCode = 200, Headers = { ["content-type"] = "text/event-stream" }, Body = answer(spec, spec.headers, false) }
		end
		local image = { url = "uai-image://pic_responses_fixture/" .. string.rep("a", 64), sessionId = "responses-session", mediaType = "image/png", bytes = 100 }
		local result = complete(f, record, { sessionId = "responses-session", stream = false, maxTokens = 12,
			messages = { { role = "user", content = "ready", images = route == "image" and { image } or nil } } })
		check(route .. " connection test succeeds", result and result.content == "ready")
		check(route .. " selects the requested transport", relayed == (route ~= "game"))
		check("direct provider calls match route", f.h.http.requestCount == (route == "game" and 1 or 0))
		check("Responses query survives", captured.url == "https://opencode.ai/inference/v1/responses?tenant=one&mode=a%20b")
		check("Responses retains desktop identity", captured.headers["x-opencode-client"] == "desktop" and captured.headers["User-Agent"] == "opencode/latest/2.0.27/desktop")
		check("Responses omits CLI project/request headers", captured.headers["x-opencode-project"] == nil and captured.headers["x-opencode-request"] == nil)
		check("Responses retains valid session", f.env.require("provider/registry").validOpencodeSession(captured.headers["x-opencode-session"]))
		check("Responses preserves streaming and tool declarations", captured.body.stream == true and #captured.body.tools >= 3)
		if route ~= "game" then check("preview belongs to conversation", captured.sessionId == "responses-session" and result.requestId == "response-preview") end
		if route == "image" then check("runtime image references enter Responses input", captured.body.input[1].content[2].type == "input_image" and captured.body.input[1].content[2].image_url == image.url) end
		f.healthy(); f.close()
	end
end)

case("Responses lane handoff preserves the selected key and original deadline", function()
	local f = F.new(); local record = recordFor(f, "zen"); record.apiKey = "first-key\nsecond-key"
	local specs, keys = {}, {}
	local http = f.env.require("net/http"); local send = http.send
	http.send = function(spec) specs[#specs + 1] = spec; return send(spec) end
	f.h.http.handler = function(spec)
		keys[#keys + 1] = spec.headers.Authorization
		if spec.url:find("/chat/completions", 1, true) then
			return { StatusCode = 403, Body = f.h.json.encode({ error = { type = "FreeTierError" } }) }
		end
		return { StatusCode = 200, Body = f.h.json.encode({ object = "response", status = "completed", output = {
			{ type = "message", content = { { type = "output_text", text = "recovered" } } },
		} }) }
	end
	local result = complete(f, record)
	check("fallback succeeds", result and result.content == "recovered")
	check("fallback stays within original deadline", #specs == 2 and specs[1].deadlineMs == specs[2].deadlineMs)
	check("fallback keeps the chosen credential", keys[1] == "Bearer first-key" and keys[2] == keys[1])
	check("next operation rotates once", complete(f, record) and keys[3] == "Bearer second-key")
	f.healthy(); f.close()
end)

case("Cowork provider calls and explicit-refusal recovery outlive native request limits", function()
	for _, lane in ipairs({ "chat", "responses", "messages", "handoff" }) do
		local f = F.new(); local record = recordFor(f, lane == "messages" and "anthropic-messages" or "zen")
		if lane == "responses" then record.model = "muse-spark-fixture" end
		record.apiKey = "first-key\nsecond-key"
		local calls, deadlines = 0, {}
		f.loaded["net/transport"] = {
			prepare = function() end, unlimited = function() return true end,
			streamForced = function() return true end, coworkWeb = function() return true end,
			shouldRelay = function() return true end,
			endpoint = function() return { target = "cowork", base = "http://127.0.0.1:8790", token = "fixture" } end,
		}
		f.loaded["net/relay"] = { request = function(spec)
			calls = calls + 1; deadlines[#deadlines + 1] = spec.deadlineMs
			if calls == 1 then
				f.h.sched.wait(301)
				return { status = lane == "handoff" and 403 or 429, body = lane == "handoff" and '{"error":{"type":"FreeTierError"}}' or '{"error":{"message":"quota"}}', headers = {}, via = "web" }
			end
			local body
			if spec.url:find("/responses", 1, true) then
				body = { object = "response", status = "completed", output = { { type = "message", content = { { type = "output_text", text = "ready" } } } } }
			elseif lane == "messages" then
				body = { type = "message", role = "assistant", content = { { type = "text", text = "ready" } }, stop_reason = "end_turn" }
			else body = { choices = { { message = { role = "assistant", content = "ready" }, finish_reason = "stop" } } } end
			return { status = 200, body = f.h.json.encode(body), headers = {}, via = "web", inferenceId = "unlimited-response" }
		end }
		local result, why = f.run(function() return f.env.require("provider/chat").complete(record, {
			messages = { { role = "user", content = "hi" } }, timeout = 1,
		}) end, 303)
		check(lane .. " outlives old one-second and 300-second limits: " .. tostring(why), result and result.content == "ready")
		check(lane .. " uses one dispatch per explicit refusal", calls == 2 and f.h.http.requestCount == 0)
		check(lane .. " recovery retains unlimited bridge deadline", deadlines[1] == math.huge and deadlines[2] == math.huge)
		f.healthy(); f.close()
	end
end)

case("Responses fallback failure stays terminal and never pins the lane", function()
	for _, failure in ipairs({ "stream", "deadline" }) do
		local f = F.new(); local record = recordFor(f, "zen"); local calls = 0
		f.h.http.handler = function(spec)
			calls = calls + 1
			if spec.url:find("/chat/completions", 1, true) then
				if failure == "deadline" then f.h.sched.wait(0.6) end
				return { StatusCode = 403, Body = f.h.json.encode({ error = { type = "FreeTierError" } }) }
			end
			if failure == "deadline" then f.h.sched.wait(1) end
			return { StatusCode = 200, Body = 'data: {"type":"response.output_text.delta","delta":"partial"}\n\n' }
		end
		local result, why = f.run(function() return f.env.require("provider/chat").complete(record, { messages = { { role = "user", content = "hi" } }, timeout = 1 }) end, 1.3)
		check(failure .. " is terminal", not result and f.env.require("net/http").terminal(why))
		check("exactly one request per lane", calls == 2)
		check("failed lane is not remembered", not f.env.require("provider/responses").remembered(record))
		f.h.sched.advance(1); f.healthy(); f.close()
	end
end)

case("Responses rotates quota keys without recovering through the retired proxy", function()
	local f = F.new(); local record = recordFor(f, "zen")
	record.model, record.apiKey = "muse-spark-fixture", "first-key\nsecond-key"
	local captured, deadlines = {}, {}
	local http = f.env.require("net/http"); local send = http.send
	http.send = function(spec) deadlines[#deadlines + 1] = spec.deadlineMs; return send(spec) end
	f.h.http.handler = function(spec)
		captured[#captured + 1] = spec
		if #captured == 1 then return { StatusCode = 429, Body = '{"error":{"message":"quota"}}' } end
		return { StatusCode = 403, Body = '{"error":{"message":"unauthorized client"}}' }
	end
	local result, why = complete(f, record, { messages = { { role = "user", content = "hi" } }, onRetry = function() error("fixture retry callback") end })
	check("client refusal is not sent to retired proxy", not result and has(why, "unauthorized client") and #captured == 2)
	check("only quota rejection rotates the key", captured[1].headers.Authorization == "Bearer first-key" and captured[2].headers.Authorization == "Bearer second-key")
	check("one shared deadline", deadlines[1] == deadlines[2])
	for _, spec in ipairs(captured) do
		check("official Responses endpoint retained", spec.url == "https://opencode.ai/inference/v1/responses")
		check("desktop fingerprint survives recovery", spec.headers["x-opencode-client"] == "desktop" and spec.headers["x-opencode-session"] == captured[1].headers["x-opencode-session"])
	end
	f.healthy(); f.close()
end)

case("Responses refuses incomplete and failed output even when it contains partial text", function()
	local f = F.new(); local responses = f.env.require("provider/responses")
	for _, status in ipairs({ "incomplete", "failed", "cancelled" }) do
		local value = { object = "response", status = status, incomplete_details = { reason = "max_output_tokens" }, output = {
			{ type = "message", content = { { type = "output_text", text = "partial" } } },
		} }
		check(status .. " JSON is not a completion", responses.fromResponse(value).streamError ~= nil)
		local stream = "data: " .. f.h.json.encode({ type = "response." .. status, response = value }) .. "\n\n"
		stream = stream .. "data: " .. f.h.json.encode({ type = "response.completed", response = { status = "completed" } }) .. "\n\n"
		check(status .. " stream cannot become successful later", responses.parse(stream).streamError ~= nil)
	end
	f.healthy(); f.close()
end)

suite.finish()
