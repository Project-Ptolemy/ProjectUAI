-- Reviewed catalog rates, accounting, and model limits; no network calls.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Model pricing")
local case, check = suite.case, suite.check
local function near(a, b) return a and math.abs(a - b) < 0.000000001 end
local function provider(baseUrl) return { baseUrl = baseUrl } end
local OPENAI = provider("https://api.openai.com/v1")
local ZEN = provider("https://opencode.ai/zen/v1")
local GO = provider("https://opencode.ai/inference/go/v1")
local ROUTER = provider("https://openrouter.ai/api/v1")
local KILO = provider("https://api.kilo.ai/api/gateway")
local CLINE = provider("https://uai-tunnel.invalid/cline/v1")

case("current model rates stay exact and scoped to the endpoint", function()
	local f = F.new(); local pricing = f.env.require("agent/pricing")
	check("GPT 6.1 Sol current base price", pricing.priceFor("gpt-6.1-sol", OPENAI)[1] == 2)
	check("Opus 5.5 current base price", pricing.priceFor("claude-opus-5-5")[1] == 4)
	check("direct DeepSeek has its own rate", pricing.priceFor("deepseek-v4-flash", provider("https://api.deepseek.com/v1"))[1] == 0.15)
	check("Zen DeepSeek has its own rate", pricing.priceFor("deepseek-v4-flash", ZEN)[1] == 0.14)
	check("OpenRouter DeepSeek has its own rate", pricing.priceFor("deepseek/deepseek-v4-flash", ROUTER)[1] == 0.091)
	check("invented snapshots do not borrow a family rate", pricing.priceFor("gpt-4o-2099-01-01", OPENAI) == nil)
	check("substrings do not borrow a model rate", pricing.priceFor("not-gpt-4o-custom", OPENAI) == nil)
	check("OpenRouter retains its provider namespace", pricing.priceFor("gpt-4o", ROUTER) == nil)
	check("a changed preset URL is not a direct-provider price", pricing.priceFor("gpt-4o", { preset = "openai", baseUrl = "https://custom.example/v1" }) == nil)
	f.healthy(); f.close()
end)

case("free variants never change paid model prices", function()
	local f = F.new(); local pricing = f.env.require("agent/pricing")
	check("CLI free model is zero", pricing.priceFor("deepseek-v4.1-flash-free", ZEN)[1] == 0)
	check("official inference alias retains its free rate", pricing.priceFor("cat-jam-free", provider("https://opencode.ai/inference/v1"))[1] == 0)
	check("official OpenAI inference alias retains its free rate", pricing.priceFor("cat-jam-free", provider("https://opencode.ai/inference/openai/v1"))[1] == 0)
	check("paid model remains priced", pricing.priceFor("deepseek-v4.1-flash", ZEN)[1] > 0)
	check("invented free model stays unknown", pricing.priceFor("invented-model:free", ZEN) == nil)
	check("same free id is not priced on a custom host", pricing.priceFor("deepseek-v4.1-flash-free", provider("https://relay.example/v1")) == nil)
	f.healthy(); f.close()
end)

case("Go metadata retains independent limits without inventing subscription charges", function()
	local f = F.new(); local pricing = f.env.require("agent/pricing"); local info = f.env.require("provider/model_info")
	local traits = f.env.require("provider/traits")
	check("Go uses its separate provider catalog", info.provider(GO) == "opencode-go"
		and info.provider(provider("https://opencode.ai/zen/go/v1/messages")) == "opencode-go")
	check("Go DeepSeek limits are known", traits.contextWindow("deepseek-v4.1-flash", GO) == 1000000
		and traits.maxOutput("deepseek-v4.1-flash", GO) == 384000)
	check("Go subscription token rates do not become an additional charge", pricing.priceFor("deepseek-v4.1-flash", GO) == nil)
	check("Go does not borrow a Zen free rate", pricing.priceFor("cat-jam-free", GO) == nil)
	f.healthy(); f.close()
end)

case("Kilo and Cline prices stay scoped to exact supported routes", function()
	local f = F.new(); local pricing = f.env.require("agent/pricing"); local traits = f.env.require("provider/traits")
	check("Kilo auto free has a verified zero rate", pricing.priceFor("kilo-auto/free", KILO)[1] == 0)
	check("Kilo paid model keeps its published rate", pricing.priceFor("openai/gpt-6.1-sol", KILO)[2] == 10)
	check("Kilo documented limits enrich discovered models", traits.contextWindow("recursive/flint-v1.0:free", KILO) == 262144
		and traits.maxOutput("recursive/flint-v1.0:free", KILO) == 235929)
	check("Kilo zero placeholders remain unknown", pricing.priceFor("google/lyria-3-pro-preview", KILO) == nil)
	for _, base in ipairs({ "https://api.kilo.ai/unrelated", "http://api.kilo.ai/api/gateway", "https://api.kilo.ai:8443/api/gateway",
		"https://api.kilo.ai.example/api/gateway", "https://custom.example/v1" }) do
		check("Kilo prices cannot cross route " .. base, pricing.priceFor("kilo-auto/free", provider(base)) == nil)
	end
	check("documented Kilo gateway alias retains scoped prices", pricing.priceFor("kilo-auto/free", provider("https://ai-gateway.kilo.ai:443/api/v1/chat/completions"))[1] == 0)
	check("Cline exact promotion has a zero rate", pricing.priceFor("reflection/beam-free", CLINE)[1] == 0)
	check("Cline cannot borrow another free or paid ID", pricing.priceFor("reflection/beam", CLINE) == nil
		and pricing.priceFor("invented:free", CLINE) == nil)
	check("Cline promotion does not price another endpoint", pricing.priceFor("reflection/beam-free", provider("https://custom.example/v1")) == nil)
	check("unsupported Cline routes have no price", pricing.priceFor("reflection/beam-free", provider("https://uai-tunnel.invalid/cline/v1/responses")) == nil)
	f.healthy(); f.close()
end)

case("October catalog changes update billing estimates and provider limits", function()
	local f = F.new(); local pricing = f.env.require("agent/pricing"); local traits = f.env.require("provider/traits")
	local mistral = pricing.priceFor("mistral-large-4", provider("https://api.mistral.ai/v1"))
	check("Mistral Large 4 uses the updated public rate", mistral[1] == 1.36 and mistral[2] == 4.18)
	local together = provider("https://api.together.xyz/v1")
	check("Together Qwen has its provider-specific updated rate", pricing.priceFor("qwen/qwen3.7-max", together)[1] == 2.5)
	check("Together Qwen reply limit comes from current catalog", traits.maxOutput("qwen/qwen3.6-plus", together) == 65536)
	check("retired Mistral model is no longer priced", pricing.priceFor("mistral-large-2411", provider("https://api.mistral.ai/v1")) == nil)
	check("direct DeepSeek context uses its corrected size", traits.contextWindow("deepseek-v4-flash", provider("https://api.deepseek.com/v1")) == 1048576)
	f.healthy(); f.close()
end)

case("included Free access is zero but personal HCNSEC prices are unknown", function()
	local f = F.new(); local registry = f.env.require("provider/registry")
	local record = registry.blank("projectuai-free"); local pricing = f.env.require("agent/pricing")
	check("included resolved model is free", pricing.priceFor("agnes-3.0-flash", record)[1] == 0)
	check("included named paid model still costs the user zero", pricing.priceFor("gpt-6.1-sol", record)[2] == 0)
	record.headers = { aUtHoRiZaTiOn = "Bearer personal-fixture-key" }
	check("an auth-header override is not included access", pricing.priceFor("gpt-6.1-sol", record) == nil
		and not f.env.require("provider/models").isFree(record, "gpt-6.1-sol"))
	record.headers = { ["x-api-key"] = "personal-fixture-key" }
	check("a second personal auth header is not included access", pricing.priceFor("gpt-6.1-sol", record) == nil)
	record.headers = { Authorization = "Bearer " .. record.apiKey }
	check("an identical explicit included header remains free", pricing.priceFor("gpt-6.1-sol", record)[1] == 0)
	record.headers = {}
	record.apiKey = "personal-fixture-key"
	check("personal key does not inherit included access", pricing.priceFor("gpt-6.1-sol", record) == nil)
	record.authStyle = "none"
	record.headers = { authorization = "Bearer personal-fixture-key", ["Api-Key"] = "personal-fixture-key", ["X-Custom"] = "keep" }
	assert(f.env.require("provider/community_key").apply(record))
	check("explicit included action selects bearer and removes auth overrides", record.authStyle == "bearer"
		and record.headers.authorization == nil and record.headers["Api-Key"] == nil and record.headers["X-Custom"] == "keep"
		and pricing.priceFor("gpt-6.1-sol", record)[1] == 0)
	f.healthy(); f.close()
end)

case("local cost depends on the parsed host", function()
	local f = F.new(); local pricing = f.env.require("agent/pricing")
	for _, base in ipairs({ "http://localhost:11434/v1", "http://127.0.0.1:1234/v1", "http://[::1]:8000/v1" }) do
		check("loopback costs zero " .. base, pricing.priceFor("local-model", provider(base))[1] == 0)
	end
	check("query text is not a loopback host", pricing.priceFor("gpt-4o", provider("https://custom.example/v1?host=localhost")) == nil)
	check("hostname suffix is not loopback", pricing.priceFor("gpt-4o", provider("https://localhost.example/v1")) == nil)
	f.healthy(); f.close()
end)

case("cache tokens and long-context tiers affect actual request cost", function()
	local f = F.new(); local pricing = f.env.require("agent/pricing")
	check("threshold itself keeps base rate", pricing.priceFor("gpt-6.1-sol", OPENAI, 272000)[1] == 2)
	check("above threshold selects long-context rate", pricing.priceFor("gpt-6.1-sol", OPENAI, 272001)[1] == 4)
	check("cached input uses discounted rate", near(pricing.costFor("gpt-6.1-sol", OPENAI, 1000, 100, 800, 0), 0.00148))
	check("long context applies the selected tier to all tokens", near(pricing.costFor("gpt-6.1-sol", OPENAI, 300000, 1000, 100000, 0), 0.835))
	local anthropic = provider("https://api.anthropic.com/v1")
	check("cache creation is charged once at its write rate", near(pricing.costFor("claude-opus-5-5", anthropic, 1000, 100, 600, 200), 0.00392))
	check("excess cached tokens cannot produce a negative charge", near(pricing.costFor("gpt-6.1-sol", OPENAI, 100, 0, 1000, 0), 0.00001))
	f.healthy(); f.close()
end)

case("usage preserves known versus unknown estimates and cache-write details", function()
	local f = F.new(); local usage = f.env.require("agent/usage")
	local result = usage.record({ prompt_tokens = 1000, completion_tokens = 100,
		prompt_tokens_details = { cached_tokens = 600, cache_creation_tokens = 200 } }, "claude-opus-5-5", nil, provider("https://api.anthropic.com/v1"))
	check("normalized cache-write detail contributes to cost", result.costKnown and near(result.cost, 0.00392))
	local responses = usage.record({ input_tokens = 1000, output_tokens = 100,
		input_tokens_details = { cached_tokens = 600 }, output_tokens_details = { reasoning_tokens = 20 },
		cache_creation_input_tokens = 200 }, "claude-opus-5-5", { prompt = 9999, completion = 9999 }, provider("https://api.anthropic.com/v1"))
	check("Responses reports counts instead of estimates", responses.prompt == 1000 and responses.completion == 100 and responses.estimated == false)
	check("Responses cache writes and reads are costed", near(responses.cost, 0.00392) and usage.session.reasoning == 20)
	local unknown = usage.record({ prompt_tokens = 100, completion_tokens = 10 }, "custom-model", nil, provider("https://custom.example/v1"))
	check("unknown rate is separate from zero", unknown.costKnown == false and unknown.cost == 0)
	check("partial totals are labeled", usage.line():find("some costs unknown", 1, true) and usage.line():find("est.", 1, true))
	usage.reset(); check("reset clears missing-rate state", usage.session.unpriced == nil)
	f.healthy(); f.close()
end)

case("documented free-route limits and direct provider limits reach model traits", function()
	local f = F.new(); local traits = f.env.require("provider/traits")
	local expected = {
		["cat-jam-free"] = { 1048576, 131072 }, ["longcat-2.5-preview-free"] = { 1000000, 131072 },
		["space-bunny-free"] = { 524288, 524288 }, ["mimo-v2.6-flash-free"] = { 200000, 32000 },
		["step-5-preview-free"] = { 1000000, 65536 }, ["deepseek-v4.1-flash-free"] = { 200000, 32000 },
		["glm-5.3-flash-free"] = { 200000, 32000 },
		["muse-spark-1.3-contributor-free"] = { 1048576, 131072 }, ["nemotron-3.5-lightning-free"] = { 262144, 262144 },
		["nemotron-3-ultra-free"] = { 1000000, 128000 }, ["big-pickle"] = { 160000, 32000 },
	}
	for id, limits in pairs(expected) do
		check("CLI input window " .. id, traits.contextWindow(id, ZEN) == limits[1])
		check("CLI output ceiling " .. id, traits.maxOutput(id, ZEN) == limits[2])
	end
	check("explicit GPT input cap is respected", traits.contextWindow("gpt-6.1-sol", OPENAI) == 922000)
	check("Zen output differs from direct DeepSeek", traits.maxOutput("deepseek-v4-flash", ZEN) == 384000
		and traits.maxOutput("deepseek-v4-flash", provider("https://api.deepseek.com/v1")) == 393216)
	f.healthy(); f.close()
end)

case("catalog reasoning flags preserve protocol rules and user overrides", function()
	local f = F.new(); local traits = f.env.require("provider/traits")
	local config = f.env.require("runtime/config")
	check("reasoning support does not imply Anthropic adaptive shape", traits.of("gpt-6.1-sol").reasoning == true and traits.thinkingStyle("gpt-6.1-sol") == nil)
	check("existing cat-jam protocol rule is preserved", traits.thinkingStyle("cat-jam-free") == "adaptive" and traits.maxTools("cat-jam-free") == 128)
	config.set("agent.forceContext", { ["big-pickle"] = 64000 })
	config.set("agent.forceReasoning", { ["gpt-6.1-sol"] = true })
	check("manual context wins over current catalog", traits.contextWindow("big-pickle", ZEN) == 64000)
	check("manual reasoning claim remains effective", traits.thinkingStyle("gpt-6.1-sol") == "adaptive")
	f.healthy(); f.close()
end)

suite.finish()
