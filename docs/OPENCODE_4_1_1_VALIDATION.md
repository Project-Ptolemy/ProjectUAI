# OpenCode Zen 4.1.1 validation

Live direct API checks on **November 22, 2026** examined every current zero-price
Chat model, with both the user-designated test key and OpenCode's published
`public` authentication token. The scoped HTTPS profile passed exact text checks
for all eleven models with the test key. Public requests also reached all eleven,
but Flint had a strict text mismatch and a later free-usage refusal. Synthetic
tool calls and tool-result replay succeeded for each model, with the Iceman
behavior described below.

These were standalone HTTPS requests to the official inference service. No
Cowork server, relay, installed CLI, OAuth session or host tool execution was
involved. A working model does not establish the others' compatibility; every
row below has its own observations. Results apply to the recorded date and
transport, and do not guarantee future free capacity.

## Earlier evidence and current request

The [October 15 investigation](OPENCODE_3.2_VALIDATION.md) established the desktop
2.0.27 identity, stable session aliases, wildcard Accept and seven compatibility
declarations. Some direct Node and Windows Schannel requests worked then. The
[November 2 investigation](OPENCODE_API_KEY_INVESTIGATION.md) showed that current
DeepSeek access additionally required truthful system environment context and
the native Bun cipher-suite offer. Its single-model success was a starting
point for this larger matrix.

The current probes used Windows, **Node 24.21.0 / OpenSSL 3.5.8**, streaming Chat
Completions, the historical desktop identity and this truthful system context:

```text
<env>
Working directory: Roblox runtime
Platform: Roblox
</env>
```

The shared `bridge/opencode-transport.js` HTTPS options supply the scoped cipher
offer before the first request. They retain certificate validation and Node's
TLS-version defaults, and need neither Bun nor the OpenCode executable. Ordinary
Node and Windows Schannel controls kept the same model, authentication, body and
headers. The three official Zen aliases did not restore the ten models that
refused ordinary TLS. Additional DeepSeek controls with a newer desktop identity,
full current native prompts and ordinary HTTP/2 also retained that refusal.

The model matrix used
`https://opencode.ai/inference/openai/v1/chat/completions`. Alias controls also
examined `/zen/v1` and `/inference/v1`. No requests were sent to Go, a custom host
or the retired HTTPS proxy.

## Model matrix

The official catalog reported **11 free Chat models** and **one free decision
model**. Eligibility is based on the catalog's explicit kind, supported protocol
and zero prices across all tiers. An ID ending in `-free` is insufficient evidence.

Each tool check requested exactly `uai_ping({"message":"PONG"})`; replay supplied
an explicitly synthetic local result and checked the assembled streamed reply.
No filesystem, shell, network or Roblox tool was executed.

| Current Chat model | Scoped HTTPS with test key | Scoped HTTPS with public token | Ordinary TLS controls |
| --- | --- | --- | --- |
| `big-pickle` | Text, tool and replay succeeded | Text, tool and replay succeeded | Free-usage refusal |
| `mimo-v2.6-flash-free` | Text, tool and replay succeeded | Text, tool and replay succeeded | Free-usage refusal |
| `deepseek-v4.1-flash-free` | Text, tool and replay succeeded | Text, tool and replay succeeded | Free-usage refusal |
| `longcat-2.5-free` | Text, tool and replay succeeded | Text, tool and replay succeeded | Free-usage refusal; one connection reset |
| `iceman-free` | Text succeeded; follow-up single tool and replay succeeded | Text, single tool and replay succeeded | Free-usage refusal |
| `beam-free` | Text, tool and replay succeeded | Text, tool and replay succeeded | Free-usage refusal |
| `flint-40b-free` | Text, tool and replay succeeded | HTTP 200 text; tool and replay succeeded | Free-usage refusal |
| `nemotron-3.5-super-vl-free` | Text, tool and replay succeeded | Text, tool and replay succeeded | Free-usage refusal |
| `nemotron-3.5-lightning-free` | Text, tool and replay succeeded | Text, tool and replay succeeded | Free-usage refusal |
| `hy4-flash-free` | Text, tool and replay succeeded | Text, tool and replay succeeded | Text, tool and replay succeeded |
| `tidepool-alpha-free` | Text, tool and replay succeeded | Text, tool and replay succeeded | Free-usage refusal |

The keyed matrix assembled exact `PONG` for every text request and ten original
replays. Iceman's first keyed forced-tool request returned **eight calls**: the
valid synthetic call plus all seven compatibility declarations. That failed
the original single-call assertion and its replay was correctly skipped. A
later request with sentinel descriptions returned exactly the requested single
call and completed replay. Public controls also completed a safe full-batch
replay: each extra compatibility call received explicit non-executed refusal
feedback. Batch recovery is distinct from single-call success.

An initial public matrix encountered a Flint tool connection reset and two
Nemotron replay resets. Fresh independent requests succeeded; these transport
failures remain part of the observations and were not retries of an uncertain
production inference. In the later public matrix, Flint's text reply had five
bytes rather than the exact four-byte `PONG`, despite HTTP 200; its tool and
replay checks were exact. API acceptance and strict output matching are recorded
separately. A later bounded public Flint text control returned HTTP 429
`FreeUsageLimitError` with no text. That refusal is retained alongside its earlier
HTTP 200 text, successful public tool/replay checks and exact keyed text check;
the workaround does not guarantee uninterrupted upstream free allowance.

## Decision and retired models

`jev-1.13-free` is a zero-price **Systemone decision** model. Its legitimate typed
decision API returned HTTP 200, the requested `PONG` choice and valid confidence
with public authentication on ordinary Node, scoped Node and Windows Schannel.
The designated test key also passed ordinary and scoped Node decision requests.
This protocol intrinsically lacks Chat messages, tool calls and tool-result
replay. The model must not appear as a usable free Chat model or be silently
substituted for a Chat request.

Historical `cat-jam-free` is absent from the current catalog. Keyed Chat and
Responses probes across all three official aliases returned HTTP 400
`server_error`, apart from one transport reset. Earlier Cat Jam success does not
establish present availability. No retired model ID is installed as a fallback.

## Shipped behavior and limits

The client discovers the official API catalog independently of the optional
CLI's normalized model list. Public authentication requires fresh catalog
evidence scoped to the connection's endpoint, authentication, headers and policy.
After restart or expiration, the client verifies the model before inference.
Unknown, priced, decision-only or incomplete catalog rows cannot become public
Chat access through name guessing.

Personal Zen credentials take precedence and keep direct API routing even if
the optional installed CLI is ready. Paused or pinned key pools, credential
storage guards, explicit authentication, custom body model overrides, queries,
sockets and unqualified URLs retain their restrictions. Current catalog Chat
models cannot inherit stale learned Responses routing. Exact compatibility
placeholder schemas are filtered during CLI handoff while genuine registered
tools with colliding names are preserved.

`FreeUsageLimitError` is a completed free-access refusal, not a temporary 429
rate limit. It does not authorize key rotation, protocol guessing, a proxy or
transport replay. Request ownership, deadlines, cancellation and normal Roblox
tool permissions remain effective.

Executor HTTP and Android OkHttp have their own TLS stacks. The shipped Lua
client can prepare direct public Chat requests, but cannot change a host's TLS
cipher offer. This Windows matrix therefore does not certify direct access to
every model on every executor or Android device. The desktop's direct HTTPS
profile is independently verified; an installed OpenCode CLI remains a separate
optional route. Historical phone inference evidence does not certify this
current all-model matrix, phone tool replay, background survival or native input.

Offline integration, source-produced tool fixtures and release build results
are recorded in [4.1.1 verification](TESTING_4.1.1.md). Live probe summaries retain
only statuses, bounded categories, counts and synthetic-output checks; credentials
and provider response bodies are excluded from public artifacts.
