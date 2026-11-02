# OpenCode API-key investigation

Investigated November 2, 2026. The designated service-account API key works for
`deepseek-v4.1-flash-free` outside the OpenCode tunnel. Two changes restore the
tested request: truthful environment context and the native Bun cipher-suite
offer. Standalone Bun 1.4.2 verified text, a synthetic UAI function call, and
tool-result replay, all HTTP 200. Ordinary Node HTTPS then returned HTTP 200 and
assembled `PONG` with the same key and production bridge headers after changing
only its cipher-suite list. The production Lua-to-bridge integration then passed
text, tool call and replay with the CLI unavailable. These checks did not use
OAuth or the CLI server.

## Working request context

The request needs a system or developer message containing an `<env>` block
with `Working directory:`. UAI can supply truthful Roblox context:

```text
<env>
Working directory: Roblox runtime
Platform: Roblox
</env>
```

The existing seven compatibility tool declarations and desktop 2.0.27 identity
still work. The full native system prompt, its twelve current tools, fake local
paths, and a new personal key are unnecessary for this verified route.

| Standalone Bun 1.4.2, same designated API key | Result |
| --- | --- |
| Truthful Roblox environment and original seven tools | HTTP 200, exact `PONG` |
| Same request plus synthetic `uai_ping` | HTTP 200, exact `{"message":"PONG"}` tool arguments |
| Replay of its locally supplied synthetic result | HTTP 200, exact `PONG`, no further tools |
| Original request without the environment context | HTTP 429 `FreeUsageLimitError` |

The environment also works after existing Project UAI system instructions. It
fails in a user message. Arbitrary OpenCode wording, empty tags, larger prompts,
platform-only context, and removing compatibility tools did not restore access.
The tool replay used an explicitly synthetic local result; no host tool executed.

Streaming text must be assembled before checking it. Replies split `PONG` into
`P` and `ONG` chunks; an early raw-body substring check missed that successful
output. Follow-up probes parsed the SSE data correctly.

Unmodified Node HTTPS and Windows Schannel curl returned 429 with the working body.
Bun was the official 1.4.2 runtime, matching the installed CLI, with reviewed
`--smol`, `--user-agent=opencode/latest/2.1.2/cli` and `--use-system-ca` flags.
Explicit request headers independently verified desktop 2.0.27 and 2.1.2.
The official archive hash matched its release digest; the runtime remained in
ignored investigation tools and was not installed globally or bundled with UAI.
The runtime comparison led to controlled Node HTTPS requests with identical key,
body and headers. A fresh connection offering Bun's cipher list returned 200;
ALPN alone, a modern-only cipher list, and reordered default TLS 1.3 suites still
returned 429. The working cipher-only request retained the production bridge's
desktop 2.0.27 User-Agent, wildcard Accept, session aliases and identity encoding,
without a generated project header. Matching the full Bun TLS options also
succeeded, but curves, signature algorithms, OCSP and other extra options were
unnecessary and are not shipped.

The bridge now supplies that cipher list on its first direct HTTPS dispatch to
exact official Zen Chat/Responses paths. It retains certificate validation and
Node's TLS-version defaults and adds no Bun dependency. Go, custom routes,
nonstandard ports, URL credentials, queries and fragments retain their ordinary
transport. Installed CLI routing still takes priority. No retry is added for a
refused or uncertain request. Executor and Android HTTP use different TLS stacks;
these probes do not establish their behavior or future upstream availability.

## Initial live comparison

The reported console logs distinguished a failed service-account request from
a successful user request. This was a useful initial difference, but the later
controls below show that identity alone does not explain the refusal.

At 10:41:57–10:42:10 UTC, a reviewed Windows Node.js probe used the designated
secondary OpenCode API key from the private handover. The credential remained
in memory and was sent only to the official HTTPS inference endpoint. The
probe used `deepseek-v4.1-flash-free`, streaming Chat Completions, high reasoning
effort, stable session headers, the seven existing compatibility declarations,
and a short request for `PONG`.

| Route | Client | Result |
| --- | --- | --- |
| `/inference/openai/v1/chat/completions`, designated API key | Desktop 2.0.27 | HTTP 429, `FreeUsageLimitError`, 947 ms |
| Same endpoint, key and payload | Desktop 2.1.2 | HTTP 429, identical error, 612 ms |
| Production `bridge/opencode.js` adapter | Installed CLI 2.1.2 | HTTP 200, exact `PONG`, 3,718 ms |

Both direct replies contained:

```text
Free usage limit reached. Free models work in OpenCode (https://opencode.ai); subscribe to OpenCode Go to keep going: https://opencode.ai/go
```

The tunnel discovered this model in its zero-price catalog and used its normal
isolated server and temporary request session. No API-key headers were passed
to the native adapter. The probe closed its owned server afterward; it did not
stop the user's running OpenCode process or change subscriptions or budgets.

This reproduces the reported refusal with the designated test key. The key
identifier in the user's log was not used as a credential, so the probe does
not establish the exact remaining allowance of that logged service account.
The native success establishes that
the tested free tunnel remained available at that time; it does not establish
all models, tool handoff, mobile behavior, or future availability.

## Identity and documented access

The official [API-key documentation](https://opencode.ai/v2/docs/console/api/)
distinguishes personal keys, which act as their creating user, from service-account
keys, which act as a separate nonhuman member. The
[inference documentation](https://opencode.ai/v2/docs/console/api/inference/)
states that free-tier chat models require OpenCode even with an API key.
The [budget documentation](https://opencode.ai/v2/docs/console/budgets/) excludes
free models from monetary budgets. This error therefore does not establish that
the working user's spending budget or CLI allowance is exhausted.

Further controls used the current signed-in user OAuth token and a newly created
personal key restricted to `models:read` and `models:request`. Both returned the
same 429 with the reviewed direct payload and current desktop headers. The
temporary personal key was revoked immediately; revocation returned HTTP 200.
OpenCode's native public token also received the same direct refusal.

A temporary plugin then observed a synthetic request from the production CLI
through its official `http.request` hook. Its actual request used CLI 2.1.2
headers, twelve native tool declarations, and the same official endpoint. The
public-token CLI request returned exact `PONG`; copies of that captured JSON and
noncredential headers returned 429 with public, user OAuth and service-key
authentication through Node and Windows Schannel curl. An additional owned CLI
request with the designated service key placed in its outgoing Request headers
also returned exact `PONG`. The later standalone probes above isolated the
required environment context and showed that the key can work without the CLI.
The capture retained synthetic body/schema data and header names, never credential
header values. Every owned native server was closed after its probe.

The public sources do not expose the exact backend decision that produced this
429. Changing the desktop version or creating a personal key did not restore
the tested direct request. The service-key native control means the failed
direct reply cannot, by itself, establish that this key has no usable free access.

## Client behavior

UAI adds reusable truthful environment context to exact Zen Chat and Responses
requests while retaining original instructions and conversation history. Its
desktop bridge applies the scoped cipher-suite offer for direct API-key requests.
Go and unrelated provider routes keep their existing contracts. The existing
compatibility declarations and explicit overrides remain effective.

UAI recognizes a remaining explicit free-usage refusal and preserves the upstream
status and message. It explains updating the client and bridge for API-key access
and the optional installed OpenCode tunnel, and avoids
same-route backoff, key rotation, or an unrelated protocol retry. Temporary
429 responses retain their normal retry behavior. Existing CLI routing remains
the supported path for models confirmed by its authenticated discovery.

The successful direct checks in
[the October 15 validation](OPENCODE_3.2_VALIDATION.md) remain historical evidence.
They do not guarantee today's eligibility.

## Production integration and verification

At 11:22:04–11:22:12 UTC, the actual Lua `provider/openai.complete` and `net/http`
modules exported synthetic production bodies and headers without credentials.
The production Node bridge supplied the designated API key in memory and used
direct HTTPS. OpenCode CLI capability was unavailable; Kilo and Cline were absent.

| Production bridge, Node 24.21.0 / OpenSSL 3.5.8 | Result | Elapsed |
| --- | --- | --- |
| Text with original UAI instructions and truthful context | HTTP 200, exact `PONG` | 2,368 ms |
| Forced synthetic `uai_ping` | HTTP 200, `{"message":"PONG"}` | 1,781 ms |
| Replay of synthetic local `PONG` result | HTTP 200, exact `PONG`, no more tools | 1,640 ms |

Exactly three HTTPS dispatches occurred, one per job, with zero CLI calls. The
original desktop 2.0.27 identity and seven compatibility declarations reached the
wire; the tool requests added one synthetic UAI declaration. No host tool ran.

A separate production control at 11:24:12–11:24:15 UTC explicitly set
`reasoning_effort: "max"` through the normal body override. It returned HTTP 200
and assembled `PONG` in 2,260 ms, with one HTTPS dispatch and zero CLI calls. The
exported body confirmed `max` on the wire, matching the reported failure setting.

Reviewed inputs were built and generated outputs inspected before verification:

- Context: 6 cases / 64 assertions; explicit-refusal policy: 9 / 102;
  provider support: 1 / 54, all passing.
- Bridge transport, native routing, streaming, security and updater: 90 tests
  passed, including acceptance by the shipped 3.1 updater.
- Browser response layout and error guidance passed.
- Native static checker: 311 files, zero failures or warnings. The official Luau
  compiler accepted changed client modules and the generated bundle.
- Code first-open, coding-tab, selection and workspace regressions: 41 cases /
  275 assertions passed. These exercise optional metric failures and construction
  cleanup; the affected user's exact native failure remains unconfirmed.
- Client and bridge artifact freshness checks and `git diff --check` passed.

The corrected client build is `3.8.0-9a5b0fa9b887f483`; bridge/web release is
`3.8.1`. The Windows shell remains 3.8.0 and Android companion remains 3.7.1.
Reload the corrected Lua client and refresh the browser after the bridge updates.
