# Provider compatibility and WebSockets

Applies to **4.0.0**, November 14, 2026.

UAI implements **Chat Completions**, **Anthropic Messages** and **Google Gemini**,
plus a dedicated **Responses** path for five verified direct OpenAI IDs and
supported OpenCode and AgentRouter models. Custom
providers can select their matching protocol. This is protocol compatibility, not a guarantee that
every model, server version, account or proprietary API works.

The compatibility checks use synthetic HTTP responses and socket events. They
need no running models, API keys or paid inference. Live server availability,
model quality, tool-call accuracy, executor networking and TLS are outside that
coverage.

## Provider setup and model discovery

Initial use requires password setup or the explicit **Continue without encryption**
choice before inference or discovery, including public no-key and included free
routes. With a vault, every execution requires unlock, including `ui = false`
embedding. A saved unprotected-storage choice skips future password prompts and
stores keys with reversible byte encoding. The gate preserves existing credentials
for verified migration; see [API key security](API_KEY_SECURITY.md).

The [individual setup guides](providers/README.md) cover separate Project UAI Free
and HCNSEC access, local/custom endpoints, key management and model discovery,
along with Vercel AI Gateway,
Perplexity Orchestrator, FriendliAI Model APIs, Venice, Nscale, Arcee AI and
AI/ML API. Each guide names the exact preset, account/key requirements, catalog
route and documented limits. Vercel's free-tier credits apply only to eligible
models; the public catalog also contains paid models. AI/ML API's documented
free tier is currently paused.

Catalog discovery is separate from inference authentication and funding. Several
providers expose public catalogs, so a successful fetch does not validate a key
or establish access to every returned model. The provider editor and model menus
support multiword search; refresh and manual entry stay available after an empty
search. Query credentials are omitted from connection summaries and loading text.

Generic model lists retain valid IDs without guessing capabilities from their
names. Manual entry, selection and discovery accept one UTF-8 ID of at most
160 bytes without control characters. Catalogs are bounded to 10,000 rows and
report invalid or truncated entries. A successful empty refresh clears stale
discovery without replacing manually saved choices. On four exact documented routes UAI reads an
explicit API kind: AI/ML API `type: openai/chat-completions`, Vercel
`type: language`, FriendliAI `mode: chat`, and Venice `type: text`. Explicit other
kinds are omitted and the discovery note reports how many were hidden. Untyped
entries and manually entered IDs remain available. These rules do not interpret
vendor fields on custom hosts, alternate ports or different API paths. Chat
compatibility still does not establish tools, vision or reasoning support.

Cloudflare Workers AI keeps Chat Completions under
`https://api.cloudflare.com/client/v4/accounts/<account-id>/ai/v1`, but that prefix
has no OpenAI `/models` endpoint. UAI fetches the account's
[`/ai/models/search` catalog](https://developers.cloudflare.com/api/resources/ai/subresources/models/methods/list/)
and uses each record's model `name`, omitting explicit tasks other than
Text Generation. Discovery owns page/per-page parameters, retains the token and
other configured queries, and reads at most ten pages or 10,000 rows. Custom
origins and paths keep normal `/models` discovery. The inference URL and manually
saved choices stay intact.

Chat and Responses requests keep at most 128 tool declarations by default.
When more tools are available, `uai_tool_catalog` exposes the remaining names,
their exact schema pages and a call action. The native dispatcher retains the
original tool permissions, scope and execution receipts. This replaces the
earlier cutoff that made later tools inaccessible. OpenCode compatibility
declarations are reserved only for OpenCode routes.

## Response speed and reasoning display

New configurations use Low effort on supported reasoning models. Older saved
choices remain effective; select **Settings → Agent → Effort → Low** to change
them. Higher effort can help difficult tasks but may delay the first response.
Provider default omits the field; it does not disable thinking. Raw provider
parameters can override the effort setting, and unsupported models may ignore it.
The model modal exposes the same global setting for documented models and for
any model with **Options → Reasoning support** enabled. Known scales remain
clamped; enabling an unknown model does not establish its accepted effort levels.

There is no 5,999-token thinking cap. Retained transcript fields are bounded to
24,000 bytes, which the old display divided by four to estimate tokens. Clipped
reasoning now says **Excerpt**. Other estimates say **tokens shown**: provider
summaries and visible text do not measure internal reasoning or billed usage.
The reply allowance, known context window and provider limits still apply.
Live answer and reasoning previews have separate limit flags, so a long answer
cannot label an otherwise complete reasoning trace as an excerpt.

Standing prompt rules precede changing environment metadata so compatible
providers can reuse more of their prompt cache. Actual cache use and latency
depend on the endpoint. Buffered executor HTTP delivers the response at completion;
UI changes cannot expose tokens before delivery. Native requests still have a
300-second maximum, regardless of a higher configured wait. Connected Cowork
inference has no overall client or bridge time limit; its individual status polls
stay short and Stop remains available. Direct/companion timeout settings do not
shorten Cowork requests, and the old bridge timeout setting is retired.

The bridge reads provider SSE incrementally and pushes received deltas to the
browser. Updated native clients also receive text/reasoning preview pages from
the bridge's existing status endpoint, at roughly one-second intervals while the
request runs. A cursor prevents repeated text after a lost poll. Missing retained
frames or a preview limit leaves a labelled excerpt until the full final arrives.
Tool arguments, Gemini signatures and usage are parsed from the authoritative
completed response. Old bridges and the companion retain their completed-body
protocol. Buffered responses never acquire artificial typing or preview replay.
Relay waiters have their own bounded admission count; only actual native HTTP
calls consume native connection slots. Local bridge calls can wait for an
available slot within their existing short call budget.

Stream failures preserve the provider's error code and message when supplied,
including plain-text `event: error` responses. Details are redacted and bounded.
An error after partial text still fails the request; it cannot cause a duplicate
socket/HTTP dispatch or execute a partially delivered tool call.

## Model prices and limits

The reviewed November 14, 2026 catalog contains 1,855 model entries across 15 providers,
including provider-specific text-token prices and context/reply limits.
Its source cutoff is **2026-11-14T16:04:42.744Z**. The committed snapshot retains
27 provenance records: five catalog feeds and 22 reviewed primary references.
[Models.dev](https://models.dev/api.json) supplies the main catalog, including
OpenCode's current free-model limits; [LiteLLM](https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json)
fills exact provider gaps. [OpenRouter](https://openrouter.ai/api/v1/models) and
[Kilo](https://api.kilo.ai/api/gateway/models) supply their own route prices.
[Cline's promotion feed](https://api.cline.bot/api/v1/ai/cline/recommended-models)
establishes zero token rates for three exact free IDs; it does not publish their
context or reply limits. Metadata enriches discovered or manually entered models;
it does not offer models the endpoint has not listed.

OpenRouter retains 471 entries, including 460 with published text-token estimates.
Kilo's 473 catalog entries apply only to its supported HTTPS gateway routes.
Zero price placeholders without an explicit free flag remain unknown. Cline
prices apply only to its reserved desktop bridge route, and the bridge still
checks current free availability before every request. Promotions and account
allowances can change after this dated snapshot.

The current Cline promotions are `cline-free/nemotron-3.5-super-vl`,
`cline-free/solar-mini4` and `nvidia/nemotron-3.5-lightning-free`.
The retired `reflection/beam-free` and `poolside/laguna-s-2.1-free` promotions
no longer establish free access.

Prices are estimates in USD per million text tokens. Documented cache rates and
long-context tiers apply to usage estimates. Special service tiers, request fees,
image/audio charges, taxes and account discounts are outside these estimates.
Unknown endpoint prices remain unknown, and a free route never sets the price of
its paid counterpart. Included Project UAI Free access is zero cost; a personal
HCNSEC key does not establish a known price.

Reviewed primary corrections live in `tools/data/model_official.json` and win
only for their exact provider/model IDs. They do not infer snapshot names or
reuse direct-provider prices on resellers.

| Direct model | Input / output USD per million | Documented limits and rate conditions |
| --- | --- | --- |
| `gpt-6.1-terra` | 1 / 5 | 1,050,000-token window, 922,000 input, 128,000 output; above 272,000 input tokens, 2 / 7.5 applies to the full request. |
| `claude-fable-5-2`, `claude-mythos-5-2` | 8 / 40 | 1,000,000-token window, 128,000 output; cache reads 0.2 and five-minute writes 10. Mythos requires eligible verified organizations. |
| `gemini-4-carbon`, `gemini-4-argon` | 2 / 10 introductory | Rates expire December 1, 2026 UTC; native nonstreaming requests have a separate 32,768 output limit. |
| `gemini-4-hydrogen` | 1.5 / 7.5 paid tier | Published account free allowances do not establish that every keyed request is free. |
| `deepseek-flash`, `deepseek-v4-flash`, `deepseek-v4-flash-vision-exp`, `deepseek-v4-pro` | Unknown fixed estimate | 1,048,576-token window, 393,216 output; rates depend on UTC peak hours and Chinese public holidays. |

Terra's documented cache-read/write rates are 0.05 / 1.25 at base and 0.1 / 2.5
above its input threshold, with 30-minute cache writes. Claude's one-hour cache
writes and other special billing categories are outside the five-minute estimate.
The exact `gpt-5.6-sol` and officially documented `gpt-5.6` alias also have
promotional rates through November 30. At **2026-12-01T00:00:00.000Z**, those rates
and direct Carbon/Argon introductory rates become unknown pending another review;
their model limits and controls remain available. Reseller estimates retain
their own published scope.

OpenRouter's `min_prompt_tokens` boundary is inclusive. Its 272,000-token Terra
tier therefore starts at 272,000, while the direct vendor's documented
"above 272,000" tier starts at 272,001. Missing tier cache categories inherit
the published base category. Duplicate or incomplete thresholds and unsupported
conditions become unknown. OpenRouter's `minimax/minimax-m3.1-flash`,
`tencent/hy4-preview` and `tencent/hy3` use UTC schedules and have unknown fixed
estimates while their catalog limits remain available.

Maintainers first capture and manually review the catalog feeds, primary model
references and `tools/data/model_official.json`, including each receipt's HTTPS
URL, SHA-256 and retrieval timestamp. The primary review day must match those
captured UTC timestamps. Reuse reviewed captures without refetching them:

```powershell
node tools/sync_pricing.js --refresh --sources-dir refer/model-refresh-4.0.0
```

That command verifies feed and primary-document bytes against their receipts and
authored primary provenance, then writes only `tools/data/model_metadata.json`.
For a new review, capture the new evidence and update the primary input first;
plain `--refresh` fetches current catalog feeds and requires a matching primary
review day. Review the resulting snapshot before generating Lua with
`node tools/sync_pricing.js`.
The refresh may include a sanitized CLI catalog using `--opencode-catalog <file>`
and `--opencode-version <version>`. Inspect `src/provider/model_data.lua` before
verification; `node tools/sync_pricing.js --check` checks freshness offline.
Rebuild the client after any catalog change.

Primary model and request references reviewed November 14:

- [GPT-6.1 Terra model](https://developers.openai.com/api/docs/models/gpt-6.1-terra.md),
  [release announcement](https://openai.com/index/introducing-gpt-6-1-terra/),
  [OpenAI pricing](https://developers.openai.com/api/docs/pricing.md)
- [Claude Fable 5.2](https://platform.claude.com/docs/en/models/fable-5-2/overview.md),
  [Claude Mythos 5.2](https://platform.claude.com/docs/en/models/mythos-5-2/overview.md)
- [Google pricing](https://ai.google.dev/gemini-api/docs/pricing),
  [DeepSeek pricing and scheduled rates](https://api-docs.deepseek.com/quick_start/pricing)

## Direct OpenAI Responses

On the exact HTTPS `api.openai.com/v1` route, UAI proactively uses `/responses`
for `gpt-6-astra`, `gpt-6.1-sol`, `gpt-6.1-terra`, `gpt-6-sol` and `gpt-6-luna`.
The saved API remains Chat Completions or its legacy default; standard port 443
and full official `/chat/completions` or `/responses` URLs are supported.
Endpoint replacement retains configured query parameters. Namespaced aliases,
invented snapshots, alternate ports, custom paths/hosts and other API kinds do
not inherit this routing. Existing GPT-5.6 and custom Chat routes keep their protocol.
Direct raw `model` overrides must match the selected model; a mismatch fails
before dispatch so returned opaque state cannot be saved under another model's scope.

OpenAI documents tool calling through Responses for Astra, Sol 6.1 and Terra.
Sol 6 and Luna also need Responses for reasoning with tools. Direct requests
default to `store=false`, follow the resolved streaming preference and request
`reasoning.encrypted_content` in `include`, even when Show reasoning is off.
Compatible raw include entries are retained. Human-readable reasoning summaries
use `auto` only when enabled. The legacy UAI gateway socket is unavailable for
these requests; they use HTTP or the selected bridge/companion transport.

Effort uses `reasoning.effort`. Astra and Sol 6.1 accept low, medium, high, xhigh
and max; Terra, Sol 6 and Luna also accept none. With reasoning enabled, unsupported
sampling and logprob fields are omitted, including `message.output_text.logprobs`
from include. An explicit manual sampling override remains effective.
Tool definitions and named choices use the flat Responses shape. Function
schemas default to `strict=false` so optional arguments remain optional;
explicit strict settings survive. Documented and temporary output limits apply
after raw provider/request overrides and after declaration-limit repair.

The complete provider output array is copied and replayed in its original order,
including encrypted reasoning and matching function calls, through normal context
saves and reloads. Replay requires the same endpoint, query, protocol and model.
Its persisted scope is a domain-separated SHA-256 comparison token; URL query
credentials are never copied into that scope. A changed scope translates the
ordinary conversation without replaying foreign opaque items.

Each retained output array is limited to 256 items, 2 MiB encoded data, 16,384
structure nodes, depth 16 and 256 fields per table. Malformed, cyclic or oversized
saved state fails before dispatch. Invalid final output fails before returned
tools can reach the agent. Incomplete streams, provider errors and uncertain
transport outcomes retain the existing terminal no-replay behavior.

- [Current GPT request compatibility](https://developers.openai.com/api/docs/guides/latest-model.md)
- [Stateless encrypted reasoning and tool continuations](https://developers.openai.com/api/docs/guides/reasoning.md)

## Current Anthropic thinking controls

Direct `claude-fable-5-2` and `claude-mythos-5-2` Messages requests use adaptive
thinking, omit unsupported sampling and offer five effort levels with high as
the provider default. Provider default omits the effort override and keeps
thinking enabled. On the exact official Anthropic route, disabled/budget thinking,
`budget_tokens` and forced any/named tool choices are rejected during preparation
before HTTP dispatch. Auto and None remain supported. Raw `params` and `extra`
retain precedence and receive the same validation. Reseller IDs and custom routes
retain their own request behavior.

## Image input

PNG, JPEG and WebP attachments from the web bridge are delivered as actual image
content: Chat Completions receives `image_url` data URLs, Messages receives
base64 `image` blocks, Gemini receives native `inlineData`, and the supported
Responses path receives `input_image` blocks. Select a model and endpoint that support vision. Text-only
models remain usable for conversations without image attachments.

Reload the updated game client and restart the updated bridge to enable this
capability. Image-bearing requests use the bridge relay in both Game and Web
runtime, keeping image bytes outside Lua and the transcript. The bridge keeps
images in memory for 15 idle minutes; deletion, expiry or restart requires
reattaching a current image. An unavailable image in an earlier user turn is
replaced with an explicit text notice so subsequent text turns can proceed.

## Local servers

Leave **Gateway socket URL** empty for these ordinary HTTP connections.

| Server / preset | Default base URL | Authentication | Tool requirements |
| --- | --- | --- | --- |
| Ollama | `http://127.0.0.1:11434/v1` | None for local models | A model supporting tools. UAI omits default `tool_choice` and `parallel_tool_calls`; explicit overrides remain possible. |
| LM Studio | `http://127.0.0.1:1234/v1` | None by default; Bearer if server auth is enabled | A suitable model and chat template; support varies by model/runtime. |
| vLLM | `http://127.0.0.1:8000/v1` | None by default; Bearer if `--api-key` is configured | A chat template, an appropriate tool-call parser and automatic tool choice enabled on the server. |
| llama.cpp | `http://127.0.0.1:8080/v1` | None by default; Bearer if `--api-key` is configured | A compatible model/template, often with `--jinja`; parser support depends on the model. |
| SGLang | `http://127.0.0.1:30000/v1` | None by default; Bearer when server auth is configured | The model's chat template and tool-call parser. |
| Other compatible servers/proxies | Enter their documented base URL under Custom endpoint | Match the server configuration | Must implement a supported protocol, including tool-result replay for agent use. |

The local preset label does not decide reachability. UAI checks the actual URL:
loopback, private IPv4/IPv6, `.localhost`, `.local` and single-label hosts require
an executor HTTP function. A public URL entered in a local preset is treated as
public; a custom localhost URL is treated as local. `localhost` refers to the
machine making the request. A remote container, VM or LAN server needs its
reachable address and port. A server's bind address such as `0.0.0.0` is not the
normal client address; use loopback or its actual interface address.

Fetch models after the server is running, or enter its exact model/deployment id.
UAI does not invent model names. Generic discovery keeps embedding IDs; Google's
native catalog explicitly identifies generation methods, so embedding-only entries
are excluded there.
An ordinary text reply does not prove tool support. Agent use also needs a model
and context window large enough for the selected tools and conversation.

Ollama's native `/api/chat` and `/api/generate`, OpenAI
Realtime, unsupported Responses endpoints, legacy Completions, Bedrock's native API and other proprietary
formats are not adapters in this client. Use a compatible surface or an external
adapter. Known mismatched native paths produce an actionable diagnostic.

## Native Google Gemini

New **Google Gemini** connections use `https://generativelanguage.googleapis.com/v1beta`
with the **Google Gemini** protocol and `x-goog-api-key` authentication. Existing
connections to `/v1beta/openai` keep their saved Chat Completions protocol and Bearer
authentication. Native discovery follows up to ten pages (10,000 entries), removes
the `models/` resource prefix, and keeps models that declare generation support.

The adapter sends native system instructions, JSON Schema function declarations,
parallel function calls and ordered function responses. It accepts complete JSON
responses and SSE, separates reasoning summaries from answer text, and counts
thinking and cached input tokens. It rejects incomplete or failed streams before
any returned tool can run. Native HTTP still receives a buffered body; bridge
streaming can show incremental progress. These paths do not implement Google's
separate Live, Interactions, audio/video generation or image-generation interfaces.

Image input uses the existing session-owned bridge references. The bridge replaces
them with `inlineData` immediately before the provider request; session history
does not contain base64 picture data. Gemini's signed model parts persist with
their exact signed boundaries and endpoint/model scope so a restored tool exchange
can continue. Signatures from another model or endpoint are never reused.

Documented Gemini 3 and Gemini 4 Carbon/Argon/Hydrogen effort controls map to native `thinkingLevel`; Gemini 2.5 uses
`thinkingBudget`. **Provider default** omits the effort override. Gemini 3 native
requests leave temperature at Google's recommended default unless explicitly set;
the documented Gemini 3.6/3.7/3.8 Flash and all three current Gemini 4 models omit unsupported sampling parameters.
The model's Temperature handling control can explicitly select Auto, Send or Omit.
Provider `params` and request `extra` accept native fields such as
`generationConfig.thinkingConfig`; the final output ceiling still applies.

The November 14 primary references distinguish the Gemini 4 native request limits:

| Model | Shared token window | Streaming output | Native nonstreaming output | Effort / provider default |
| --- | --- | --- | --- | --- |
| `gemini-4-carbon` | 1,048,576 | 65,536 | 32,768 | low, medium, high / medium |
| `gemini-4-argon` | 1,048,576 | 65,536 | 32,768 | low, medium, high / medium |
| `gemini-4-hydrogen` | 1,048,576 | 65,536 | 65,536 | low, medium, high, xhigh / high |

The Carbon/Argon nonstreaming clamp applies only to the exact native Google route.
The adapter resolves global, record, request and forced transport streaming
preferences before applying that limit. Both raw override layers remain bounded
by the relevant model limit and any lower temporary output ceiling.

Native protocol references were reviewed October 17, with the current Gemini 4
model, thinking and pricing references reviewed November 14:

- [GenerateContent REST API](https://ai.google.dev/api/generate-content)
- [Native API discovery schema](https://generativelanguage.googleapis.com/$discovery/rest?version=v1beta)
- [Gemini 3 thinking and temperature guidance](https://ai.google.dev/gemini-api/docs/gemini-3)
- [Gemini 3.8 thinking levels and parameter changes](https://ai.google.dev/gemini-api/docs/whats-new-gemini-3.8)
- [Thinking and signed response parts](https://ai.google.dev/gemini-api/docs/thinking)
- [Gemini 4 Carbon model and native limits](https://aistudio.google.com/docs/models/gemini-4-carbon)
- [Gemini 4 Argon model and native limits](https://aistudio.google.com/docs/models/gemini-4-argon)
- [Gemini 4 Hydrogen model and native limits](https://aistudio.google.com/docs/models/gemini-4-hydrogen)
- [Current Gemini thinking levels](https://aistudio.google.com/docs/thinking)

## Preset routing matrix

Every catalog preset has a row in the offline matrix in
`test/provider_compatibility.lua`: its base URL, protocol, auth header and both
request shapes are exercised without a live model. The table below lists only the
routes whose shape is not plain Chat Completions at the catalog base URL. Every
other preset uses Chat Completions, sends the configured model id in the request
body, and discovers models under the same base. `/models` is not required: when a
service does not expose it or the key cannot list models, manual ids remain usable.

| Preset | Base path / host | Protocol | Default auth |
| --- | --- | --- | --- |
| Project UAI Free | `api.hcnsec.cn/v1` | Chat Completions | Distributed community Bearer credential |
| HCNSEC | `api.hcnsec.cn/v1` | Chat Completions | Personal Bearer key |
| OpenAI | `api.openai.com/v1` | Responses for the five documented direct GPT-6 IDs; other models retain Chat | Bearer |
| AgentRouter | `agentrouter.org/v1` | GPT: Responses; others: selected protocol | x-api-key |
| Anthropic Messages | `api.anthropic.com/v1` | Messages | x-api-key |
| Google Gemini | `generativelanguage.googleapis.com/v1beta` | Native generateContent / streamGenerateContent | x-goog-api-key |
| Azure AI Foundry | `<resource>.openai.azure.com/openai/v1` | Chat Completions | api-key |
| Azure OpenAI (deployment path) | `<resource>.openai.azure.com/openai/deployments/<deployment>` | Chat Completions plus `api-version` | api-key |
| OpenCode Zen | `opencode.ai/zen/v1` | Chat Completions; dedicated Responses lane when required | Bearer |
| OpenCode Go | `opencode.ai/inference/go/v1` | Model-specific Chat, Responses, Messages or Gemini | Bearer |

The remaining presets cover OpenRouter, DeepSeek, Groq, Cerebras, Mistral,
Together, Fireworks, DeepInfra, Hyperbolic, Nebius, Novita, SambaNova, Moonshot,
DashScope, SiliconFlow, Volcano Ark, Hunyuan, Qianfan, StepFun, Yi, Baichuan,
Spark, Upstage, Reka, AI21, Cohere's compatibility layer, the Hugging Face
router, Ollama Cloud, Baseten, Kluster, Chutes, Featherless, NanoGPT, Requesty,
Scaleway, RunPod, Kilo, LLM7, OVHcloud, ModelScope, Z.ai, NVIDIA NIM, GitHub
Models, Cloudflare Workers AI and Aion Labs. GitHub Models is absent because the
service was retired on 30 July 2026; the local servers are listed separately above. Each is Chat
Completions at the base URL the gallery shows. A vendor whose documented API this
client's base-URL normaliser would misroute is not offered as a preset; it remains
reachable through Custom endpoint with its exact path.

The gallery groups presets into free, paid and local tiers and describes each one
before a key exists. The tier is access, not capability: a free route and a paid
one use the same adapters, and a successful model list never proves that an
account, subscription or tool-calling model is available. A hybrid service — one
with both a free and a paid half — is recommended and labelled with the free half
rather than called paid: OpenCode Zen names its free desktop-CLI models,
OpenRouter names its free model ids, and OpenCode Go separates its subscription
from the free CLI catalog. Project UAI Free is labelled Included because its key
is distributed with the client.

## Connection and response behavior

### Project UAI Free

New users and configurations with no provider start with an empty provider list.
Choose **Providers > Add a provider > Project UAI Free**, then save, to opt in to
community access and its verified `auto` router. No personal key or model entry
is required. Browsing the library does not install a provider. Empty imports,
resets and later starts do not recreate a removed provider.

**HCNSEC** is a separate personal-key preset, with no community credential or
default model. Existing personal keys and custom names stay intact. Legacy
community records on the official endpoint move to the separate
`projectuai-free` preset while retaining selection, pauses and custom names.
Changing a Free draft to a personal/custom preset removes its public keys;
adding a personal key switches that draft to HCNSEC and retains only personal
keys. See [provider migration](providers/migration.md).

Included community access is scheduled **daily from 20:00 to 12:00 the following
midday, fixed UTC+8 (Beijing/Singapore)**. The client's local timezone and daylight
saving do not change these hours. Outside the schedule, UAI explains the next
opening and skips new included-access inference, model discovery and background
probes. Choose another provider or return at 20:00 UTC+8. You can still save the
free provider; personal HCNSEC keys do not use this community schedule. An already
accepted inference may finish after 12:00. These checks provide client guidance;
the service controls actual availability and must enforce any server access limits.

**Settings → Agent → Automatic free routing** is enabled by default and optional.
Turn it off to stop background measurements and retain the selected provider model
for future requests. An accepted request finishes on its existing route. When UAI
selects a measured model, a conversation notice names it and gives this setting path.
The provider may still perform its own routing when its selected model is `auto`.

During scheduled hours, with automatic free routing enabled, `auto` selected and
the default Chat settings, UAI measures models in the background when you open the
model picker or send an agent request. It discovers
the live catalog, checks a small tool call and its result replay, and prefers the
fastest verified candidate whose two responses each finished within ten seconds.
The picker shows the latest synthetic probe time. The first request can use the
provider's `auto` while measurements run; opening the picker warms selection
without sending your conversation. Two workers check at most 32 advertised IDs;
measurements last ten minutes and expire when connection/auth settings change.

The selected model must have a known context window large enough for the prepared
request and reply. Images, unknown context limits and explicit provider body,
query or socket settings keep their existing route. Selecting a model by name or
using a personal key keeps that choice fixed. A slow or failed real response
removes that candidate for later selections; it never launches a duplicate of
the current prompt. The saved selector remains `auto`, and scoped API limit
lessons still persist. Free choices have green rounded borders in model menus.

**Ten seconds is a selection target, not a guarantee for a real request.** Longer
prompts, tool catalogs, reasoning and shared load can take longer. Native probes
use the active direct/relay lane and contain only a synthetic connectivity tool;
they never execute it or include conversation data. See
[the measured HCNSEC results](FREE_ROUTING_VALIDATION.md).
Shared capacity changes, so requests may be fast, slow, rate limited or unavailable.
Help, availability updates and community news: https://discord.gg/9xYyyYuKap.

### OpenCode desktop and mobile

The desktop workaround uses the historically verified desktop User-Agent/client
identity, timestamp-based session headers and wildcard Accept header. Required
compatibility tool declarations remain present on direct and bridge routes, and
explicit custom headers stay effective. Historical `FreeTierError` and explicit
protocol refusals retain the Chat/Responses fallback where applicable.

OpenCode can refuse direct API-key requests with HTTP 429 `FreeUsageLimitError`
even while the installed CLI works for the same account. Current Zen Chat and
Responses requests include truthful Roblox `<env>` context with `Working directory:`
in their system/instructions metadata. On November 2, 2026, that context restored
DeepSeek Flash API-key text, a synthetic UAI tool call, and result replay through
standalone Bun with the existing desktop headers and seven declarations. Ordinary
Node HTTPS also returned 200 after offering the same cipher-suite list with
production bridge headers. The current desktop bridge supplies this scoped TLS
profile before the first direct Zen Chat/Responses request; it requires no CLI
or Bun installation and preserves certificate validation. Use the current client
and bridge for the verified API-key route. Executor and Android transport behavior
remain unverified. UAI reports a remaining
explicit refusal without repeating the same route, rotating keys, or trying
the Responses protocol. Ordinary temporary 429 responses retain their retries.
See [the current investigation](OPENCODE_API_KEY_INVESTIGATION.md).

The desktop bridge adds an optional installed OpenCode CLI server path for its
verified free-model catalog. Install OpenCode separately; Project UAI does not
package its binary. See [desktop setup](../desktop/README.md) and
[live model verification](OPENCODE_3.2_VALIDATION.md). The bridge owns authenticated
loopback access, temporary sessions and tool handoff to Roblox. CLI model discovery
uses its authenticated bridge capability; without that capability normal direct
model discovery remains available. Missing CLI and models outside its public catalog
retain the existing direct HTTP route.

**Mobile OpenCode requires the UAI Relay app from Discord**: install and start the
app, then connect it in UAI. Project UAI Free remains an alternative for a
mobile-compatible provider. A mobile free-tier
refusal does not retry Responses or a proxy. Share errors and get updates in
[Discord](https://discord.gg/9xYyyYuKap).

The OpenCode proxy is retired. Saved or entered old proxy URLs migrate to the
official Zen URL. Historical successful direct requests are observations for their
host and date, not a guarantee that every executor or future upstream version works.

### OpenCode Go subscriptions

Choose **OpenCode Go** and use a key from the subscribed OpenCode workspace. Its
canonical base is `https://opencode.ai/inference/go/v1`; the legacy
`https://opencode.ai/zen/go/v1` alias retains Go routing. An old ambiguous proxy
record still migrates to Zen, so select Go explicitly. Go uses its own model list
and remains a keyed upstream request even when the desktop free CLI backend is ready.
The mobile free-model restriction does not apply to paid Go; native mobile Go
behavior has not been verified.

| Go model family | API route |
| --- | --- |
| DeepSeek | `/chat/completions` |
| GPT, Grok, Muse | `/responses` |
| Claude, Minimax, Qwen | `/messages` |
| Gemini | `/models/<model>:generateContent` or `:streamGenerateContent?alt=sse` |

The supported families route automatically without changing the saved API choice.
Requests retain the Go base, selected key, query parameters, identifiable
`ProjectUAI/<version>` User-Agent and stable `x-opencode-session`; custom headers
remain explicit overrides. The separate metadata catalog supplies known limits;
Go subscription cost is not inferred from Zen token prices.

A successful public `/models` fetch does not validate the key or subscription.
An **active Go subscription required** refusal means OpenCode rejected subscription
access for that request: check the key's workspace and its subscription, and contact
OpenCode support if already active. A **Global regions required** refusal identifies
the workspace Privacy setting required by that model; review that choice in OpenCode.
A retired-proxy **410** says nothing about Go subscription validity. Actual live
results and their limits are in [OpenCode validation](OPENCODE_3.2_VALIDATION.md).

### Automatic unauthorized-client recovery

When an official AgentRouter endpoint explicitly returns an
**unauthorized client** error, UAI switches its Base URL and retries through the
Project UAI proxy on its proper domain (no Workers.dev fallback):

| Provider | Recovery Base URL |
| --- | --- |
| AgentRouter | `https://puai-proxy.davidzk.tech/agentrouter/v1` |

The proxy receives the same provider key, request and model. The selected protocol,
custom headers and query parameters are retained, as are the required vendor
identity headers. A live provider's new Base URL is saved and remains editable in
Providers. A connection test or model fetch in an unsaved editor changes only that
draft until it is saved. The retry status identifies the switch.

This route shares the proxy operator's stated **90,000 requests per day** limit;
availability depends on the proxy and its upstream provider. The proxy does not
change account permissions, model access or provider billing. Invalid keys,
ordinary 401/403 responses, free-tier/account restrictions, HTML challenges and
transport failures do not trigger this recovery. Only explicit structured error
fields or a short plain-text client refusal qualify; successful content and stream
errors cannot redirect a request.

Automatic proxy switching is limited to AgentRouter's official `/v1` route,
including full inference URLs. Custom hosts,
custom paths and nonstandard ports remain unchanged. An operation switches at
most once, and proxy retries share the HTTP deadline and cancellation state.
In-flight edits, removed providers and stale model fetches cannot overwrite a new
connection. Known proxy routes use HTTP or the selected web relay; a configured
UAI socket gateway has its own upstream origin and cannot route this proxy switch.

### General connection rules

- A bare public hostname gains `https://` and, if no path exists, `/v1`. Bare local
  addresses gain `http://`. An explicit scheme and custom prefix are preserved.
  IPv6 addresses use brackets. Unsupported schemes and URL userinfo are rejected.
- Full `/chat/completions` or `/messages` URLs work, including query strings;
  switching protocol or discovering models replaces the endpoint suffix. URL
  fragments are omitted. Extra query fields override a same-named base query
  field without duplicating it, and other base query values are preserved.
- Auth styles are literal: Bearer, x-api-key, api-key, both, or none. Native
  Anthropic presets select x-api-key; an explicit Bearer choice is honored for
  Messages gateways. Key pools rotate ready credentials round-robin on each new
  discovery or inference request. Rate-limited keys are skipped during cooldown;
  proxy recovery keeps the selected credential. Transport retries of one request
  keep that request's key. Cached model lists consume no pool slot.
  Later header maps override earlier names case-insensitively.
- Discovered ids are cached for ten minutes for that connection/auth configuration.
  Unsaved drafts are separate. Changing settings, invalidating or starting a newer
  fetch prevents an older response from overwriting the list. HTTP error documents
  are not successful empty model lists. Manually entered models remain first.
- The provider editor clears fetched choices when its URL, protocol, auth, key or
  preset changes, including changing away and back during a pending fetch. Manual
  ids remain available. Choosing a preset applies its identity defaults and clears
  the previous preset's gateway URL; local presets link to server setup docs.
- JSON and buffered SSE use one bounded Chat Completions assembler. Text,
  reasoning, usage and indexed tool-argument fragments survive; a whole argument
  object is serialized to JSON. Mixed object/fragment arguments fail visibly.
  Corrupt or incomplete streams cannot become successful replies.
  Missing-completion diagnostics name the expected final marker. Recognizable
  events from another protocol identify the mismatch and direct the user to
  check Protocol and Base URL. Partial text and complete tool JSON cannot prove
  completion; `malformed_stream` remains terminal to avoid inference replay.
- Clear 400/422 parameter refusals can teach bounded request repairs. FastAPI
  validation errors expose field locations/messages without echoing their `input`.
  Repairs and learned output limits follow the endpoint, protocol and model;
  old unscoped lessons adopt the current configuration on first use. Context
  refusals naming at least 512 tokens are recognized, including 2K/4K local models.
  Learned context windows retain the existing global, lowercased model-id map.
- HTTP is buffered by the Roblox/executor API. Selecting SSE does not make that
  transport incremental. Native HTTP/socket requests have a maximum 300-second
  wait and 8 MiB response budget; the host/server may impose shorter limits.
  The removed 8,192-token executor ceiling does not return on HTTP fallback.

## Exactly how the WebSocket option works

It is an optional **UAI gateway protocol**, not the provider's normal HTTP API.
No matching inference WebSocket gateway ships in `bridge/` or `tools/`. The
optional browser bridge uses its own relay protocol and is a separate transport.

```mermaid
sequenceDiagram
    participant U as UAI Chat Completions adapter
    participant W as Configured UAI WebSocket gateway
    participant P as Gateway's configured provider
    U->>W: Connect to wsUrl (one socket per completion)
    U->>W: JSON {path, headers, body}
    W->>P: POST provider origin + path, using headers and body
    P-->>W: Chat Completions chunks
    W-->>U: JSON chunks or SSE data events
    W-->>U: [DONE], or finish_reason followed by close
    U->>U: Assemble final reply; disconnect callbacks and close
```

1. The adapter uses the socket only for Chat Completions when the effective body
   has `stream: true`, `wsUrl` is set, an executor connector exists, and the web
   relay is not selected. Discovery remains HTTP. Messages ignores `wsUrl`.
2. UAI calls `connect(wsUrl)` with **no custom upgrade headers**. A gateway requiring
   custom HTTP authentication headers during the WebSocket handshake is not
   supported by this connector. The gateway receives provider credentials in the
   first application message instead.
3. UAI sends one JSON envelope, for example:

   ```json
   {
     "path": "/proxy/v1/chat/completions?api-version=example",
     "headers": {
       "Authorization": "Bearer <provider-key>",
       "Content-Type": "application/json",
       "Accept": "text/event-stream"
     },
     "body": {
       "model": "server-model-id",
       "messages": [{"role": "user", "content": "Hello"}],
       "stream": true
     }
   }
   ```

   `path` is the complete provider path and query, with no origin. The gateway
   needs its own configured upstream origin; UAI does not choose that upstream
   for it. Headers use the same auth, custom fields and required identity as HTTP.
   A gateway therefore sees the provider key, prompt and tools.
4. Replies may be individual Chat Completions JSON objects or SSE events. SSE
   comments/metadata, CRLF, multiline data and events split/combined across socket
   messages are accepted. A complete single `data: {...}` message without a blank
   separator remains supported. Each accepted chunk updates the live preview and
   is retained for final assembly.
5. `[DONE]` completes the exchange. A close following a valid `finish_reason`
   also succeeds. Closing mid-event or before completion, invalid JSON, provider
   error events, callback failures and exceeded budgets fail the request. A stream
   with no data is not a success.
6. Connect/setup failures, a connector unavailable before dispatch, or a connection
   deadline before `Send` permit HTTP fallback. After entering `Send`, delivery may
   have happened even if the call raises: timeout, cancellation, malformed data
   and premature close are terminal. They cannot silently retry by HTTP or another
   provider. Late connections are closed without sending; late callbacks are
   disconnected and cannot update the transcript.

Limits are four connection/send workers and four reserved active connections,
1–300 seconds per attempt (120 seconds when called directly without a timeout),
8 MiB of received data, 1 MiB per SSE/JSON event, 200,000 socket messages/events,
64 tool calls and 256,000 argument bytes per tool call. A completion creates and
closes its own socket; chats do not share a permanent connection.

OpenAI's documented Responses WebSocket mode instead connects to `/v1/responses`,
authenticates during connection and sends `response.create` events. Its event
schema and connection state are different. Realtime is another API again. Neither
can receive the UAI envelope above without an adapter.

## Offline verification

Manually audit source, snapshot, documentation and fixture inputs before building.
Generate model data, rebuild the client and inspect generated outputs before
running the tests. Implementation and regression fixtures are written before verification.
The focused suites cover every catalog preset's routes/auth, JSON and SSE,
tool-call/result replay, local compatibility failures, discovery races in both the
model service and provider editor, scoped repairs, socket framing, cleanup and
dispatch/fallback boundaries.

```powershell
luajit test/provider_compatibility.lua
luajit test/provider_proxy.lua
luajit test/provider_transport.lua
luajit test/provider_editor.lua
node test/model_pricing.js
luajit test/model_pricing.lua
luajit test/direct_responses.lua
luajit test/anthropic_current_models.lua
luajit test/gemini_provider.lua
node tools/sync_pricing.js --check
node tools/test_native.js --verify-only
```

After reviewing build inputs, use `node tools/test_native.js --build-only` for
the native build phase. Inspect the generated bundle, model data and guide
references before running `--verify-only`. That verification phase checks generated
artifacts, runs the main/focused suites and performance contracts, then compiles
with official Luau.
Results and any remaining limitations are recorded in
[the 4.0.0 external testing report](TESTING_4.0.0.md).

Published protocol references consulted September 25, 2026:

- [Ollama OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility)
- [LM Studio compatibility](https://lmstudio.ai/docs/developer/openai-compat),
  [tools](https://lmstudio.ai/docs/developer/openai-compat/tools) and
  [authentication](https://lmstudio.ai/docs/developer/core/authentication)
- [vLLM online serving](https://docs.vllm.ai/en/latest/serving/online_serving/)
- [llama.cpp server documentation](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- [SGLang OpenAI-compatible APIs](https://docs.sglang.io/docs/basic_usage/openai_api_completions.md)
- [OpenAI Responses WebSocket mode](https://developers.openai.com/api/docs/guides/websocket-mode)
