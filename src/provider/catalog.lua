-- Built-in provider presets.
--
-- A preset is a base URL and an auth style, nothing more. It deliberately does not
-- carry a model list: the only authority on which models an endpoint serves is the
-- endpoint, so models come from GET /v1/models or from the user typing one in. A
-- hardcoded list goes stale, and offering a model the provider does not have wastes
-- a turn on a 404 that looks like a bug. Project UAI Free is the managed exception:
-- its provider-supported `auto` router was verified with discovery and tool calls.
--
-- Every preset also carries what the provider gallery needs to describe it before a
-- key exists: a tier, a two-sentence description, an access line, and search tags.
-- The gallery is the first screen of the add flow, so a vendor that cannot say what
-- it is and what it costs in one card is a vendor nobody picks. `note` remains the
-- long-form setup guidance the editor shows after a card is chosen.
--
-- Tiers mean one thing each:
--   free  -- a first request can be made without paying (included key, free quota,
--            free tier or no key at all). "Free" is about starting, not about an
--            unlimited service, so the access line always says which it is.
--   paid  -- needs credit, a subscription or a top-up before the endpoint answers.
--   local -- a server the user runs; no vendor account is involved.
-- `free = true` is a separate flag and belongs only to Project UAI Free, because it
-- is what installs the distributed community key.
return function(env)
	local M = {}

	-- Included access is an explicit library choice. Quick picks are independent
	-- from the gallery and never install an included provider on first run.
	M.tiers = {
		{
			id = "free",
			label = "Recommended",
			caption = "Free to start. No card needed.",
			empty = "No free route matches that search.",
		},
		{
			id = "paid",
			label = "Paid",
			caption = "Needs credit, a plan or a top-up.",
			empty = "No paid provider matches that search.",
		},
		{
			id = "local",
			label = "Local",
			caption = "Servers you run yourself.",
			empty = "No local server matches that search.",
		},
	}

	-- authStyle: bearer | x-api-key | x-goog-api-key | api-key | both | none
	--   both sends Authorization and x-api-key together, which is what several
	--   self-hosted relays expect and what the reference client did unconditionally.
	-- Reachability is derived from the configured URL, including custom endpoints.
	-- RequestAsync refuses loopback and private addresses.
	M.presets = {
		-- Free to start -------------------------------------------------------
		{
			id = "projectuai-free",
			label = "Project UAI Free",
			tier = "free",
			order = 1,
			description = "Optional community access, daily 20:00-12:00 UTC+8 (Beijing/Singapore). No account, payment or personal key.",
			cost = "Included \194\183 no key needed",
			tags = { "free", "included", "auto", "community", "hcnsec" },
			baseUrl = "https://api.hcnsec.cn/v1",
			authStyle = "bearer",
			keyHint = "Community access only. Choose the separate HCNSEC provider for a personal key.",
			docs = "https://discord.gg/9xYyyYuKap",
			free = true,
			defaultModel = "auto",
			note = "Optional access for the Project UAI community. No account, payment or personal API key is needed. Add this provider from the library and save to opt in. Available daily 20:00-12:00 UTC+8 (Beijing/Singapore), through the following midday. Outside these hours, choose another provider or return at 20:00 UTC+8. Auto prefers recently verified tool-capable models; response times and shared capacity vary. Personal HCNSEC accounts use the separate HCNSEC provider. Help and availability updates: https://discord.gg/9xYyyYuKap",
			noteHighlight = "No account, payment or personal API key is needed.",
			badge = "Included",
			badgeTone = "good",
			highlight = true,
		},
		{
			id = "agentrouter",
			label = "AgentRouter",
			tier = "free",
			order = 2,
			description = "A Claude Messages and GPT Responses gateway. Models vary by account and availability; registration needs a GitHub account at least 1 year old.",
			cost = "Free quota \194\183 GitHub account 1+ year",
			tags = { "claude", "anthropic", "gpt", "responses", "deepseek", "gateway", "free" },
			-- The normaliser adds /v1; adapters select the model's documented protocol.
			baseUrl = "https://agentrouter.org",
			authStyle = "x-api-key",
			keyHint = "AgentRouter API key",
			docs = "https://agentrouter.org/register?aff=4pqF",
			api = "anthropic",
			headers = { ["anthropic-version"] = "2023-06-01" },
			featured = true,
			featuredOrder = 2,
			requiresClaude = true,
			note = "Use your AgentRouter API key and fetch the models available to that account. UAI selects Responses for supported GPT models and Messages for other models on the official AgentRouter route. A model appearing in the list does not guarantee capacity or regional availability. Registration needs a GitHub account at least 1 year old.",
			noteHighlight = "a GitHub account at least 1 year old",
			badge = "Free tier",
			badgeTone = "good",
			highlight = true,
		},
		{
			id = "zen",
			label = "OpenCode Zen",
			tier = "free",
			order = 3,
			description = "OpenCode's curated relay: free models through the desktop CLI, paid models with a Zen key. Hybrid, not a paid-only service.",
			cost = "Free models via desktop CLI \194\183 paid key",
			tags = { "opencode", "zen", "cli", "free-models" },
			baseUrl = "https://opencode.ai/zen/v1",
			authStyle = "bearer",
			keyHint = "API key from opencode.ai/zen",
			docs = "https://opencode.ai/zen",
			-- Keep the existing OpenCode request compatibility headers, scoped to the
			-- official host, without mixing in the Claude Code identity.
			claudeUa = false,
			-- Desktop retains direct request compatibility; the installed CLI is an
			-- additional route through the desktop bridge, never a bundled binary.
			note = "Desktop supports the direct OpenCode workaround without a bridge. Project UAI Bridge also supports a separately installed OpenCode CLI for free models; models fetched from the connected CLI need no personal key. Mobile OpenCode requires the UAI Relay app from Discord; install and start the app, then connect it in UAI. The retired OpenCode proxy cannot restore mobile access. Direct and paid Zen API access use your own key. Help and updates: https://discord.gg/9xYyyYuKap",
			noteHighlight = "Mobile OpenCode requires the UAI Relay app from Discord",
			featured = true,
			featuredOrder = 3,
			badge = "Free models",
			badgeTone = "good",
			highlight = true,
		},
		{
			id = "openrouter",
			label = "OpenRouter",
			tier = "free",
			order = 4,
			description = "One key for hundreds of models, including free ones, with automatic route fallbacks. Hybrid: free ids need no credit.",
			cost = "Free model ids \194\183 top up for the rest",
			tags = { "gateway", "router", "models", "free-models" },
			baseUrl = "https://openrouter.ai/api/v1",
			authStyle = "bearer",
			keyHint = "sk-or-...",
			docs = "https://openrouter.ai/keys",
			featured = true,
			featuredOrder = 4,
			-- OpenRouter reads both of these for attribution, and sending only one of
			-- them is a shape no real client produces.
			headers = {
				["X-Title"] = "Project UAI",
				["X-OpenRouter-Title"] = "Project UAI",
				["HTTP-Referer"] = "https://github.com/Project-Ptolemy/ProjectUAI",
				["X-OpenRouter-Categories"] = "game,cli-agent",
			},
			claudeUa = false,
			note = "Lists several hundred models. Fetch them and pick, or type the id shown on openrouter.ai. Ids ending in :free cost nothing but are rate-limited; a one-time credit purchase raises that limit.",
			badge = "Free models",
			badgeTone = "good",
		},
		{
			id = "opencode-go",
			label = "OpenCode Go",
			tier = "free",
			order = 5,
			description = "OpenCode Go's paid endpoint, plus the desktop CLI's free model catalog. Hybrid: the subscription covers Go, not the free CLI route.",
			cost = "Subscription for Go \194\183 free CLI catalog",
			tags = { "opencode", "go", "subscription" },
			baseUrl = "https://opencode.ai/inference/go/v1",
			authStyle = "bearer",
			keyHint = "API key from the workspace with your active OpenCode Go subscription",
			docs = "https://opencode.ai/docs/go/",
			claudeUa = false,
			note = "Paid OpenCode Go access uses your own subscribed workspace key and the separate Go endpoint. Review the workspace Privacy region setting if Go requires Global regions. Fetch models from Go; DeepSeek uses Chat, GPT/Grok/Muse use Responses, Claude/Minimax/Qwen use Messages, and Gemini uses its native API automatically. Go uses keyed requests; the desktop-only free CLI catalog is separate. A successful model list does not verify your subscription.",
			badge = "Free CLI",
			badgeTone = "good",
		},

		{
			id = "kilo",
			label = "Kilo Code",
			tier = "free",
			order = 6,
			description = "A free gateway with an auto-router over a rotating free pool. No key and no account.",
			cost = "Free \194\183 no key \194\183 hourly allowance",
			tags = { "free", "no-key", "gateway", "auto", "coder" },
			baseUrl = "https://api.kilo.ai/api/gateway",
			authStyle = "none",
			-- A public no-key gateway is not a Claude endpoint, and the identity headers
			-- would be a claim about a client it never asked for.
			claudeUa = false,
			docs = "https://kilo.ai",
			note = "Free models share an hourly allowance. Anonymous use is limited by outbound address; signed-in use is limited by account. To sign in, choose Bearer and enter your Kilo key. The optional Kilo tunnel in Cowork can try another connection after an anonymous quota response. Each connection still has an allowance, and shared exits may already be limited.",
			badge = "No key",
			badgeTone = "good",
		},
		{
			id = "cline",
			label = "Cline",
			tier = "free",
			order = 6.5,
			description = "Cline's supported free models through UAI Bridge on Windows. Uses your Cline sign-in in the desktop app.",
			cost = "Free models \194\183 desktop bridge \194\183 Cline sign-in",
			tags = { "cline", "free", "cli", "desktop", "tunnel" },
			baseUrl = "https://uai-tunnel.invalid/cline/v1",
			authStyle = "none",
			claudeUa = false,
			docs = "https://docs.cline.bot/cline-cli/overview",
			note = "In the Windows app, open Tunnels, enable Cline and sign in. Connect Cowork, then fetch models here. Cline must be installed separately. This connection supports text only; image requests are rejected. Only the bridge's current free catalog is supported; provider allowances still apply. Android and direct executor requests cannot use this connection. No Cline sign-in credentials are copied into Roblox.",
			badge = "Free CLI",
			badgeTone = "good",
		},

		{
			id = "ovh",
			label = "OVHcloud AI Endpoints",
			tier = "free",
			order = 7,
			description = "EU-hosted open models with an anonymous tier that needs no key at all.",
			cost = "Free anonymous tier \194\183 2 req/min",
			tags = { "free", "no-key", "eu", "europe", "open-models" },
			baseUrl = "https://oai.endpoints.kepler.ai.cloud.ovh.net/v1",
			authStyle = "none",
			claudeUa = false,
			docs = "https://endpoints.ai.cloud.ovh.com",
			note = "Anonymous requests are limited to about two per minute per model. Add an OVHcloud key and select Bearer for production limits and pay-as-you-go billing.",
			badge = "No key",
			badgeTone = "good",
		},
		{
			id = "google",
			label = "Google Gemini",
			tier = "free",
			order = 8,
			description = "Google's native Gemini API: text, images, tools and signed reasoning replay. The key is free from AI Studio.",
			cost = "Free tier \194\183 key from AI Studio",
			tags = { "google", "gemini", "vision", "images", "free" },
			baseUrl = "https://generativelanguage.googleapis.com/v1beta",
			authStyle = "x-goog-api-key",
			api = "gemini",
			keyHint = "AIza...",
			docs = "https://aistudio.google.com/apikey",
			note = "Gemini's native generateContent API supports text, tool calls, image input through the bridge, reasoning summaries and signed multi-step tool replay. Fetch models with your Google AI Studio key. Existing OpenAI-compatible connections remain supported.",
			badge = "Free tier",
			badgeTone = "good",
		},
		{
			id = "groq",
			label = "Groq",
			tier = "free",
			order = 9,
			description = "Very fast LPU inference on open models, with a free developer tier.",
			cost = "Free tier \194\183 30 req/min",
			tags = { "fast", "open-models", "llama", "free" },
			baseUrl = "https://api.groq.com/openai/v1",
			authStyle = "bearer",
			keyHint = "gsk_...",
			docs = "https://console.groq.com/keys",
			badge = "Free tier",
			badgeTone = "good",
		},
		{
			id = "cerebras",
			label = "Cerebras",
			tier = "free",
			order = 10,
			description = "Wafer-scale inference that returns open-model answers faster than almost anything else.",
			cost = "Free tier \194\183 daily token allowance",
			tags = { "fast", "open-models", "free", "llama", "qwen" },
			baseUrl = "https://api.cerebras.ai/v1",
			authStyle = "bearer",
			docs = "https://cloud.cerebras.ai",
			badge = "Free tier",
			badgeTone = "good",
		},
		{
			id = "mistral",
			label = "Mistral",
			tier = "free",
			order = 11,
			description = "European models with a free experiment tier and OpenAI-compatible endpoints.",
			cost = "Free tier \194\183 monthly credits",
			tags = { "eu", "europe", "free", "mistral", "codestral" },
			baseUrl = "https://api.mistral.ai/v1",
			authStyle = "bearer",
			docs = "https://console.mistral.ai/api-keys",
			badge = "Free tier",
			badgeTone = "good",
		},
		{
			id = "modelscope",
			label = "ModelScope",
			tier = "free",
			order = 12,
			description = "Alibaba's open-model hub with a daily free inference allowance.",
			cost = "Free \194\183 2,000 requests/day",
			tags = { "china", "open-models", "qwen", "free" },
			baseUrl = "https://api-inference.modelscope.cn/v1",
			authStyle = "bearer",
			keyHint = "ModelScope access token",
			docs = "https://modelscope.cn",
			note = "Needs a ModelScope account bound to Alibaba Cloud with real-name verification. The daily quota is shared across models and each model has its own cap.",
			badge = "Free tier",
			badgeTone = "good",
		},
		{
			id = "zai",
			label = "Z.ai (GLM)",
			tier = "free",
			order = 13,
			description = "Zhipu's GLM models, including free Flash variants, on an OpenAI-compatible API.",
			cost = "Free Flash models \194\183 key required",
			tags = { "china", "glm", "zhipu", "free", "coding" },
			baseUrl = "https://api.z.ai/api/paas/v4",
			authStyle = "bearer",
			keyHint = "API key from the Z.ai console",
			docs = "https://z.ai/model-api",
			note = "The mainland-China endpoint is https://open.bigmodel.cn/api/paas/v4. Free Flash models allow one concurrent request; paid models are billed per token.",
			badge = "Free tier",
			badgeTone = "good",
		},
		{
			id = "nvidia",
			label = "NVIDIA NIM",
			tier = "free",
			order = 14,
			description = "NVIDIA's hosted NIM catalogue of open models, free for developer-program members.",
			cost = "Free developer credits \194\183 40 req/min",
			tags = { "nvidia", "open-models", "free", "nim" },
			baseUrl = "https://integrate.api.nvidia.com/v1",
			authStyle = "bearer",
			keyHint = "nvapi-...",
			docs = "https://build.nvidia.com",
			note = "Keys come from a NVIDIA Developer Program account. Rate limits apply per model, and the catalogue includes models that only some accounts can call.",
			badge = "Free tier",
			badgeTone = "good",
		},
		{
			id = "cloudflare",
			label = "Cloudflare Workers AI",
			tier = "free",
			order = 15,
			description = "Serverless open-model inference billed in daily Neurons, with a free allocation.",
			cost = "Free daily allocation \194\183 account ID",
			tags = { "cloudflare", "serverless", "free", "open-models" },
			baseUrl = "https://api.cloudflare.com/client/v4/accounts/YOUR-ACCOUNT-ID/ai/v1",
			authStyle = "bearer",
			keyHint = "API token with Workers AI access",
			docs = "https://developers.cloudflare.com/workers-ai/",
			note = "Replace YOUR-ACCOUNT-ID with the account id from the Cloudflare dashboard. The free allocation resets daily and overages fail instead of billing.",
			badge = "Free tier",
			badgeTone = "good",
		},
		{
			id = "aionlabs",
			label = "Aion Labs",
			tier = "free",
			order = 16,
			description = "A free key with a small daily token allowance, tuned for roleplay and long-form writing.",
			cost = "Free \194\183 20K tokens/day",
			tags = { "free", "roleplay", "story", "writing" },
			baseUrl = "https://api.aionlabs.ai/v1",
			authStyle = "bearer",
			docs = "https://aionlabs.ai",
			note = "The free allowance is small and meant for evaluation. Model availability and limits are set by the provider.",
			badge = "Free tier",
			badgeTone = "good",
		},

		{
			id = "vercel",
			label = "Vercel AI Gateway",
			tier = "free",
			order = 18,
			description = "A multi-provider gateway with monthly starter credits for eligible models. Uses a Vercel team's AI Gateway key.",
			cost = "$5/month free-tier credits / eligible models only",
			tags = { "vercel", "gateway", "free", "credits", "openai", "anthropic", "google", "tools" },
			baseUrl = "https://ai-gateway.vercel.sh/v1",
			authStyle = "bearer",
			claudeUa = false,
			keyHint = "AI Gateway API key from your Vercel team",
			docs = "https://vercel.com/docs/ai-gateway/sdks-and-apis/openai-chat-completions",
			note = "Create an AI Gateway API key for your Vercel team, then fetch models. The free tier provides $5 monthly credits for a subset of models with lower per-model rate limits; the public catalog also lists paid models. Check Vercel's Free Tier model list before selecting. Purchasing credits moves the account to the paid tier and ends the monthly free credit. Chat Completions supports streaming and tool calling.",
			badge = "Free credits",
			badgeTone = "good",
		},

		-- Paid ----------------------------------------------------------------
		{
			id = "hcnsec",
			label = "HCNSEC",
			tier = "paid",
			order = 45,
			description = "Use your own HCNSEC account and API key. Models and charges depend on that account.",
			cost = "Personal account and API key",
			tags = { "hcnsec", "personal", "gateway", "account" },
			baseUrl = "https://api.hcnsec.cn/v1",
			authStyle = "bearer",
			keyHint = "Your personal HCNSEC API key",
			docs = "https://api.hcnsec.cn",
			note = "Enter your personal HCNSEC key and fetch the models available to your account, or enter an exact model ID. Account quotas, availability and pricing come from HCNSEC. This provider has no Project UAI community credential or daily community schedule. Optional Project UAI Free access is a separate provider in the library.",
			badge = "Personal key",
			badgeTone = "neutral",
		},
		{
			id = "openai",
			label = "OpenAI",
			tier = "paid",
			order = 1,
			description = "The reference API for GPT models, images and tools, and the most compatible target for new features.",
			cost = "Pay as you go \194\183 top up",
			tags = { "gpt", "openai", "vision", "images", "reasoning" },
			baseUrl = "https://api.openai.com/v1",
			authStyle = "bearer",
			keyHint = "sk-...",
			docs = "https://platform.openai.com/api-keys",
		},
		{
			id = "anthropic-messages",
			label = "Anthropic (Messages API)",
			tier = "paid",
			order = 2,
			description = "Anthropic's native Messages API. Reasoning and tool calls arrive in their real shape.",
			cost = "Pay as you go \194\183 top up",
			tags = { "claude", "anthropic", "reasoning", "tools" },
			baseUrl = "https://api.anthropic.com/v1",
			authStyle = "x-api-key",
			keyHint = "sk-ant-...",
			docs = "https://console.anthropic.com/settings/keys",
			-- The native API rather than the compatibility shim: thinking blocks and
			-- tool_use content survive the round trip, and nothing is being translated
			-- twice on the way through someone else's adapter.
			api = "anthropic",
			note = "Anthropic's own Messages API. Preferred over the OpenAI-compatible route: reasoning and tool calls arrive in their real shape.",
		},
		{
			id = "anthropic",
			label = "Anthropic (OpenAI-compatible)",
			tier = "paid",
			order = 3,
			description = "Anthropic's OpenAI-compatible endpoint for clients that speak Chat Completions.",
			cost = "Pay as you go \194\183 top up",
			tags = { "claude", "anthropic", "compatible" },
			baseUrl = "https://api.anthropic.com/v1",
			authStyle = "x-api-key",
			keyHint = "sk-ant-...",
			docs = "https://console.anthropic.com/settings/keys",
			-- The compatibility route wants the version header; it is harmless
			-- elsewhere but only defaulted on here.
			headers = { ["anthropic-version"] = "2023-06-01" },
			note = "Anthropic's OpenAI-compatible endpoint. Tool calling works; some sampling fields are ignored.",
		},

		{
			id = "deepseek",
			label = "DeepSeek",
			tier = "paid",
			order = 5,
			description = "DeepSeek's own API: strong reasoning at low prices, with thinking streamed separately.",
			cost = "Pay as you go \194\183 top up",
			tags = { "deepseek", "reasoning", "cheap", "coding" },
			baseUrl = "https://api.deepseek.com/v1",
			authStyle = "bearer",
			keyHint = "sk-...",
			docs = "https://platform.deepseek.com/api_keys",
			note = "Reasoning models here stream their chain of thought as reasoning_content, which the transcript shows separately.",
		},
		{
			id = "xai",
			label = "xAI",
			tier = "paid",
			order = 6,
			description = "Grok models with a large context window, live search options and native tool calling.",
			cost = "Pay as you go \194\183 top up",
			tags = { "grok", "xai", "reasoning", "search" },
			baseUrl = "https://api.x.ai/v1",
			authStyle = "bearer",
			keyHint = "xai-...",
			docs = "https://console.x.ai",
		},
		{
			id = "together",
			label = "Together AI",
			tier = "paid",
			order = 7,
			description = "A broad catalogue of open-weight models with per-token pricing and fast endpoints.",
			cost = "Pay as you go \194\183 top up",
			tags = { "open-models", "llama", "qwen", "serverless" },
			baseUrl = "https://api.together.xyz/v1",
			authStyle = "bearer",
			docs = "https://api.together.ai/settings/api-keys",
		},
		{
			id = "fireworks",
			label = "Fireworks",
			tier = "paid",
			order = 8,
			description = "Fast open-model serving with a large catalogue and function calling.",
			cost = "Pay as you go \194\183 top up",
			tags = { "open-models", "fast", "serverless", "llama" },
			baseUrl = "https://api.fireworks.ai/inference/v1",
			authStyle = "bearer",
			keyHint = "fw_...",
			docs = "https://fireworks.ai/api-keys",
		},
		{
			id = "deepinfra",
			label = "DeepInfra",
			tier = "paid",
			order = 9,
			description = "Low-cost open-model inference with an OpenAI-compatible surface.",
			cost = "Pay as you go \194\183 top up",
			tags = { "open-models", "cheap", "serverless" },
			baseUrl = "https://api.deepinfra.com/v1/openai",
			authStyle = "bearer",
			docs = "https://deepinfra.com/dash/api_keys",
		},
		{
			id = "hyperbolic",
			label = "Hyperbolic",
			tier = "paid",
			order = 10,
			description = "Cheap open-model inference with a simple prepaid balance.",
			cost = "Pay as you go \194\183 top up",
			tags = { "open-models", "cheap", "serverless" },
			baseUrl = "https://api.hyperbolic.xyz/v1",
			authStyle = "bearer",
			docs = "https://app.hyperbolic.xyz/settings",
		},
		{
			id = "nebius",
			label = "Nebius AI Studio",
			tier = "paid",
			order = 11,
			description = "European GPU cloud serving open models on an OpenAI-compatible API.",
			cost = "Pay as you go \194\183 trial credits",
			tags = { "eu", "open-models", "serverless" },
			baseUrl = "https://api.studio.nebius.com/v1",
			authStyle = "bearer",
			docs = "https://studio.nebius.com",
		},
		{
			id = "novita",
			label = "Novita AI",
			tier = "paid",
			order = 12,
			description = "Open-model inference with a wide catalogue and per-token pricing.",
			cost = "Pay as you go \194\183 top up",
			tags = { "open-models", "serverless", "cheap" },
			baseUrl = "https://api.novita.ai/v3/openai",
			authStyle = "bearer",
			keyHint = "sk_...",
			docs = "https://novita.ai/settings/key-management",
		},
		{
			id = "sambanova",
			label = "SambaNova",
			tier = "paid",
			order = 13,
			description = "Fast inference on open models, including large Llama variants.",
			cost = "Pay as you go \194\183 free tier",
			tags = { "fast", "open-models", "llama" },
			baseUrl = "https://api.sambanova.ai/v1",
			authStyle = "bearer",
			docs = "https://cloud.sambanova.ai/apis",
		},
		{
			id = "moonshot",
			label = "Moonshot (Kimi)",
			tier = "paid",
			order = 15,
			description = "Kimi models with very long context from Moonshot AI.",
			cost = "Pay as you go \194\183 top up",
			tags = { "kimi", "long-context", "china" },
			baseUrl = "https://api.moonshot.ai/v1",
			authStyle = "bearer",
			keyHint = "sk-...",
			docs = "https://platform.moonshot.ai/console/api-keys",
			note = "The mainland-China endpoint is https://api.moonshot.cn/v1 and uses a separate key.",
		},
		{
			id = "dashscope",
			label = "Alibaba Qwen (Model Studio)",
			tier = "paid",
			order = 16,
			description = "Qwen models on Alibaba Cloud's OpenAI-compatible Model Studio endpoint.",
			cost = "Pay as you go \194\183 free quota",
			tags = { "qwen", "alibaba", "china", "long-context" },
			baseUrl = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
			authStyle = "bearer",
			keyHint = "sk-...",
			docs = "https://bailian.console.aliyun.com/",
			note = "The mainland-China endpoint is https://dashscope.aliyuncs.com/compatible-mode/v1. Keys are region-specific, so use the console that issued yours.",
		},
		{
			id = "siliconflow",
			label = "SiliconFlow",
			tier = "paid",
			order = 17,
			description = "Chinese and open models with a single key, including free ids on selected models.",
			cost = "Pay as you go \194\183 free models",
			tags = { "china", "open-models", "free-models", "qwen" },
			baseUrl = "https://api.siliconflow.cn/v1",
			authStyle = "bearer",
			keyHint = "sk-...",
			docs = "https://cloud.siliconflow.cn/account/ak",
			note = "The international endpoint is https://api.siliconflow.com/v1. Ids whose price is zero are free but rate-limited.",
		},
		{
			id = "volcengine",
			label = "ByteDance Volcano Ark",
			tier = "paid",
			order = 18,
			description = "Doubao models on ByteDance's OpenAI-compatible Ark API.",
			cost = "Pay as you go \194\183 top up",
			tags = { "doubao", "bytedance", "china", "vision" },
			baseUrl = "https://ark.cn-beijing.volces.com/api/v3",
			authStyle = "bearer",
			keyHint = "Ark API key",
			docs = "https://console.volcengine.com/ark",
			note = "Use an inference endpoint id or a model id as the model. The console issues keys per region, and this URL is the Beijing region.",
		},
		{
			id = "hunyuan",
			label = "Tencent Hunyuan",
			tier = "paid",
			order = 19,
			description = "Tencent's Hunyuan models on an OpenAI-compatible endpoint.",
			cost = "Pay as you go \194\183 free quota",
			tags = { "tencent", "hunyuan", "china" },
			baseUrl = "https://api.hunyuan.cloud.tencent.com/v1",
			authStyle = "bearer",
			keyHint = "API key from the Tencent Cloud console",
			docs = "https://console.cloud.tencent.com/hunyuan",
		},
		{
			id = "qianfan",
			label = "Baidu Qianfan",
			tier = "paid",
			order = 20,
			description = "Baidu's ERNIE models on the Qianfan v2 OpenAI-compatible API.",
			cost = "Pay as you go \194\183 free quota",
			tags = { "baidu", "ernie", "china" },
			baseUrl = "https://qianfan.baidubce.com/v2",
			authStyle = "bearer",
			keyHint = "bce-v3/ALTAK-...",
			docs = "https://console.bce.baidu.com/qianfan/",
			note = "Keys are issued as bce-v3/ALTAK-... bearer tokens. Some models are served through endpoint ids rather than model names.",
		},
		{
			id = "stepfun",
			label = "StepFun",
			tier = "paid",
			order = 21,
			description = "Step models with strong multimodal coverage and an OpenAI-compatible API.",
			cost = "Pay as you go \194\183 top up",
			tags = { "china", "step", "vision", "multimodal" },
			baseUrl = "https://api.stepfun.com/v1",
			authStyle = "bearer",
			docs = "https://platform.stepfun.com/interface-key",
		},
		{
			id = "yi",
			label = "01.AI (Yi)",
			tier = "paid",
			order = 22,
			description = "Yi models from 01.AI on an OpenAI-compatible endpoint.",
			cost = "Pay as you go \194\183 top up",
			tags = { "yi", "china", "open-models" },
			baseUrl = "https://api.lingyiwanwu.com/v1",
			authStyle = "bearer",
			docs = "https://platform.lingyiwanwu.com/apikeys",
		},
		{
			id = "baichuan",
			label = "Baichuan",
			tier = "paid",
			order = 23,
			description = "Baichuan's chat models on an OpenAI-compatible endpoint.",
			cost = "Pay as you go \194\183 top up",
			tags = { "baichuan", "china" },
			baseUrl = "https://api.baichuan-ai.com/v1",
			authStyle = "bearer",
			keyHint = "sk-...",
			docs = "https://platform.baichuan-ai.com/console/apikey",
		},
		{
			id = "spark",
			label = "iFlytek Spark",
			tier = "paid",
			order = 24,
			description = "iFlytek's Spark models behind an OpenAI-compatible HTTP endpoint.",
			cost = "Pay as you go \194\183 free quota",
			tags = { "iflytek", "spark", "china" },
			baseUrl = "https://spark-api-open.xf-yun.com/v1",
			authStyle = "bearer",
			keyHint = "APIPassword from the Spark console",
			docs = "https://console.xfyun.cn/services/cbm",
			note = "Spark's HTTP service uses the APIPassword value as a bearer token. Model ids include the version suffix shown in the console.",
		},
		{
			id = "upstage",
			label = "Upstage Solar",
			tier = "paid",
			order = 25,
			description = "Solar models from Upstage, with a strong Korean-language focus.",
			cost = "Pay as you go \194\183 free credits",
			tags = { "solar", "korean", "upstage" },
			baseUrl = "https://api.upstage.ai/v1/solar",
			authStyle = "bearer",
			keyHint = "up_...",
			docs = "https://console.upstage.ai/api-keys",
		},
		{
			id = "reka",
			label = "Reka",
			tier = "paid",
			order = 26,
			description = "Reka's multimodal models, including video and image understanding.",
			cost = "Pay as you go \194\183 top up",
			tags = { "reka", "multimodal", "video", "vision" },
			baseUrl = "https://api.reka.ai/v1",
			authStyle = "bearer",
			docs = "https://platform.reka.ai/apikeys",
		},
		{
			id = "ai21",
			label = "AI21 Labs",
			tier = "paid",
			order = 27,
			description = "Jamba models with long context and OpenAI-compatible chat.",
			cost = "Pay as you go \194\183 top up",
			tags = { "jamba", "long-context", "ai21" },
			baseUrl = "https://api.ai21.com/studio/v1",
			authStyle = "bearer",
			docs = "https://studio.ai21.com/account/api-key",
		},
		{
			id = "cohere",
			label = "Cohere",
			tier = "paid",
			order = 28,
			description = "Command models through Cohere's OpenAI-compatibility layer.",
			cost = "Pay as you go \194\183 trial key",
			tags = { "command", "cohere", "rag", "tools" },
			baseUrl = "https://api.cohere.ai/compatibility/v1",
			authStyle = "bearer",
			keyHint = "Trial or production key",
			docs = "https://dashboard.cohere.com/api-keys",
			note = "This is Cohere's compatibility layer, not its native v2 API. Tool calling and streaming work; Cohere-specific fields do not.",
		},
		{
			id = "huggingface",
			label = "Hugging Face Router",
			tier = "paid",
			order = 29,
			description = "One token for dozens of inference providers behind the Hugging Face router.",
			cost = "Credit-metered \194\183 free allowance",
			tags = { "huggingface", "router", "open-models" },
			baseUrl = "https://router.huggingface.co/v1",
			authStyle = "bearer",
			keyHint = "hf_...",
			docs = "https://huggingface.co/settings/tokens",
			note = "Model ids are namespaced, for example meta-llama/Llama-3.3-70B-Instruct. The router picks a hosting provider and bills through your Hugging Face account.",
		},
		{
			id = "ollama-cloud",
			label = "Ollama Cloud",
			tier = "paid",
			order = 30,
			description = "Ollama's hosted catalogue, reachable with the same OpenAI-compatible path as a local server.",
			cost = "Subscription \194\183 usage limits",
			tags = { "ollama", "hosted", "open-models" },
			baseUrl = "https://ollama.com/v1",
			authStyle = "bearer",
			keyHint = "Ollama API key",
			docs = "https://ollama.com/settings/keys",
			note = "Session and weekly limits apply and are not published as fixed numbers. Fetch the model list rather than guessing an id.",
		},
		{
			id = "baseten",
			label = "Baseten",
			tier = "paid",
			order = 31,
			description = "Deploy and call open models with per-token billing and your own deployments.",
			cost = "Pay as you go \194\183 top up",
			tags = { "baseten", "deploy", "open-models" },
			baseUrl = "https://inference.baseten.co/v1",
			authStyle = "bearer",
			docs = "https://app.baseten.co/settings/api_keys",
		},
		{
			id = "kluster",
			label = "Kluster AI",
			tier = "paid",
			order = 32,
			description = "Verified open-model inference with batch discounts.",
			cost = "Pay as you go \194\183 top up",
			tags = { "kluster", "batch", "open-models" },
			baseUrl = "https://api.kluster.ai/v1",
			authStyle = "bearer",
			docs = "https://platform.kluster.ai/apikeys",
		},
		{
			id = "chutes",
			label = "Chutes",
			tier = "paid",
			order = 33,
			description = "Serverless open-model inference on Bittensor, with a free starting allowance.",
			cost = "Pay as you go \194\183 free quota",
			tags = { "bittensor", "open-models", "serverless", "free" },
			baseUrl = "https://llm.chutes.ai/v1",
			authStyle = "bearer",
			keyHint = "cpk_...",
			docs = "https://chutes.ai/app/api",
		},
		{
			id = "featherless",
			label = "Featherless",
			tier = "paid",
			order = 34,
			description = "A flat-rate subscription for a large open-model catalogue.",
			cost = "Subscription \194\183 flat rate",
			tags = { "subscription", "open-models", "roleplay" },
			baseUrl = "https://api.featherless.ai/v1",
			authStyle = "bearer",
			docs = "https://featherless.ai/account/api-keys",
		},
		{
			id = "nano-gpt",
			label = "NanoGPT",
			tier = "paid",
			order = 35,
			description = "Pay-per-prompt access to many chat and image models with one balance.",
			cost = "Prepaid balance \194\183 pay per prompt",
			tags = { "gateway", "images", "cheap" },
			baseUrl = "https://nano-gpt.com/api/v1",
			authStyle = "bearer",
			docs = "https://nano-gpt.com/api",
		},
		{
			id = "requesty",
			label = "Requesty",
			tier = "paid",
			order = 36,
			description = "A routing layer over many providers with one key and per-request observability.",
			cost = "Pay as you go \194\183 top up",
			tags = { "gateway", "router", "observability" },
			baseUrl = "https://router.requesty.ai/v1",
			authStyle = "bearer",
			docs = "https://app.requesty.ai/api-keys",
		},
		{
			id = "scaleway",
			label = "Scaleway",
			tier = "paid",
			order = 37,
			description = "EU-hosted open models with pay-as-you-go pricing.",
			cost = "Pay as you go \194\183 top up",
			tags = { "eu", "open-models", "serverless" },
			baseUrl = "https://api.scaleway.ai/v1",
			authStyle = "bearer",
			keyHint = "Scaleway secret key",
			docs = "https://console.scaleway.com/iam/api-keys",
		},
		{
			id = "runpod",
			label = "RunPod Serverless",
			tier = "paid",
			order = 38,
			description = "Your own serverless vLLM endpoints, addressed by endpoint id.",
			cost = "Pay per GPU second",
			tags = { "runpod", "vllm", "serverless", "self-hosted" },
			baseUrl = "https://api.runpod.ai/v2/YOUR-ENDPOINT-ID/openai/v1",
			authStyle = "bearer",
			keyHint = "rpa_...",
			docs = "https://www.runpod.io/console/user/settings",
			note = "Replace YOUR-ENDPOINT-ID with the id of a running serverless endpoint. The endpoint must expose the OpenAI routes; a vLLM worker does by default.",
		},
		{
			id = "azure-foundry",
			label = "Azure AI Foundry",
			tier = "paid",
			order = 40,
			description = "Azure's v1 surface, which speaks chat completions and /models like any other endpoint.",
			cost = "Azure billing \194\183 subscription",
			tags = { "azure", "microsoft", "enterprise", "foundry" },
			-- The v1 surface rather than the per-deployment preview path: it speaks
			-- /chat/completions and /models, so this client needs no adapter of its own.
			-- The resource name is part of the URL the user has to edit.
			baseUrl = "https://YOUR-RESOURCE.openai.azure.com/openai/v1",
			authStyle = "api-key",
			docs = "https://learn.microsoft.com/azure/ai-foundry/",
			note = "The v1 endpoint of an Azure AI Foundry resource. Replace YOUR-RESOURCE, then fetch models or type a deployment name.",
		},
		{
			id = "azure",
			label = "Azure OpenAI (deployment path)",
			tier = "paid",
			order = 41,
			description = "The classic Azure OpenAI deployment URL, including the api-version query.",
			cost = "Azure billing \194\183 subscription",
			tags = { "azure", "microsoft", "enterprise", "legacy" },
			baseUrl = "https://YOUR-RESOURCE.openai.azure.com/openai/deployments/YOUR-DEPLOYMENT",
			authStyle = "api-key",
			docs = "https://learn.microsoft.com/azure/ai-services/openai/",
			query = { ["api-version"] = "2024-10-21" },
			note = "The base URL must include the deployment path. Azure takes the model from the deployment, so the model field is not sent.",
		},



		{
			id = "perplexity",
			label = "Perplexity Orchestrator",
			tier = "paid",
			order = 42,
			description = "Open-weight models through Perplexity's OpenAI-compatible Orchestrator API. Uses a funded Perplexity API account.",
			cost = "Pay as you go / API credits",
			tags = { "perplexity", "orchestrator", "deepseek", "kimi", "glm", "tools", "open-models" },
			baseUrl = "https://api.perplexity.ai/orchestrator/v1",
			authStyle = "bearer",
			claudeUa = false,
			keyHint = "Perplexity API key",
			docs = "https://docs.perplexity.ai/docs/router/quickstart",
			note = "Use a Perplexity API key with API credits, then fetch the Orchestrator catalog. This endpoint accepts standard Chat Completions and model IDs from its own /models list. Perplexity's separate Agent, Search and legacy Sonar endpoints use other routes. Web-app subscriptions do not establish API credit availability.",
		},
		{
			id = "friendli",
			label = "FriendliAI Model APIs",
			tier = "paid",
			order = 43,
			description = "Hosted chat models through FriendliAI's Model APIs, with streaming and OpenAI-compatible tool calling.",
			cost = "Pay as you go / prepaid credits",
			tags = { "friendli", "serverless", "glm", "open-models", "tools" },
			baseUrl = "https://api.friendli.ai/serverless/v1",
			authStyle = "bearer",
			claudeUa = false,
			keyHint = "Personal API key from Friendli Suite",
			docs = "https://friendli.ai/docs/guides/openai-compatibility",
			note = "Create a Personal API key in Friendli Suite and check your team's prepaid balance. Fetch models to select an exact model ID. This preset uses the shared Model APIs endpoint; a Dedicated Endpoint has its own deployment and billing setup. Tool calling is supported for compatible chat models, including parallel calls where the selected model supports them.",
		},
		{
			id = "venice",
			label = "Venice",
			tier = "paid",
			order = 44,
			description = "Venice's OpenAI-compatible text API, with model-dependent vision, streaming and tool calling.",
			cost = "Funded DIEM, bundled credits or USD balance",
			tags = { "venice", "open-models", "vision", "tools", "privacy" },
			baseUrl = "https://api.venice.ai/api/v1",
			authStyle = "bearer",
			claudeUa = false,
			keyHint = "Venice Inference Only API key",
			docs = "https://docs.venice.ai/getting-started/quick-start",
			note = "Create an Inference Only API key in Venice settings and fund the account with supported credits. The public /models route lists text models by default; listing models does not confirm your key or spending limit. A 402 may mean the individual API key's limit was reached even when the account has a balance. Use a model that advertises tool calling for UAI agent tasks.",
		},
		{
			id = "nscale",
			label = "Nscale",
			tier = "paid",
			order = 45,
			description = "Nscale's serverless inference API for chat models, using standard Chat Completions and bearer authentication.",
			cost = "Prepaid credits / model token rates",
			tags = { "nscale", "serverless", "open-models", "tools" },
			baseUrl = "https://inference.api.nscale.com/v1",
			authStyle = "bearer",
			claudeUa = false,
			keyHint = "Nscale API key",
			docs = "https://docs.nscale.com/docs/getting-started/quickstart",
			note = "Create an Nscale account, add credits and create an API key. Fetch models or copy an exact serverless model ID from the dashboard. Promotional credits may be offered to eligible accounts but are not guaranteed. The chat API accepts OpenAI-style tool definitions; model capabilities and rate limits still apply.",
		},
		{
			id = "arcee",
			label = "Arcee AI",
			tier = "paid",
			order = 46,
			description = "Arcee Platform's OpenAI-compatible chat API for its hosted model catalog, with provider-specific token prices.",
			cost = "Pay as you go / funded API account",
			tags = { "arcee", "trinity", "glm", "deepseek", "kimi", "open-models" },
			baseUrl = "https://api.arcee.ai/api/v1",
			authStyle = "bearer",
			claudeUa = false,
			keyHint = "Arcee Platform API key",
			docs = "https://docs.arcee.ai/get-started/quick-start",
			note = "Create an API key in Arcee Platform and confirm your billing balance. Fetch the current catalog and use its exact model IDs. The published pricing page lists paid token rates; a similarly named free promotion at another provider does not establish free access here. Model capabilities may differ across hosted routes.",
		},
		{
			id = "aimlapi",
			label = "AI/ML API",
			tier = "paid",
			order = 47,
			description = "One OpenAI-compatible endpoint for a broad model catalog. The documented free tier is currently paused.",
			cost = "Paid API access / free tier paused",
			tags = { "aimlapi", "ai/ml", "gateway", "openai", "anthropic", "google", "tools" },
			baseUrl = "https://api.aimlapi.com/v1",
			authStyle = "bearer",
			claudeUa = false,
			keyHint = "AI/ML API key",
			docs = "https://docs.aimlapi.com/quickstart/simple-model",
			note = "Create an AI/ML API key and choose a paid billing option; its free-tier documentation says the free tier is paused. Fetch models from the public /v1/models catalog, then choose a text model with the capabilities your task needs. Some catalog entries use image, audio or other specialized APIs, so appearing in the full list does not mean a model accepts Chat Completions.",
		},

		-- Local ---------------------------------------------------------------
		{
			id = "ollama",
			label = "Ollama (local)",
			tier = "local",
			order = 1,
			description = "The easiest local server: pull a model and it serves an OpenAI-compatible /v1 API.",
			cost = "Local \194\183 no key",
			tags = { "local", "ollama", "llama", "qwen", "no-key" },
			baseUrl = "http://127.0.0.1:11434/v1",
			authStyle = "none",
			claudeUa = false,
			docs = "https://docs.ollama.com/api/openai-compatibility",
			note = "Uses Ollama's OpenAI-compatible /v1 API, not its native /api/chat route. Local models need no key. Tools depend on the selected model; local access needs executor HTTP.",
		},
		{
			id = "lmstudio",
			label = "LM Studio (local)",
			tier = "local",
			order = 2,
			description = "A desktop model runner with a local server and a model browser.",
			cost = "Local \194\183 no key",
			tags = { "local", "lmstudio", "desktop", "no-key" },
			baseUrl = "http://127.0.0.1:1234/v1",
			authStyle = "none",
			claudeUa = false,
			docs = "https://lmstudio.ai/docs/developer/openai-compat",
			note = "Start the LM Studio server, then fetch models. If server authentication is enabled, select Bearer and enter its token. Tools depend on the model and chat template.",
		},
		{
			id = "vllm",
			label = "vLLM",
			tier = "local",
			order = 3,
			description = "High-throughput serving for open models, with an OpenAI-compatible API.",
			cost = "Self-hosted \194\183 no key",
			tags = { "local", "vllm", "self-hosted", "gpu", "no-key" },
			baseUrl = "http://127.0.0.1:8000/v1",
			authStyle = "none",
			claudeUa = false,
			docs = "https://docs.vllm.ai/en/latest/serving/online_serving/",
			note = "No key by default; select Bearer if the server uses --api-key. Automatic tools need the server's tool-call parser, chat template and enable-auto-tool-choice settings.",
		},
		{
			id = "llamacpp",
			label = "llama.cpp server",
			tier = "local",
			order = 4,
			description = "llama-server's lightweight /v1 API, for one model on one machine.",
			cost = "Self-hosted \194\183 no key",
			tags = { "local", "llama.cpp", "gguf", "cpu", "no-key" },
			baseUrl = "http://127.0.0.1:8080/v1",
			authStyle = "none",
			claudeUa = false,
			docs = "https://github.com/ggml-org/llama.cpp/tree/master/tools/server",
			note = "Use llama-server's /v1 API. Select Bearer if --api-key is set. Tool calling needs a compatible model and chat template, often with --jinja.",
		},
		{
			id = "sglang",
			label = "SGLang",
			tier = "local",
			order = 5,
			description = "Fast structured-generation server for open models, with OpenAI routes.",
			cost = "Self-hosted \194\183 no key",
			tags = { "local", "sglang", "self-hosted", "gpu", "no-key" },
			baseUrl = "http://127.0.0.1:30000/v1",
			authStyle = "none",
			claudeUa = false,
			docs = "https://docs.sglang.io/docs/basic_usage/openai_api_completions.md",
			note = "Use the server's OpenAI-compatible API. Select Bearer when authentication is configured. Tool support depends on the model, template and server tool-call parser.",
		},
		{
			id = "localai",
			label = "LocalAI",
			tier = "local",
			order = 6,
			description = "A self-hosted, drop-in OpenAI replacement that also serves images and audio.",
			cost = "Self-hosted \194\183 no key",
			tags = { "local", "localai", "docker", "no-key" },
			baseUrl = "http://127.0.0.1:8080/v1",
			authStyle = "none",
			claudeUa = false,
			docs = "https://localai.io/basics/getting_started/",
			note = "LocalAI listens on 8080 by default, the same port llama.cpp uses; run one at a time or change one port. Add an API key in LocalAI and select Bearer when the server is reachable by others.",
		},
		{
			id = "koboldcpp",
			label = "KoboldCpp",
			tier = "local",
			order = 7,
			description = "A single-file GGUF runner with an OpenAI-compatible endpoint.",
			cost = "Local \194\183 no key",
			tags = { "local", "kobold", "gguf", "roleplay", "no-key" },
			baseUrl = "http://127.0.0.1:5001/v1",
			authStyle = "none",
			claudeUa = false,
			docs = "https://github.com/LostRuins/koboldcpp",
			note = "Enable the OpenAI-compatible API in the launcher. The default port is 5001; KoboldCpp's native API is a different shape and is not used here.",
		},
		{
			id = "textgen",
			label = "Text Generation WebUI",
			tier = "local",
			order = 8,
			description = "oobabooga's web UI with an OpenAI-compatible extension for local models.",
			cost = "Local \194\183 no key",
			tags = { "local", "oobabooga", "textgen", "no-key" },
			baseUrl = "http://127.0.0.1:5000/v1",
			authStyle = "none",
			claudeUa = false,
			docs = "https://github.com/oobabooga/text-generation-webui",
			note = "Start the UI with the openai extension enabled. Without it the server answers on its own routes and /v1/chat/completions returns 404.",
		},
		{
			id = "jan",
			label = "Jan",
			tier = "local",
			order = 9,
			description = "A desktop client whose local server exposes an OpenAI-compatible API.",
			cost = "Local \194\183 no key",
			tags = { "local", "jan", "desktop", "no-key" },
			baseUrl = "http://127.0.0.1:1337/v1",
			authStyle = "none",
			claudeUa = false,
			docs = "https://jan.ai/docs",
			note = "Start Jan's local API server from its settings. The default port is 1337.",
		},
		{
			id = "litellm",
			label = "LiteLLM proxy",
			tier = "local",
			order = 10,
			description = "A proxy that puts one OpenAI-compatible surface in front of many providers.",
			cost = "Self-hosted \194\183 optional key",
			tags = { "local", "litellm", "proxy", "gateway", "self-hosted" },
			baseUrl = "http://127.0.0.1:4000/v1",
			authStyle = "none",
			claudeUa = false,
			docs = "https://docs.litellm.ai/docs/proxy/quick_start",
			note = "LiteLLM listens on 4000 by default. If the proxy sets LITELLM_MASTER_KEY, select Bearer and enter that key.",
		},
		{
			id = "openwebui",
			label = "Open WebUI",
			tier = "local",
			order = 11,
			description = "A self-hosted chat front end whose API is OpenAI-compatible.",
			cost = "Self-hosted \194\183 token",
			tags = { "local", "openwebui", "docker", "self-hosted" },
			baseUrl = "http://127.0.0.1:3000/api",
			authStyle = "bearer",
			keyHint = "Open WebUI API key from Settings, Account",
			docs = "https://docs.openwebui.com/",
			note = "Uses Open WebUI's /api surface, so the base URL ends in /api rather than /v1. Create an API key in the account settings.",
		},

		-- Escape hatch --------------------------------------------------------
		{
			id = "custom",
			label = "Custom endpoint",
			tier = "custom",
			order = 1,
			description = "Any URL that speaks Chat Completions, Anthropic Messages or Google's Gemini API.",
			cost = "Whatever the endpoint costs",
			tags = { "custom", "self-hosted", "any" },
			baseUrl = "",
			authStyle = "bearer",
			note = "An endpoint implementing Chat Completions or Anthropic Messages. Choose its protocol and auth style; enter a model id if discovery is unavailable.",
		},
	}

	local TIER_ORDER = { free = 1, paid = 2, ["local"] = 3, custom = 4 }

	-- A lowercase blob per preset, built once. Searching runs on every keystroke of
	-- the gallery's field, and rebuilding seven strings per preset per character is
	-- work the user can feel on a phone.
	local SEARCH = {}
	for _, preset in ipairs(M.presets) do
		local parts = {
			preset.label, preset.id, preset.tier, preset.description, preset.cost,
			preset.keyHint, preset.docs, preset.api,
		}
		for _, tag in ipairs(preset.tags or {}) do parts[#parts + 1] = tag end
		SEARCH[preset] = table.concat(parts, " "):lower()
	end

	local function orderOf(preset)
		return preset.order or 999
	end

	function M.get(id)
		for _, preset in ipairs(M.presets) do
			if preset.id == id then return preset end
		end
		return nil
	end

	function M.ids()
		local out = {}
		for _, preset in ipairs(M.presets) do out[#out + 1] = preset.id end
		return out
	end

	function M.tierOf(preset)
		return (preset and preset.tier) or "paid"
	end

	function M.tierLabel(tier)
		for _, entry in ipairs(M.tiers) do
			if entry.id == tier then return entry.label end
		end
		return tostring(tier or "Paid")
	end

	-- The short badge the gallery and the detail header put on a provider.
	--
	-- A preset can name its own access label, because "free" and "paid" are not the
	-- only two states: OpenCode Zen, OpenRouter and OpenCode Go all have a free route
	-- and a paid one, and calling any of them "Paid" hides the reason to try them.
	function M.badge(preset)
		if preset and preset.badge then
			return preset.badge, preset.badgeTone or "good"
		end
		local tier = M.tierOf(preset)
		if tier == "free" then return "Free", "good" end
		if tier == "local" then return "Local", "info" end
		if tier == "custom" then return "Custom", "neutral" end
		return "Paid", "neutral"
	end

	-- One tier, in display order. The gallery never sorts on its own: the order in
	-- this file is the editorial order, and a caller that re-sorts by label would put
	-- AgentRouter somewhere in the middle of the free list.
	function M.byTier(tier)
		local out = {}
		for _, preset in ipairs(M.presets) do
			if M.tierOf(preset) == tier then out[#out + 1] = preset end
		end
		table.sort(out, function(a, b)
			if orderOf(a) ~= orderOf(b) then return orderOf(a) < orderOf(b) end
			return a.label < b.label
		end)
		return out
	end

	-- Everything except the custom escape hatch, for a search that spans tiers.
	function M.searchable()
		local out = {}
		for _, preset in ipairs(M.presets) do
			if M.tierOf(preset) ~= "custom" then out[#out + 1] = preset end
		end
		return out
	end

	-- Every whitespace-separated word has to appear somewhere, so "free claude" is a
	-- useful query and not a literal phrase. Rank rewards a name match over a mention
	-- in prose: typing "openai" should not put a provider that merely lists OpenAI
	-- compatibility above OpenAI itself.
	function M.search(query)
		local text = tostring(query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
		if text == "" then return nil end
		local tokens = {}
		for token in text:gmatch("%S+") do tokens[#tokens + 1] = token end
		local found = {}
		for index, preset in ipairs(M.presets) do
			local haystack = SEARCH[preset]
			local matched = true
			for _, token in ipairs(tokens) do
				if not haystack:find(token, 1, true) then matched = false; break end
			end
			if matched then
				local name = tostring(preset.label):lower()
				local rank = 3
				if name == text then rank = 0
				elseif name:sub(1, #text) == text then rank = 1
				elseif name:find(text, 1, true) then rank = 2 end
				found[#found + 1] = { preset = preset, rank = rank, index = index }
			end
		end
		table.sort(found, function(a, b)
			if a.rank ~= b.rank then return a.rank < b.rank end
			local at, bt = TIER_ORDER[M.tierOf(a.preset)] or 9, TIER_ORDER[M.tierOf(b.preset)] or 9
			if at ~= bt then return at < bt end
			if orderOf(a.preset) ~= orderOf(b.preset) then return orderOf(a.preset) < orderOf(b.preset) end
			return a.index < b.index
		end)
		local out = {}
		for index, entry in ipairs(found) do out[index] = entry.preset end
		return out
	end

	-- The empty panel's quick picks, in their own order.
	function M.featured()
		local out = {}
		for _, preset in ipairs(M.presets) do
			if preset.featured then out[#out + 1] = preset end
		end
		table.sort(out, function(a, b)
			local ao, bo = a.featuredOrder or math.huge, b.featuredOrder or math.huge
			if ao ~= bo then return ao < bo end
			return a.id < b.id
		end)
		return out
	end

	return M
end
