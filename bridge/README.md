# Cowork bridge

Use UAI in your browser while Roblox runs your tools and keeps the conversation.
Run both on the same computer. The [Windows desktop app](../desktop/README.md)
detects installed Node.js and offers a verified download if needed. Open the
single Windows executable from the [latest release](https://github.com/Project-Ptolemy/ProjectUAI/releases/latest),
complete Node setup, click **Start
Cowork**, and load the updated UAI script. The browser opens and Roblox connects
automatically on dedicated port **28791**. No terminal or token copying is needed.

The bridge needs **Node.js 18 or newer** and has no production npm dependencies.

Join the [Project UAI Discord](https://discord.gg/9xYyyYuKap) for help, provider
availability updates and new free options. Add Project UAI Free explicitly from
the Providers library if you want that route. HCNSEC is a separate provider.

## Obsidian notes

Open **Settings → Obsidian** to connect a vault folder on this computer. Browse,
search, copy and download Markdown notes in the browser, or let the agent use
the `obsidian` tools. Connections start read-only; enable editing explicitly to
create or change notes. Revision checks protect against overwriting observed
external edits, and disconnecting keeps your files.
See [Obsidian setup](../docs/OBSIDIAN.md) for limits and conflict recovery.

## Free model tunnels

Open **Tunnels** in the Windows app or Cowork to inspect OpenCode, Kilo and
Cline. The Windows switches apply on the next bridge start. Cline requires a
separately installed CLI and a signed-in Cline profile;
choose **Cline (Bridge)** in Providers and fetch its current free models.
The Windows app checks CLI installation before Cowork starts and provides
**Refresh installed apps** independently of connection and sign-in checks.
Kilo starts its private connection only after a completed anonymous quota refusal.
See [Cline setup](../docs/CLINE_TUNNEL.md) and [Kilo setup](../docs/KILO_TUNNEL.md).
Quotas and free promotions remain controlled by each service.

## OpenCode on desktop

For external harnesses that should run Roblox tools directly, the bridge also
provides native MCP over Streamable HTTP and stdio. Open **Settings → MCP** for
connection details, or follow the [MCP setup guide](MCP.md) for Claude Code,
Codex, Cursor, OpenCode and command-based MCP clients. Roblox retains permission
decisions and executes tools in isolated external sessions.

For free API-key requests, use the current UAI client and bridge. The client adds
truthful Roblox environment context; the bridge matches OpenCode's native TLS
cipher-suite offer on exact official Zen Chat/Responses routes. The same service
key returned HTTP 200 for DeepSeek Flash outside the CLI in November 2 tests.
Certificate validation stays enabled; no Bun installation is needed. Direct
executor and Android TLS behavior remain unverified. See the
[API-key investigation](../docs/OPENCODE_API_KEY_INVESTIGATION.md).

Version 3.2 also added an optional native route through an **already installed
OpenCode CLI**. Install
[OpenCode Desktop](https://opencode.ai), restart Cowork, and wait for its OpenCode
status to become ready. UAI does not download or package the OpenCode binary.
OpenCode free models require the UAI Relay app from Discord on mobile; install and
start the app, then connect it in UAI. Project UAI Free also remains available.
The retired OpenCode HTTPS proxy is never used; the proxy supports AgentRouter only.

**OpenCode Go subscriptions use a separate endpoint:**
`https://opencode.ai/inference/go/v1`, with your Go API key. The legacy
`https://opencode.ai/zen/go/v1` route also remains accepted. Go requests use that
endpoint directly and never enter the isolated native free-model connection.
The desktop-only free-model restriction does not apply to Go subscriptions.

The bridge detects OpenCode Desktop's per-user and all-user Windows installations,
macOS app bundles, native `opencode-cli`/`opencode` binaries on PATH, and
`~/.opencode/bin`. It also finds native payloads behind npm and Bun shims, including
the Windows user npm folder when the desktop app inherited an older PATH, active
nvm paths, and custom `NPM_CONFIG_PREFIX`/`BUN_INSTALL` locations. For the current
standalone v2 CLI, use `npm install -g @opencode/cli`; the legacy `opencode-ai`
package may still install an incompatible v1 server. After installing, stop and
start Cowork. Quoted PATH folders are supported. A custom native binary may be
selected with the absolute `UAI_OPENCODE_BINARY` environment variable; an invalid
override is reported as missing instead of silently selecting another installation.
Shell shims and the Electron Desktop launcher are not executed.
`UAI_OPENCODE_DISABLED=1` disables this optional CLI route; direct keyed HTTPS
requests still use the bridge's Zen transport compatibility.
OpenCode's v2 server API is required (verified with CLI 2.0.32). The bridge checks
all required routes before accepting requests and reports the selected binary's
actual version. Incompatible installations produce an update instruction.
If more than one native installation is present, setup checks the next candidate
after stopping an incompatible or failed one. An older CLI on PATH cannot hide a
working v2 installation. This happens before inference; a running request never
switches CLI processes or repeats inference. An explicit binary override selects
only that installation.
The desktop app's **OpenCode tunnel** switch persists between launches and applies
when Cowork starts. It controls this private local connection, not a public tunnel.

The bridge starts `serve` privately on a random loopback port with a random Basic
Auth password and isolated configuration/data directories. It never reads the
user's OpenCode account credentials or forwards a provider key to that process.
Only models reported by the native public catalog route through it; paid/custom
models and installations without a ready native backend retain the direct path.
Model discovery uses authenticated `GET /api/opencode/models`; `/api/hello` exposes
`capabilities.opencode = {schema:1, enabled, available, state, models, binary?, version?, message?}`
without CLI credentials. Disabled, missing, starting, ready and failed states are
distinct; `binary` is only the executable's filename.

Each request gets a temporary native session and location. UAI tools are exposed
through a private MCP server, collected after the provider stream completes, and
returned as ordinary tool calls for Roblox to execute. Native desktop actions are
never approved. A private plugin adds an execution permission gate even when a
native tool wrapper omits its own permission request. Exact UAI tool names on the
private remote MCP server remain available; other host execution must ask.
The native built-in schemas remain visible, as hiding them causes upstream
`FreeTierError`. The bridge waits for a tool's matching pending permission,
including requests that appear after its tool state. A desktop tool choice with
that permission becomes a reserved `opencode_host_action` refusal
receipt after the stream finishes and interruption is confirmed. The next normal
Roblox agent step can use an available tool; the bridge never repeats the native
prompt or approves that desktop action. Mixed batches retain provider order even
when MCP calls arrive out of order. Text/reasoning previews and image
attachments pass through the native API. Stop interrupts and deletes the session;
bridge shutdown stops the owned CLI and removes its temporary data. Requests keep
their original bridge ID across polling retries. No inference deadline is added.
Usage totals include cached input and reasoning output; cache reads, cache writes,
and reasoning counts remain available separately for UAI's usage accounting.

## Start in three steps

1. **Start the desktop app.** Download the Windows executable from the
   [official release](https://github.com/Project-Ptolemy/ProjectUAI/releases/latest).
   Open **Workspace**, finish Node.js setup if requested, then click **Start Cowork**.
2. **Connect Roblox.** Load the updated UAI script on this computer. In
   **UAI → Cowork**, keep **Find desktop app automatically** enabled. Use
   **Reconnect** if discovery was disconnected. Credentials refresh automatically
   and stay in memory.
3. **Open Cowork.** Choose **Open Cowork** in the desktop app, select a provider
   and model, then send a message. Keep Roblox and the app open while you work.
   Use **Stop bridge** in the app to end the desktop connection.

**Disconnect** in Roblox suspends discovery until **Reconnect**. Turning off
automatic discovery saves that choice. Older saved manual port, token and enable
values are discarded when the client loads or imports configuration.

## Automatic updates

The bridge checks official stable GitHub releases after startup and every 15
minutes, downloads compatible releases and verifies the package and file SHA-256
hashes. It activates updates only when inference, commands, agents and retained
receipts/pictures are idle. Pairing tokens survive automatic worker restarts.
Failed downloads or startup keep a working version. Git checkouts and executor
download packages are never overwritten; updates live in a per-install user cache.
The desktop app can also trigger one immediate supervised check through the
authenticated `POST /api/desktop/update-check`; the supervisor answers with its
update state before any restart it causes. The cache keeps the active version
and recent entries, and prunes stale predecessors and quarantine folders.

Publish `dist/bridge-release.json` and `dist/uai-bridge-package.json` on the same
official `v4.0.5` GitHub release. Bridge-only releases may use a matching
`bridge-v<version>` tag. Release 4.0.5 supplies the client, bridge,
web UI and Windows app together; the Android companion retains its separate
release. Generate the bundles with
`node tools/build_bridge.js` after reviewing final bridge/web inputs, inspect
the outputs, then run `node tools/build_bridge.js --check` and focused tests.
Later releases must bump `bridge/release.js` and use the matching release tag.
The release builder embeds OpenCode, MCP and support helpers into the original
permitted root filenames so compatible installed updaters can verify and activate 4.0.5. Checkout,
executor downloads and desktop payloads retain the separate source modules.

Existing compatible installs receive bridge and web updates while idle.
Refresh an open browser page to load changed web assets. The desktop's **Copy
client script** uses its embedded client; update the desktop app to refresh that
copy. See the [4.0.5 release guide](../docs/RELEASE_4_0_5.md),
[3.8.0 verification record](../docs/POLISH_2026_10.md),
[3.6.5 verification](../docs/TESTING_3.6.5.md) and the earlier
[bridge 3.6.2 record](../docs/TESTING_3.6.2.md).

The [desktop app](../desktop/README.md) independently downloads its own release
and applies it on restart. An old 1.0 desktop ZIP needs one manual upgrade first.

## Working in the browser

- **Streaming is real when the provider supplies it.** Cowork reads incoming SSE
  chunks and pushes text/reasoning deltas to the browser as they arrive. Roblox
  also displays those deltas through short status polls, roughly once a second,
  when both the bridge and script include the native-preview update. Restart the
  bridge and reload the script to use it. Old bridges, direct executor HTTP and
  providers that return only a final answer cannot show text before delivery.
  The installed OpenCode route reads its evolving local response; it cannot
  expose output that the installed CLI has not returned yet.
- **Chat** follows the active Roblox conversation. Use the sidebar to find or
  start conversations; draft text and code files stay with their conversation.
  An empty conversation centers the prompt and composer, with quick ideas below.
  Live answers format as they arrive; new text fades in while completed paragraphs
  and code remain steady. Thinking and tool details open when you want to read them.
  Each user turn has one response heading and continuous answer text. Tools,
  thinking and delegated updates share a collapsed **Activity** drawer below the
  answer. Progress and failures remain visible in its summary; permission prompts
  stay outside it. **Copy response** copies the answer without internal activity.
  Expand reasoning for its formatted text and separate Copy action. Error cards
  explain the problem and show recovery actions; the original diagnostic remains
  available under technical details.
- **Runtime follows the connection.** Successful authenticated bridge contact
  selects Web automatically, with live responses when the provider supports
  streaming. Disconnecting restores Game for subsequent requests. Roblox owns
  conversations and tools in both modes; reconnecting never resends a message.
- **Bridged requests have no overall time limit.** Cowork waits for completion,
  Stop, or a real provider/connection failure. This is permanent, with no timeout
  setting. Individual status polls stay short and reuse the original request ID;
  a stalled poll does not submit the provider request again.
  A missed or unusable desktop-discovery check pauses admission through that
  connection while accepted requests keep polling their verified endpoint.
  Recovery reuses the same job; Stop, turning off discovery, changed desktop
  credentials/instance and actual terminal provider failures still end it.
  Waiting inference jobs do not occupy the native HTTP slots needed for those
  polls. The bridge cannot remove a provider's own timeout or a tool's execution
  deadline.
- **Attach text or code** with the paperclip, drag a file onto the composer, or
  paste long text. Large inputs become verified files that the agent can read.
  Limits: 10 MiB per file/input, 16 text files and 16 MiB per draft.
- **Attach pictures** with the image button, paste, or drop. PNG, JPEG and WebP
  are sent as **actual image content** to your selected model; choose one that
  supports vision. Reload the updated game client and restart the bridge first.
  Limits: 8 pictures, 5 MiB each, 20 MiB held by the
  bridge, 4096 × 4096 and 12 megapixels. Animated images are not supported.
- **Stop** cancels the current turn. Closing or refreshing the browser does not.
  If delivery is unclear, use **Check delivery** before sending again.
- **Follow-ups** can be sent while an answer is running. They wait visibly above
  the composer and enter the conversation in order at a safe turn boundary.
  Expand a numbered message to read or copy it, edit inline text, or move it up
  or down. Images stay attached; file-backed inputs keep their verified text.
  Clear removes only the messages reviewed in its confirmation. Stale changes
  are rejected and your current composer draft remains intact. Remove a pending
  message or use Resume queue after Stop, a failure, or a budget limit pauses
  the queue. Stop stays separate from the follow-up send action.
- **Connection, Providers, Tools, Subagents, Chat loops, Memory & skills, and
  Activity** open in a modal workspace above your conversation. Switch views in
  its top navigation; nested provider and tool dialogs return to the same view.
  Connection shows the browser, bridge, and Roblox status with desktop setup
  guidance. Close the workspace to return to your draft.
- **Settings** opens a focused modal above your conversation. General offers
  Light, Dark, System, and Roblox theme previews. Appearance, Agent, Advanced,
  and Data organize your remaining preferences; changes save as you go.
  **Settings → MCP → Copy setup prompt** gives your desktop agent the detected
  connection details and instructions to configure and verify MCP for you.
  The MCP section also offers configuration snippets for individual harnesses.
  Free models have a rounded green border and Free label in the picker, the
  composer, and provider summaries. Available auto-routing probe status is
  displayed without promising the same latency on future requests.
  The model picker pairs searchable model cards with context/output limits and
  the selected model’s supported reasoning controls. Temperature handling can
  follow known model/provider support automatically or explicitly send/omit the
  shared value for a model. Provider setup supports Gemini generateContent as
  well as OpenAI-compatible and Anthropic Messages APIs. The composer’s context ring
  opens a token breakdown and compaction threshold; partial estimates and unknown
  context limits are labelled explicitly.
  **Subagents → Preview** opens live output, expandable tool progress/results,
  and task/access details in separate tabs. Reading position, open calls and
  follow-up drafts survive live updates. When the run finishes, send a follow-up
  into its retained context or copy its report; Stop remains independent.
  Browser previews retain bounded excerpts and up to 12 active/recent tool calls.
  Conversation text scaling keeps sidebar labels compact. Dialogs keep their
  headings and actions available while long forms scroll, and restore focus
  when dismissed. Client animations are permanently enabled; browser system
  reduced-motion preferences still apply to browser transitions.
  Exported conversations include picture metadata, not image bytes. A full
  configuration copy excludes credentials by default; private copies require
  the explicit credentials choice.

Commands can arrive immediately while Roblox's long poll is waiting. Desktop
polls can wait 18 seconds; touch-only mobile clients request one-second polls
with short request deadlines. Game updates are batched about
every 150 ms, live browser text paints about every 60 ms, and command receipts
are checked every 250 ms. These are batching intervals, not an end-to-end latency
guarantee; executor scheduling and the provider's response time also matter.

## If something is stuck

| What you see | What to do |
| --- | --- |
| Node.js is missing | Use **Get Node.js** or **Manual setup** on the app's Workspace page, then **Check again**. |
| The desktop app cannot start Cowork | Check its startup details and verify that port 28791 is available. |
| Roblox is waiting to connect | Keep Roblox and UAI Bridge open on this computer. Click **Start Cowork** in the app, enable automatic discovery in Roblox, then choose **Reconnect**. |
| The browser asks for a token | Choose **Open Cowork** in the desktop app to open its current authenticated link. |
| Live responses are unavailable | Check that Cowork says connected and Web runtime, then check provider SSE support. Non-streaming providers still return a complete reply. |
| A picture is expired or unavailable | Attach it again. Pictures expire after 15 minutes of inactivity and disappear when the bridge stops. |
| The bridge is reconnecting | Keep your draft in the tab and restart/reconnect the bridge. Review the conversation if a delivery receipt was lost. |
| A deadline error appears | Use the highlighted Discord tutorial link. Cowork imposes no overall deadline, but an upstream provider or transport can still fail. |
| OpenCode reports `FreeTierError` | Use the current UAI client with Project UAI Desktop Bridge for the verified free API-key route. Direct executor access depends on the host transport. The bridge also supports a separately installed OpenCode CLI for free models. On mobile, use the UAI Relay app from Discord. [Discord help](https://discord.gg/9xYyyYuKap). |

## Development and tests

`server.js` owns authenticated loopback routes, command receipts and browser SSE.
`inference.js` owns provider requests and bounded preview replay. `picture-store.js`
keeps validated image bytes in memory. `launcher.js` restores existing distribution packages.
`opencode.js` owns the external native server, temporary sessions and MCP handoff;
`support.js` supplies consistent Discord error help.
`supervisor.js` owns the worker process, token and idle replacement;
`updater.js` validates releases and maintains the isolated cache.
`web/` contains the dependency-free UI, Markdown, previews, pictures, themes and
asynchronous draft storage. Roblox remains authoritative in both runtimes.

Checkout development can start `node bridge/server.js --desktop` to expose the
same automatic discovery route on port 28791. Native Cowork setup uses desktop
discovery; the client has no bridge file downloader or token/port inputs.

All bridge tests live in `tests/`. Shared utilities are in `tests/helpers/` and
synthetic game/image inputs in `tests/fixtures/`. The JPEG/WebP fixtures are real
encoded images; tests generate valid PNG chunks without additional dependencies.

Manually audit implementation, documentation and test changes, then build:

```powershell
luajit tools/bundle.lua --native
node tools/build_bridge.js
node tools/build_site.js
```

Inspect the generated client, bridge and site outputs before verification:

```powershell
node tools/build_bridge.js --check
node --test bridge/tests/opencode-native.test.js bridge/tests/opencode.test.js bridge/tests/desktop.test.js bridge/tests/security.test.js bridge/tests/streaming.test.js bridge/tests/updater.test.js
luajit test/web_runtime.lua
luajit test/desktop_bridge.lua
```

For real browser checks, install Playwright **outside this repository**, including
its Chromium browser. Set `PLAYWRIGHT_MODULE` to that package's absolute directory
if it is not on the normal module path. Optionally set `UAI_SCREENSHOTS` to an
output directory, then run:

```powershell
node bridge/tests/run.js --browser-only
```

The browser suites cover navigation, forms, streaming, picture ownership/replay,
upload cancellation, receipt races, full drafts, themes, drawer focus, token
recovery, CSP, reduced motion, and 320–1440px layouts. The UI audit suite also checks
short screens with full drafts, long task lists and model names, live question and
selection updates, dialog errors, keyboard focus, contrast, and forced colors.
The model picker also follows provider additions, renames and removals while
open, and preserves its rows, focus and scroll position on unrelated workspace
updates. Malformed and duplicate model IDs are ignored. The lifecycle fixture
checks these behaviors with an 800-model catalog.

Tunnels opens a loading dialog immediately when fetching free models. Closing
that dialog cancels its browser request, and a late response cannot reopen it
over a different page. Failed reads offer **Try again** inside the same dialog.
Connection usage shows **Unknown** when no request has a known cost. Mixed
usage labels the known estimate and states how many unpriced requests it
excludes; a confirmed zero-cost model remains distinct from missing pricing.
Inspect the saved screenshots as well as checking geometry. These fixtures do not
replace a live executor check. See the [UI audit](UI_AUDIT.md) for the findings.
The [3.6.5 verification record](../docs/TESTING_3.6.5.md) records the current
release checks. The [3.6.0 record](../docs/TESTING_3.6.0.md),
[3.5.6 record](../docs/TESTING_3.5.6.md) and
[3.3.5 record](../docs/TESTING_3.3.5.md) remain available for the earlier releases.

Protocol remains version 2. `/api/hello` advertises optional picture and normalized
stream capabilities. `--legacy` disables pictures and uses compatibility delta
frames. Raw provider response bodies remain separate from browser preview rings;
oversized or truncated responses fail explicitly. Picture capability v2 uses
`provider-image-content`; game state advertises `imageInput = true`. The bridge
rejects image sends to older clients instead of substituting text markers.

Fresh browser connections share at most 4,096 preview deltas and 7 MiB across
32 running/recent uncommitted jobs. Running jobs take priority; older preview
omissions are announced. Each shortened tail has a gap notice and retains its
terminal outcome. This leaves room for the saved transcript backlog and picture
catalog during bounded browser recovery. Raw Roblox receipts stay complete, and
recovery never submits inference again.

Image sends carry compact, conversation-scoped references into model context.
At inference dispatch, the bridge expands them to Chat Completions `image_url`
data URLs, Anthropic base64 `image` blocks or Responses `input_image` blocks.
Image-bearing requests use the relay in either
runtime. Tokens, image bytes, and provider keys are never added to browser event
frames. A missing current image fails explicitly; expired earlier images become
a clear unavailable-image text block so a later text-only turn can continue.
Request retries use their original ID before resolving images, so expiry cannot
cause a second provider dispatch. Active upload bodies and provider bodies are
bounded separately. Model vision support remains provider-specific.

The bridge binds to loopback, rotates its bearer token on restart,
checks browser origins and serves local assets under a same-origin CSP. Desktop
mode adds a native-only local discovery route with exact Host checking, a custom
POST header, browser-header rejection and no CORS. See the desktop guide for its
local-program trust boundary and launcher lifecycle tests.
