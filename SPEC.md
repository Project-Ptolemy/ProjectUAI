# Project UAI — contract

Release: **Project UAI client, bridge/web UI and Windows desktop 3.8.0 —
October 31, 2026**. This release adds focused tool families, persistent script
goals, optional provider setup, separate Free/HCNSEC presets, native Obsidian
browsing/editing, conversation and editor conveniences, and staged startup.
The embedding SDK is **1.1.0** and standalone **UI LIB is 1.6.0**.
The Android companion remains **3.7.1 (version code 8)**; its existing protocol,
Kilo quota recovery and release assets are unchanged.

Bridge 3.8.0 and Windows desktop 3.8.0 use verified automatic GitHub updates.
Bridge worker replacement waits for idle work and retains its session token;
desktop app updates stage for restart with a retained fallback. Desktop detects
Node.js 18+ or downloads a verified LTS runtime per user instead of bundling Node.
The Windows distribution is one independent executable. Bridge, browser, client
and license files are embedded and verified into a private cache automatically;
users do not extract a ZIP or maintain an adjacent support folder.

Kilo free quota recovery is enabled by default in both local apps and starts
only on a complete anonymous `PROMOTION_MODEL_LIMIT_REACHED` refusal. Its scope
is exact HTTPS Kilo inference routes with free models and no credential headers
or URL credentials/query. One tunnel attempt and one circuit retry retain the
original payload and deadline; uncertain outcomes and partial streams are never
replayed. The apps advertise optional `capabilities.kilo` schema 1 with enabled,
available, state and a bounded display message. Disconnect clears client state.
See [Kilo tunnel](docs/KILO_TUNNEL.md) for controls and quota evidence.

Cline is a bridge-only local CLI route. Its provider uses the reserved
`https://uai-tunnel.invalid/cline/v1` marker, which must never reach executor
HTTP or the Android companion. The bridge accepts Chat Completions only,
requires no provider credential headers, and admits only current free models
available through the authenticated CLI. Optional `capabilities.cline` schema 1
advertises enabled, available, state and a bounded message. Missing authentication
is visible as `auth-required`; it cannot be reported as ready. CLI host tool
requests are denied; validated UAI calls return to Roblox's normal permissions.
See [Cline tunnel](docs/CLINE_TUNNEL.md).

A universal Roblox AI agent client. Universal means: no game, no gateway and no
host script is assumed. It runs standalone under an executor, embedded in a host
script, or in any context that can call `loadstring`.

Everything below is a contract. Modules are written against it, `test/check.lua`
enforces the mechanical parts, and `test/run.lua` exercises the rest headlessly
under LuaJIT.

## 1. Authoring rules

Luau is written in a dialect that LuaJIT can also parse, so the whole project can
be checked and executed offline. `test/check.lua` fails the build on a violation.

| Rule | Why |
| --- | --- |
| No type annotations, no `->`, no `::` | LuaJIT cannot parse them |
| No backtick string interpolation | same; use `string.format` |
| No `continue`, no `goto` | keeps control flow trivially transpilable |
| No `//`, no digit separators, no binary literals | Lua 5.1 lexer |
| Compound assignment (`+=`, `..=`) only as a standalone one-line statement | makes the rewrite to `a = a + (b)` exact |
| Tabs for indentation, no trailing whitespace | matches the reference tree |
| Every module is exactly `return function(env) ... end` | one uniform loader |
| No module reads a global the allowlist does not name | catches typos offline |
| `--!globals name1 name2` extends the allowlist for one file | for the bootstrap only |

## 2. Loader and `env`

A module is a factory. `env.require(id)` loads it once and memoises the result.
`id` is the path under `src/` without the extension: `env.require("ui/theme")`.

```lua
return function(env)
    local theme = env.require("ui/theme")
    local M = {}
    return M
end
```

`env` is built once by `init.lua`:

| Field | Meaning |
| --- | --- |
| `env.require(id)` | memoised module loader |
| `env.services` | memoising service proxy — `env.services.CollectionService` |
| `env.hs` `env.uis` `env.tween` `env.run` `env.guisvc` `env.players` | the six hot services |
| `env.plr` | `Players.LocalPlayer` |
| `env.caps` | capability report from `runtime/caps` |
| `env.caps.fn` | resolved executor functions (`request`, `writefile`, `loadstring`, ...) or nil |
| `env.context` | table the host passed in; `{}` when standalone |
| `env.info` | `{ name, version, folder, uaVersion }` |
| `env.root` | the mounted app's `ScreenGui`, including credential-storage entry |

Cycles are a load error, not a hang. `runtime/*` must not require anything above
it; `ui/*` must not require `agent/*` except through `agent/session`.

`runtime/clock.debounce` retains one scheduled wakeup and the latest packed
arguments per pending burst. Cancellation releases retained arguments. A callback
may yield and queue another call without losing that new call. UTF-8 validation
and repair preserve their byte/character contracts while processing contiguous
ASCII or valid spans.

`runtime/boot_progress` receives real Prepare, Restore and Open milestones from
`init.lua`; `ui/boot` presents the responsive startup card. Loaded-module counts
remain separate from stage progress because feature modules load lazily. Elapsed
time is visible, and eight seconds without progress adds a still-working hint.
Success closes the card; failure freezes the current stage with console guidance
until Close notice. Raw host errors stay off the card. Its pulse, listeners and
delays are owned and released on completion, dismissal or unload.
`context.ui = false` suppresses this splash. Native startup does not introduce a
reduced-motion setting.

### Embedding SDK

The full client initially requires password setup or the explicit red
Continue without encryption choice. An enabled vault requires unlock on every
execution, including `context.ui = false`, same-build reuse and changed-build
replacement. A saved unprotected-storage choice skips future password prompts.
The app is mounted for credential entry; `context.ui = false` keeps its normal
window hidden after access is granted. Runtime boot still owns capabilities, configuration,
providers, sessions, tools, hooks and cleanup. Explicit `show`, `toggle`, or
`openSession(id)` can show the standard app after access is granted. `handle.uiMounted`
reports mounting, not visibility. A same-build rerun requests showing the app after
any required authentication unless `context.reuse = true`, which retains the existing
display preference and boot context; it does not bypass an enabled vault. Changed-build
replacement keeps the existing guarded save/reload contract.

`handle.sdk.version` independently identifies the embedding API as `1.1.0`.
`features` advertises `passwordGate`, `resourceScopes`, `requests`, `sessionLookup`,
`requestSnapshots` and `scheduledScopes`; `uiFreeBoot` is false because `ui = false`
hides the normal app rather than guaranteeing no application construction. SDK
APIs use dot calls.
Public `hooks`, `permissions`, and
`openSession` remove the need to import presentation or lifecycle internals for
ordinary host integrations. `env` and `app` remain implementation escape hatches,
not a promise that all their internals are covered by the SDK version.

`sdk.createScope(id)` owns cleanup functions, UAI/Roblox signal subscriptions,
hooks, and tool registrations. Duplicate live scope IDs are rejected. Scope or
client destruction releases resources once, contains cleanup errors, and removes
only the tool definition it registered. Tool removal denies its pending approval
and invalidates cooperative running calls; it does not undo applied effects or
kill a native call. Scope destruction does not delete conversations or unload a
shared client.

Scope IDs are nonblank UTF-8 strings of at most 128 bytes without control
characters. `scope.delay(seconds, callback, ...)` accepts a finite nonnegative
delay and returns an idempotent cancellation function. Firing or cancellation
releases ownership before the callback; destruction cancels pending callbacks.
`resourceCount()` reports resources still owned. Already-running callbacks remain
cooperative. Host tool descriptions are bounded to 16,000 UTF-8 bytes; schemas
are bounded to 256 KiB of text, 8,192 entries and depth 32. Composed schemas,
additional-properties schemas and numeric/length ranges are validated before
registration.

`sdk.request(session, text, options?)` returns a request or `nil, reason` on
admission rejection. Options provide `onEvent`, `onComplete`, and the established
`files`/`images` references. Accepted requests settle exactly once as `succeeded`,
`failed`, or `cancelled`, with `{ ok, status, text, error?, sessionId }`. Host
callbacks are protected. Ordinary settlement follows busy release; removal and
unload settle cancellation even when legacy send callbacks cannot run. Cancelling
targets only that request and stays cooperative. `await(timeoutSeconds?)` returns
the result or `nil, reason`; timeout stops waiting, not the request.
Events and completion results are copied per callback; `await()` and the public
`result` field are detached from the retained outcome. `snapshot()` returns
`status`, `sessionId`, `startedAt`, optional `finishedAt`, `elapsedMs` and an
optional detached result. Polling or mutating these copies cannot change another
observer's result or settle the request.

`sessions.get(id)` looks up a registered conversation. `open(id, options?)`
returns `session, created` and selects only with `activate = true`; existing
conversation options otherwise remain unchanged. `newThread` keeps default
activation and accepts `activate = false` and `ephemeral = true`. IDs are bounded
to 120 alphanumeric/underscore/hyphen characters; duplicates cannot replace live
entries. Hiding the normal app leaves permission policy unchanged. The mounted
application owns approval presentation after authentication.
Creation validates option types and copies string-to-boolean tool maps. Ordinary
session persistence stores a versioned policy containing tool filters/groups/
exclusions, turn/time budgets, unlimited mode, and streaming preference. Valid
policies survive restore. Invalid or future policy versions skip the conversation
without deleting its file; older saves without policy restore legacy defaults.
Saved IDs remain reserved even when their conversations are not registered;
`open` does not load arbitrary archived history or replace a skipped saved file.
Hosts must inspect existing conversation policy before reuse because `open`
does not replace it with newly supplied options.
See [docs/EMBEDDING.md](docs/EMBEDDING.md) for the public contract and examples.

### Standalone script UI library

`ui-lib/src` contains independent factory modules for Project UAI UI LIB, shipped
as `dist/uai-ui.lua`. It shares the application's visual language without changing
the existing `src/ui` application. Script authors declare tabs/sections/controls and
logic; the library owns layout, input, state, lifetime, and the fixed bottom
`Project UAI | UI LIB.` attribution. Navigation and action labels are text-only;
legacy script Icon options are ignored. The library draws its own frame-based
brand mark and window-control glyphs, so no uploaded assets are required. The
sidebar profile uses Roblox headshots with a readable initial, display name,
username and game. Motion is owned, reversible,
and reduced-motion aware; cleanup settles active transitions exactly.
See `docs/UI_LIBRARY.md` for the public API.

UI LIB 1.6.0 adds `NumberInput`, selectable `TextView`, searchable/paged `ItemList`,
`ActionGroup`, `Callout` and `KeyValue`. Item lists retain at most 500 records with
1–20 visible records per page; action groups own 1–8 actions; key/value readouts
accept at most 64 rows. Form validation, profiles and owned callbacks use the
same window lifecycle as existing controls. Scripts declare domain values and
callbacks instead of implementing these components locally.

`node tools/build_ui_lib.js` deterministically generates the library, SHA-256
manifest, and `runtime/ui_library_docs` from that guide. The read-only
`ui_library_docs` tool supplies bounded UTF-8 pages, and main/subagent prompts
require this library for new script UIs. No UI is mounted by reading the guide.
Imports validate known fields before applying and are silent by default.
Cleanup must release global input listeners, gestures, key holds, owned tasks,
overlays and script resources, including replacement by the same window Id.

## 3. Transport and identity

`net/http` owns inference and general-purpose HTTP requests. The bundled
decompiler adapters are an explicit exception: they use the executor's bytecode
and HTTP functions directly under `runtime/script_sources` worker/deadline
ownership. A timed-out reader does not release a still-running native transport
slot. These adapters neither send inference identity nor log bytecode, service
credentials or raw error bodies. Runtime modules do not depend on `net/*`.

* Executor `request` is preferred because it can set `User-Agent`. `HttpService:RequestAsync`
  silently drops that header, so on a vanilla client the Claude Code identity
  cannot be sent — `caps.uaSupported` is false and the UI says so rather than
  pretending.
* Every outbound inference call is stamped by `net/ua`: `User-Agent: claude-cli/<v> (external, cli)`,
  `x-app: cli`, and the `X-Stainless-*` companion set. The stamp happens inside
  `net/http`, so no caller can accidentally skip it.
* No Roblox transport can read a body incrementally. `stream: true` is still
  used: the whole SSE body arrives at once and `net/sse` replays it into deltas,
  which is what makes reasoning text and index-keyed `tool_calls` fragments
  usable. `net/ws` upgrades to real token streaming when the executor exposes
  `WebSocket.connect`, `websocket.connect` or `syn.websocket.connect` and a
  configured gateway implements UAI's envelope protocol. A normal local server
  or OpenAI Responses/Realtime socket does not implement that protocol. See
  [the provider and WebSocket contract](docs/PROVIDER_COMPATIBILITY.md).
* Explicit `x-should-retry: false` suppresses transport retries.
* Retries: 408/409/429/5xx and transport errors, exponential backoff with
  jitter, numeric or GMT-date `Retry-After` honoured with a cancellable 60-second
  maximum wait, capped attempts, then the next provider in the
  fallback chain.
* Native request deadlines, cancellation, malformed streams and response-limit
  errors are terminal. A long unanswered transport failure cannot trigger a
  smaller-request retry, key/provider fallback or a second dispatch after a socket
  send with an unknown outcome. Explicit API refusals can still teach a reply
  ceiling in `record.maxTokensCap = { model, tokens, scope }`; a timeout teaches no cap.
  Learned output caps and request repairs are scoped to endpoint, protocol and
  model. Older saved lessons adopt the current scope on first use.
  Both provider adapters protect retry callbacks and enforce these terminal states.
  Streamed error events retain bounded, redacted error codes/messages, including
  explicit plain-text SSE errors. Partial output or a later completion marker does
  not turn a failed stream into a successful response.
* Touch-only HTTP calls share one native exchange lane and a separate bounded
  cancellation lane. Native completion releases ownership; Lua timeout, Stop,
  discovery and unload do not. Executor globals retain ownership across client
  replacement where available. Relay `always` mode requires a relay even after a
  failed health check. Oversized or malformed relay replies stop polling once;
  the companion checks complete JSON envelope bytes before expanding provider
  bodies, returning a small terminal 413 when the wire response would exceed 8 MiB.
* Both adapters parse context-length refusals separately from output-token limits.
  A named window of at least 512 tokens is saved under the lowercased model id in
  `agent.forceContext`, only lowering an existing value. Like `record.maxTokensCap`,
  the learned value persists; the context map is also included in configuration
  export. The loop compacts against the refusing model and retries it once before
  continuing the fallback chain. Cancellation and a history with nothing to fold
  do not trigger repeated requests.
* Buffered HTTP and socket fallback use the configured output budget and model
  limits; the old `agent.executorReplyCeiling` setting is ignored. Native transports
  bound a request to at most 300 seconds and 8 MiB; individual executors and servers
  may stop sooner. A socket uses the effective `stream` body value and the full
  provider path/query. Connect/setup failures before `Send` may fall back to HTTP;
  failures after entering `Send` remain terminal. The Messages adapter uses HTTP
  or the web relay and does not use `wsUrl`.
  Socket setup, an allowed HTTP fallback and native retries spend the original
  request budget; a caller's earlier deadline wins. An expired socket request
  never opens a connection. Header maps reject invalid names, duplicate names
  ignoring case, nonscalar values and line/control injection before dispatch.
* Base URLs preserve explicit schemes, path prefixes and query strings. Bare local,
  LAN and private addresses default to HTTP; public hosts default to HTTPS. Local
  reachability is checked by URL, including custom records. Model-list caches are
  scoped to connection/auth settings, keep drafts separate and reject stale results
  and HTTP error documents; manual model ids remain available.
* Secrets are redacted in the request log; only the last four characters of a
  key are displayed in diagnostic views, and the Providers panel never renders the
  key itself. Configuration copies omit credentials by default. The separate
  explicitly labelled private copy retains vault encryption when enabled, or
  contains reversibly encoded credentials after the unprotected-storage choice.
  Included community access is represented by a reference, never its raw key.
  Import previews report counts and provider names without displaying keys, and
  imports retain this device's storage choice and vault password, if any.
* `util.encode` is the only path to `JSONEncode`, and it scrubs on the way through:
  every string is repaired to valid UTF-8, NaN and the infinities become `0`, and a
  function, userdata or thread becomes a marker rather than a raise. This is not
  defensive coding for its own sake. `JSONEncode` refuses a string with one stray
  Latin-1 byte in it and raises `Can't convert to JSON` with no position, because it
  is a C function; a web search's scraped snippet is full of candidates; and the tool
  result is already in the message history by then, so the failure repeats on every
  following turn. `util.truncate` and `util.ellipsis` cut on character boundaries for
  the same reason — both index in bytes and would otherwise bisect an em dash.

## 4. Provider records

```lua
{
    id = "openai",                       -- stable key
    label = "OpenAI",
    baseUrl = "https://api.openai.com/v1",
    apiKey = "sk-...",
    keyNames = { "Personal" },            -- optional labels aligned with deduplicated keys
    keyPaused = { false },                -- optional pause flags; missing means active
    keyIds = { "00000000-0000-4000-8000-000000000001" }, -- generated accounting IDs
    keyMode = "rotate",                   -- rotate (default) | single
    selectedKey = 1,                      -- saved key index used by single mode
    authStyle = "bearer",                -- bearer | x-api-key | api-key | both | none
    models = { "gpt-4o" },               -- only what the user added or picked
    model = "gpt-4o",                    -- current selection
    headers = { ["HTTP-Referer"] = "" }, -- extra per-provider headers
    params = { temperature = 0.7 },      -- extra body fields
    stream = true,
    enabled = true,
    order = 1,
    claudeUa = true,                     -- send the Claude Code identity
    health = { ok = 0, fail = 0, lastError = "", cooldownUntil = 0 },
}
```

Base URLs are normalised once: a trailing slash is dropped, a missing `/v1` is
added unless the URL already names a path, and a URL that already ends in
`/chat/completions` is used verbatim.

Adding a provider opens a gallery before the editor. It has three tiers — free
routes, paid routes and local servers — plus a search field that spans them and a
custom-endpoint card in every tier. A preset carries a description and an access
line so the cost of a route is visible before a key exists, and still carries no
model list. Choosing a card seeds the editor with that preset; nothing is written
until Save, and a dismissed editor draft resumes on the next Add instead of
reopening the gallery. Switching vendors from inside the editor reopens the same
gallery and keeps everything already typed. Each card carries an access label
rather than a bare tier: Included for the distributed community key, Free tier or
No key for free routes, and the free half by name for hybrid services (OpenCode
Zen's CLI models, OpenRouter's free ids, OpenCode Go's CLI catalog). A hybrid is
never labelled Paid, and no label claims a whole service is free when only part
of it is.

The setup form groups Connection, Access and Model, with direct catalog and
manual model-ID actions. Custom setup puts the URL, protocol and authentication
header together at the top; connection controls remain directly visible.
Extended vendor guidance has its own disclosure, expanded by default. The gallery
uses two card columns when space allows and one on narrow screens, with inset card boundaries,
aligned Set up actions and complete access lines. Short viewports scroll the
complete gallery body while retaining its search field and current tier.

`registry.requiresClaude(record)` recognizes `agentrouter.org` and its subdomains,
including manually entered endpoints. `identityFor` returns `claude` there even
when `record.claudeUa` is false. Inference and model-discovery requests mark this
identity as required, so `net/http` applies its headers despite the global switch
or conflicting custom headers. The provider UI explains the requirement instead
of offering a toggle. The featured preset uses `https://agentrouter.org` with the
Anthropic Messages adapter, producing `https://agentrouter.org/v1/messages`.

Only AgentRouter can recover an explicit unauthorized-client refusal through
`https://puai-proxy.davidzk.tech/agentrouter/v1`. Exact official AgentRouter
hosts/routes qualify; credentials, protocol, custom headers and query parameters
survive one retry within the original deadline. Invalid keys, custom endpoints,
timeouts and cancellation never switch. Registered records persist the URL;
editor drafts remain local until Save. No Workers.dev fallback is supported.
The proxy receives requests and provider keys and shares a 90,000-request daily cap.

OpenCode proxy routing is retired. Saved or newly entered retired OpenCode proxy
URLs normalize to `https://opencode.ai/zen/v1`; the old Workers.dev OpenCode URL is
recognized only for migration away from it. `FreeTierError` never switches to a
proxy. Direct desktop requests use the verified desktop User-Agent/client headers,
timestamp-based session identity and wildcard Accept header, while retaining required
compatibility tool declarations and the Chat/Responses protocol fallback. Explicit
custom header overrides remain effective. Generated project/request headers are
omitted because the live Chat probe rejected the previous CLI fingerprint. Mobile
OpenCode requires the UAI Relay app from Discord; mobile free-tier refusals do not
retry the alternate lane or a retired proxy. Errors explain the optional installed
CLI desktop path and the mobile relay requirement.

OpenCode Go is a separate keyed preset at `https://opencode.ai/inference/go/v1`.
Its legacy `/zen/go/v1` alias remains a Go route. Go model discovery and every
inference protocol retain that route and cannot use the native free-model catalog.
Documented model families select Chat (DeepSeek), Responses (GPT/Grok/Muse), or
Messages (Claude/Minimax/Qwen), or native Gemini (Gemini).
Go uses an identifiable Project UAI User-Agent and stable session header, with
explicit custom headers preserved. Ambiguous retired OpenCode proxy records still
migrate to Zen; selecting Go is explicit. Errors distinguish retired-route 410,
Go subscription refusal and the model's Global-region requirement. The client never
changes OpenCode privacy or subscription settings.

A connected desktop bridge can additionally serve supported free OpenCode models
through a separately installed official CLI binary. The binary is never packaged.
The bridge advertises authenticated `capabilities.opencode` (schema 1, enabled,
availability, state, binary filename and detected version), validates its required
v2 API routes, lists verified CLI models at `/api/opencode/models`, and routes supported
models through its existing inference job protocol. Missing CLI and models outside
its verified public catalog retain direct HTTP behavior. The native server binds
loopback, uses private authentication and isolated owned sessions, and leaves UAI
tools to Roblox. A private execution plugin enforces ask permission before host
tool execution, including native wrappers that omit their own permission gate.
Only exact UAI tool names on the private remote MCP server bypass that gate.
Native schemas remain available for free-model compatibility. Permission requests
may arrive after the tool state; the bridge waits for their matching identities.
Blocked native tool choices return a reserved, non-executable
`opencode_host_action` receipt after their pending permissions are verified and
interruption is confirmed. The ordinary Roblox agent step records that refusal
and can choose an available tool within the same conversation's scope. The bridge
never submits a corrective native prompt or approves desktop execution. Mixed tool
batches retain provider order even when MCP calls arrive out of order.
Capability and catalog data cannot survive a changed connection.

Project UAI Free is an optional Providers library preset (`projectuai-free`),
separate from personal-key HCNSEC (`hcnsec`). Selecting its card prepares a draft;
Save configures it. Startup, reset and empty imports do not insert a provider.
Existing saved configurations remain intact. Recognized legacy community-only
records adopt Free's identity; arbitrary personal/custom records are not guessed.
Switching away from Free removes recognized community credentials, even after a
draft's endpoint/auth fields change, while preserving other personal key metadata.

Project UAI Free uses an intentionally distributed community key
and the provider-supported `auto` router, verified through live discovery and tool
inference. New included-access inference, discovery and background probes are
admitted daily during **20:00–12:00 UTC+8**, including the opening instant and
excluding the closing instant, independent of the device's local timezone.
Accepted replies retain their owner and are not cut off at 12:00. Personal
HCNSEC credentials and other providers are unaffected. Client checks communicate
the schedule; the upstream service must enforce actual availability and quotas.
The key is reversibly encoded to deter literal searches, not encrypted or secret
from other executor scripts. Exact retired included credentials migrate on the
official endpoint; personal keys and custom endpoints are not guessed or replaced.
**Settings → Agent → Automatic free routing** (`agent.autoFreeRouting`)
is optional and enabled by default. Disabling it cancels background measurements
and preserves the selected provider model for future requests; accepted requests
keep their original owner and route until completion. The provider's `auto` can
still perform server-side routing. A retained `model:route` notice names each
changed measured-model selection and gives the exact settings path to disable it.
With this setting enabled, default Chat settings and saved `auto` selection, opening the
model picker or preparing an agent request starts background latency measurements.
At most two workers probe up to 32 live-discovered IDs with synthetic tool calls
and tool-result replay, each with a ten-second deadline. No conversation or real
tool execution enters a probe. The fastest fresh candidate whose two responses
both finish below ten seconds is selected before prompt preparation when its
documented context can hold the estimated request and reply. Images, unknown
windows, explicit body/query/socket settings and manual/private-key selections
retain their existing route. A cold or unmatched request uses `auto` immediately.
Measurements expire after ten minutes and on connection/auth changes. Slow or
failed user responses remove that candidate for subsequent requests; they never
race or replay the current prompt. Synthetic latency is not a real-request SLA.
Per-request selections retain the saved `auto`, preserve scoped adapter lessons,
and cannot override later provider edits. Free model choices have a subdued green
rounded outline in the model picker and provider menus; selection stays distinct.
Empty startup/import/reset configurations remain empty. Public credentials remain
masked in the UI. The welcome directs new users to Providers; a selected Free
record shows its schedule and variable shared availability. Personal HCNSEC
setup never offers or automatically installs the community credential.
No session-only development credential belongs in source or generated artifacts.

Saved providers own exact-ID model favorites and recent selections in
`ui.modelFavorites[providerId]` and `ui.recentModels[providerId]`. Favorites lead
recents without changing the saved catalog, with at most 100 favorites and 12
unique recents per provider. Removing a provider removes its shortcut buckets.
Public configuration copies retain these preferences; import rejects unknown
provider buckets, malformed IDs, duplicate recents and excess counts.
`runtime/model_id` is the shared UTF-8/control/160-byte boundary, with the
compatible `provider/model_id` entry point. Model filters support words in any
order, quoted phrases, exclusions, favorites and documented tool support.

Duplicate setup opens an unsaved draft retaining public endpoint/model/protocol
fields and fresh preset defaults; it omits keys, URL queries and custom maps.
Community access is added through its own library card. Reset learned
compatibility clears parameter repairs and token/tool limits while retaining
health, key cooldowns and accepted request ownership. It never resends work.

Provider key pools select ready credentials round-robin, advancing the shared
cursor before network work can yield. Quota refusals bench their rejected key;
proxy recovery and transport retries retain the selected request key. Intentional
request snapshots share the originating record's cursor, while independent
provider-editor drafts remain isolated. Cached model discovery uses no key slot.
Manage API keys opens a dedicated modal from provider setup or saved-provider
details. Each masked entry has an optional name; empty names display API key N.
Names are trimmed single-line UTF-8 text, at most 120 bytes, stored in the ordered
`keyNames` array alongside the deduplicated `apiKey` pool. Adding appends keys;
replacing or removing an entry preserves other credentials and their names. There
is no UI limit on the number of entries. Existing newline/comma-separated pools
remain compatible and default to rotation without rewriting their saved data.
Name/status search hides existing manager rows without replacing its focused
field or searching credential contents. Browser pool replacement preserves the
names, pauses and accounting IDs of exact surviving keys. A browser form for a
removed provider cannot silently recreate it.

`keyMode` defaults to `rotate`. In `single` mode only `selectedKey` is used for
inference and model discovery; quota recovery never selects a different key from
that provider. The ordinary provider fallback setting remains independent. Removing
an earlier entry adjusts the selected index; removing the selected entry restores
rotation and explains the change. Discovery caches include the request policy,
while a name-only edit preserves both discovery results and the rotation cursor.
Accepted request snapshots retain their original key policy.

`keyPaused` is an optional dense boolean array aligned with the keys. Paused
entries are excluded from rotation and model discovery. All-paused and pinned
paused configurations may be saved; requests then stop with an actionable error
instead of sending anonymously or selecting another credential. Selecting a new
single key requires an active entry. Replacements preserve pause state; appended
keys start active. Pausing affects future requests, not accepted snapshots.

`keyIds` is an optional dense array of unique lowercase GUIDs, generated before
live records are copied for requests or editing and persisted with configuration.
Names, pauses and index shifts preserve IDs; a different replacement credential
gets a new ID. These identities are for local accounting and do not invalidate
authentication caches or expose credentials. Diagnostic exports omit key IDs and
private names; full configuration transfers preserve the metadata.

The manager keeps an isolated draft until Apply. In provider setup, Apply returns
the key changes to the connection draft and Save persists them; opening directly
from a saved provider applies them to that provider. Cancel or Escape discards
manager edits. Explicit private configuration transfer includes names and routing preferences;
diagnostic support exports omit private key names.

### Provider credential storage

The bootstrap activates `config.requireVault()` before loading configuration.
Plaintext and byte-encoded configurations restore the same live provider records,
preserving pools, names, pauses, selection and accounting IDs for the initial
storage choice. Their original file is retained until password setup verifies
encrypted storage or the user explicitly chooses verified unprotected storage;
startup does not rewrite undecided legacy credentials before that verification.
The versioned `storedCredentials` envelopes from `runtime/credential_codec`
are reversible encoding with a corruption checksum, not encryption. Invalid or
future envelopes remain recoverable and block affected requests. Migration never
silently replaces unreadable keys with empty data.

The `credentialVault` envelope uses RFC 5297 AES-256-SIV and PBKDF2-HMAC-SHA256
with a 64-byte derived key (two AES-256 keys). New vaults and explicit password
changes use 100,000 iterations. Existing envelopes retain their stored count,
including 600,000, during unlock and ordinary saves. An explicit password change
can use the same password to rewrite the vault at the new count. The reduced
derivation workload also reduces resistance to offline password guessing.
The public GUID-based salt distinguishes vaults; SIV does not require a
random nonce. The authenticated header binds format version, cipher, KDF,
iterations and salt. The payload binds protected provider fields to unique provider
IDs and includes identity headers. Envelopes and plaintext size are bounded. The
implementation uses the LuaJIT-compatible Luau modules bundled with the client,
without external apps or executor cryptography.

`config.enableVault(password, options)` preserves legacy live keys and enables
encryption only after staging and reading back the encrypted projection and
verifying the primary save. No plaintext backup is written. A failed primary write
attempts to restore previous bytes from memory; an encrypted pending file can
recover an interrupted write when the primary is missing or unreadable, or a failed
removal left a session-only primary beside its last encrypted recovery copy. Failures
retain live records and the previous storage choice. `config.storageError` is
transient and never includes a credential. Cancellation before commit leaves the
prior file and configuration intact.
Configuration loads and writes are serialized. Reentrant loads and credential
edits cannot replace a save's state; unrelated settings changed while it yields
remain dirty for a subsequent save. Unload and changed-build replacement retain
the current client while credential derivation or filesystem work owns storage;
they can be retried after it finishes or derivation is cancelled. Generic
replacement/reset of security settings cannot bypass the verified storage controls.

`config.continueWithoutEncryption(options?)` is the explicit alternative. It
preserves live key pools and identity fields, verifies a reversible byte-encoded
save, then persists `security.credentialProtection = "unprotected"`. This selection
admits use without a vault and skips future password prompts. The UI action is red
and states that saved API keys are unprotected. An existing encrypted vault must
first satisfy the current password challenge, or be reset to discard its keys;
the choice cannot decrypt or silently replace locked credentials. When opting out
after unlock, encryption and the private key are cleared only after the new save
is verified. Legacy `rememberCredentials = false` alone never skips the initial
choice. Ordinary security setters and imported configuration cannot opt out for
the user. Privacy can enable password protection again.

Cold vault loads remain locked, retain their encrypted envelope, and block provider
credential use and edits until `config.unlockVault(password, options)` succeeds.
Wrong passwords, malformed envelopes and authentication failures release no keys.
`config.vaultStatus()` reports required, ready, enabled, locked, busy, error and
protection state (`password`, `unprotected` or `undecided`).
`config.accessProblem()` returns nil when required access is ready; otherwise it
returns a bounded setup/unlock/storage-choice explanation. New inference, model discovery, free routing,
agent/tool dispatch, remote commands and credential transfers respect this gate.
With a vault enabled, re-execution challenges even an unlocked session: the password
is derived and verified again while current live edits are retained. Keeping a
private key for safe saves or build handoff never satisfies the new challenge.
Cancellation and closing other UI cannot grant access; Exit unloads the client.
Derivation yields cooperatively and supports progress/cancellation callbacks.
New passwords need at least 12 Unicode characters; several unrelated words are recommended.
The password is never persisted. The derived key stays in the vault module's
private session state, outside configuration, exports and diagnostics.
Setup prominently warns that there is no password recovery and that resetting
after a forgotten password removes the vault's saved credentials, requiring re-entry.
During setup or unlock derivation, the password dialog and its full-screen backdrop
hide in favor of a compact bottom-right panel showing the operation title above
the current percentage, Cancel and Exit. It does not capture input outside its
bounds; password entry releases keyboard focus while suspended. The required
access gate remains active, with normal UAI controls hidden. Cancellation or failure restores password entry with cleared
fields and feedback; successful authentication and any required verified save
release the gate. Cancel and Exit retain the runtime's storage ownership rules.

`config.lockVault()` saves current protected fields before clearing live credentials
and its session key. `config.changeVaultPassword(password, options)` requires an
unlocked vault and verifies the new envelope before switching keys.
`config.disableVault()` and `config.setRememberCredentials(false)` retain their
legacy session-only semantics outside the bootstrap gate and cannot stand in for
the explicit unprotected-storage choice. `config.resetVault()` explicitly discards
locked vault credentials, retaining other settings and returning to the storage choice.
It does not revoke keys at their providers or erase existing exports and backups.
Executors without verifiable filesystem persistence cannot complete either
saved-storage choice. Accepted request snapshots are not erased retroactively;
Lua strings cannot promise secure memory zeroization. Other scripts with executor
access can intercept passwords or live credentials during use.
Bridge and relay pairing tokens keep their existing storage behavior.

Legacy session-only saves contain a separate copy without private API keys, all custom
provider headers/query/body overrides, URL userinfo/query/fragments, identity
extra headers, error text and learned scopes that can duplicate credentials.
These stripped pools lose their saved per-key metadata and are marked
`credentialsOmitted`; requests require a reviewed connection Save before reuse.
Background/model-only saves cannot clear that guard. `keyRotation` is never
persisted, including remembered mode, because its cooldown map contains raw keys.
Included credentials use `communityCredential` references in all saved configs
and exports, with restoration restricted to the official endpoint. Versioned
`communityKeyState` preserves included-key names, pauses, selection and accounting
IDs in local saves/private transfers; a changed credential revision resets its IDs.
Ordinary exports omit that private metadata. Unrestorable references cannot dispatch.

Legacy storage APIs remain available to isolated compatibility modules but cannot
bypass the bootstrap's required storage choice. Bridge/relay pairing storage
remains independent.
Changed-build replacement passes a private in-memory configuration snapshot and,
when unlocked, a matching vault key to the new loader. With a vault enabled, both
replacement and genuine unload/restart require the password before admitting new
work. The verified unprotected-storage choice survives replacement and cold boot.
Existing exports/backups are not erased.

`config_transfer.export()` and `copyToClipboard(write)` exclude connection
credentials. `{includeCredentials=true}` explicitly requests a private transfer.
Private exports preserve vault encryption when enabled, otherwise use reversible
byte encoding. Encrypted imports request the source password before review.
Imports replace providers, not merge key pools, and retain the receiving device's
storage choice and vault password, if any. The destination must complete setup/unlock
or its explicit unprotected-storage choice before import or export.
User-authored memory, notes and instructions still require
review before sharing. See [API key security](docs/API_KEY_SECURITY.md).

**Models are never guessed.** General presets carry no model list; the managed
Project UAI Free default uses the live-verified `auto` router. `provider/models`
resolves a provider's models from exactly two sources — ids the user added by
hand (which rank first, and persist on the record) and whatever `GET /v1/models`
reported, or the authenticated desktop backend's catalog for CLI routes (cached
for ten minutes, not persisted). Generic catalogs retain every ID. Native Gemini
uses explicit generation methods; exact AI/ML API, Vercel, FriendliAI and Venice
catalog routes use documented type/mode fields to omit explicit non-chat APIs.
Unknown field shapes, custom routes and manually entered IDs remain available.
Names never determine whether a model is chat-compatible. An endpoint with no
`/models` route is a normal case: the Providers editor
takes a typed id, and saving requires one.

Model metadata is independent of discovery: the reviewed catalog enriches known
ids but never adds models to a provider. `tools/data/model_metadata.json` records
the source URLs, hashes and refresh date; `tools/sync_pricing.js` generates
`provider/model_data`. Refresh uses verified TLS and fails on missing sources;
offline generation and `--check` are deterministic. Prices match exact ids within
their provider, never a paid id inferred from a free alias. Rates include documented
cache categories and context tiers. Unknown gateway prices stay unknown. Included
Project UAI Free access costs zero; personal HCNSEC rates are not assumed. Context
and reply limits use the same catalog, while protocol-specific request traits
remain explicit. User-declared context overrides remain effective.

Usage counters must be finite and nonnegative. Missing or invalid input/output
counts use the labelled estimate for that side. Cache reads/writes stay within
input tokens and reasoning stays within output. Unknown-cost request counts and
cache-write totals persist with usage history; unknown prices are never treated
as evidence of free access.

Tool discovery filters the same current capability, permission, group and
conversation scope as provider declarations without cloning all schemas.
`tool_search` supports bounded multiword queries and returns normalized schema
pages with byte limits separate from listing row limits. The Tools panel builds
parameter/permission details only when expanded. Diagnostic searches span
request fields and retained log details. Stored log values are bounded after
redaction, with omission markers for truncated content.

Rolling compaction writes a structured handover: goal, current state, decisions,
exact facts (paths/IDs/revisions/commands), completed work and checks, open
threads and the next step, and what not to redo. It feeds the previous handover
back to the summarizer with newly removed turns and complete older assistant/tool
exchanges from long turns. It retains recent user requests and the latest two
exchanges, bounds merged handovers to 12 KiB, reserves handover headroom, and
replaces history only after checking for context reduction and cancellation.
Removed messages are kept as a bounded per-conversation archive (512 KiB across
64 KiB segments) and named by a short system line; `context_archive` lists,
searches and byte-pages that archive so folded work stays recoverable without
staying in the live window. Summary input includes bounded tool arguments, paths,
results and continuation offsets. Automatic failed/disabled summaries use
explicitly labelled bounded excerpts; manual compaction requires a successful
summary and otherwise preserves the conversation and reports the reason. Summary
calls are included in usage. Prepared requests bound their reply budget to the
remaining known model window without persisting that temporary ceiling.
The context inspector uses the same pressure and
limit calculation as compaction: estimated messages and summary plus prepared
system/schema overhead. Usage is calibrated against a dispatch-time snapshot and
scoped to provider ID, endpoint and model; changing prompts adjusts the estimate,
and history shrinkage retires the corresponding tokenizer-error correction.
Before the first prepared request, totals are labelled partial. Its colored bar
uses the model window when known and the compaction point otherwise; the marker
and legend make that scale explicit. Category labels reserve the remaining row
width, and live refreshes are coalesced and disconnected when the inspector closes.

Native requests no longer apply an executor-specific output ceiling; saved
`agent.executorReplyCeiling` values are ignored. Genuine socket frames and live
Cowork relay deltas produce transient `assistant:preview` events through
`agent/stream`, with coalesced 64 KiB
text/reasoning previews and cancellation. Final text/reasoning replace their
previews and are retained once; buffered HTTP replies render immediately without
simulated typing. The prompt requests brief assistant-content updates between
tool steps. Tokens cannot be displayed before the host/provider delivers them.

Responses tool assembly binds item IDs, call IDs and output positions to one
slot. Full argument events replace streamed fragments; nonempty final output
replaces superseded partial calls. Streamed and whole responses enforce shared
limits of 64 calls and 256,000 argument bytes. Exceeding either limit is terminal.

Generation settings live in `runtime/config` and are persisted in `UAI/config.json`:

| Setting | Default | Behavior |
| --- | --- | --- |
| `agent.maxTokens` | 128000 | Saved reply limit; model limits and learned per-model caps apply when constructing requests. |
| `agent.contextTokens` | 1000000 | Hard context budget before compaction. Larger contexts spend more of an executor's request window on upload and prefill. |
| `agent.contextFraction` | `0.8` | Share of a known model window at which compaction starts. The hard budget above still applies. |
| `agent.effort` | `"low"` | Prefer shorter reasoning where supported. Saved choices and explicit request/provider overrides remain effective; `"off"` omits the effort field. |
| `permissions.mode` | `"full"` | Allow everything for new configurations. Saved modes and explicit tool rules are preserved. |

The model modal edits the same global effort preference as Agent settings. It
offers documented levels where known, and the global choices when reasoning
support is manually enabled for an otherwise unknown model. Provider default
omits the effort field. Model-specific clamping never rewrites the saved global
choice. Open controls follow external settings changes and release subscriptions
when closed. A manual reasoning claim does not establish which levels a provider accepts.
Temperature policy and its numeric value live under Models → Options → Temperature,
so the settings do not reserve a permanent block above the model list.

Main and subagent prompts place standing rules before changing environment facts,
keeping a stable prefix eligible for provider caching without guaranteeing cache
support. Shared rules favor direct action, relevant skill reads and focused checks.
Task lists and delegation are useful options, not mandatory setup for routine work.
The loop builds tool definitions once per request and passes them to the prompt
builder; specialized workflow sections follow the offered catalogue. An unscoped
prompt preview includes all sections. Subagents receive their own plan, permission
mode, selected model, host instructions and reply language, and follow-ups take
precedence over the original task. Custom instructions override workflow/style
defaults but cannot override tool permissions.

The shared prompt explicitly requires native function calls with complete JSON
objects, exact offered tool names and schema keys, and observed targets before
dependent actions. Returned receipts, not plans or emitted calls, establish
success. It distinguishes safe argument repair from uncertain side effects,
preserves pagination cursors and calls for a requirement check before finishing.

Chat and Responses declarations respect the provider's ceiling (128 by default)
without silently losing later tools. A request-local `uai_tool_catalog` function
(collision-safe name) lists the omitted names and bounded descriptions.
`action=describe` returns paginated exact schemas; `action=call` supplies the real
name and argument object. Only tools from both the original offered catalog and
the authoritative loop scope qualify. Native dispatch rechecks permissions and
capabilities. Provider history keeps the wrapper and call ID for valid replay;
execution, progress and UI receipts use the original name. Explicit tool choice
is preserved, and a smaller limit refusal retains the full original catalog.

`scripting_docs` is a read-only tool in the script group with no host capability
requirements. It supplies the detailed `docs/SCRIPT_DEVELOPMENT.md` guide offline.
Both main and child prompts include only a short pointer when the tool is offered:
read Quickstart once, then relevant sections as needed and reuse retained guidance.
The index and section bodies use bounded UTF-8 pages with one-based `offset`,
`nextOffset` and `eof`. Reading guidance performs no HTTP, file access or execution
at runtime and does not expand a conversation's tool scope.

The native bundler invokes `tools/build_script_docs.lua` before collecting modules
to generate `runtime/script_development_docs` from stable second-level headings.
The normal build generates the reference; `--check` only compares it and fails
when stale. Review guide prose, examples, reader and generator inputs before
building; inspect generated output before the focused guide integration check.
The detailed guide is not injected into every request, and updating it does not
change the separate UI LIB artifact or API.

Each provider attempt receives that provider's model identity, including fallback
and context recovery. Request hooks receive a fresh copy of messages and tool
schemas per attempt; changes do not mutate saved conversation history, registered
tools or subsequent attempts. Hook cancellation is checked before dispatch, and
a replacement request supplies the frame callback for that attempt.

Saved memory values are retrieved on demand through `memory_read`, not injected
as standing instructions. A stable, quoted key index fits within 2 KiB; omitted
keys remain discoverable by literal case-insensitive search over keys/values or
paginated full reads. Exact-key reads also paginate within the tool result budget.
Current instructions and observed state supersede historical facts. Stored memory
is preserved, and listing it never sorts the persisted array in place.

The transcript's 24,000-byte field retention is a display/storage bound, not a
model reasoning budget. Reasoning events retain truncation metadata; the UI labels
excerpts and estimates only visible text. Folded reasoning defers Markdown
formatting and measurement until opened. Its native text label stays empty with
automatic sizing disabled while folded; opening assigns text and folding clears
it again. Reopening and resizing reuse parsed text;
formatting failures leave the original text readable.
Live previews report independent `textLimited` and `reasoningLimited` flags,
alongside the aggregate `limited` flag. Clipping one channel cannot label the
other as an excerpt; legacy producers supplying only `limited` remain supported.

## 5. Tool contract

```lua
{
    name = "instance_find",
    group = "instance",
    risk = "read",                 -- read | write | danger
    needs = { "loadstring" },      -- capability keys, checked before dispatch
    description = "...",           -- what the model sees
    parameters = { type = "object", properties = {}, required = {} },
    run = function(args, ctx) return "text" end,
}
```

`ctx` carries `emit(kind, payload)`, `progress(text)`, `aborted()`, `env`, `session`,
`depth` (subagent nesting) and `budget`. Progress is tagged with the originating
call ID; `emit("tool:progress", { text = "..." })` is also supported. A handler
returns a string, or a table
`{ text = "...", data = <table> }` for structured results. After `postTool` hooks,
both text and structured evidence reach the model through a bounded representation;
the interface retains its original text/data receipt. IDs, revisions, listings and
continuations must remain usable. Large native results use the existing scoped
detail readers; clipped text must never be paired with an offset that skips the
missing bytes. A
handler may yield. Raising an error is caught and reported to the model as a tool
error, not a crash. Returning `{ ok = false, text = "..." }` reports a semantic
failure without raising. Dispatch rechecks disabled groups and the session's tool
filters before execution, including after a pending approval resolves.

The default `agent.toolProfile` is `focused`. It exposes at most nine families
(`uai_files`, `uai_code`, `uai_instances`, `uai_game`, `uai_inspect`, `uai_connect`,
`uai_automate`, `uai_context`, `uai_other`) plus seven eligible direct tools:
`ask_user`, `notify`, `dispatch_agent`, `agent_status`, `agent_followup`,
`tool_search` and `script_workflow`. Empty or unavailable families are omitted.
Each family supports `list`, paged `describe` and `call`; declarations use
`strict=false` for optional discovery fields and arbitrary action arguments.
Exact target schemas and up to three validated examples are read on demand.

Family calls re-enter the underlying action's ordinary dispatcher, including
permissions, approval, hooks, revisions, timeouts and cancellation. The original
request's allowed action names remain authoritative through family and overflow
dispatch. Conversation exclusions and named/headless restrictions cannot widen
when a schema is requested or a call runs. Existing profiles and `all` remain
selectable; consolidation changes declarations without deleting tools.

Schema validation preserves already-valid union types and bounds recursive work
to depth 32, 8,192 visited values and 16 reported errors. Declared oversized
arrays fail before member coercion. Invalid worker counts fall back to eight;
tool result order remains the original call order. Fitting native summary/detail
receipts reach the model immediately. References are exposed only for the
originating available reader and are checked after hooks replace a result.

Shared retained tool details expire after five minutes and are bounded to 20
snapshots/4 MiB. Text pages fit the configured result budget and preserve UTF-8
continuation. Oversized or expired details are reported as unavailable.
`http_get`/`http_request` fail on HTTP errors; a retained body continuation does
not issue another request. `json_api.keys` selects exact keys, including dots and
numeric-looking strings, and preserves `false`. `web_read` accepts a URL or an
immutable `page_id`, retains four readable-text snapshots/4 MiB for five minutes,
and rejects responses over 2 MiB or sanitized text over its snapshot limit.

Metadata tools share a 32-entry product cache for 60 seconds and accept explicit
`refresh=true`. Counts and uptime remain live. Failed or empty API documents are
errors, and the native `place_info` path does not require executor HTTP.

`conversation_search` accepts `scope=all|conversations|pastes`. Each pass reads at
most 128 paste files/8 MiB and scans at most 12,000 conversation entries/8 MiB.
The last whole value may cross the byte budget. Limited or unreadable searches
report incomplete coverage and support narrower follow-up through scope or
`file_search` on an exact paste path.

Small property batches preflight reads and value conversion before writes, then
report observed changes, failures and unreadable effects. A clamped value or a
setter throwing after a change cannot be described as untouched. These writes
are not atomic. Player selection gives exact usernames priority; duplicate
display names require a narrower identity. Distance listings capture values
before sorting. GUI text traversal checks ancestor visibility/Enabled, includes
an explicitly selected text root and discloses incomplete traversal.

Discovery and dispatch use the same permission decision: explicit tool rules
override the base mode, including `allow` or `ask` rules in read-only mode.
Capability and conversation-scope checks still apply. A rejected tool result
distinguishes saved rules, the mode, a user's decision, an unanswered approval
timeout and cancellation. Timeout/cancellation never claims the user declined,
executes the pending call, or saves a denial rule. Late answers cannot revive a
settled prompt. The agent continues other allowed work without a redundant question.

Stop and scope/permission revocation release tool waiters on the next scheduler
check without closing native continuations. Cancelled calls suppress late progress
and results and remain cancelled if permissions or the active turn change. Native
effects may still finish; cancellation never claims rollback. Invalid dynamic tool
timeouts fall back to the configured positive finite deadline, then 25 seconds.

Virtual input owns up to 32 held keys/buttons by conversation and original
provider. Stop, revocation, epoch replacement and unload attempt release; a
native down returning after early cleanup is released again. Accepted or
uncertain presses never trigger another provider's press. Failed releases retain
ownership for explicit `up` recovery. One watcher handles eligible cleanup.

The prompt asks for successive batches of normally 1–4 independent calls, waits
for their results, and discourages dozens of calls in one response. Dependent
calls and changes to the same file or runtime state run in successive steps.
This is prompt guidance only; tool-call limits and concurrency are unchanged.

Inputs over 8,000 UTF-8 bytes become verified files in `UAI/pastes/`, with a
10 MiB maximum per file. Preserve the original bytes, including whitespace, and
send only a compact path/size/line-count reference without a source preview.
Short messages stay inline. The native composer separates a large inserted
block from the surrounding editable text; attachment-only sends are valid.
The browser transfers long text through ordered `attachment:upload` commands
before `send`, with conversation ownership, byte offsets and idempotent retries.
Only a verified final write produces a usable reference. Failed saves, missing
files or unavailable file tools leave the draft intact and never send the long
source inline. These are executor workspace files, not provider-specific uploads.
Browser images use a separate compact, session-scoped reference in model context.
The bridge resolves that reference to actual Chat Completions or Messages image
blocks only at provider dispatch; image-bearing requests use the relay regardless
of the selected runtime. No image bytes enter Lua context or transcript events.
Missing current images fail with a reattach instruction; expired images in older
user turns become explicit unavailable-image text. Old clients without imageInput
capability cannot accept image sends. Vision support depends on the model.
Explicit `files/` and `pastes/` paths resolve before bare-name fallbacks; client
configuration is never a fallback scope. Saved-paste slices return at most 6,000
source bytes with UTF-8-safe continuation offsets, including batch reads.

`runtime/workspace` supplies the exact per-place path in every main/subagent
environment block, using cached place metadata rather than a product-info call
on each step. The display name is separate from filesystem identity. New folder
labels use ASCII letters, digits, spaces, underscores and hyphens, bounded to 72
bytes, and always append PlaceId. Accessible existing folders and saved PlaceId
selections in `workspace.json` take precedence, including bounded discovery of
legacy repeated `files/` containers. Existing Unicode paths remain exact; an
inaccessible saved Unicode folder falls back to a portable folder without moving
its files. Discovery probes each candidate folder once, including failed probes
repeated in recursive host listings. Damaged or unsupported identity files are left intact while the session
selects an existing or portable default. Folders are never automatically renamed,
flattened or merged. Scripts go in the game folder; decompiled/dumped source goes
in `dump/`. Shared and cross-game files remain
reachable. Initialization does not require inspecting or decompiling the game.

File tools return canonical `files/...` paths that file, search, compile and
execution tools accept unchanged. The shared main/subagent filesystem contract
supersedes old prefix workarounds. The namespace prefix is stripped once; a real
nested `files/` directory stays distinct. Legacy workspace-relative paths remain
supported. Reads also accept explicit `pastes/...` paths. Listings paginate with `offset` and
`nextOffset`. Host listings resolve only unique existing paths within the requested
directory. Ambiguous, corrupt and inaccessible entries are disclosed as incomplete,
while usable entries remain available. Leading spaces in explicit paths are
preserved. Legacy-file migration verifies destination bytes before deleting sources,
preserves conflicts, and never removes an incompletely listed directory.

`run_luau` uses a separate managed executor with a default 10-second deadline
(configurable to 1–60 seconds), cooperative loop checkpoints, bounded output, and
capture of multiple returns. Functions scheduled through its task wrappers share
the deadline and complete before the result is delivered. Stop, failure, timeout,
and unload stop managed tasks cooperatively without native `task.cancel`. Pending
Roblox/executor continuations retain live coroutines instead of targeting closed
ones. Managed delays use cancellable wait slices; explicit cancellation accepts
only this execution's task handles, treats finished handles as a no-op, and exits
self-cancelling tasks inside their protected wrapper. Work suspended outside
managed waits may still resume before its next checkpoint, which is disclosed.
Dynamically loaded code, native engine calls, and persistent engine-signal
callbacks are outside this guarantee. Failed turns invalidate their tool contexts;
starting another main or subagent turn cannot revive old workers.

`check_luau` only compiles. Both `check_luau` and `run_luau` accept either inline
`code` or a saved `path`, using the same workspace/paste resolution as `file_read`.
This keeps saved source out of repeated model output. `file_edit` requires an exact
unique match unless replace-all is explicit, permits empty replacement text, and refuses stale file
contents. `file_read` and `script_source` use contiguous UTF-8 slices with 1-based
byte offsets and continuation cursors; each slice fits the registry's result budget.
Successful standalone syntax checks retain at most 16 exact-source entries/2 MiB
and invalidate on compiler replacement or unload. They retain no executable
closures; managed execution wrappers compile fresh. Exact file edits verify
written bytes before reporting success. `code_read` line ranges avoid allocating
all document lines and reject conflicting source/version/proposal selectors.
`file_write` and `file_append` advertise and enforce a 2 MiB content limit per call
before disk access. The prompt and tool descriptions direct edits of existing
large files to `file_edit`/`file_edit_many`; full writes create files or replace
most of their contents. Large new scripts use small sequential writes/appends,
then syntax checks and execution by path. JSON repair preserves the complete outer
object and rejects unclosed strings. Every dispatched tool rejects missing closers
instead of dropping unfinished targets, filters or edits/options. A token-limited
tool batch produces
an error result for every call without executing any, allowing the model to send
smaller complete calls on its next step.

Main and subagent prompts read relevant or explicitly requested enabled skills
before applying them; unrelated skills require no reads. The environment supplies
a stable inventory of names, exact filenames and descriptions within 3 KiB, with
an explicit omission notice. `skills_list` supplies the complete inventory and
`skills_read` supplies bodies, both through UTF-8-safe byte-offset pages within
the result budget. Restricted subagents retain skill reads without write/install/
delete tools. Disabled skills remain unreadable; denied or unavailable reads need
no retries. Reuse unchanged bodies retained in context, including on resume; read
needed bodies again after changes or compaction removes them.
The prompt inventory alone may reuse its bounded rendered text for five seconds;
explicit skill listings/body reads stay fresh. Skill saves, removals, enabled
policy changes and configuration replacement invalidate that inventory.

The Project Gravity tool group resolves the live `_GRAVITY_CONTEXT` for each
action, falling back to `env.context.gravity`. Desktop and mobile Gravity
launchers pass that context explicitly. Initialization publishes the handle;
teardown clears only its own handle. Reloaded or torn-down contexts cannot be
used for a pending mutation. `gravity_status` is available without a connection;
engine and shape operations use the dynamic `gravity` capability and normal
permissions. Shape catalogs and control metadata come from the live runtime and
paginate; controls use their real keys and stored slider units, including `Div`,
`IntOnly` and the native speed-range extension. Setting batches validate before
mutation, preserve table identities, and invoke the relevant native handlers.

`gravity_parts` lists the authoritative held-part map in claim-ID order, with
filters, continuation offsets and at most 25 records per call. IDs include the
Gravity session ID; stale or cross-session IDs cannot select a new part.
`gravity_part_control` uses the native selection/assignment/ride/physics/release
handlers, requires the guarded Part Control API, and honors the native 512-part
selection ceiling. Shape loads recheck cancellation, session identity and the
entire selected-record snapshot before assignment. Group movement preserves
spacing, using current pin/manual targets or the parts' world positions.
Selection clearing retains overrides; `release_all` includes unselected ride and
physics overrides even without a mode. Per-part overrides are session state.

Engine configuration also covers UI scale, HUD, visual performance, FPS, core RGB
color, ignore tags and Part Control panel defaults. FPS requires native executor
support. Typed batches validate before mutation and restore previous settings
when a native effect fails, reporting an incomplete restoration when necessary.
Part Control defaults are separate from assigning overrides to a selection.
`gravity_keybind` rebinds native core/shape shortcuts after rejecting collisions;
`gravity_favorite` changes the native favorites table and selector. A settings
reset uses Gravity's complete reset hook, including visual restoration, hotkeys,
control refresh and post-startup plugin defaults. `persist=false` avoids requesting
a save for settings, keybindings, favorites, shape selection and reset. Manual
Slingshot launch/charge requires that shape and its manual-control mode.

`gravity_plugin_read` supplies the module guide, template or bounded local/official
source slices. `gravity_plugin_write` accepts source or a saved file path, checks
syntax, verifies the real `GravityShapes/` file, and requires `overwrite=true` for
replacement. Default loading runs setup once under the existing execution deadline,
validates the returned module and controls, cleans up a previous module and
preserves compatible settings. An inactive shape is not selected automatically.
`load=false` saves syntax-checked source without executing it. Replacements check
for file/runtime changes during setup; failed verification restores the previous
file where possible. Released plugin callbacks have no setup deadline but retain
explicit task cancellation; persistent callbacks require plugin-owned cleanup.

Infinite Yield tools read the running engine's environment, for both an ambient
IY and a captured internal load. `iy_cmds` joins the executable command registry
with IY's `CMDs` signature/description list by name or alias, retaining the first
description for a token and limiting descriptions to 120 bytes. Older engines
without `CMDs` retain name/alias/plugin output. Filtering and result limits remain
available.

`iy_players` is a read tool with no extra host capability requirement. It delegates
`selector` to IY's `getPlayer(selector, localPlayer)` and returns `{ names, count }`
alongside text limited to 50 names by default (maximum 200). Empty matches and
unavailable resolvers are explicit. Supported selector syntax follows the live
IY, including `all`, `others`, `me`, `random`, `#<n>`, `%<team>`, `allies`, `enemies`,
`team`, `nonteam`, `friends`, `nonfriends`, `guests`, `bacons`, `age<n>`, `nearest`,
`farthest`, `group<id>`, `alive`, `dead`, `rad<n>`, `cursor`, `npcs`, `+`/`-`, and
comma-separated lists. In the reviewed upstream version, `@name` matches username
prefixes without considering display names.

`iy_control` retains write permission for its combined inspect/edit surface.
Inspection sections are `all`, `events`, `keybinds`, `settings`, `aliases`, and
`waypoints`. Alias and waypoint sections expose 1-based indexes, `items`, `total`,
and `nextOffset`; malformed entries are labeled and still advance pagination.
Waypoint inspection includes coordinates, the place ID and the all-place count
when available.

The existing event/keybind actions and `stop_loops` are joined by:

- `alias_add`, `alias_remove`, `alias_clear`: validate command names and aliases,
  update both `aliases` and `customAlias`, refresh the native editor, and request
  IY's save. Adds use the first command token and reject unknown commands, duplicate
  aliases, native command collisions, whitespace and IY command delimiters.
- `waypoint_add`, `waypoint_remove`, `waypoint_clear`: validate names and finite
  coordinates, floor explicit or current-root coordinates, and update `WayPoints`
  plus `AllWaypoints`. Removal is case-insensitive and scoped to the current place,
  including legacy entries without a place ID. Clear defaults to the current place;
  `all_places=true` explicitly clears all saved places. Tables are cleared in place
  so native GUI references remain live. The buggy upstream coordinate command is
  not used.
- `configure` additionally accepts `gui_scale` (0.4–2) and `logs_webhook` (HTTP(S)
  URL or empty to disable). These use `guiscale` and `chatlogswebhook`, report
  asynchronous dispatch, and require saving because the native commands save
  themselves. `persist=false` remains available for direct native edits; mode
  changes alone continue to work without loading IY.

Batch tools use the existing `instance` and `fs` groups and the same permission
and capability checks as individual operations. Array schemas enforce `minItems`
and `maxItems` before dispatch; oversized arrays are rejected before visiting
their members.

- `instance_query` combines name/class/tag filters with up to 12 selected
  properties and 12 attributes. `instance_get_many` accepts up to 20 known paths
  with per-path failures. Fields are compact and bounded; bulk projections
  direct Source reads to `script_source`.
- `instance_find` and `instance_query` walk children incrementally, without
  allocating a whole descendant list. Scans stop as soon as a page fills, yield
  cooperatively, and inspect at most 20,000 nodes. Query offsets refer to the
  current traversal order; restart if the tree changes. An incomplete scan must
  never be presented as proof of absence.
- `file_find` discovers filename globs without reading contents. It uses the
  bounded directory inventory, sorted canonical paths and offset/limit pages;
  restart after files change. Incomplete inventory never proves absence.
- `file_search` searches single-line literals in the files scope or an explicit
  `pastes/` path, supporting
  filename globs and a case-sensitive option. Its inventory caps are 128
  directories, 1,000 files, and 6,000 entries. It skips binary files and files
  over 2 MB and scans at most 8 MB and 50,000 new lines per page. The read budget
  counts skipped data and is checked between whole-file reads: hosts expose no
  portable stat/range API, so the final read can exceed it. Returned cursors
  include a path, line, and (where available) direct byte offset. Continue with
  the same search; restart after source changes. Read errors and incomplete
  inventories appear in both text and structured results. Skipped binary or
  oversized files also make coverage incomplete.
- `file_read_many` accepts up to 12 files or saved pastes, each up to 2 MB. It
  shares the configured output budget, retains individual failures, and returns
  per-slice offsets plus a request index if the batch fills the page. Repeated
  slices and canonical path aliases reuse at most 2 MB of cached content within
  that call only. The default per-file slice is 6,000 bytes, reduced fairly to
  fit the shared budget.
- `file_edit_many` accepts 1–20 ordered exact edits to one workspace file. Each
  edit sees the previous edit's proposed result. Every match and size check must
  pass before rereading the original to check staleness and performing one write.
  An unchanged result performs no write. Original and resulting files are
  bounded to 2 MB. Cancellation before the write returns an aborted status.

Instance paths are parsed, never executed. Dotted paths continue to work;
JSON-quoted bracket segments preserve exact names, including punctuation and
surrounding whitespace. Known `Character`, `CurrentCamera`, and `PrimaryPart`
links can resolve when no named child exists. String property coercion preserves
whitespace, and scalar numeric coercion rejects nonfinite values.

### Script projects

The existing `coding` group also registers `project_scaffold`, `project_map`,
`project_patch`, `project_patch_read`, `project_patch_apply`,
`project_patch_restore`, `project_patch_discard`, `script_analyze`, `script_test`
and `project_build`. Runtime modules own project snapshots, lexical outlines and
proposals; tool modules own permission-aware execution and editor-draft checks.
See [docs/SCRIPT_PROJECTS.md](docs/SCRIPT_PROJECTS.md) for their public contract.

Version-1 JSON manifests explicitly map module IDs to relative source files,
declare an entry and optional tests. Sources remain under `files/`; paths reject
traversal and case aliases. Limits are 64 modules, 16 test modules, 256,000 bytes
per source, 1 MiB per project and 32,000 bytes per manifest/fixture JSON. Builds
produce deterministic editable bundles up to 256,000 bytes with source locations;
they compile without executing and cannot overwrite project inputs.

Project patches retain complete original/proposed bytes, require observed hashes
for existing files, preflight all targets and verify individual writes. Hashes are
conflict identifiers, not cryptographic proofs. Apply and restore refuse unsaved
bound Code drafts. Clean editor views keep their existing Save conflict detection.
Eight conversation-owned proposals/checkpoints retain at most 8 MiB (2 MiB each),
expire after ten minutes/unload, and never persist to disk. Writes are not atomic;
partial results retain recovery source. Restore refuses external or unverified
partial bytes and removes only files whose recorded current content still matches.

Analysis explicitly distinguishes host syntax compilation, lexical outlines and
literal dependency checks from unsupported type/API inference. Missing compilers
are reported; build/test require one. Lexical scanning caps at 50,000 tokens and
256 symbols/imports each, reports omissions, and treats interpolation as opaque.
Columns are byte positions. Literal cycles are conservatively rejected; shadowed
requires can produce false dependency reports. Bundled require resolves only
declared project IDs, memoizes false, converts nil to true and detects active cycles.

Outlines reuse exact source strings within 128 entries and 4 MiB of accounted
source/outline storage; callers receive detached data. Project syntax outcomes
reuse exact path/source and compiler identity within 128 records/2 MiB of source.
No compiled closures are retained. Saved bytes and dependency graphs are checked
again. Analysis exposes compiled/reused module counts and explicit incomplete
cancellation. Staged patch hashes are reused for metadata; full-byte guards remain
authoritative for apply and restore.

Test modules return named functions receiving assertions and fixture data. Each
case gets fresh module caches/fixtures, but native client state is shared. Tests
use the existing managed execution engine, high-impact permission, cancellation
and 1–60 second deadline, with at most 100 cases per run. They are not a security
sandbox, isolated process or native Roblox validation. Main and subagent prompts
describe review, build, output inspection and focused test/repair workflows.
`script_test.modules` restricts execution to distinct declared test IDs;
`filter` is a case-sensitive literal substring of case names. Skipped cases are
counted, fresh state is created for each executed case, and zero matching cases
is an incomplete failed run.

`script_workflow` records a conversation-owned goal with 1–16 acceptance criteria
and six stages: define, inspect, plan, build, validate and review. Advancement
requires stage evidence; completion requires evidence for every checked criterion
and a successful syntax receipt for the current source revision. A failed latest
test blocks validation. A later validation failure reopens validation, and known
source writes or editor source changes invalidate receipts and completed criteria.
Receipts capture the workflow identity/revision at dispatch start, so a late check
cannot validate work changed while it ran. The history retains at most 24 receipts.
Blocked goals retain their observed blocker; rewind and resume are explicit.
Goals persist with the existing conversation policy and credential storage.
Runtime workflow state never dispatches tools or imports the agent layer.

The native project wizard stages new files for complete source review before an
explicit Apply. A cancelled review preserves the form draft and discards its
untouched proposal; a partially applied checkpoint stays available for recovery.
Its original conversation/operation lifetime gates reads and writes.

## 6. Event stream

Ordinary conversation sends may queue follow-ups while inference or a tool batch
is running. One worker still owns each conversation. Up to 16 pending messages
(128,000 prepared text bytes) reserve their order before attachment preparation;
the loop consumes them only between complete assistant/tool exchanges. A final
assistant response continues when follow-ups remain, within the existing turn
and time budgets. A late terminal-event follow-up starts only after its prior
worker has settled. SDK request handles retain their busy-admission contract.

Queue receipts identify accepted messages. `message:queued`, `message:consumed`,
`message:removed` and `queue:state` report pending changes; `user` is emitted when
the message actually joins context. Stop, errors and exhausted budgets hold
unconsumed messages for explicit Resume or a later idle send. Preparing inputs
are cancelled with their composer draft retained. Prepared follow-ups in saved
conversations restore held; reload never starts inference. Attachment references
are revalidated before resuming. Queue review supports individual removal in
Roblox and the bridge; Stop is separate from Send. Pending inline text can be
edited with an expected-text guard, retaining its ID and attached images.
File-backed inputs preserve their verified references. Adjacent moves require the
observed neighbor ID and cannot overtake a preparing entry. Clear removes only
the reviewed IDs, preserving later arrivals. Queue snapshots advertise supported
operations; edits, moves and removals never interrupt active inference.

`agent/loop` never touches the interface. It emits into `agent/session`, which
fans out to subscribers. Every payload also carries `kind` and `at` (epoch ms),
stamped by `session.emit`.

| kind | payload |
| --- | --- |
| `user` | `{ text }` |
| `status` | `{ text }` |
| `turn:start` / `turn:end` | `{ turns, unlimited }` / `{ text }` |
| `request:start` | `{ provider, providerId, model, attempt, messages, stream }` |
| `request:retry` | `{ provider, attempt, attempts, status, wait, reason }` |
| `request:done` | `{ provider, model, ms, streamed, via }` or `{ provider, model, ms, error }` |
| `provider:switch` | `{ from, to, reason }` |
| `assistant:text` | `{ text, final }` |
| `assistant:reasoning` | `{ text }` |
| `tool:call` | `{ id, name, group, risk, arguments }` (arguments is the raw JSON string) |
| `tool:progress` | `{ id, name, text }` — scoped to its originating call |
| `tool:result` / `tool:error` | the dispatch result: `{ id, name, ok, text, ms, risk, group, args, error, full, truncated, data }` |
| `permission:ask` | `{ id, name, group, risk, description, args, resolve }` |
| `usage` | `{ session, turn }` — the two counter tables from `agent/usage` |
| `compact` | `{ summary, before, after }` |
| `subagent:start` | `{ id, call, label, task, preset, turns, budget, unlimited, depth, followUp }` |
| `subagent:status` / `subagent:text` | `{ id, call, label, text, bad? }` |
| `subagent:tool` / `subagent:tool:done` | `{ id, callId, name, risk, arguments, index }` / `{ …, ok, ms, summary }` |
| `subagent:done` | `{ id, ms, ok, aborted, messages, turns, resumable, text }` |
| `cleared` | `{}` |
| `error` | `{ message, fatal }` |
| `abort` | `{}` |

Parallel tool results are emitted as each call finishes. The batch still returns
results in the original call order for model context. A progress event without an
ID is rendered only when one call is open, so legacy emitters cannot overwrite the
status of unrelated parallel work. Failed and stopped turns restore Ready status.

The task list does not travel on this stream: `agent/state` owns it and publishes
`todosChanged(items, session)`, because the list outlives a turn and a panel opened
later has to be able to read it rather than replay it. The list itself lives on the
session (`session.todos`), so `setTodos`, `todoCounts`, `todoBlock` and `todoList`
all take the session they are about and the subscriber filters on the second
argument. A client-wide list is not an option: two conversations can run at once,
and one plan for both means a running turn resumes against somebody else's steps.

`agent/session.anyEvent` fires `(session, payload)` for every event of every
session. A surface that must answer a conversation nobody is looking at subscribes
there rather than to `session.events`; `ui/panels/permission` is the case that
requires it, since a prompt raised by a background conversation has to reach the
screen or its own deadline denies every call behind it. Subscribers must skip
`session.headless` -- a subagent's prompts are forwarded onto its parent's stream,
so the child's own copy is a duplicate.

Pending permission requests are per-session too. `permissions.request` records the
asking session on the entry, `denyAll(reason, session)` sweeps only that
conversation's prompts, and `pendingCount(session)` counts them. `denyAll()` with
no session still clears everything, which is what an unload wants.

Every dispatch is registered in `agent/subagent`: `records` (running first, finished
history capped at 24), the `changed` signal, `list`, `running`, `resumable`, `get`,
`find(reference)`, `stop(id)`, `stopAll` and `clearHistory`. A record carries `id,
label, task, preset, depth, parentId, parentTitle, startedAt, status, calls,
finishedCalls, tools, currentTool, statusText, ms, messages, runs, unlimited, report`,
the `parent` session currently waiting on it and the `callId` inside that session, and
the child `session` that `stop` sets `abortFlag` on. `status` is one of `queued`,
`running`, `done`, `stopped`, `failed`. A stop is noticed between steps, not on the
instant -- Luau cannot kill a thread.

The live monitor reads `currentTask`, `provider`, `model`, `request`, `preview`,
`latestText`, `latestReasoning` and `activity` from that same record. Text and
reasoning previews retain UTF-8-safe latest excerpts within 4 KiB each; truncation
is disclosed. Activity retains at most 24 call entries, preferring active calls,
with progress and result summaries bounded to 1 KiB each. Progress matches its
call ID; unscoped legacy progress applies only with one outstanding call.
Completion clears the current tool, and follow-ups reset the current activity.
The register and open Details monitors preserve their rows and coalesce changes
to at most ten refreshes per second; hidden registers suspend drawing. Closing
the view releases its subscriptions. Genuine transport previews appear when
delivered, while buffered HTTP cannot expose text before the response arrives.

A dispatch is a conversation, not a single question. The `dispatch_agent` and
`agent_followup` tools default to background work: register or reserve the child
synchronously, return its ID, then run it in an owned worker. `background=false`
retains blocking report delivery. Runtime `dispatch` and `followUp` stay blocking;
`start` and `startFollowUp` return the registered record immediately. Follow-up
reuses the child's existing context, and `runs` counts these turns.

The default `read` preset intersects its groups with an explicit read-risk tool
allowlist. It cannot acquire writes from a mixed group. Unknown preset names fail
before a child is registered. `agent_status` reports delegated workers;
`client_status` reports client diagnostics.

The parent continues independent work and calls `agent_status` every two or three
work batches or roughly 15–30 seconds. Status reads belong to its own children,
support optional waits of at most 30 seconds and UTF-8 report pagination, and never
put child context into the parent. Reading every report page contiguously through
the final page acknowledges that run, including after child context expires.
Live or uncollected background work in the current parent epoch prevents a prose
reply from being classified as final: an internal coordination reminder asks the
parent to continue work or collect the report. Ordinary step and time budgets
still apply. Positive bounded status waits may repeat; tight zero-wait polling
still meets the repeat breaker. Stop and all terminal parent exits stop unfinished
descendants. Preparation captures the parent epoch before scheduling, so a queued
worker cannot revive after Stop or adopt a later turn. Admissions and uncollected
reports are bounded; excess starts fail before creating a worker.

`parent` and `callId` live on the record rather than in a closure
because the turn asking a follow-up is a different tool call, possibly in a different
conversation, and the live card has to appear under the row the user is looking at
now. Only the newest `RESUMABLE` (6) finished records keep their `session`; past that
the record keeps its report and the context behind it is released, so `followUp`
refuses with a reason rather than resuming something that is no longer there.

`agent.subagentUnlimited` lifts a child's step limit and wall-clock budget and makes
an explicitly blocking dispatch wait as long as the child takes. Background work
still belongs to its parent turn. The setting is separate from
`agent.unlimitedTurns`, which the loop applies only to a session with no step budget
of its own: the dispatcher passes its decision down as `session.unlimited`, so a
delegated child is lifted only when that has been asked for in those words. What
still bounds a child either way: the repeat breaker, each tool's own timeout, the
provider retry cap, the depth and concurrency ceilings, and Stop.

`agent/transcript` owns each session's bounded, chronological `session.log`.
Dialogue/notices have 512 events within 1 MiB; subagent start/report records have
128 events within 256 KiB; detailed activity has 256 events within 256 KiB.
Activity cannot spend the dialogue budget. Calls/results and dispatch start/report
records are evicted as groups, preferring completed work; removing a dispatch
also removes its dependent activity. Limits still apply to hosts that never finish
their calls. Fields are bounded, UTF-8-safe primitives; callbacks and result graphs
are excluded. Pending progress is coalesced separately and released on completion.

Persistence writes the same snapshot plus versioned omission/recovery metadata;
it does not apply a second FIFO that discards the protected dialogue. Legacy files
recover missing prose still present in saved model context, preserving repeated
prompts and avoiding duplicated overlap. Text already lost from both stores cannot
be reconstructed. Modern intentional retention limits are not undone by recovery.

The transcript subscribes before taking its replay snapshot and renders at most
12 events or approximately 6 ms per scheduled slice. Durable events arriving during
replay queue in order; current preview/progress is reconciled afterward. Generations
cancel work on switch, clear and destruction. Completed replay buffers and expired
GUI rows are released; dialogue uses measured spacers and mounts only nearby
message/Markdown chunks in batches of up to four, yielding between batches.
Visible chunks take priority over prefetch. A bounded warm set keeps nearby
renderers for backtracking; scroll-only passes reuse the sibling geometry index.
An upward scroll releases follow immediately, and reflow preserves the visible
Markdown chunk inside a long reply when that chunk remains mounted. New replies
below the reader appear in the Latest control without taking their position.
Tool activity starts as a compact summary with running, completed and failed
counts. Opening details is a reading action: the header stays anchored and results
never change the reader's chosen disclosure state. Tool inputs and outputs render
on demand. Delegated tasks keep their goal, status and report separate from their
folded activity, with stable row identities for retention and incremental replay.
Hidden/minimized views suspend drawing and retain their bounded renderer cache,
live preview, expanded sections and reading anchor. Returning from native tabs or
minimize queues only unseen events; unchanged history takes no replay slices and
does not rebuild its text. Session switches, clear and destruction release the
appropriate content. Retained nested agents survive removal of a dispatch row.
History notices disclose retention/recovery. Reading position and follow preference
are session-local, with a measured message anchor when available. **Refresh
conversation** redraws the view without changing the session or composer draft.
Calls without a saved outcome stop spinning on idle restore and state that no result
was kept. Conversation search includes retained dialogue after model compaction.

## 6a. What is counted, and where

`agent/stats` is the only place a figure the interface displays as a statistic
comes from. It observes the stream through the `onEvent` hook and the
`usage.recorded` signal, buckets everything by local day and local hour, and
persists to `stats.json`.

Per-key and per-conversation request counters observe actual inference dispatches
through `runtime/request_accounting`. Native retries and protocol/key/provider
fallbacks count separately; relay submission retries for the same inference job
count once. Model discovery, connection health checks and relay polling do not
count; synthetic inference probes count toward their key, without a conversation.
Failed requests count if dispatched; rejected preparation and cancellation before
dispatch do not. A subagent's attribution is captured from its parent before dispatch.
These local counters persist from their tracking start; past requests are not
inferred from transcript length. The chat header and context breakdown show the
conversation total, independent of the currently active provider.

Per-key records use provider ID plus opaque key ID, never credential strings or
key names. Input and output usage are credited once from normalized provider
counts, with labelled estimates filling missing fields when available. UI reads
these counters and their change signal through the `agent/session` facade; usage
refreshes update existing labels without rebuilding key drafts or prompts.

Anthropic input accounting includes uncached, cache-read and cache-creation
tokens; all occupy context. Price estimates retain their documented approximation
and do not claim cache-discount billing accuracy. Reload restores persisted
lifetime model first/last-use dates and hour totals as well as current buckets.

* A number is recorded or it is absent. Nothing is modelled, sampled or
  interpolated, and no surface may compute a headline figure of its own.
* Tokens are counted from the first request this store ever sees. There is no
  history to recover -- `agent/usage` has always been in-memory -- and an
  estimate would be a figure with no measurement behind it.
* Messages and conversations *are* recovered once, on the first run, from the
  real timestamps in the transcripts already on disk.
* A subagent's requests and tokens count toward the conversation that dispatched
  it; its messages do not, because nobody typed or read them.
* Buckets are local, via `runtime/clock`: `dayKey`, `hourOf`, `dayNumber`. The
  conversion is arithmetic on the epoch plus this host's UTC offset, probed once
  from `DateTime`, because Roblox's pattern formatter is the only calendar API
  and its pattern support differs between client versions.

Persisted files, all under one folder (`env.info.folder`, default `UAI/`):

| file | written by | holds |
| --- | --- | --- |
| `config.json` | `runtime/config` | every setting, the provider list, permission rules, memory |
| `sessions/<id>.json` | `agent/session` | one conversation: context, transcript, title, place and timestamps; newest 64 restored, older disk history retained |
| `sessions/.folders.1.json`, `.folders.2.json` | `runtime/conversation_folders` | alternating verified custom-folder catalogs; names, stable IDs and revision |
| `stats.json` | `agent/stats` | per-day and per-model counters; days capped at 400 |
| `export/*.json` | the Import & export pane | a diagnostic settings copy with connection credentials excluded; review remaining personal text before sharing |

## 7. Design tokens

Conversation organization is independent from execution context. Sessions retain
their recorded place and policy when moved into Universal or a custom folder.
`agent/session` exposes `folders`, `groups`, `folderLabel`, `createFolder`,
`renameFolder`, `removeFolder`, and `moveToFolder`; creation accepts `folderId`.
Legacy saves use their recorded game. Removing a custom folder preserves chats,
including archived memberships, which resolve to Universal without rewriting
archived or unsupported-policy files. Up to 64 custom folders have unique names
of at most 120 UTF-8 bytes. Unreadable or future-format catalogs block edits;
an intact older snapshot can recover a damaged newer snapshot.

No use site writes a raw colour or number. `ui/theme` exposes `theme.color.*`,
`theme.text.*` (role -> size/font/lineHeight/height), `theme.space.*`,
`theme.size.*`, `theme.radius.*`, `theme.stroke.*`, `theme.opacity.*`,
`theme.scale.*`, `theme.motion.*`, `theme.z.*`. `ui/responsive` reports the active
breakpoint and layout mode from the live viewport, so a window that opens on a
phone and is then rotated re-lays-out rather than keeping whatever was true at
boot; it holds no metrics of its own.

The palette is one warm neutral ramp of twelve steps plus one accent. Surfaces are
separated by two or three steps of lightness and a hairline, never by a shadow or a
heavy fill; the code surface sits *below* the canvas rather than above it -- except
under the light code palette, which inverts that pair deliberately and separates the
block from the page with its own border instead. The accent is reserved for meaning
-- inline code, a running turn, a risk level -- and the single loud control per view
is `color.solid`, a cream fill with dark text, which is deliberately not the accent.
`test/run.lua` computes WCAG contrast over every pair the interface actually puts
together, for every accent and every code palette, and fails the build under 4.5:1
for text, so a token cannot be retuned into something unreadable.

Four token groups are settings rather than constants, and each has to change what
is on screen or it is decoration:

| setting | token | effect |
| --- | --- | --- |
| `ui.interfaceFont` | every non-mono `theme.text.*.font` and `.face` | the family the interface is set in |
| `ui.codeFont` | `theme.text.mono`, `theme.text.monoSmall`, `theme.codeFontEnumName` | the family code is set in, fenced and inline |
| `ui.codeTheme` | `color.codeSurface`, `codeBar`, `codeText`, `codeGutter`, `codeAdd*`, `codeRemove*` | a light or dark code palette, in the transcript as well as the preview |
| `ui.transcriptWidth` | `size.reading` | how wide the transcript and composer columns grow |

Type resolves in two layers. `theme.text.<role>.font` is an `Enum.Font` and always
takes; `.face` is a `FontFace` carrying the family plus an independent weight, and
`P.text` layers it over the enum only when the client produced one -- so `strong` is a
real SemiBold where the modern type stack exists and degrades to the family's legacy
medium where it does not. The family list is *discovered*: each candidate is read back
off the engine with `Font.fromEnum` and dropped when the member is absent, so a name
this client cannot load can never be offered. A hardcoded `rbxasset://fonts/families`
path has the opposite failure mode -- it constructs fine and renders nothing.

A clickable row uses `P.rowButton`: the button *is* the row and the layout goes
inside it. A transparent full-size button dropped in beside a row's contents does
not layer over them -- a `UIListLayout` gives it a slot of its own and pushes them
past the row's edge, where they are still drawn because nothing clips them.

The window root is a plain `Frame` on every device. Large transcripts do not depend
on a CanvasGroup's offscreen texture allocation, resolution or fade state. The
shell has no entrance `UIScale`; hide/show is synchronous. Centered dimensions
retain whole-pixel parity through `handle.centred`. Maximize changes geometry and
its icon in place, keeping the transcript, live preview, focus and drafts mounted.

Modal cards, the settings dialog and Quick Chat use bounded, unscaled CanvasGroups
that fade as a unit at their final geometry. Modals reveal after the caller fills
their content and the first layout pass settles. Their entrances and exits never
tween size, position or text metrics. Replacements release the outgoing surface;
Quick Chat reverses its current fade without flashing or losing its draft. Client
animations are permanently enabled. The retired `ui.reduceMotion` setting is
removed from settings, bridge commands and configuration transfer; legacy values
are discarded. The main window and transcript remain plain frames. The standalone
UI LIB and browser system accessibility preferences remain independently owned.

Shared modal bodies use balanced vertical padding and consistent horizontal
insets. Log details and the context breakdown fit their current contents up to
the usable viewport height, scrolling when needed instead of reserving blank space.

The transcript canvas uses `UIListLayout.AbsoluteContentSize` plus vertical padding.
Lightweight spacers preserve the measured size of unmounted dialogue. Drawing
work is bounded independently of the retained event count, and data retention
does not depend on the visibility of the window.
Transient zero measurements during hidden/resizing states do not erase a populated
canvas. Geometry changes preserve follow intent and restore a measured reading
anchor instead of forcing the reader to the newest row. Markdown replacements are
built before old content is released; a failed block falls back to readable text.

Breakpoints: `xs < 520`, `sm < 900`, `md < 1280`, `lg < 1700`, `xl`. Layout modes:
`sheet` (xs), `panel` (sm, touch-only input, and any portrait orientation), `window` (md+), plus `tv`
when `GuiService:IsTenFootInterface()`. These modes control placement and bounds;
phones use the same application components and navigation as desktop. Handheld
layout metrics use 55% of desktop dimensions, spacing and radii before user
density settings. Handheld text has a 10px baseline minimum before the user's
text scale; the mobile sidebar uses dedicated 9px navigation roles while keeping
its control sizes. Standard icons have a 12px minimum to retain their strokes.
Controls have a 15px minimum on handhelds, 28px
with a pointer and 48px on a console. Native dimensions are reduced directly;
the application is not resampled through a UIScale.

Control, row, tab and status heights also reserve their text line boxes when
large type and compact density are combined. Compact multiline fields reduce
their vertical inset as needed to keep the first line readable, preserving the
same field, draft and selection through expansion and keyboard changes.

The model and saved-provider pickers use 40px touch targets for their primary
controls and may use more available vertical space for the catalogue. This
does not reposition or rescale the main window. The model catalogue always has
its own scrolling viewport; provider, search and footer controls stay fixed.
Short layouts reserve the reasoning level buttons before compacting provider
details and the catalogue, omitting the effort caption when needed. Only keyboard
space too small for search, a model row and the levels moves effort into Options;
the free filter also remains available there. The original
search field, selection and catalogue position survive these layout changes.
Catalogue modals use the shared modal's `pinFooter` option to keep actions out
of the body scroll. Other forms retain the normal scrolling-footer fallback.

The shared header retains its brand, detail and Minimize/Maximise/Close actions.
The shared welcome view, composer, Quick Chat, Code tabs and document tabs remain
present, including the normal sidebar. Its collapse control and regular app menu
remain available. Settings categories and provider lists use their normal
column or horizontally scrolling strip according to the available width. Menus
use the same anchored, bounded, scrolling presentation on every device.

Ordinary handheld typing stays compact until explicitly expanded. In short
keyboard space, the same multiline input contracts without replacing its native
field or changing its draft. Quick Chat retains its field, draft and selection
on rotation, and mobile Return inserts a newline. Slider gestures wait for
horizontal intent, so vertical page swipes cannot alter values. Code, table and
reasoning scroll areas account for keyboard-obstructed height. Settings
categories retain live fields and their individual scroll positions.
Short Code surfaces scroll the original composition as a whole; controls stay
mounted in their normal rows instead of moving into separate mobile menus.

The Discord invitation is an app-owned optional modal. Automatic display requires
five minutes since mounting and 30 seconds of idle time in a visible focused
Chat/Home view, with no draft, focused field, other overlay, scrolled-back chat,
keyboard or active request. Busy transitions and window focus changes reset idle
time. Persisted cooldown is 14 days, with at most one display per loaded client.
Dismissal keeps the cooldown; opting out or successfully copying the invite
disables reminders. Manual menu access stays available. A hidden normal window
does not qualify for automatic display; screen destruction and runtime disposal
release the watcher.

The introduction is an app-owned modal. It opens once when the mounted window
is visible and enabled, deferring while an overlay, focused text field or request
is active. Showing it marks it seen; a manual open also consumes a pending
automatic introduction. Tutorial in the profile menu reopens it from the start.
Back and Next move through six pages in a fitted, scrolling card with compact
progress and navigation. Chat and Providers actions open those panels without
sending a request or changing the selected conversation; Discord and donation
actions open the existing dialogs. A hidden normal window defers display. Screen
destruction and runtime disposal cancel pending automatic display.

Dismissal hit targets surround modal and menu cards without covering their
interiors, including empty form space. Closing Add provider retains an unsaved
draft in memory for this client session, including protocol and authentication
choices. Start over clears it, and successful Save consumes it. Existing-record
edits remain isolated from the Add draft.

The player profile menu has a branded ProjectUAI entry alongside the existing
What's New entry. Its project/support modal opens the official repository on an
explicit Star us on GitHub action, falling back to a copied or selectable URL
when the host denies browser access. Both entry and modal reuse the frame-drawn
brand mark. Viewing it does not mark release notes read.

UI LIB retains its existing per-window Light/Dark token palettes and live bindings.
Its built-in header mode icon, `GetTheme` and `ToggleTheme` use `SetTheme`;
`ThemeToggle=false` permits a script's existing theme control. Configuration
profiles optionally retain mode and custom accent, with validation before any
changes and compatibility with earlier profiles. Custom accent foregrounds use
linear sRGB contrast. Theme switching preserves controls, drafts, and layout.
The appearance contract also includes Palette (`Neutral`, `Graphite`, `Ocean`,
`Forest`, `Rose`), Contrast (`Standard`, `High`), Density (`Comfortable`, `Compact`,
`Spacious`), Shape (`Rounded`/8, `Soft`/14, `Square`/0 or custom `CornerRadius`),
Typography (`Sans`, `System`, `Mono`) and TabHeader (`Simple`, `Detailed`, `Hidden`).
Neutral and Simple are defaults. `GetAppearance`/`SetAppearance` update semantic
settings; `GetAppearanceOptions` and `GetPalette` return copied values.
Configuration remains version 1, and omitted new fields retain current choices.

On touch devices, Enter inserts a newline; only Send submits. Attachments use the
shared wrapping scroll region, with management available from Message options
when keyboard space hides their preview.
Rotation relays out existing views without replacing their text fields,
selections or live forms. Collapsing the sidebar does not rebuild the window or
transcript. The shared conversation search opens a matching chat directly;
conversation management remains in the sidebar and app menu. The
mobile launcher is visible only while the main window is minimized.

`runtime/command_catalog` and `runtime/shortcuts` own search and key policy;
`ui/commands` presents actions, settings and up to 64 loaded conversation titles.
Ctrl+K opens commands, Ctrl+Shift+P searches dialogue, Ctrl+, opens settings and
Ctrl+L focuses the composer. Only a visible, unlocked window with no focused
field, handled input or other overlay accepts these shortcuts. Command Up/Down
and Enter operate on the selected result; touch has the same row actions.
Window destruction/unload releases its global listener. Conversation search
reveals matches in pages of 12, keeps UTF-8 excerpt boundaries, and excludes
system/tool context from fallback dialogue results.

Code tabs retain drafts when closed and offer bounded recent reopening (20 views)
and cycling without recreating source documents. Reentrant selection callbacks
cannot consume the wrong history entry or overwrite a newer source selection.
Explicit line transforms use UTF-8 byte boundaries and undo checkpoints; go-to
positions use code-point columns. Reload from disk refuses dirty drafts and
rechecks document revision and file-binding ownership after a yielded read.
Observers saving another file during reload retain their newer binding.

`runtime/transcript_export` freezes retained user/assistant dialogue as Markdown
when its export dialog opens. Tool results/arguments, reasoning and request
internals are excluded. Output is capped at 1 MiB between whole messages with an
omission notice; the UI preview is capped separately at 12,000 bytes. Copy uses
the host clipboard result; Save chooses a new scoped filename and verifies bytes
before reporting success. Repeated Save after success does not duplicate the file.
Conversation exports are readable files, not credential-vault encrypted payloads.

`runtime/clipboard.write` recognizes native exceptions and explicit false returns
as failures without logging payload-bearing host errors. Nil is a valid executor
success result; no portable clipboard readback exists.

Sheets, panels and desktop windows can all be moved. Default desktop placement
avoids CoreGui's top bar, but dragging and restoring a chosen position use the full
device-safe parent, measured through a transparent frame inside the ScreenGui.
The top-bar inset is not a physical obstruction across that whole parent. Geometry
is recorded on release, separately in `ui.window`, `ui.mobilePanel` and
`ui.mobileSheet`; maximised or keyboard-constrained sizes never overwrite a normal
placement. Keyboard dismissal restores it. Header controls do not initiate drags,
and each gesture continues to follow only the input that began it.

Mobile geometry is keyed by orientation, including tablets whose portrait and
landscape modes are both `panel`. A forced mobile `window` layout still uses mobile
geometry. Auto retains its compact placement; explicit Sheet, Panel and Window
use bottom, right and centred placement, respectively. Explicit mode placements
are stored under `ui.mobileSheet.layouts.<mode>` or
`ui.mobilePanel.layouts.<mode>` for the current orientation, keeping Auto and
desktop placements intact. Keyboard positioning uses the reported top edge when available, and
focused mobile fields are revealed through their scrolling ancestors. Desktop
geometry and pointer layouts retain their existing behavior.

When a mobile keyboard leaves too little height for a form, its footer actions
join the body scroll region at their configured control size. Dismissal remains
available; keyboard dismissal restores the pinned footer and preserves the fields. Focus
reveal accounts for clipping ancestors and the keyboard edge without repeating
the displacement of an inner scroller. Shared conversation search includes
folder names; create, move and manage flows remain available from the app menu.

Profile avatars start with a readable initial behind a renderable image. A deferred
worker resolves a ready headshot through `Players:GetUserThumbnailAsync` and calls
`ContentProvider:PreloadAsync`, retrying up to three times. It checks `IsLoaded`
after preloading as well as on property changes. Destroying the avatar invalidates
its results without cancelling a coroutine inside a native thumbnail or preload
request. The request finishes naturally and no longer updates the destroyed view;
failed loads retain the initial without blocking UI construction.

The minimize/restore launcher uses parent-relative offsets and a fixed anchor,
preserving the pointer's grab offset after its 6px drag threshold. Only the
initiating mouse/touch controls a gesture. Dragged, cancelled and ignored inputs
cannot activate the button; focus loss, destruction and rebuild release gesture,
service and layout listeners. Placement is saved on drag release, clamped within
the usable viewport, and restored after temporary keyboard or viewport changes.

The Code workspace is owned by `runtime/code_store` and composed in
`ui/panels/code`. Editor, Files, Explorer, Remotes, Output, History, Library and Game changes
are destinations within Code. Layout follows the available panel rectangle. Native
TextBox editing owns source input, selection and IME; escaped line-state syntax
highlighting, a visible caret, virtual labels and an independent gutter remain
available during ordinary editing. Syntax labels remain visible while dragging
or selecting a range; bounded selection fills follow the native TextBox's byte
endpoints without switching to its full-document text renderer. Native multiline
font probes calibrate editor and preview line advances without accumulated
rounded-height drift. Cursor-follow
scrolling yields to pointer selection. Source
remains raw and unwrapped. Enter inserts a newline; Run is explicit.

Documents have stable IDs, monotonic revisions and distinct open-view state. They
are loaded once and shared immediately with tools before delayed disk saves.
Closing a view retains its document. Two verified snapshots in reserved `code/`
store documents, versions, proposals, action snapshots and small preferences.
Legacy files are retained; damaged snapshots are copied to verified recovery files
before replacement. Unreadable or future-format data prevents overwriting. Failed
saves retain live drafts and report status. Build replacement preflight protects
pending Code work. Limits are 50 documents, 10 open views, 256,000 UTF-8
bytes per editable source, 12 versions per document within 4 MiB of source history,
50 actions and three proposals per document. The serialized envelope is capped at
12 MiB; an oversized envelope preserves live source and reports a save failure.
Larger inspected source, up to 2 MiB, uses a bounded snapshot reader; opening it
does not create temporary files. Explicit exports retain verified file behavior.

`runtime/script_sources` is the shared source/decompile service. Results carry
instance identity/path, runtime epoch, method/origin, status, byte count, capture
time, content hash, read-only state and diagnostics. Empty source is successful;
unavailable objects, unsupported classes, missing/failed decompilers, expired or
stale requests, invalid text and oversized source have distinct structured errors.
Per-instance capability reads do not decompile. Only explicit requests spawn
decompile workers (maximum four, 15-second waiter deadline), deduplicated by target,
method and generation. Late, cancelled and old-runtime results are discarded.
Fallbacks begin only while at least one reader remains active. Native output is
validated before luacid and ByteFall are considered; unusable output cannot block
a working fallback. Both external adapters cap bytecode at 2 MiB and omit raw
service errors. Luacid installs into a private environment and shares this
service's cache, so explicit Refresh can make a new service request. Native
transport continuations retain their worker slots until they return.
Completed snapshots retain at most eight items/8 MiB with a five-minute TTL; a
visible source view pins its snapshot and hiding/destroying the view releases it.
Host-readable and decompiled documents remain read-only across persistence and
cannot run, accept proposals or become actions until extracted into a separate
editable document. No inspected source is a live binding or automatic write-back.

Shared UTF-8 utilities use one-based byte offsets, exclusive range ends and code
point status columns, not UTF-16 or grapheme-cluster columns. Search and slicing
preserve code-point boundaries. Case folding is ASCII; whole-word classification
treats letters/digits/underscore and non-ASCII bytes as word constituents, without
Unicode linguistic segmentation. Combining characters are not grapheme-aware. Shifted
unchanged lines reuse syntax spans and measurements; multiline lexical state
invalidates dependent lines. TextBox updates still receive the bounded full string.
Drawing pools at most 160 rows, measures long lines in 2 KiB chunks and clips
horizontal syntax windows. Search offers counts/current match, overlays, case and
whole-word options, with a 10,000-match retention limit. Full-snapshot large-source
search can find matches across 6,000-byte display pages.

Storage exposes Saving, Saved, Retry required, Conflict and expired-source states.
An owned partial write can be retried; external modifications are not overwritten.
Typing publishes revision metadata without copying whole documents into events.

Source history is distinct from native TextBox Undo and Game changes. Restore and
proposal application guard source revisions. Actions retain immutable executable
snapshots; updates guard both action and source revisions. Up to 12 named
string/number/boolean/choice inputs are passed as data in `local inputs = ...`.
`tools/code_runner` calls the existing managed execution engine with one manual
workspace run at a time; agent concurrency is unchanged. Retained output identifies
the run/document/revision. `tools/execution.runOperation` manages native calls
without a compiler and reports still-outstanding dispatched calls after timeout or
Stop, never retrying them or claiming to roll back server effects.

`instance_refs`, `instance_fields`, `instance_schema`, `instance_scan`,
`instance_edits` and `changes` serve Explorer and the instance tools. Epoch-scoped
weak identities survive rename/reparent, with bounded pins and stale detection.
Paths reject duplicate-name ambiguity. Supported properties come from a bundled
curated catalog; actual protected reads/writes remain authoritative. Typed edits
preflight expected values, read back engine values, record observed changes and
conditionally recover partial failures. Undo checks every current recorded value
before writing. Tags and hierarchy operations are outside initial Undo coverage.
Edits report local observations, without a server replication guarantee.

Explorer tracks up to 64 branches, searches cooperatively within 20,000 nodes and
returns bounded snapshot cursors. Child enumeration caps at 20,000 children per
branch; UI pages cap at 4,000 rows, and reveal caps at 64 ancestor levels. Counts
separate returned, omitted, filtered and unreadable results and mark unknown totals.
At most eight search snapshots remain; cancelled queries cannot publish shared
state. Runtime services own page merging and query IDs/generations. UI rows are
pooled. Selection is capped at 20
objects and field batches at 100 operations. Drafts survive live updates and view
rebuilds. Create/duplicate/move/detach/delete use exact targets, expected parents and
normalized selections, with the Inspector's epoch, revision, IDs and primary target.
Clicked, focused, primary and selected identities are distinct; selection also has
an anchor and mode. Stale or ambiguous hierarchy actions fail before writing.
Source is a provenance-labelled snapshot, never a live
write-through editor. Nil roots, bookmarks and world picking are explicit. Metadata
export is verified and bounded; no full-map or unverified saveinstance adapter exists.

`runtime/values` supplies packed graphs with exact nil positions, typed Roblox
values, binary encoding and bounded cycle/alias inspection. Unsupported, incomplete,
opaque or cyclic/sparse graphs remain inspectable but cannot replay. `remote_capture`,
`remote_store` and `remote_hooks` own explicit capture sessions independently of GUI.
Imports/schema/state reads install no hooks and send no traffic. Outgoing hooks use
reusable neutral forwarding cells and owned detached routing probes; intercepted
Invoke outcomes have separate unverified coverage. Incoming capture uses events
only, never replaces function callbacks. `hooked_unknown` is the default outgoing
attribution unless verified. Probes do not invoke the predecessor; host network
behavior is not guaranteed. Stop reports whether an inert forwarding wrapper remains.

Capture holds at most 1,000 records within 4 MiB, 128 pending outcomes, 2,048 incoming
subscriptions, 10 pins within an additional 1 MiB, and 32 KiB per typed graph
(16 KiB per string, 256 slots/table nodes, depth 12, 1,024 values). Summaries report
omissions/eviction gaps; details/bytes paginate. View filters, admission filters and
exact-target blocking rules are separate. Pause stops recording; Stop also disarms
rules. Native and tool Start default to 30 seconds; persistence is explicit. The UI
requires a selected remote by default; all-game and subtree capture are explicit.
Private queue eviction preserves public ordering, cursor gaps, pins and late
completion handling. Summary and byte reads avoid copying unrequested graphs;
returned mutable detail sections remain detached from retained records.
One target resolver validates the displayed Explorer selection and its primary.
Permission/group/session revocation removes
agent-owned behavior. Capture survives navigation/minimize with a launcher indicator;
unload/reset disarms it. Visible capture/property refresh is coalesced to 10 Hz.

Replay prepares a five-minute immutable plan with target, packed arguments, source
revision, rule revision and digest, then dispatches at most once. Generated bound
source uses expiring runtime bindings; portable snippets resolve explicit paths and
reject ambiguity. Copy/export of portable scripts requires a current source-review
digest. Incoming records expose diagnostics, caller inspection/source and metadata
export; only outgoing records expose replay and editable replay arguments. Caller
identity is captured in hooks, but resolution and source/decompile happen afterward.
Source provenance and bounded name/path text matches accompany exported captures;
these matches suggest call sites without proving them. Opening/importing source
never runs it. Late Invoke completion recalculates both ring and pin byte budgets.
Export freezes records and the maximum sequence before paging, so concurrent
arrivals and completions cannot change the exported snapshot. Reconfiguration
failure explicitly reports that the prior session stopped. Explicit exports use
unique scoped destinations, verified parts and a completion manifest. Imported
captures remain offline until explicit current-target rebinding. Tool summaries and
structured data share a roughly 6,000-byte budget with retained detail pages for
larger operation results.

The Code workspace was introduced in version 1.7.0; the native reliability, chat
and provider improvements ship in 1.8.0. [NATIVE_CLIENT.md](docs/NATIVE_CLIENT.md) is the current
native feature and limitation reference. Native input, touch/gamepad,
executor forwarding/coexistence and performance need the client scenarios in
`docs/CODE_WORKSPACE_TESTING.md`. Historical files in `archive/` are references only.

## 8. Build and verification

Audit changed source, documentation, examples, tests and build inputs before
building. Rebuild changed client source with `luajit tools/bundle.lua --native`,
inspect the generated bundle/manifest/reference outputs, then run only focused
checks justified by the change. Review each fix before rebuilding affected
outputs and rerunning affected checks. Use native static checks, deterministic
freshness checks and the official Luau compiler where applicable.

The 3.3.0 plan and actual outcomes belong in
[docs/TESTING_3.3.0.md](docs/TESTING_3.3.0.md). The entire native suite is not part
of that release pass. `tools/test_native.js --verify-only` is a separate full-suite
workflow, not a substitute for selected checks. The broader command reference
below includes independent product/site workflows; it does not require running
them for every client change. Offline verification measures behavior and syntax,
not native Roblox rendering, host input, live model quality or native performance.

```
luajit tools/bundle.lua --native # src/ -> dist/uai.lua and module manifest
luajit tools/bundle.lua --native --check # read-only deterministic freshness
luajit test/check.lua --native # lint, parse and link native modules
luajit test/code_workspace.lua # shared source/history/actions and UI fixtures
luajit test/native_workspace.lua # identities, typed edits, capture/replay
luajit test/run.lua --native # load dist/uai.lua against the mock client, native scenarios
luajit test/iy_control.lua   # IY selectors, native configuration and plugin contracts
luajit test/tool_workflows.lua # batch tools, pagination, scopes, cancellation
luajit test/attachments.lua    # exact saved inputs, compact payloads, upload recovery
luajit test/gravity.lua        # live adapter and plugin registration contracts
luajit test/execution_tools.lua # managed execution and released callback cancellation
node bridge/tests/run.js
node bridge/tests/run.js --browser-only # requires external Playwright
node tools/build_site.js      # actual tool catalog and root/docs site copies
node tools/build_site.js --check
python test/site_static.py    # structural checks; no browser or image loading
node test/site_browser.js     # responsive site behavior; requires external Playwright
```

For browser checks, install Playwright and Chromium outside the repository and
set `PLAYWRIGHT_MODULE` to the absolute Playwright package directory (for example,
`$env:PLAYWRIGHT_MODULE = 'C:\path\to\node_modules\playwright'` in PowerShell).
`UAI_SCREENSHOTS` optionally saves website review images.

Authenticated bridge contact automatically selects Web runtime; disconnect
restores Game for subsequent requests. Active Cowork inference has no overall
request time limit in the client or bridge. The retired `bridge.requestTimeout`
setting is stripped from saved/imported configurations and cannot be edited.
Individual executor polling calls remain bounded to five seconds; lost receipts
reuse the original job ID. Stop, unload, changed credentials and actual provider
failures remain terminal. Providers may impose their own upstream limits.

Updated bridges advertise `capabilities.inferencePreview = {schema:1}`. Native
Cowork requests with a preview callback poll `/api/inference/<id>?after=<cursor>`
at the existing roughly one-second cadence. Running receipts return bounded,
ordered text/reasoning pages from the real provider stream; cursor deduplication
prevents repeated fragments. Gaps or clipped pages freeze a labelled preview
until the final result. Completed receipts retain the exact raw provider body,
without duplicate preview payload. Old bridges and the companion keep their
existing completed-body exchange. No provider inference is replayed for previews.
Up to 16 relay waiters are accounted separately from the eight native HTTP
connection slots. Bridge control and result polls may wait for an available
native slot within their individual call budget. A timed-out native call still
owns its slot until it returns; a waiting relay job owns no native slot between
polls. Each job's short exchanges share native ownership: a timed-out exchange
must return before another submission/result poll can dispatch for that job.
Waiting stays within each exchange's deadline and Stop can independently send
cancellation. Local admission failures remain terminal and identify capacity, not a
provider timeout.

The bridge's protocol, installation, browser workflow and verification are
documented in [bridge/README.md](bridge/README.md). Executor downloads start with
`node UAI/bridge/start.txt`; Git checkouts use `node bridge/server.js`. Bridge test
fixtures and helpers live under `bridge/tests/` and are excluded from downloads.

### Obsidian vaults

Authenticated bridge routes `/api/vaults` and `/api/vaults/config` serve local
Markdown vaults. User configuration connects up to 16 absolute folders and
controls read-only policy; agents cannot configure roots or enable writes.
Agent-facing listings omit absolute paths. Configuration is persisted on the
bridge computer, separate from executor configuration and credential storage.

Notes are UTF-8 `.md` files up to 1 MiB. Paths reject traversal, hidden components,
reserved Windows names and linked files/folders. Reads paginate on UTF-8 boundaries
and expose SHA-256 revisions. Create refuses existing notes; update/append require
the exact read revision and verify saved bytes. A stale or uncertain write is
terminal and never automatically retried. Native and browser views retain drafts
when a save cannot be confirmed. Disconnecting a vault removes its configuration,
not its files. Search/backlinks have bounded discovery and explicit incomplete
coverage; metadata is a bounded subset of Markdown/frontmatter, not a YAML engine.

`runtime/obsidian` holds pure path/paging contracts, `net/obsidian` owns authenticated
loopback requests and connection epochs, and `tools/obsidian` exposes operations
through the normal permission/scope dispatcher. Notes read by the agent enter its
conversation with the selected provider. The native settings pane owns connections
and opens Browse notes for connected vaults. Native and browser surfaces provide
folder/text filters, paged listings, note creation, metadata, outgoing links,
backlinks and a complete Markdown editor. No companion routes are added.

Native complete reads bind revision, size, byte offsets and eof across at most
90 pages/1 MiB. Editing preserves existing CRLF. Save explicitly creates or
updates once and validates returned path/revision/byte count. A failed or
unconfirmed save blocks another Save until Read current file completes a review.
Keep draft adopts the reviewed revision for a later explicit Save; Use file
discards local text. Neither review choice writes. Closed unsaved or uncertain
drafts stay only in memory, at most eight; the ninth is refused without eviction.
Each draft has one modal owner, and unload clears all drafts without executor
recovery files. Read-only notes disable editing and Save.
See [Obsidian](docs/OBSIDIAN.md) and [its API](docs/OBSIDIAN_API.md).

The separate Windows launcher in `desktop/` embeds its bridge/client/license
payload in one executable and verifies it into a private user cache. It detects
Node.js 18+ or offers an official, checksum-verified LTS installation per user.
Desktop release updates verify executable bytes and stage them for the next
app restart, preserving the original executable and a working fallback.
Its native dashboard persists OpenCode, MCP, browser-open, start-on-launch and
automatic desktop-update preferences under the stable installation identity.
Ctrl+1 through Ctrl+5 select Workspace, Connections, Updates, Settings and Tunnels
through the same navigation commands. Current supported capability replies own
OpenCode/Cline/Kilo status; missing, malformed or disconnected replies clear stale
readiness and versions. Desktop 3.8.0 embeds the matching reviewed client and
bridge, including all native/browser Obsidian payload modules.
Integration switches apply at Start and remain disabled while running. Minimize
retains the taskbar window; closing stops owned processes and exits. No tray icon
or close-to-tray behavior remains. Disabling automatic desktop downloads keeps
manual update checks and previously verified staged updates available.
The launcher owns a bridge supervisor and its attached worker in
`--desktop` mode on `127.0.0.1:28791`. Start opens Cowork after a structured ready
message; Stop/Exit use owned stdin control, and a Windows Job Object prevents
orphan processes. Manual CLI behavior remains on its configured port (8790 by
default). The desktop-only discovery POST rejects browser Origin/Fetch Metadata
headers, non-loopback peers, incorrect Host and missing protocol headers. Native
local programs share this trust boundary; ordinary API routes retain bearer auth.

The desktop bridge also exposes UAI tools to external MCP harnesses at authenticated
`/mcp` (`/api/mcp` alias), with Streamable HTTP and a stdio adapter. The desktop
executable's `--mcp-stdio` entry owns an adapter process without opening another
window; it discovers an already-running desktop bridge. Checkout users can run
`node bridge/server.js --mcp-stdio`. Connection examples live in the browser's
Settings modal and [bridge/MCP.md](bridge/MCP.md).

The Updates page triggers a bridge and web UI check on demand through the
authenticated `POST /api/desktop/update-check`; the supervisor answers with its
update state after the check and applies a staged release once the worker is
idle, so the reply is never severed by the restart it causes. Extracted-payload,
desktop-update and bridge-update caches keep referenced and recent entries and
prune stale predecessors on use.

`UAI_MCP_DISABLED=1` disables public MCP admission, returning HTTP 503 at both
aliases and `enabled=false` in its authenticated capability/configuration.
`UAI_OPENCODE_DISABLED=1` independently disables the native inference backend,
including its private MCP server. Neither flag changes Roblox tool permissions.

MCP advertises schemas from the connected client's registry, excluding unavailable
capabilities, disabled groups and effective denials. `net/mcp` executes through
the normal dispatcher in isolated, ephemeral conversations without switching the
active chat. Every connection retains its own tool epoch across successive calls;
Stop, close, changed bridge credentials and unload invalidate its work. Call
cancellation affects only that call. Approval prompts remain in Project UAI.
The bridge retains request identities and receipts to avoid replaying uncertain
effects; expired receipts never authorize another dispatch of that request ID.
The host's tool deadlines and cancellation limits still apply. No model inference
is required for MCP execution, and no mobile companion routes are added.

`net/bridge_connection` holds the effective connection and temporary desktop
credentials. `bridge.autoDiscover` defaults to true, probes every four seconds
with a two-second deadline, skips touch-only mobile clients, and yields to an
explicitly enabled manual bridge.
The token is never persisted or copied into manual settings. Discovery validates
product, protocol, port, token and instance; stale completions after settings
changes or unload cannot connect. `bridge.stop()` suspends discovery until sync
or a connection-setting change. Commands, pictures and inference use the same
effective connection. A changed endpoint/token aborts an active relay rather than
resubmitting inference. Desktop tests exercise real local processes and simulated
game input, not native Roblox/executor behavior. See [desktop/README.md](desktop/README.md).

The Android companion in `companion/` is a narrower relay, not a second Cowork: it
holds the provider connection so every executor-visible call stays short, which is
what a phone executor's HTTP wall-clock limit otherwise cuts off. It implements only
`/api/hello`, `/api/pair`, `/api/inference`, `/api/status` and the `/api/executor`
POST adapter — no agent routes, no
web UI, no static files. `relay.mode` defaults to `auto`; `net/relay_link` probes
`127.0.0.1:8790`, requires protocol 2 and the `uai-relay` marker (so a PC bridge on
the same port is never mistaken for it), and pairs once for a token that survives
companion restarts. Saved pairing is authenticated on first contact and after a
changed companion instance; an explicit bad-token response repairs pairing before
inference. Mobile sends can run a shared bounded discovery probe after five seconds
without a successful connection, so starting the companion does not require waiting
through the idle discovery backoff.

Discovery hello, saved-pairing verification and pairing each have a five-second
budget. Native integer timeouts round positive remaining fractions up; the
client's original deadline still bounds its wait, and timed-out native work
retains its slot until completion. A failed probe distinguishes unavailable
executor transport, connection/deadline failures, HTTP refusals and incompatible
replies without exposing response bodies or pairing credentials.

Companion discovery can compare captured native request implementations using
unauthenticated `GET /api/hello` only. The primary implementation is tried with its
normal options, then with the minimal documented options after a completed native
exception; distinct aliases can also try minimal options. Repeated aliases of the
same function are deduplicated. No-response deadlines, cancellation, capacity
limits, returned HTTP/response errors or incompatible companion metadata end the
search. A working profile is retained only after the companion marker, protocol,
instance and authenticated pairing are verified. It stays local to the relay and
is captured for an active job's submissions, polls and cancellation. Discovering
a new profile does not switch or replay that job.

Minimal native options omit the optional empty Headers table and undocumented
Timeout field. The Lua caller still stops waiting at its own deadline; a native
function that continues afterward keeps its connection slot until it ends.

Companion 3.5.7 advertises `capabilities.executorPost = {schema:1}`. After completed
native discovery failures, DataModel HttpGet/HttpPost can discover and pair.
Authenticated operations use POST `/api/executor` with a schema-1 method/path/
token/body envelope; credentials and provider data never enter GET URLs. This
endpoint accepts only existing relay operations, checks loopback Host, rejects
browser Origin/Fetch Metadata, and requires JSON and the constant-time token check.
It returns the operation status and JSON body in a schema-1 envelope. Job identity,
leases, cancellation and native deadline/slot ownership retain their existing rules.
Older companions cannot select this profile.

Companion 3.6.0 decodes gzip POST bodies before interpreting JSON, including a
gzip signature when the native wrapper omitted Content-Encoding. Both wire and
expanded bodies have an 8 MiB limit, including chunked requests. Invalid gzip,
invalid UTF-8 and unsupported encodings return fixed error categories without
logging request content. Executor errors preserve their status in the POST
response envelope. This fixes compressed submissions rejected before token or
inference validation; it does not authorize inference replay or pairing resets.

Updated companions advertise `capabilities.inference = {schema:1, unlimited:true}`.
With the normal `agent.requestUnlimited` setting, default inference uses an
unlimited job (`timeout:0`), while every executor-visible exchange remains bounded
to five seconds. Explicit request timeouts/deadlines and disabled unlimited settings
remain finite. Legacy companions retain finite jobs. Finite submission timeouts are
integer seconds, as required by the Kotlin protocol. Lost polls retain the accepted
job identity; Stop, unload, changed credentials, lost receipts and upstream failures
remain terminal. Provider limits still apply. No timeout causes a direct retry.
Companion jobs retain a separate 120-second monotonic ownership lease, renewed only
by their authenticated result poll or matching submission retry. A five-second
service sweep cancels abandoned provider calls and releases idle wake locks after
Roblox disappears. Lease expiry is terminal `client_disconnected` and cannot
authorize replay; normal polling can keep an unlimited job alive indefinitely.

The Android app checks official stable `Project-Ptolemy/ProjectUAI` releases on
startup and every 15 minutes while its process is alive. Automatic downloads are
enabled by default. An update must have the expected package ID, compatible SDK,
newer version name/code, matching size/hash and the same installed signing
certificate. Checking and downloading never stop inference. Installation requires
an explicit user action and Android confirmation, and reserves admission only
after active jobs and retained receipts are gone. The app owns and persists its
Android installation session; after interruption, that session must be abandoned
before relay admission resumes. See [companion/UPDATES.md](companion/UPDATES.md)
for the signed release assets, initial debug-build transition and device checks.

`net/transport` is the single transport decision point: a
connected Cowork connection wins, then the companion, then the executor directly.
Images always relay because they need a resolver. `relay.*` is independent of
`bridge.*` and is preserved across settings import. The companion never persists or
logs provider keys, binds loopback only, and compares its token in constant time.
JVM tests cover the engine and server contract; a device is needed for the service
and the executor compatibility measurement. See [docs/MOBILE_COMPANION.md](docs/MOBILE_COMPANION.md).

`dist/uai.lua` is what a user runs:

```lua
loadstring(game:HttpGet("<url>/dist/uai.lua"))()
```
