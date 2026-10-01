# Mobile Relay and Android Companion — Detailed Plan

Status: planning only. No implementation in this change.
Scope decision: Android only. The existing `bridge/` directory is not modified.
PC Cowork behaviour must be observationally unchanged.

This document is the source of truth for building the Android companion app and the
client-side decoupling that lets the in-game mobile UI route inference through it.

---

## 0. Decisions locked

1. **Android only.** No iOS app, no iOS background work. iOS devices use a relay
   hosted elsewhere (LAN PC, another phone, or a VPS) if they are supported at all.
2. **`bridge/` is frozen.** `server.js`, `inference.js`, `launcher.js`, `picture-store.js`
   and `bridge/web/` are not edited by this project. The companion is a second,
   independent implementation of the same contract.
3. **PC Cowork flow unchanged.** With `bridge.enabled` and `bridge.runtime == "web"`,
   behaviour is identical to today, including the browser UI, streaming, images,
   agent commands and the token/port workflow.
4. **Companion has explicit START and KILL.** KILL is authoritative and must not be
   undone by watchdogs.
5. **While started, the companion must not die** under normal OS pressure (screen
   locked, Roblox foreground, memory pressure, user swiping Recents).
6. **Graceful fallback.** No companion means direct executor transport, unchanged
   from today except for clearer messaging.

### What "bridge untouched" costs

The companion still has to satisfy the protocol in `src/net/relay.lua`. That file is
therefore the normative specification in Section 4 — not `bridge/server.js`. The two
must not silently diverge, which is why Section 9 defines contract fixtures as a
deliverable rather than a nice-to-have.

---

## 1. Problem statement

Mobile Roblox executors impose a wall-clock limit on HTTP calls made through their
native `request`/`http_request` bridge (commonly described as ~30 seconds; the exact
value is unverified and must be measured per executor — see Section 9.4). Reasoning
models, long system prompts and high-context turns routinely take 40–120 s, so a direct
call is cut off before the provider answers.

The PC solution already exists: `src/net/relay.lua` submits the long request to a local
server that owns the upstream connection, then polls a short loopback route until the
result is ready. Every executor-visible call is a few milliseconds, so the wall is never
reached.

```
Direct (dies on mobile)                 Relay (survives)
Executor request() -- 120 s --> gone    POST /api/inference   -> ~10 ms
                                        GET  /api/inference/:id -> ~5 ms, once per second
                                        (the relay holds the upstream connection)
```

Mobile cannot reuse the PC server: there is no Node runtime, and a background Node
process is killed while Roblox holds the foreground. A small, purpose-built Android
foreground service can hold the socket instead.

---

## 2. Scope

### In scope

- A new Luau module that probes, pairs with and tracks the companion.
- New `relay.*` configuration and the provider gating that routes inference through it.
- Minimal, additive edits to `src/net/relay.lua` so it addresses `relay.*` instead of
  the Cowork-specific `bridge.*` keys.
- UI: a Relay status/setup surface, settings row, privacy endpoint listing, log lines.
- An Android (Kotlin) app: foreground service, loopback HTTP server, pairing, job
  engine, Start/Kill, notification, survival hardening, diagnostics.
- Tests: client offline scenarios, protocol contract fixtures, companion JVM tests,
  and an executor compatibility spike that gates the whole effort.

### Out of scope

- iOS.
- Any change to `bridge/`.
- A hosted/cloud relay service.
- Incremental streaming of the reply into the in-game UI (Section 12, open decision).
- App-store distribution (sideload only).

---

## 3. Architecture

```
┌──────────────────────────── Android device ────────────────────────────┐
│                                                                        │
│  Roblox process                              Companion process         │
│  ┌───────────────────────┐   loopback   ┌────────────────────────────┐ │
│  │ UAI client (Luau)     │  127.0.0.1   │ Foreground service         │ │
│  │  provider/chat        │─────────────▶│  HTTP server (:8790)       │ │
│  │  net/relay            │◀─────────────│  job engine (coroutines)   │ │
│  │  net/relay_link ──────┼── probe/pair │  upstream OkHttp ──────────┼─┼──▶ provider
│  │  in-game UI           │              │  notification + watchdog   │ │
│  └───────────────────────┘              └────────────────────────────┘ │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

### Transport precedence (normative)

For a single inference request, in order:

1. **Cowork web runtime** — if `bridge.enabled` is true and `bridge.runtime == "web"`,
   relay exactly as today (PC only in practice). Unchanged.
2. **Companion** — if the companion is paired and the last probe succeeded, relay to it.
   The in-game UI stays mounted; this is the mobile path.
3. **Direct executor** — otherwise. This is today's behaviour on mobile.

Image-bearing requests (Section 5.4) are a special case: they require a resolver and
therefore always use a relay (Cowork or companion) when one is available, and fail with
an explicit message when none is.

---

## 4. Wire protocol (normative)

Source of truth: `src/net/relay.lua`. Anything below is derived from that file and is
what the companion must implement to be compatible.

### 4.1 Transport shape

- Base URL is `http://127.0.0.1:<port>`, default port `8790`.
- Every call is small and bounded: `relay.lua` uses `timeout = 15` and `silent = true`
  for all short calls (`src/net/relay.lua:18`).
- All calls except `hello` (see 4.3) carry `Authorization: Bearer <token>`.
- Bodies are JSON. Responses are JSON.
- No cookies, no keep-alive requirements, no WebSocket.

### 4.2 Endpoints

| Route | Method | Auth | Purpose |
| --- | --- | --- | --- |
| `/api/hello` | GET | see 4.3 | Health, protocol version, server identity |
| `/api/pair` | POST | loopback + origin/host guard | Issue the ephemeral/stable token |
| `/api/inference` | POST | Bearer | Start (or idempotently re-fetch) a job |
| `/api/inference/:id` | GET | Bearer | Poll: `running` / `completed` / terminal |
| `/api/inference/:id` | DELETE | Bearer | Cancel an in-flight job |
| `/api/status` | GET | Bearer or app-internal | Diagnostics for the app UI (not used by the client) |

Note on `hello` auth: today `bridge/server.js` authenticates before routing, so its
`/api/hello` needs a token. The companion needs an *unauthenticated* hello for
zero-touch discovery, so the companion is where this differs. `relay.lua` always sends
the bearer header anyway, so accepting it is harmless; what matters is that the probe
can succeed before a token exists.

### 4.3 `GET /api/hello`

The client requires, from `src/net/relay.lua:34-38`:

```json
{ "protocol": 2, "instance": "<opaque non-empty string>", "ok": true }
```

- `protocol` must be exactly the number `2`.
- `instance` must be a non-empty string. It identifies *this server lifetime*; it changes
  on every companion restart. The client re-reads hello before every inference and sends
  the instance back in the submit body, and the companion must reject a mismatched
  instance (`inference.js:145`). This is how "the relay restarted mid-job" is detected
  rather than silently resubmitted.
- Additional fields are ignored by the client and are safe to add. The plan adds:
  - `"server": "uai-relay"` — a marker so a non-UAI process on 8790 is not mistaken for
    the companion (Section 5.5).
  - `"capabilities": { "serverSidePairing": true, "deltas": false, ... }` — negotiation
    space for later (Section 4.13).

### 4.4 `POST /api/pair`

Not used by `relay.lua`; added for zero-touch. Request:

```json
{ "client": "ProjectUAI-Mobile", "version": "1.0.0", "protocol": 2,
  "placeId": 123456789, "gameId": 987654321 }
```

Response `200`:

```json
{ "ok": true, "token": "<64 lowercase hex>", "instance": "<same as hello>", "protocol": 2 }
```

Rules:

- Only reachable over loopback (bind `127.0.0.1`; consider `::1` too, see 4.12).
- Rejected when an `Origin` header is present and not a loopback form (mirrors
  `bridge/server.js:144-150`), and when the `Host` header is not `127.0.0.1`/`localhost`
  with the right port. The Host check is what defeats DNS rebinding.
- Rate limited (e.g. 10/min) to blunt local spam.
- The token is stable across restarts and is persisted (Section 6.7), which is the whole
  point: a killed-and-restarted companion must not force a re-pair.
- Pairing while already paired returns the existing token (idempotent).
- Place/game ids are stored only for display ("Connected: Place 123456789").

### 4.5 `POST /api/inference`

Request fields are exactly what `relay.lua:39-40` sends:

```json
{ "id": "inference_<guid>", "instance": "<from hello>", "url": "https://provider/...",
  "headers": { "Authorization": "Bearer <provider key>", ... },
  "body": "<provider request JSON as text>", "timeout": 180, "sessionId": "<optional>" }
```

Companion responsibilities (mirroring `bridge/inference.js:143-183`):

- `id` must match `^[\w-]{8,100}$`; else reject.
- `instance` must equal the current instance; else fail with "restarted" semantics.
- `body` must be a string within the size cap.
- `url` must parse as `http:` or `https:` with no embedded credentials.
- `headers` are filtered: drop `host`, `connection`, `content-length`,
  `transfer-encoding`, `accept-encoding`; force `accept-encoding: identity`; set
  `content-length` to the body length.
- `timeout` is clamped to `[10, 86400]`, default 180.
- **Idempotency**: a fingerprint over `url + sorted filtered headers + body + sessionId`
  is stored per id. A re-submit of the same id with the same fingerprint returns the
  existing job view; a different fingerprint is an error.
- A previously seen id that has been evicted is answered as `expired` with a
  "do not resubmit" error, and must never run again (tombstone/horizon).
- Respond `202` with the job view (below) and begin the upstream call.

Job view:

```json
{ "id": "...", "state": "running", "error": null, "status": 0, "headers": {}, "body": null }
```

`body` is only present when `state == "completed"`.

### 4.6 `GET /api/inference/:id`

| Case | Status | Body | Client behaviour |
| --- | --- | --- | --- |
| Running | 200 | `{id,state:"running"}` | Keep polling |
| Completed | 200 | `{id,state:"completed",status,headers,body}` | Return body to provider |
| Failed | 200 | `{id,state:"failed",error}` | Terminal failure, no resubmit |
| Cancelled | 200 | `{id,state:"cancelled"}` | Terminal failure |
| Expired/evicted | 200 | `{id,state:"expired",error}` | Terminal failure |
| Unknown id | 404 | `{error:"Unknown inference ID; do not resubmit"}` | Terminal failure (client: `relay.lua:60-64`) |

The 404 case is important: it is the client's signal to stop and *not* pay for the
request twice.

### 4.7 `DELETE /api/inference/:id`

Cancels the upstream call and marks the job `cancelled`. Idempotent. Used by the client
on abort and on deadline (`relay.lua:21,43,74`).

### 4.8 Job lifecycle

```
POST → running ──(upstream 2xx)──▶ completed
              ├─(upstream 4xx/5xx)──▶ completed (status carried; body may be an error body)
              ├─(transport error)──▶ failed
              ├─(DELETE)───────────▶ cancelled
              └─(retention passed)─▶ expired (tombstoned, never rerun)
```

Retention: keep completed bodies for a bounded window (start at 60 s, configurable) for
idempotent retries, then purge and tombstone the id. Caps: max jobs, max active jobs,
max retained bytes (mobile budgets in Section 6.11).

### 4.9 Client-visible error semantics

`relay.lua` treats these distinctly, so the companion must not blur them:

- A **4xx on submit/poll** is terminal and quotes `error` in the message
  (`relay.lua:60-64`). Use 4xx for "your request is wrong"; do not use it for transient
  capacity problems.
- A **5xx or dropped connection** is retried by the client, with the *same id*, up to 3
  times before it gives up (`relay.lua:65-66`). Idempotency makes that safe.
- A **state other than `running`/`completed`** is terminal (`relay.lua:57-58`).
- Capacity pressure should therefore be `503`, not `400`.

### 4.10 Limits

Start from the PC values (`bridge/inference.js:11-22`) and reduce for a phone:

| Limit | PC | Companion (proposed) |
| --- | --- | --- |
| Body in/out cap | 16 MiB / 8 MiB | 8 MiB / 8 MiB |
| Max jobs | 10000 | 200 |
| Max active jobs | 16 | 4 |
| Max retained bytes | 64 MiB | 32 MiB |
| Retention | 300 s | 60 s |
| Tombstone horizon | 50000 | 20000 |

The client itself rejects any provider body over 8 MiB (`src/net/http.lua:18`), so the
deliverable cap does not need to exceed that.

### 4.11 Auth and origin

- Comparison should be length-checked then constant-time (mirror `server.js:158-159`).
- Token format: 64 lowercase hex.
- Bind loopback only. If `::1` is supported, either bind both or prefer `127.0.0.1` and
  document IPv6-only devices as a spike item.
- Reject a browser `Origin` that is not loopback.
- Validate `Host`.
- Never emit permissive CORS headers.

### 4.12 Versioning

`protocol: 2` is the contract. Additive fields are allowed (the client ignores unknown
keys). A breaking change requires a new protocol number and a client that refuses the
old one, exactly as `relay.lua:36` refuses anything that is not 2. The companion's
`capabilities` block is where optional features are advertised so the client can use
them without a version bump.

### 4.13 Explicitly NOT implemented by the companion

The following belong to the Cowork link, not the relay contract, and the companion must
not implement them (doing so is the scope creep this plan exists to avoid):

- `/api/agent/inbox`, `/api/agent/events`, `/api/agent/ack` (state sync + commands)
- `/api/stream` (browser SSE)
- `/api/send`, `/api/command`, `/api/abort`, `/api/clear`, `/api/permission`
- `/api/pictures*`
- Static file serving / the web UI

This is why the client must not simply flip `bridge.enabled` to reach the companion:
that key starts the Cowork loops (`src/net/bridge.lua:576`, routes at `:403-471`), which
would 404 against the companion and upload conversation state for nothing. Section 5.1
introduces a separate `relay.*` block instead.

---

## 5. Client design (Luau)

### 5.1 Configuration

Add a `relay` block to `DEFAULTS` in `src/runtime/config.lua`, beside the existing
`bridge` block (`src/runtime/config.lua:203-209`):

```lua
relay = {
    mode = "auto",   -- "auto" | "always" | "off"
    port = 8790,     -- mirrors the companion's port
    token = "",      -- written by /api/pair, stable across companion restarts
    instance = "",   -- last instance seen from hello (diagnostics + skew detection)
    server = "",     -- "uai-relay" once a real companion answered
    placeId = 0,     -- last place the client paired from (display only)
},
```

Keep this separate from `bridge.*` on purpose (Section 4.13). `bridge.*` continues to
mean "the Cowork link". `relay.*` means "the local transport relay".

Timeout: for v1 the companion reuses `bridge.requestTimeout` (already in the UI and in
`relay.lua:13`). A dedicated `relay.requestTimeout` is listed as an open decision
(Section 12); if added, `relay.lua` resolves it per target (Section 5.3).

Validation: `config_transfer.validate` reconstructs from `config.defaults`, so new keys
are accepted automatically, but the mode must also be added to the `enums` table
(`src/runtime/config_transfer.lua:185-194`) and the port range checked explicitly.

### 5.2 New module: `src/net/relay_link.lua`

One module owns discovery, pairing, and status. It performs no long work and never
blocks boot.

```
M.mode()            -> "auto" | "always" | "off"        (from relay.mode)
M.mobile()          -> boolean                          (single definition, see 5.5)
M.usable()          -> boolean  paired AND last probe ok AND mode ~= "off"
M.target()          -> "cowork" | "companion" | nil     (shared with net/transport)
M.status()          -> { mode, state, port, server, instance, placeId, error, lastProbeAt }
M.ensure()          -> starts/stops the background prober to match mode + config
M.probe(force)      -> one attempt; returns ok, error
M.forget()          -> clears relay.token/instance/server; state = "searching"
M.changed           -> signal.new("relay")  (UI subscribes)
```

State machine:

```
off ─────────────▶ (no probing)
auto/always ─────▶ searching ──hello+pair ok──▶ ready
                        ▲                         │
                        └──── probe fails ◀───────┘  (30 s cadence, recoverable)
```

Rules:

- Probing runs only when `caps.has("http")`.
- `probe()`:
  1. `GET /api/hello` with a 1 s budget. Note `src/net/http.lua:268` floors any request
     at 1 s, so "500 ms" is not achievable; 1 s is the probe cost.
  2. Accept only if `protocol == 2` and `instance` is a non-empty string. When a
     `server` field is present it must be `"uai-relay"`; if `relay.token` is empty and
     the marker is absent, treat the port as occupied by something else and do **not**
     pair (this is what protects a PC running `bridge/server.js` on the same port).
  3. If not yet paired: `POST /api/pair` and persist `token`, `instance`, `server`,
     `placeId`. If already paired: just refresh `instance`.
- Cadence: re-probe every 30 s while `mode ~= "off"` (cheap: one hello), plus on demand
  ("Scan now") and on any `relay.*` config change. A single state-change log line per
  transition, not per probe.
- Recoverable failure: keep the token, set `state = "error"`, keep probing. A companion
  that is killed and restarted must come back without the user re-pairing. Only
  `forget()` clears the token.
- Instance skew: because the companion's instance changes on restart, a job started
  before a restart is rejected as "restarted" and never resubmitted (Section 4.3). The
  prober refreshes the instance so the *next* turn succeeds.
- Place id: read from `runtime/place` (`M.id`, `M.gameId`, `:30-33`) at pair time.

### 5.3 Changes to `src/net/relay.lua`

The file keeps its structure; only target selection and copy change.

- Replace the fixed reads of `bridge.port`/`bridge.token`/`bridge.requestTimeout`
  (`relay.lua:11-13`) with a resolved target from `net/transport`:
  - target `"cowork"` → base/token/timeout from `bridge.*` (today's values, today's
    messages).
  - target `"companion"` → base/token from `relay.*`, timeout from 5.1.
  - no target → the failure path (as today when the bridge is not enabled).
- Keep the hello-per-call (`relay.lua:34`). It costs ~5 ms and is what guarantees the
  instance is current; using a cached instance risks a spurious "restarted" failure
  after a companion restart within the 30 s probe window.
- Keep idempotent submit, the 3-attempt submit guard, DELETE-on-abort, and the
  "never resubmit" terminal semantics exactly as they are (`relay.lua:41-75`).
- Fix the `via` field: `"web"` for cowork (unchanged) and `"relay"` for companion
  (`relay.lua:30,56`). Consumers are limited to the transport label
  (`src/ui/panels/providers.lua:86`) and the request log; confirm no assertion depends
  on `via == "web"` for a companion path.
- Rewrite the two Cowork-worded failures (`relay.lua:32-33`) so the companion target
  says something actionable ("Start the Project UAI Companion app, then retry") while
  the cowork wording is untouched.

### 5.4 Provider gating

Today the relay is chosen inline in two providers and only for the Cowork web runtime:

- `src/provider/openai.lua:885` (force stream) and `:926`/`:949` (`web`, `relay = web`)
- `src/provider/anthropic.lua:496` (force stream) and `:523-524` (`relay = ...`)

Introduce one decision point, `src/net/transport.lua`, so providers, `relay.lua` and the
UI cannot drift:

```
M.coworkWeb()                 -- bridge.enabled and bridge.runtime == "web"  (today's rule)
M.companionReady()            -- relay_link.usable()
M.target()                    -- "cowork" | "companion" | nil
M.shouldRelay(imageRequest)   -- imageRequest or coworkWeb or companionReady
M.streamForced()              -- coworkWeb only (unchanged)
```

Provider edits become one-line substitutions:

- openai: `wantStream` force unchanged (cowork only); `web = transport.shouldRelay(imageRequest)`.
- anthropic: same shape for its single `relay` expression.

Behavioural notes:

- **Streaming** is forced only for Cowork (as today). For the companion, `stream` follows
  the user's setting; either way the body arrives whole from the relay and is parsed by
  `net/sse`, so output renders at completion. Incremental rendering is Section 12.
- **Images** already force the relay regardless of runtime
  (`openai.lua:925`, `anthropic.lua:523`) because the relay resolves image references
  (`bridge/inference.js` `prepareBody`). Consequence: on mobile, images require the
  companion (or Cowork). Without it, images fail, and the new copy must say so plainly
  rather than mentioning the web bridge.

### 5.5 Mobile detection

Single source of truth for "is this a phone/tablet":

```lua
-- matches src/ui/responsive.lua:90-92
touch and not mouse  ->  mobile
```

`ui/responsive.lua` already computes this, but it is a UI-layer module read at load.
`relay_link.mobile()` reads `env.uis.TouchEnabled` / `env.uis.MouseEnabled` under `pcall`
so a non-UI caller does not depend on the UI. Mobile detection is **presentation and
defaults only**; the prober runs the same way everywhere (auto-probe is safe on PC
because the hello marker check prevents pairing with a Cowork server).

### 5.6 UI surfaces

- `src/ui/panels/cowork.lua`: add a **Relay** card at the top. On mobile, hide/de-emphasise
  the Node installer card (`:163-192`) and show:
  - status line: `● Relay connected (Place 123456789)` / `○ Companion not found`
  - state from `relay_link.status()`, `relay.port`, masked token, `Scan now`, `Unpair`
  - a `Mode` segmented control: Auto / Always / Off (`C.segmented`, pattern at `:199`)
- `src/ui/settingspanes.lua`: list the companion in "Where your data goes" the way the
  bridge is listed (`:261-263`), because inference now leaves through it.
- `src/ui/panels/providers.lua:86`: report `Relay (companion)` as the transport when the
  companion is the active target.
- Text-only labels and the existing visual language; no new icon assets.

### 5.7 Commands and transfer

- `src/net/bridge_commands.lua`: allow `relay.*` in the `setting` branch (`:23`), add
  `["relay.mode"] = { auto=true, always=true, off=true }` to `choices` (`:29-38`), and a
  `relay.port` range `{1, 65535}` to `ranges` (`:40-45`).
- `src/runtime/config_transfer.lua`: add `["relay.mode"]` to `enums` (`:185-194`) and a
  port range check near `:198`. The `bridge_commands.lua:112` import guard already
  preserves `bridge`; add the same line for `relay` so importing settings on a phone
  cannot wipe the paired token.

### 5.8 Logging and diagnostics

- `relay_link` logs one line per state transition (paired, lost, mode change). Probe
  failures are silent between transitions to avoid log spam.
- The relayed inference remains recorded in the Requests view via the normal
  `http.request` path, with `via = "relay"`.

### 5.9 Backward-compatibility matrix

| Host | Cowork (web) | Companion | Result |
| --- | --- | --- | --- |
| PC | enabled | — | Cowork relay — **unchanged** |
| PC | disabled | — | Direct — **unchanged** |
| PC | disabled | paired | Companion relay (new) |
| Mobile | — | ready | Companion relay, in-game UI (new) |
| Mobile | — | absent | Direct + hint; images explain that a relay is required |
| Mobile | enabled (LAN) | — | Cowork relay — existing behaviour |

---

## 6. Companion app (Android / Kotlin)

### 6.1 Repository layout

Proposed as a `companion/` directory in this repo (separate repo is an open decision):

```
companion/
  settings.gradle.kts, build.gradle.kts, gradle/
  app/
    build.gradle.kts
    src/main/AndroidManifest.xml
    src/main/kotlin/dev/projectuai/relay/
      MainActivity.kt
      ui/                 Compose screens (Home, Jobs, Settings, Diagnostics)
      service/            RelayService.kt, BootReceiver.kt, WatchdogReceiver.kt
      server/             HttpServer.kt, Router.kt, Auth.kt
      engine/             JobEngine.kt, InferenceJob.kt, Forwarder.kt, Fingerprint.kt
      data/               RelayStore.kt (EncryptedSharedPreferences)
    src/test/kotlin/      JVM unit tests (no device)
    src/androidTest/kotlin/ Instrumentation tests
  README.md
```

Kotlin + Gradle KTS. `minSdk` and `targetSdk` are open decisions; a reasonable start is
`minSdk 26` (Android 8) and the current `targetSdk`. The APK must be built on a machine
with the Android toolchain; this repo carries source and tests only.

### 6.2 Process and component architecture

- `RelayService` is a foreground `Service` that owns the HTTP server, the socket and the
  job engine. The socket lives here, not in the Activity, so the relay survives the
  screen going off or the Activity being destroyed.
- `MainActivity` is a thin Compose controller that binds to the service for live status
  and issues Start/Kill. Closing it does not stop the relay.
- `BootReceiver` and `WatchdogReceiver` resurrect the service when permitted.
- Optional `android:process=":relay"` isolates the socket from a UI crash (adds an IPC
  hop; open decision).

### 6.3 Start and Kill

Single persisted flag `userStopped` is the source of truth.

- **START** (button, notification action, or auto-start): `userStopped = false`; start the
  foreground service; post the ongoing notification; bind the loopback socket.
- **KILL** (button or notification action): `userStopped = true`; stop accepting
  connections; cancel every in-flight job (closes the upstream calls); remove the
  notification; `stopSelf()`.
- Watchdogs and boot receivers return immediately when `userStopped` is true. This is what
  makes an explicit Kill stick while a launched service self-heals.
- Swiping the app out of Recents is **not** a Kill; `onTaskRemoved` restarts the service.

### 6.4 Survival ("MUST NOT DIE")

Ordered by importance.

**Manifest**

```xml
<service
    android:name=".service.RelayService"
    android:exported="false"
    android:foregroundServiceType="specialUse">
    <property
        android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
        android:value="local inference relay for the Project UAI client" />
</service>
```

- Use `specialUse`, **not** `dataSync`. Android 15 caps `dataSync` foreground services at
  6 hours per 24-hour period, which would terminate a long session; `specialUse` has no
  such cap. Play policy does not apply to a sideload.
- Permissions: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE`,
  `POST_NOTIFICATIONS`, `WAKE_LOCK`, `RECEIVE_BOOT_COMPLETED`, `SCHEDULE_EXACT_ALARM`
  (fallback `USE_EXACT_ALARM`), `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `INTERNET`,
  `ACCESS_NETWORK_STATE`. No storage permission.

**Runtime**

- `onStartCommand` returns `START_STICKY`; `onCreate` creates a LOW-importance channel
  (no sound, no vibration) and calls `startForeground`.
- `onTaskRemoved` schedules an immediate restart unless `userStopped`.
- **Watchdog**: `AlarmManager.setExactAndAllowWhileIdle` (or `setAndAllowWhileIdle` when
  exact alarms are denied) every 15 min; if `!userStopped` and the service is not running,
  start it. An exact alarm is a documented exemption from the Android 12+ restriction on
  starting foreground services from the background, which is why this is the reliable
  resurrection path rather than boot alone.
- **Battery**: hold `PARTIAL_WAKE_LOCK` only while at least one job is in flight; release
  when idle. Doze is largely irrelevant while the screen is on, and a permanently held
  wakelock is what gets an app uninstalled.
- **Battery optimisation exemption**: request
  `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` as an explicit onboarding step with a deep
  link to the settings screen.
- **OEM autostart is the dominant real-world killer**, more than stock Android. Detect
  `Build.MANUFACTURER` and deep-link the vendor screen for MIUI/HyperOS, EMUI, ColorOS,
  FuntouchOS and One UI. Treat this as required onboarding.
- **Force stop is unrecoverable on non-rooted Android.** Document it in onboarding.
- **Memory**: keep RSS small and purge job bodies at retention (Section 6.11). Under LMK
  pressure the largest process is evicted first, which is exactly why the relay must stay
  tiny while Roblox runs.

### 6.5 HTTP server engine (decision)

| Option | Footprint | Notes |
| --- | --- | --- |
| Ktor server (CIO) | ~1–2 MB, coroutines | idiomatic, testable, async |
| NanoHTTPD | ~50 KB, single file | tiny, synchronous, minimal |
| `ServerSocket` + custom parser | smallest | most code, most risk |

Recommendation: **Ktor CIO** for maintainability and JVM tests, with **OkHttp** for the
upstream. Revisit NanoHTTPD only if the footprint budget proves tight.

### 6.6 Forwarding engine

- One coroutine per job on a bounded dispatcher; at most 4 active (Section 4.10).
- One OkHttp `Call` per job with per-call timeouts; DELETE cancels the call cooperatively.
- Request normalisation mirrors `bridge/inference.js:143-183`: id regex, instance check,
  header filtering (`host`, `connection`, `content-length`, `transfer-encoding`,
  `accept-encoding`), forced `accept-encoding: identity`, computed `content-length`, URL
  scheme + no-credentials checks, timeout clamp `[10, 86400]`.
- Idempotency: SHA-256 fingerprint over url + sorted filtered headers + body + sessionId.
  Same id + same fingerprint returns the existing view; a different fingerprint errors.
- Response: store the raw body as text; `completed` carries `status`, filtered response
  headers (drop hop-by-hop) and `body`; cap at 8 MiB to match `src/net/http.lua:18`.
- Retention 60 s with tombstones; evicted ids answer `expired`.
- Error mapping: capacity → 503 (retryable by the client); malformed request → 400; unknown
  id on GET → 404.
- No delta/streaming endpoint in v1 (Section 12).

### 6.7 Storage and secrets

- `EncryptedSharedPreferences` holds `token` (64 lowercase hex), `port`, `userStopped`,
  `autoStart`, `allowLan`.
- Token generated once with `SecureRandom` and persisted; rotating it is a Settings action
  that immediately invalidates old clients (which then re-pair — only relevant if the user
  forces it).
- `instance` is generated per service start (`UUID.randomUUID()`), returned by `hello`,
  and never persisted.

### 6.8 Companion UI (Compose)

- **Home**: start/kill, status card (state, port, masked token + copy, connected place,
  uptime, active jobs, battery-exemption status).
- **Jobs**: recent inferences — provider host, duration, status, state, error, live counter.
- **Settings**: port, auto-start on boot, allow LAN (Section 7), notifications, battery
  exemption, rotate token, retention/clear.
- **Diagnostics**: log tail, survival self-test (Section 9.5), OEM help.
- **Notification**: ongoing, LOW importance, "Relay active · inference running 34s", with a
  Stop action.

### 6.9 Dropped from the earlier concept

- The shared workspace file (`/sdcard/.../uai_relay.json`) fallback is removed. It only
  solved token discovery, not transport, and it dragged in scoped-storage permissions.
- iOS is removed entirely.

### 6.10 Budgets

Idle RSS < 20 MB; ≤ 4 active jobs; ≤ 32 MiB retained; wakelock only while working; ongoing
notification while running.

---

## 7. Security model

| Threat | Mitigation | Residual |
| --- | --- | --- |
| Web page on the phone hits `127.0.0.1:8790` (including DNS rebinding) | Bind loopback; reject a non-loopback `Origin` (mirror `bridge/server.js:144-150`); validate `Host`; never emit CORS headers | A page cannot read a pair reply, so it cannot obtain the token |
| Another local app pairs and uses the relay | Rate-limit `/api/pair`; optional first-pair confirmation in the app; log pair events | A local app could use the relay as a generic HTTP proxy or DoS it; it cannot steal provider keys |
| Provider keys leaked | Keys only transit a job in memory; never persisted or logged by the companion; client already redacts via `log.redact` | Crash dumps are out of scope |
| SSR/SSRF via the forwarded `url` | Reject URLs with embedded credentials; reject link-local/metadata targets (`169.254.0.0/16`) by default | A local app could target an arbitrary public host; on-device threat only |
| Token theft from storage | `EncryptedSharedPreferences`; `allowBackup=false` (or data-extraction rules) | Rooted device is out of scope |
| Token in transit | Loopback only; never leaves the device | — |
| LAN exposure | **v1 binds loopback only.** The `allowLan` setting mentioned in 6.7/6.8 is deferred and hidden until a LAN feature ships, because exposing the relay on Wi-Fi changes the threat model entirely | — |

Additional hardening: no exported activities/services/receivers except the launcher;
`android:usesCleartextTraffic` is required only because user-configured providers may be
plain `http://` (default on `targetSdk` 28+ blocks cleartext); consider a network security
config that allows cleartext without weakening the rest. The API surface must reject
anything that is not the routes in 4.2, and must never serve files.

---

## 8. Failure modes and degradation

| Failure | Detection | Behaviour |
| --- | --- | --- |
| Companion absent | Probe fails in ~1 s | Direct executor transport; discreet hint; images explain a relay is required |
| Port occupied by another service | `hello` missing or marker absent | Not treated as a companion; never paired |
| Loopback unreachable for the executor | Spike gate (9.4) | Companion cannot help that executor; documented, not shipped as a promise |
| Companion killed mid-job | Poll transport error, then 404 after restart | Client keeps polling to its deadline; a reset instance produces a terminal "restarted" result rather than a resubmit |
| Companion restarted while idle | Next hello has a new instance | Prober refreshes; next turn works without re-pairing |
| Token rotated | Inference answers 401 | Terminal error; offer "Pair again" (probe re-pairs) |
| Provider slower than timeout | Companion cancels at timeout | `failed`; client reports the deadline, does not resubmit |
| Memory pressure evicts a job | `expired` state | Terminal; user retries a new turn |
| OEM kills the service | Heartbeat/watchdog | Resurrection if `!userStopped`; survival self-test tells the user which OEM setting to change |
| Force stop | — | Unrecoverable without reopening the app; documented in onboarding |

---

## 9. Test and verification plan

### 9.1 Client offline harness (runs here, no device)

New scenarios, either in a new `test/mobile_relay.lua` or appended to `run.lua`. The mock
HTTP handler can already script multiple loopback responses; the mock may need
`TouchEnabled`/`MouseEnabled` values and a second loopback "server" identity.

1. **Pair and relay end to end** — hello with `server = "uai-relay"`, pair issues a token,
   provider inference completes through the relay, result arrives, `via` reflects the
   companion target.
2. **PC Cowork unchanged** — with `bridge.enabled` + `runtime = "web"` and *no* companion
   marker, the request goes through Cowork exactly as `web_runtime.lua` asserts today;
   no pairing attempt is made.
3. **Companion absent** — probe fails; direct executor request is used; no errors, no
   request-history pollution from probes (they stay silent).
4. **`relay.mode = "off"`** — no probe, no relay.
5. **Instance skew** — hello returns a new instance after submit; the job is rejected as
   restarted and never resubmitted.
6. **Unknown id on poll (404)** — terminal, exactly one submission.
7. **Capacity 503 on submit** — retried with the same id, not duplicated; job runs once.
8. **Abort** — DELETE is sent and no resubmission follows.
9. **Probe recovery** — companion appears after boot; the 30 s prober (or Scan now) moves
   the state to ready and the next turn relays.
10. **Cowork precedence** — both Cowork and a companion configured; Cowork wins while
    `runtime == "web"`.
11. **Config transfer** — `relay.*` round-trips; importing settings does not clear the
    paired token; an invalid `relay.mode` is rejected.
12. **Cowork link isolation** — enabling the companion does not start `bridge.lua`; no
    `/api/agent/*` traffic is generated.

Existing suites that must stay green, unmodified: `test/web_runtime.lua`,
`test/config_transfer.lua`, `test/provider_transport.lua`, `test/mobile_*.lua`, and the
full `test/run.lua` plus `test/check.lua` as the project defines them.

### 9.2 Protocol contract fixtures

Because `bridge/` is frozen, the contract must be pinned independently of both
implementations. Deliverable: a small JSON fixture set under `companion/app/src/test/`
(and mirrored for the client tests) with, per route, a valid request, a response, and the
client-visible consequence. Derived strictly from Section 4. A checklist attached to
`relay.lua` changes ("if you change this file, re-run the companion contract tests") is
part of the deliverable.

### 9.3 Companion tests

JVM unit tests (no device): routing, auth (64-hex, constant-time), origin/Host rejection,
pair idempotency and rate limit, id regex, instance validation, header filtering,
fingerprint idempotency, retention/tombstones, capacity 503, unknown id 404, cancel,
8 MiB caps.

Instrumentation: service start/Kill, `userStopped` blocking watchdogs, notification
behaviour, startForeground across API levels, portrait/rotation, process death and
resurrection (`adb shell am kill`).

### 9.4 Executor compatibility spike — the go/no-go gate

Run before any app code. A small Luau script under each target executor measures:

1. Can `request()` reach another local process on `127.0.0.1:<port>`? (Spike listener can
   be a throwaway APK or Termux `nc`; it must not be the companion, which does not exist yet.)
2. Where exactly does the wall land for a slow response — 10 s, 20 s, 30 s, 45 s, 60 s?
3. Does setting `Timeout` in the request options change it? (`src/net/http.lua:240-243`
   already documents that some executors honour it and some do not.)
4. Does the wall change when Roblox is backgrounded or the screen is locked?
5. Are there payload-size or concurrent-call limits that matter?

Executors: Delta, Codex, Arceus X, Hydrogen, Fluxus (extend as needed). Exit criteria:
primary executors can reach loopback and demonstrably cut long calls; executors that do
not cut long calls are documented as direct-capable and do not need the companion.

### 9.5 Manual device matrix and survival self-test

- **Survival self-test (in-app)**: start the service, ask the user to lock the screen and
  open Roblox for 2 minutes, then report heartbeat continuity, whether the service was
  killed, and whether it was resurrected — with the OEM setting to change if it failed.
  This is how "MUST NOT DIE" is proven on the user's actual phone rather than asserted.
- Devices: Pixel/stock (Android 12–15), Xiaomi HyperOS, Samsung One UI, Oppo/vivo, plus a
  low-end Android 10 device.
- Cases: 120 s inference; 4 concurrent jobs; screen lock; Recents swipe; `adb shell am kill`;
  force stop (expected unrecoverable); reboot with auto-start on/off; battery saver on/off;
  airplane mode mid-job; provider timeout exceeded.

---

## 10. Roadmap

Effort figures are rough and assume one developer familiar with the client. Each phase
ends with the project's audit-then-build-then-verify order (audit inputs, build, inspect
outputs, then run tests) from `AGENTS.md`.

| Phase | Work | Exit criteria | Rough effort |
| --- | --- | --- | --- |
| **0. Spike (gate)** | Executor loopback + wall measurements (9.4) | Loopback reachable on primary executors and long calls demonstrably cut; otherwise stop and re-plan | 2–4 days |
| **1. Client** | `relay.*` config, `relay_link`, `transport`, `relay.lua` target split, provider gating, UI, commands/transfer, offline tests | `test/run.lua`, `web_runtime.lua`, `config_transfer.lua`, `provider_transport.lua`, `mobile_*` all green; PC Cowork byte-for-byte unchanged; companion path proven against a stub server in the harness | 3–5 days |
| **2. Companion MVP** | Ktor server, router, auth/pair, job engine, fingerprint, Start/Kill, notification, basic Compose UI | JVM tests green; on a device, a real inference from the client completes through the companion; Start/Kill behave | 2–3 weeks |
| **3. Survival hardening** | `specialUse` FGS, watchdog alarms, battery exemption, OEM onboarding, wakelock policy, survival self-test | Self-test survives lock + Roblox foreground for 2 min; resurrection after `am kill`; Kill stays down | 1–2 weeks |
| **4. Polish** | Jobs/diagnostics UI, token rotation, docs, budget tuning | Budgets met; README/onboarding complete | ~1 week |
| **5. Streaming (optional)** | Deltas endpoint + `relay.lua` extension + incremental UI | Reply renders progressively on the phone | TBD |

Phase 1 ships value on its own: it also enables pointing the client at a relay running
anywhere reachable (a LAN PC or a VPS running the unmodified `server.js`), which needs no
Android app.

---

## 11. Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Executors block loopback to another app | Companion cannot work | Phase 0 gate; no app code until measured |
| The "30 s wall" does not exist on some executors | Companion unnecessary there | Phase 0 measurement; document direct-capable executors |
| OEM background killing | "MUST NOT DIE" fails on real phones | `specialUse` FGS, exact-alarm watchdog, OEM onboarding, self-test |
| Force stop / clear-all | Unrecoverable without reopen | Documented onboarding |
| Android FGS policy keeps changing | Future OS updates break survival | `specialUse` (no 6 h cap); keep watchdog independent of boot |
| Buffered output UX (spinner until done) | Perceived slowness | Accepted v1; Phase 5 deltas |
| Second protocol implementation drifts from `relay.lua` | Silent breakage | Contract fixtures (9.2) + companion tests; `relay.lua` change checklist |
| Mobile memory pressure evicts jobs early | `expired` results | Small caps + 60 s retention; retry is a new turn |
| Sideload friction / Play Protect prompts | Install friction | README + onboarding; no Play dependency |
| Open pair endpoint abuse by a local app | Proxy/DoS | Rate limit, loopback-only, Host/Origin checks, optional confirmation |
| No JDK/SDK in this environment | Cannot build the APK here | Source + JVM tests in-repo; APK built on a toolchain machine |

---

## 12. Open decisions

1. **HTTP engine**: Ktor CIO (recommended) vs NanoHTTPD vs custom.
2. **`allowLan`**: ship in a later version, or never (v1 is loopback-only).
3. **Separate `relay.requestTimeout`** vs reusing `bridge.requestTimeout` (v1 reuses).
4. **Pair confirmation**: fully zero-touch, or a one-time in-app "a client wants to pair"
   confirmation on first pair.
5. **`via` naming**: rename `"web"` to something transport-neutral, or add `"relay"`
   alongside it (this plan adds `"relay"`).
6. **minSdk / targetSdk** values.
7. **Process isolation** (`:relay`) yes/no.
8. **Repo location**: `companion/` here vs a separate repository.
9. **Delta/streaming** support and its protocol shape.
10. **App name and package id**.
11. Whether PC `server.js` should also grow an explicit `/api/pair` later purely for
    symmetry (not required; the client can keep using a pasted token for Cowork).

---

## Appendix A — Client change map

| File | Location | Change |
| --- | --- | --- |
| `src/runtime/config.lua` | `:203-209` | Add the `relay` defaults block |
| `src/net/relay_link.lua` | new | Probe/pair/status/state machine |
| `src/net/transport.lua` | new | `target()`, `shouldRelay()`, `streamForced()` — single decision point |
| `src/net/relay.lua` | `:11-13`, `:30`, `:32-33`, `:56` | Target-based base/token/timeout, `via`, companion-aware copy |
| `src/provider/openai.lua` | `:885`, `:926`, `:949` | Route via `transport.shouldRelay(...)`; stream force stays cowork-only |
| `src/provider/anthropic.lua` | `:496`, `:523-524` | Same |
| `src/net/bridge_commands.lua` | `:23`, `:29-38`, `:40-45`, `:112` | Allow `relay.*`; mode choices; port range; preserve `relay` on import |
| `src/runtime/config_transfer.lua` | `:185-194`, `:198`, summary | `relay.mode` enum, port range, optional summary field |
| `src/ui/panels/cowork.lua` | `:163-203` | Relay card; mobile hides the Node installer card |
| `src/ui/panels/providers.lua` | `:86` | "Relay (companion)" transport label |
| `src/ui/settingspanes.lua` | `:261-263` | List the companion in "Where your data goes" |
| `test/mobile_relay.lua` | new | Scenarios in 9.1 |
| `docs/MOBILE_COMPANION.md` | new | This document |
| `companion/**` | new | Android app, tests, README |

## Appendix B — Companion request examples

```bash
# Discovery (no token required)
curl -s http://127.0.0.1:8790/api/hello
# -> {"ok":true,"protocol":2,"instance":"...","server":"uai-relay","capabilities":{...}}

# Pair (loopback only; no Origin header)
curl -s -X POST http://127.0.0.1:8790/api/pair \
  -H 'content-type: application/json' \
  -d '{"client":"ProjectUAI-Mobile","version":"1.0.0","protocol":2,"placeId":123456789}'
# -> {"ok":true,"token":"<64 hex>","instance":"...","protocol":2}

# Submit (as relay.lua does)
curl -s -X POST http://127.0.0.1:8790/api/inference \
  -H 'authorization: Bearer <64 hex>' -H 'content-type: application/json' \
  -d '{"id":"inference_XXXX","instance":"...","url":"https://provider/v1/chat/completions",
       "headers":{"Authorization":"Bearer <provider key>"},"body":"{...}","timeout":180}'
# -> 202 {"id":"inference_XXXX","state":"running"}

# Poll / cancel
curl -s http://127.0.0.1:8790/api/inference/inference_XXXX -H 'authorization: Bearer <64 hex>'
curl -s -X DELETE http://127.0.0.1:8790/api/inference/inference_XXXX -H 'authorization: Bearer <64 hex>'
```

## Appendix C — Config reference

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `relay.mode` | enum | `"auto"` | `auto` probes and pairs; `always` requires it (still probes); `off` disables |
| `relay.port` | number | `8790` | Companion port |
| `relay.token` | string | `""` | Set by `/api/pair`; stable across companion restarts |
| `relay.instance` | string | `""` | Last instance seen; diagnostics/skew detection |
| `relay.server` | string | `""` | `"uai-relay"` once a companion answered |
| `relay.placeId` | number | `0` | Last place paired from; display only |

`bridge.*` keys are unchanged and continue to drive Cowork.

## Appendix D — Executor spike script (sketch)

```lua
-- Run under each mobile executor. Replace PORT with a throwaway listener on the device.
local PORT = 8790
local function timed(name, fn)
    local t = tick(); local ok, res = pcall(fn); local dt = tick() - t
    print(("%s ok=%s in %.1fs -> %s"):format(name, tostring(ok), dt,
        tostring(type(res) == "table" and (res.StatusCode or res.Status) or res)))
end
-- 1. Loopback reachability
timed("loopback hello", function()
    return request({ Url = ("http://127.0.0.1:%d/api/hello"):format(PORT), Method = "GET",
        Headers = { Accept = "application/json" }, Timeout = 5 })
end)
-- 2. Where the wall lands (listener delays N seconds before answering)
for _, seconds in ipairs({ 10, 20, 30, 45, 60 }) do
    timed("slow " .. seconds .. "s", function()
        return request({ Url = ("http://127.0.0.1:%d/slow?ms=%d"):format(PORT, seconds * 1000),
            Method = "GET", Timeout = seconds + 15 })
    end)
end
-- 3. Repeat step 2 with Timeout omitted, and once more with the screen locked.
```

Record per executor: reachable yes/no, wall size, whether `Timeout` changes it, behaviour
under lock/background, payload limits. This result decides whether the companion ships.

<!-- END -->
