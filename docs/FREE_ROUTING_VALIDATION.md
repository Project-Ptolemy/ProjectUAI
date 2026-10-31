# Managed Free latency routing

Current setup is opt-in: add **Project UAI Free** from the Providers library and
save it before using this routing. HCNSEC personal accounts have their own
provider and never enable these community probes. Empty startup, import and reset
configurations remain empty. See the [setup guide](providers/projectuai-free.md).

The measurements and test counts below describe their dated runs. They are not
current availability guarantees or evidence for a later release.

Measured October 17, 2026, from the development desktop using the intentionally
distributed community credential. No private credential or conversation was used.
These are availability snapshots, not native Roblox or executor benchmarks.

`GET https://api.hcnsec.cn/v1/models` returned HTTP 200 in 2.61 seconds with 15
IDs. Each advertised ID received a small Chat request asking for `uai_ping`.
Successful tool calls received a synthetic tool result in a second request.
Each request had a ten-second timeout; no timed-out request was retried.

| Advertised model | Tool response | Result replay | Observation |
| --- | ---: | ---: | --- |
| DeepSeek-V4-Flash | 3.40 s | 1.44 s | Tool call and text replay succeeded |
| auto | 3.60 s | 4.40 s | Tool call and text replay succeeded; served `agnes-3.0-flash` |
| DeepSeek-V4-Pro | 6.41 s | 5.31 s | Tool call and text replay succeeded |
| MiMo-V2.6-Flash | 4.68 s | 4.74 s | Tool call and text replay succeeded |
| longcat-2.5 | 8.93 s | 5.86 s | Tool call and text replay succeeded |
| Qwen3.8-27B | 4.46 s | 6.90 s | Tool call and text replay succeeded |
| step-5-preview | 3.13 s | — | Returned text without the requested tool call |
| Qwen3-Embedding-8B | 1.24 s | — | HTTP 404 on Chat |
| sensenova-u1.5-lite | 2.29 s | — | HTTP 404 on Chat |

DeepSeek-V4.1-Flash, glm-5.3, glm-5.3-flash, MiniCPM-V-4.7-35B-A3B,
Qwen3.8-Flash-Next and sensenova-6.8-flash-lite exceeded the ten-second deadline.
Listing a model does not prove that it accepts Chat or tools.

A second check used the runtime's exact prompt, tool schema, `max_tokens=128`,
and tool declarations on both requests, validating the nonce and call ID.
`auto` completed in 2.03 s / 1.45 s; DeepSeek-V4-Flash completed in 4.18 s / 3.43 s.
Both passed tool and replay validation. The ordering reversed within this session,
which is why the implementation measures locally and does not hardcode the first
winner. These desktop checks used Node fetch; executor/bridge timing can differ.

Automatic routing is optional and enabled by default under **Settings → Agent →
Automatic free routing**. Disabling it stops background measurements and new
measured-model selections without interrupting an accepted request. A retained
conversation notice names each newly selected model and gives the same opt-out
path. Keeping the provider's model set to `auto` still permits its server-side routing.

The runtime discovers IDs again rather than saving this list. It requires the
expected tool name, arguments and call ID, then validates a successful text reply
after tool-result replay. It compares the slower of each candidate's two
responses. It selects only a fresh candidate with an appropriate documented
context window; the provider's `auto` remains the cold/unsuitable-request fallback.
This small probe cannot establish full agent quality, vision, large-context speed,
or a guarantee that a real request will complete within ten seconds.

Focused offline coverage is in `test/free_routing.lua`: nonblocking warmup,
tool/result validation, timeouts, context and image guards, explicit/private
settings, optional routing and accepted-request ownership, retained notices,
stale scopes, per-request persistence, prompt/hook identity, relay
deadlines, and green free-model outlines. Run after reviewing source and rebuilding
the native client. These fixtures do not verify native Roblox rendering or input.

After manual review, native bundle build `3.2.0-931b9e84ce7720fe` and generated-output
inspection, the focused checks passed:

| Command | Cases | Assertions |
| --- | ---: | ---: |
| `luajit test/free_routing.lua` | 11 | 127 |
| `luajit test/free_provider.lua` | 8 | 68 |
| `luajit test/provider_key_snapshots.lua` | 6 | 19 |
| `luajit test/provider_key_rotation.lua` | 8 | 42 |
| `luajit test/release_provider_ui.lua` | 4 | 12 |

The new routing fixture was corrected to observe transient request events through
the session event stream. The older key-snapshot fixture was updated to the
supported AgentRouter proxy route; its retired OpenCode proxy expectation
contradicted the current contract. Both fixes were manually reviewed before the
affected checks were rerun. The full native suite was not run.
