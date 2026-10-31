# Changelog

## 3.8.0 - October 31, 2026 - Everyday work, easier

Client, bridge, browser workspace and Windows desktop: **3.8.0**.
UI LIB: **1.6.0**. Embedding SDK: **1.1.0**. Android companion: unchanged **3.7.1**.

### Script goals and tool discovery

- New installations use the Focused tool profile: available actions fit into at most nine families plus seven direct workflow tools. Saved profiles remain selected.
- Each family lists exact action names and supplies full schemas on demand. Calls retain the original action's validation, approvals, hooks, deadlines and conversation/request scope.
- All, Lean and task-specific profiles remain available. Hidden permitted actions can still be reached through tool_search.
- On-demand tool help includes validated, copyable examples for 25 core workflows without executing them or adding their full detail to every request.
- Script goals persist with the conversation and follow Define, Inspect, Plan, Build, Validate and Review stages.
- Goals contain 1–16 acceptance criteria, stage evidence and explicit block, resume and rewind actions. Code shows the saved goal and copyable progress.
- Validation records actual compiler and test receipts. Source changes invalidate prior checks; checks that began before an edit or a replacement goal cannot validate the new work.
- A failed final check reopens validation. Completion requires current successful syntax checks and evidence for every acceptance criterion.
- Typing invalidates goal state immediately and coalesces its save after a short pause; explicit goal actions save immediately.

### Code workspace and project creation

- Create a basic project or a UI LIB interface starter from Code, with a manifest, settings and tests. The interface starter separates its view from a testable domain model and owns cleanup.
- Review every proposed new file before applying a project. Existing files and unsaved bound Code drafts are protected.
- Project setup drafts survive cancelled previews. Untouched proposals are discarded, while applied or partial checkpoints remain available for recovery.
- Cancelled or stale previews cannot resume writes after a yielded read; opening another turn, clearing a conversation or unloading invalidates the captured operation.
- Quick-open scripts with Ctrl+P and search retained workspace source with Ctrl+Shift+F. Results show source lines and reject stale revision locations.
- Jump to a line and Unicode column with Ctrl+G. Navigation is guarded against a document changing before the delayed focus operation.
- Toggle comments, duplicate or delete selected lines, trim trailing spaces and convert indentation between tabs and four spaces as undoable source changes.
- Reopen recently closed script views with Ctrl+Shift+T, cycle open tabs with Ctrl+Tab, close other views and copy a script's name from its tab menu.
- Reload a clean draft from disk while preserving edits or bindings changed during the read. An unavailable existence probe cannot be treated as a missing file.
- Document details show lines, bytes, line-ending style and selection size. Library, file and history search support words, phrases and excluded terms.
- Source comparisons copy bounded change summaries and identify the current change region. Previous change starts at the final region correctly.
- Clear completed run output while retaining running work. Empty output and omitted printed lines are described explicitly.
- Typed forms retain detached drafts, validate required and whole-number values, focus invalid fields, support Enter submission and reject repeated in-flight submissions.
- Virtual lists support page and edge navigation and handle empty selections safely.

### Obsidian vaults

- Connect up to 16 local Obsidian or Markdown vault folders through the bridge. Connections start read-only; disconnecting preserves notes.
- Vault paths reject traversal, hidden entries, symbolic links or junctions, hard-linked notes and non-Markdown files. Replaced roots become unavailable.
- Read UTF-8 Markdown notes up to 1 MiB in explicit bounded pages. Native full-note assembly verifies one revision, byte count and advancing offset throughout.
- Create, replace or append notes with revision checks. Stale revisions and uncertain writes require reading current state before another explicit save.
- Search paths and note content with bounded traversal and visible incomplete-coverage notices.
- Inspect titles, headings, inline tags, raw frontmatter and supported scalar properties. Frontmatter inspection does not claim complete YAML parsing.
- Explore wiki links, local Markdown links and backlinks with explicit resolved paths and ambiguous matches; code examples are excluded from backlinks.
- Browser vault controls include connection management, vault selection, paginated browse/search, new-note drafts, editing, copy and download.
- Native Settings opens the note browser, editor, metadata and link navigation directly, including folder/text filters and pagination.
- Native saves preserve existing CRLF style and verify the returned path, revision and size. Unconfirmed saves cannot be blindly repeated.
- Conflict review offers Keep draft or Use file after reading the current note. Neither review action writes.
- Closing an editor keeps up to eight unsaved or uncertain note drafts in memory. A ninth is refused without evicting edits; recovery clears on unload.
- Agent vault tools retain UAI permissions and each vault's read-only policy. Models cannot connect arbitrary folders or enable editing; listings omit absolute folder paths.
- Damaged vault configuration is preserved for recovery, filesystem errors are sanitized and bridge packages include the required vault modules.

### Conversation organization and recovery

- Pin conversations within folders. Pinned histories also receive priority when restoring the bounded set of loaded conversations.
- Unread reply and failure counts follow actual background output. Viewing or marking a conversation read clears them; minimized windows do not silently mark output read.
- Browse All, Pinned, Unread or failed, Running and Has draft views, with title, folder and recent-transcript search.
- Conversation browsing and transcript results fill the dialog width, wrap long titles and size to their contents. Blank searches retain all conversations, and closing the browser releases its filter menu.
- Find in conversation supports words, quoted phrases, exclusions, message/reply/error filters and older-result continuation, then opens the stable transcript event.
- Composer drafts recover from existing conversation storage after a typing pause. Oversized updates preserve the previous complete recovery, and restoring never sends.
- Draft recovery follows the conversation's existing storage choice and adds no separate recovery file. Draft details show word/byte counts and offer Copy text.
- New file references retain SHA-256 fingerprints where supported, detecting same-size edits before sending restored follow-ups. Older references retain their size checks.
- Large attachment fingerprints check cancellation in bounded batches and yield by elapsed CPU time, keeping other work responsive without forcing frame delays on fast hashes.
- Attachment details show paths, sizes and validation state, copy paths and remove references without deleting files.
- Task plans and bounded notes persist per conversation. Active tasks restore as pending; completed and dropped tasks retain their state.
- Queued follow-up messages and plan details can be copied. Home continuation cards show retained messages, pending work and draft state without switching the worker.
- Markdown export previews retained dialogue before copying or saving, excludes tool internals and hidden reasoning, and verifies saved output.
- Conversation search offers further result pages and preserves Unicode excerpts instead of presenting system/tool context as an ordinary reply.

### Conversation and delegated-work lifetime

- Conversation checkpoints serialize overlapping writes and retain newer dirty revisions.
- Burst creation of background conversations coalesces sidebar refreshes into one owned update, avoiding repeated full-list layouts.
- Deleting a conversation or choosing Not saved cleans up an already-running old checkpoint and reserves its ID until that write finishes.
- Stale callbacks cannot change the storage choice of a removed conversation or recreate deleted history.
- Delegated workers intersect the parent's available original actions and request-local exclusions. Full presets and later follow-ups cannot widen an earlier child's scope.
- Stopped or replaced tool contexts remain cancelled even when a later send clears the conversation's ordinary abort flag.

### Provider setup and key management

- Project UAI Free is an optional Providers library preset. Fresh, reset and empty imported configurations no longer insert a provider automatically.
- HCNSEC remains separate for personal keys. Community authentication is restricted to the official Free endpoint and historical mixed setups migrate separately.
- Preset transitions remove incompatible community authentication while preserving supported user settings and labels.
- Free availability distinguishes schedule closure, paused keys and locked access. Countdown refreshes preserve the favorite label and actionable status.
- Exact model IDs share trimmed UTF-8 validation, a 160-byte limit and rejection of control characters.
- Catalog parsing deduplicates IDs, bounds processing and reports invalid, non-chat or partial results without caching an unusable empty catalog.
- Model selections and list edits restore the previous in-memory state when saving fails.
- Model lists support search, favorites-only filtering, up to 100 favorites and the last 12 unique successful selections per provider.
- Favorite and recent-model changes reorder existing controls, preserving focused search and scrolling instead of rebuilding the catalog.
- Public configuration transfers retain model shortcuts without keys, validate provider buckets and limits, and detach applied preference snapshots.
- Key management searches names and status without searching secrets, and refreshes preserve focused edits.
- Replacing a key pool preserves surviving key names, pause state, accounting identities and selected-key position; removing a pinned key restores rotation.
- Provider cards expose sanitized health, availability, paused-key counts and effective API/transport explanations.
- Duplicate setup opens an unsaved draft with safe connection/model settings and omits credentials and custom header/body maps.
- Reset learned compatibility clears inferred API/output behavior while preserving quota cooldowns, health and accepted request ownership.
- Browser provider forms validate model IDs, headers and preset transitions. Stale forms cannot recreate removed providers.

### Network and model compatibility

- A shared deadline begins before WebSocket setup. HTTP fallback, provider retries and proxy recovery spend the original remaining request budget.
- Deadline parsing rejects invalid or nonfinite inputs while retaining the explicit unlimited relay policy.
- Retry-After accepts bounded numeric seconds and GMT HTTP dates for cooldown scheduling.
- Custom HTTP header names, values and counts, plus URL and User-Agent input, are bounded and validated before dispatch.
- Vendor pricing requires the documented HTTPS vendor route; arbitrary paths and stacked API suffixes no longer inherit vendor pricing.
- Bearer authorization matching is case-insensitive for per-key accounting without treating unrelated header formats as Bearer credentials.
- OpenCode, Cline and Kilo capabilities require supported schemas and coherent states; malformed or stale snapshots show unavailable.
- Model refreshes and bridge callbacks reject results from replaced provider settings or obsolete connection generations.

### UI LIB 1.6 appearance

- Neutral is the default palette, with Graphite, Ocean, Forest and Rose alternatives across Dark and Light themes.
- Built-in Appearance offers Standard/High contrast, Comfortable/Compact/Spacious density, Rounded/Soft/Square shape and Sans/System/Mono typography.
- Simple tab headings are the default. Detailed shows section/control counts; Hidden removes the introduction and remains hidden during search.
- Appearance changes preserve field drafts, focus and validation, and remeasure text using the selected font.
- The library retains fixed Project UAI | UI LIB. attribution, text-only navigation/actions and its frame-drawn brand and window controls.

### UI LIB controls and script workflow

- NumberInput combines typed finite values, bounds, step quantization, Less/More actions and form validation.
- TextView supplies selectable read-only text, bounded append, scroll-to-end and honest clipboard failure results.
- ItemList provides stable item IDs, search and explicit pages for up to 500 entries, retaining only a still-valid selection after replacement.
- ActionGroup exposes one to eight named actions with independent busy states and owned asynchronous work.
- Callout presents a semantic message with an optional owned action. KeyValue displays up to 64 ordered responsive facts with copied snapshots.
- Complete-form GetValues/SetValues, per-field drafts, required/pattern/custom validation, commit and reset support larger script forms.
- Named profiles store values and appearance through supplied storage callbacks and validate the full data before application.
- Window-owned tasks, delayed work and debounce are cancelled during cleanup, including same-ID window replacement.
- Stable-ID Reveal and search open the correct tab/section, expand collapsed content and scroll to a control without activating it.
- Seven runnable examples and focused appearance, forms, lifecycle, profiles, collections and readout guides accompany the generated bundle and embedded reference.

### Native settings, focus and everyday controls

- Both settings surfaces search public labels, categories and exact paths, then reveal the matched control. Saved values and credentials never enter the index.
- Settings search/category changes preserve field instances, unfinished drafts and reading position where the pane remains valid.
- Sliders support keyboard/controller steps, Home/End and Page Up/Down with a single commit; hidden controls and text-entry focus suppress slider shortcuts.
- Disabled switches, rows and buttons ignore activation. Busy buttons remain unavailable across enable refreshes, and read-only fields support select-all.
- Hiding the main window releases text/gamepad focus while retaining drafts. Quick Chat preserves caret/selection across appearance rebuilds and keeps rejected sends.
- Password setup Enter advances to confirmation, Show/Hide preserves selection and leaving the app remasks visible passwords.
- What's new searches release notes and copies the entire latest release even with an active filter.
- Failed invite copies select the existing read-only link for manual copying. Cached ready headshots avoid repeated resolution during view rebuilds.
- Timeout messages explain uncertain completion and link directly to request-wait settings.
- Find a command reaches actions, settings and conversation titles. Ctrl+K, Ctrl+Shift+P, Ctrl+comma and Ctrl+L provide common navigation and focus shortcuts.
- Shared clipboard workflows report host refusals instead of claiming a successful copy.

### Script loading screen

- A responsive branded startup card replaces the plain loading pill.
- Prepare, Restore and Open stages follow real startup boundaries. Actual loaded-component counts remain separate from stage progress.
- Elapsed time and a hint after eight seconds without progress explain slow startup without inventing an overall percentage.
- Failures retain a readable failed stage until dismissed; full exceptions remain in the console.
- Successful completion waits until the bridge, embedding SDK and final initialization finish. Pulse, listeners and delayed exit work are owned and cleaned up.
- The native reduced-motion setting remains retired.

### Desktop 3.8.0 and embedding SDK 1.1.0

- The standalone Windows app packages the 3.8.0 client, bridge and required Obsidian browser assets, retaining extraction manifests and hash validation.
- Desktop capability parsing matches native rules, clears stale details on disconnect and ignores delayed update callbacks from an obsolete bridge generation.
- Ctrl+1 through Ctrl+5 navigate Workspace, Connections, Updates, Settings and Tunnels through the existing commands.
- SDK request events, completion data, snapshots and await results are detached from internal state.
- SDK scopes own delayed callbacks, cancel them on destruction, release completed resources and expose active resource counts.
- SDK tool registration bounds descriptions and schema depth/size while preserving validated union argument types.
- The Android companion remains unchanged at 3.7.1.

### Website, guides and release preparation

- Website tool filters have shareable query/group/risk URLs, restore on load and update browser history without adding unrelated parameters.
- Website setup distinguishes optional Project UAI Free from personal-key HCNSEC and links Obsidian and getting-started guidance.
- The README is a short introduction with focused setup, conversation, provider, Code, UI LIB and troubleshooting guides.
- Startup and settings/accessibility guides explain the new native controls; SDK documentation clarifies authentication, reruns and resource lifetime.
- Release notes include a file-by-file change ledger that separates authored source, regression tests, examples and generated outputs.
- Client, bridge, browser workspace and desktop target 3.8.0, with independently versioned UI LIB 1.6.0 and SDK 1.1.0. Local preparation does not publish a release.

See the [file-by-file ledger and verification record](docs/POLISH_2026_10.md)
and [release artifact notes](docs/RELEASE_3_8_0.md).

## 3.7.2 - October 29, 2026 - Password vault and scheduled free access

- Offer password protection by default and a red **Continue without encryption**
  choice. The explicit alternative verifies reversible byte-encoded storage,
  preserves key pools, leaves saved API keys unprotected, and skips future password
  prompts. Existing encrypted vaults must unlock or reset before opting out.
  Legacy session-only preferences alone cannot make this choice.
- Use AES-256-SIV and PBKDF2-HMAC-SHA256 entirely in bundled Luau. Existing
  byte-encoded and plaintext keys migrate with their exact pool metadata after an
  encrypted save is staged and verified. Cancellation and failed saves preserve
  current keys. Password changes and locking are available in Privacy.
  New vaults and explicit password changes use **100,000 iterations** for less
  derivation work. Existing 600,000-iteration vaults keep their recorded count;
  using Change master password, including the same password, rewrites at 100,000.
  Password entry remains required on each execution while a vault is enabled.
- Show encryption/unlock progress as a compact percentage with Cancel and Exit
  at the screen edge. The password dialog and backdrop hide during the wait;
  access remains gated, and failure or cancellation restores entry.
- Encrypt custom authentication fields alongside key pools and omit temporary
  key-rotation maps, which can contain duplicate keys.
- Exclude credentials from normal settings copies and diagnostics. Keep a separate
  clearly labelled private copy that retains encryption when enabled or reversible
  encoding otherwise. Encrypted imports request their source password before
  review; imports retain this device's storage choice and vault password.
  Older byte-encoded imports remain supported for migration.
  Preserve unreadable encoded records and reject unsafe imports instead of silently
  discarding credentials. Existing exported files and backups are not automatically erased.
- Replace the included community credential, migrate exact retired included keys
  on the official endpoint and store only a community reference in config/exports.
  Encode its bundle representation to deter literal searches; it remains recoverable
  by scripts with equivalent executor access. Personal keys are not rotated remotely.
- Admit included Project UAI Free requests daily from **20:00 to 06:00 UTC+8**
  (Beijing/Singapore), with UI guidance and paused off-hours background probes.
  Accepted replies continue across closing; personal HCNSEC keys are unaffected.
- Explain that dashboard key replacement/revocation differs from UAI's request
  rotation. Bridge, desktop and companion implementations remain unchanged.
- Keep reasoning levels visible when enabling reasoning support in a short model
  picker. Compact provider details and the effort caption first; only extremely
  limited keyboard space uses the existing Options fallback.
- Rename the Claude Code Settings tab to **Project UAI**.

## 3.7.1 - October 25, 2026 - UI polish, individual API keys and Kilo free routes

- The Roblox client joins the bridge, web UI and Android companion (version
  code 8) at 3.7.1. The Windows desktop remains 3.7.0. Installed bridges and
  companion apps pick the patch up automatically from the `v3.7.1` GitHub
  release; the companion APK keeps the existing production signing identity.
- Manage provider credentials in a dedicated modal with named, masked entries.
  Add, rename, replace or remove one entry without overwriting the others.
  Rotation is the default; choose one specific key for inference and discovery.
  Removing the selected key restores rotation. Apply/Cancel keeps edits isolated,
  and configuration transfers retain key names and request preferences.
  Preserve existing key pools, automatic rotation and unsaved provider drafts;
  saved credentials stay masked, including keys shorter than five characters.
- Pause and resume individual keys without deleting their names or local usage.
  Show requests and input/output tokens per key, with estimates marked. Keep a
  paused selected key pinned until the user resumes it or changes the selection.
- Show each conversation's AI request count in its header and context breakdown.
  Count retries, tool follow-ups, summaries and subagents; retain local counters
  across reloads. Earlier untracked requests are not reconstructed.
- Finish the provider gallery and configuration polish with clearer sections,
  model controls and validation. Keep the setup guide expanded by default.
- Fit log details and context breakdown to their contents, retaining scrolling
  when space is limited. Give shared modal bodies consistent padding and improve
  the Discord invitation, tutorial and donation dialogs.
- Keep model search, provider selection and footer controls fixed while the model
  list scrolls. Show names and metadata on separate lines, preserve focused fields
  through compact layouts, and keep reasoning options reachable on small screens.
- Group related settings, reveal the selected category, wrap long answer choices
  and improve tool, conversation and subagent rows. Keep larger text readable in
  compact controls, captions and forms.
- Keep long Code documents and previews visible while selecting text, with bounded
  syntax and selection layers aligned to native line spacing. Improve comparison
  contrast, document tabs, status details and resize gesture cleanup.
- Accept Kilo free routes whose model id ends in `free` behind any separator:
  `:free`, `/free` or `-free`. `reflection/beam-free` — the only free route
  spelled with a dash in the October 25 catalog — and the `openrouter/free`
  router previously failed the tunnel's model check, bypassed quota recovery
  and returned the anonymous refusal directly. Verified live: with the local
  address limited, the same `reflection/beam-free` request completed HTTP 200
  through a fresh Tor exit. See [Kilo quota recovery](docs/KILO_TUNNEL.md) and
  the [3.7.1 verification](docs/TESTING_3.7.1.md).

## 3.7.0 - October 25, 2026 - Models, tunnels and faster workflows

- Align the Roblox client, bridge/web UI, Windows desktop and Android companion
  at 3.7.0; Android advances to version code 7 with its existing production signer.
- Use native Responses for AgentRouter GPT models, with the selected reasoning
  effort, stateless requests and optional tool fields preserved. Verify an actual
  UAI tool batch and result replay with `gpt-6.1-sol`. See [AgentRouter](docs/AGENTROUTER.md).
- Add Vercel AI Gateway, Friendli, Venice, Nscale, Arcee, AI/ML API and Perplexity
  Orchestrator presets with documented access labels and [setup guides](docs/providers/README.md).
  Filter explicitly incompatible catalog entries and add searchable model menus.
- Add a Tunnels page to the Windows bridge and Cowork for OpenCode, Kilo and
  Cline. Cline uses the separately installed, signed-in CLI and its live free
  model catalog. The new Cline (Bridge) provider requires the local bridge;
  Roblox keeps tool execution, approvals and Stop. See [setup](docs/CLINE_TUNNEL.md).
- Detect installed OpenCode and Cline apps before Cowork starts. Keep installation,
  enablement and connection readiness separate, with an independent refresh.
- Refresh the Roblox model picker with searchable saved providers, clearer model
  details and connection health, and larger controls on touch devices. Cancel
  stale catalog refreshes when closing the picker or switching providers.
- Keep the Remotes Following action readable on narrow screens with larger text;
  the toolbar scrolls instead of compressing the action label.
- Refresh prices and context/reply limits from five catalog sources on October 25:
  1,760 entries across 15 providers, including 401 Kilo entries and five exact
  Cline free promotions. Preserve unknown prices and provider-specific rates.
- Add multiword Tools and Logs searches, ranked tool discovery and useful schema
  page sizes. Avoid building hidden parameter controls and cloning every schema
  during discovery. Bound retained logs after redaction.
- Reject invalid token counters, retain cache-write totals and persist unknown-cost
  request counts in usage history. Show incomplete cost coverage on Home.
- Keep Cowork catalogs current after provider changes while preserving focus and
  scroll. Cancel closed catalog dialogs and discard late results; unrelated state
  snapshots no longer rebuild large model lists.
- Recover completed anonymous Kilo quota refusals through a private Tor tunnel,
  enabled by default and started only when needed. Limit circuit retry to one,
  suppress repeated terminal refusals for 60 seconds, preserve deadlines and
  cancellation, and exclude signed-in requests and other providers.
- Add switches and live connection status in the apps, Cowork web UI and Roblox.
  Honor upstream `x-should-retry: false` instead of repeating terminal refusals.
- Ship the Windows helper by pinned, verified download and native Tor in the
  Android APK. Retain old bridge updater compatibility by embedding new modules
  in its existing release package filenames.
- Correct stale Kilo quota claims and document the observed IP-scoped recovery,
  account limits, shared-exit limitations and [setup](docs/KILO_TUNNEL.md).
  Recovery does not guarantee unlimited requests.
- Include the 3.6.7 WPF desktop, reliable bridge payload packaging, manual update
  checks and cache cleanup. See [verification](docs/TESTING_3.7.0.md).
- Fix tunnel shutdown races, retained-request memory accounting and stale
  browser connection status after disconnect or bridge replacement. Update the
  Android build toolchain for the current Tor library's compile API requirement.

## 3.6.6 — October 23, 2026 — A provider gallery and a clearer queue

- Rebuild the add-provider flow as a gallery. Add a provider opens three tiers --
  Recommended, Paid and Local -- with a search field that spans them, a result
  count, and one card per provider carrying a description, an access line and an
  access label. The custom-endpoint card closes every tier. Choosing a card seeds
  the editor with that preset; nothing is written until Save.
- Grow the catalog to 66 presets: 16 recommended, 38 paid, 11 local and the custom
  endpoint. Recommended now reads Project UAI Free (Included), AgentRouter (Free
  tier), OpenCode Zen (Free models), OpenRouter (Free models), OpenCode Go (Free
  CLI), then Kilo, OVHcloud, Gemini, Groq, Cerebras, Mistral, ModelScope, Z.ai,
  NVIDIA NIM, Cloudflare Workers AI and Aion Labs.
- Label access honestly. Hybrid services are recommended and named by their free
  half, so OpenCode Zen, OpenRouter and OpenCode Go are never labelled Paid.
  Highlighting is carried by the catalog, so the accent border stays on Project
  UAI Free, AgentRouter and OpenCode Zen wherever they sit in the list.
- Keep the catalog free of routes this client cannot serve. LLM7 is removed;
  GitHub Models was retired on 30 July 2026; Perplexity's root-path API and
  Databricks' invocations route would be misrouted by the base-URL normaliser and
  remain reachable only through a custom endpoint. Kilo and OVHcloud no longer
  send the Claude Code identity.
- Rebuild the queued-messages surface as Up next: a state line with a dot,
  numbered cards with the next message marked, edit, reorder and remove on a quiet
  row, an empty state, and a live byte counter in the editor. The composer's queue
  strip is tinted and shows the held state as a dot.
- Open the settings modal from the sidebar's Settings row (formerly Customize) on
  the General pane, and remove the duplicate Settings entry under More. Give the
  profile menu's Tutorial row its icon.
- Document the gallery in [SPEC.md](SPEC.md) and
  [provider compatibility](docs/PROVIDER_COMPATIBILITY.md), and record the focused
  verification in [3.6.6 testing](docs/TESTING_3.6.6.md).
- Ship the client as 3.6.6. The bridge already ships as `bridge-v3.6.6`; the
  Windows and Android downloads remain 3.6.5 until their own builds.

## Bridge 3.6.6 — October 22, 2026 — Runtime context for MCP harnesses

- Tell external MCP harnesses what they are actually connected to. The
  `initialize` instructions and every tool description now state that tools act on
  one live Roblox client, that Roblox Studio is never involved, that reads observe
  this client's replicated DataModel, and that writes stay local and remain subject
  to the game server. A harness model previously received only its own system
  prompt, so it could answer as if UAI were a Studio project.
- Apply the same statement to the OpenCode tunnel, which sent no instructions at
  all and passed tool descriptions through unchanged.
- Refresh the conversation reading surface. Transcript, composer, tables and code
  share one 720px measure; headings use a 28/22/18/15 ladder with balanced wrapping;
  each answer is separated by a hairline and introduced by a monogram byline with a
  model chip; the activity drawer is a quiet footnote row instead of a card; and
  tables, code headers, inline code, links and the floating jump control were
  restyled. No markup or class contract changed.
- Publish the bridge package as `bridge-v3.6.6`. Existing installs receive it
  automatically while idle. Client, desktop and Android downloads stay 3.6.5.

## 3.6.5 — October 21, 2026 — Reliable connections and a refreshed desktop

- Release the client, bridge, Windows app and signed Android companion together
  as 3.6.5. Preserve verified updates and the Android production signing identity.
- Refresh the Windows launcher with clearer connection status, setup, runtime
  and update controls. Correct single-instance startup so an unowned existing
  mutex does not silently discard the first launch; retain early restore requests.
- Share unfinished native HTTP ownership on touch-only devices across discovery,
  new requests, Stop and supported client reloads. Keep one independent bounded
  cancellation lane, and retain desktop parallel capacity.
- Enforce Always use relay after failed discovery. Stop oversized or malformed
  relay replies once without polling the same unusable response indefinitely.
- Check the complete UTF-8 companion response, including both JSON escaping
  layers, before expanding large provider bodies. Return a small 413 error above
  8 MiB, preserving the exact receipt and original provider submission.
- Bound expanded mobile reasoning before Markdown formatting and native layout.
  Label the excerpt and preserve full reasoning in model context and persistence.
- Add read-only network and payload capture (`net_capture`). Fixed forwarding
  hooks observe executor and game HTTP, `HttpService` methods, `loadstring`,
  `load`, `require` and queued code without rewriting arguments or results.
  Bounded records redact credentials, link responses to compiled chunks by hash
  or thread, flag code-like responses that never compile, exclude UAI's own
  requests and compiles, and restore hooks on Stop. See
  [the capture guide](docs/NET_CAPTURE.md).
- Add opt-in tool profiles and a `tool_search` toolbox. **All tools** stays the
  default; leaner profiles declare a core set, while hidden tools remain callable
  with the same permissions, groups and conversation scope. See
  [the tool context guide](docs/TOOL_CONTEXT.md).
- Retain large tool results in a durable per-conversation evidence ledger without
  changing the inline receipt. The default 8 KiB threshold skips small results and
  tools with their own persistent home, and identical results are deduplicated.
  Writes are queued and batched off the tool path with a 64-result / 4 MiB bound,
  so a fast model cannot grow the queue or block every call on disk. Settings →
  Agent → Tool evidence can switch to all, large or off. `evidence`
  lists, searches and pages full text or structured data after compaction, while
  `evidence_clear` removes a conversation's ledger. Other conversations remain
  unreadable.
- Add a local, redacted support bundle for bug reports. It collects capabilities,
  provider health, permissions, enabled tools, session metadata, recent HTTP
  failures and logs, while excluding API keys, memory, custom instructions,
  conversation text, file contents and captured payloads.
- Include bridge 3.6.2's verified OpenCode execution permission gate. The reported
  Android SIGSEGV has no native backtrace; these fixes remove reproduced defects
  without claiming to identify or reproduce that device crash.

## Bridge 3.6.2 — October 21, 2026 — OpenCode execution permission gate

- Fix the remaining `OpenCode could not verify that a desktop tool was blocked`
  failure after 3.6.1. OpenCode's native execution wrapper did not always ask for
  permission, and a tool could appear before its pending permission request.
- Install a private execution gate in the isolated OpenCode server, preserving
  the native schemas required by free models. Host tool execution must ask for
  permission; exact UAI calls on the private remote tool server remain available.
  Wait for the matching permission and confirmed interruption before returning
  blocked-action feedback to the Roblox conversation.
- Publish the bridge package as `bridge-v3.6.2`. Existing desktop 3.6.0 installs
  receive it automatically when idle. Client stays 3.6.1; desktop and Android
  downloads stay 3.6.0.

## 3.6.1 — October 20, 2026 — OpenCode tunnel tool recovery

- Keep OpenCode conversations running when the model selects a desktop tool.
  Verify that its permission is blocked, interrupt the native session, and return
  a non-executable receipt so the Roblox agent can select a real available tool.
- Preserve provider order for mixed desktop/Roblox tool batches, including MCP
  calls that arrive out of order. Stop, invalid handoffs and provider errors remain
  terminal; desktop actions are never approved and native prompts are not replayed.
- Release client and bridge 3.6.1. Existing desktop 3.6.0 fetches the bridge and
  web files automatically while idle; refresh the browser and reload the published
  Roblox client. Desktop and Android app downloads remain 3.6.0.

## 3.6.0 — October 19, 2026 — Clearer conversations and reliable connections

- Rebuild the public Project UAI page with a white monochrome palette, responsive
  layouts, an interactive animated 3D centerpiece and SVG motion. Keep installation,
  downloads and the searchable tool catalog close at hand, with pause and
  reduced-motion support.
- Rebuild bridge conversations around the assistant's answer. Each turn has one
  heading and a collapsed activity drawer for tools, thinking and delegated work.
  Expand details when needed; approvals and failures remain visible.
- Give reasoning a readable formatted view with its own Copy action. Present
  errors with a clear explanation and recovery actions, keeping original
  technical diagnostics available in a separate disclosure.
- Find installed OpenCode CLI binaries behind npm and Bun launchers, in common
  Windows user/system folders, active nvm paths and macOS app resources. Handle
  quoted PATH entries and show detected versions with actionable setup guidance.
- Decode compressed companion POST requests before JSON parsing. Previously,
  gzip message bodies produced `invalid executor request` before inference could
  start even when pairing succeeded. Bound both wire and expanded request sizes,
  preserve authentication and same-job retries, and report malformed encodings
  without logging credentials or message contents. The reported Delta failure
  occurs at this decoding stage; its device-specific encoding remains unobserved.
- Redesign UAI Relay around clear connection status, one Start/Stop action,
  short setup steps and compact request activity. Keep advanced settings and
  diagnostics out of the main setup flow while retaining update recovery controls.
- Release client, bridge, Windows desktop and signed Android companion 3.6.0.
  Existing production Android installs keep their signing identity and pairing.
- Keep bridge update status tied to the version actually serving requests during
  an automatic worker replacement.

### Changes since 3.5.6

- Correct the mobile OpenCode guidance. OpenCode now works on Android through the
  UAI Relay app from Discord: install and start the app, then connect it in UAI.
  A user confirmed OpenCode inference on a Delta Android phone after manually
  retrying an initial `Relay rejected the request (400)`. Phone tool execution,
  tool-result replay and background survival remain unverified.
- Add companion 3.5.7's authenticated POST transport for Delta builds where
  `request` fails on loopback but `HttpGet` works. The client discovers through
  `HttpGet` and uses `HttpPost` for pairing and authenticated operations,
  preserving job IDs, deadlines and cancellation. A companion update is required.
- Probe companion request compatibility with unauthenticated hello requests.
  A completed executor exception can try the minimal documented request format
  and distinct native request aliases. A validated, authenticated selection is
  retained for local polling and cancellation; provider requests are not replayed
  to discover a working transport. Diagnostics identify the attempted formats.
- Keep native HTTP timeouts positive after worker scheduling; fractional remaining
  budgets no longer become `Timeout = 0`. The original caller deadline still
  applies and a timed-out native request keeps its slot until it actually ends.
- Allow five seconds per companion discovery and pairing exchange. Report the
  actual connection, HTTP or protocol failure instead of treating every failed
  hello as an absent companion. Discovery remains quiet during background scans.
  See [discovery verification](docs/TESTING_RELAY_DISCOVERY.md).

## 3.5.6 — October 18, 2026 — Mobile relay reliability and automatic updates

- Fix companion request admission by sending finite timeouts as integer seconds,
  matching the Android protocol instead of submitting rejected fractional values.
- Negotiate unlimited default inference with updated companions, removing the
  unintended five-minute client limit while keeping each executor exchange within
  five seconds. Explicit deadlines and older companions retain finite budgets.
  Lost polls reuse the original job; Stop, lost receipts and upstream failures
  stay terminal without replaying inference.
- Authenticate saved pairing, repair explicitly rejected tokens, and rediscover
  a newly started companion when sending instead of waiting through idle backoff.
- Show live client contact separately from saved pairing, plus accepted/active
  requests, received bytes and safe failure categories. Accepted jobs immediately
  own foreground activity and a wake lock. A two-minute ownership lease cancels
  orphaned jobs after Roblox stops polling and releases idle resources.
- Add automatic Android update checks at startup and every 15 minutes while the
  app or relay process runs. Download compatible official releases by default,
  verify size, SHA-256, package/version/SDK and signing certificate, and preserve
  verified downloads across restart. Manual download remains available.
- Require Android installation approval and idle work before replacing the app.
  Persist the owned installer session and admission pause across interruptions;
  resume the relay only after successful replacement or cancellation of that
  session. Explicit Stop remains authoritative.
- Publish the signed Android companion with release metadata and a checksum.
  Earlier debug-signed installs need a one-time uninstall/reinstall and new
  pairing; production updates use the same signing key and preserve app data.
- Add executor loopback/polling/cancellation probes and a controlled delay fixture.
  OpenCode text, tool calls and tool-result replay passed on Windows using the
  companion's Java HTTP library and settings. **Native Android, mobile executor
  behavior and OpenCode acceptance on a phone remain unverified.** OpenCode free
  models remain unsupported on mobile; use Project UAI Free or another supported
  provider. See [mobile research](docs/OPENCODE_MOBILE_RESEARCH.md). (Corrected
  October 18, 2026: mobile OpenCode requires the UAI Relay app from Discord.)
- Ship client, bridge, Windows desktop and Android companion 3.5.6. UI LIB remains
  1.3.0 and SDK 1.0.0. See [companion updates](companion/UPDATES.md) for signing and
  installation details.

## 3.3.5 — October 18, 2026 — Stronger agents and desktop bridge

- Strengthen main and worker prompts with exact native tool-call rules,
  schema-aware arguments, observed targets, complete pagination, safe recovery
  and evidence-based completion. Keep detailed guides on demand.
- Fix the incomplete 128-tool workaround from `fbd093a`: retain access to tools
  beyond the provider's declaration ceiling through a bounded catalog adapter.
  Tool execution still uses the original dispatcher, scope and permissions.
- Refresh the desktop dashboard with persistent OpenCode tunnel, MCP server,
  browser-open and automatic desktop-update switches. Minimize stays on the
  taskbar; closing the app stops its bridge and exits instead of hiding in the tray.
- Check the installed OpenCode CLI version and required API routes, distinguish
  disabled/missing/failed states, and report actionable setup details. Verify
  real native tool handoff and tool-result replay with CLI 2.0.32.
- Improve queued-message review, editing, ordering and clearing in Roblox and
  the browser, preserving attachment ownership and rejecting stale edits.
- Refine bridge assistant responses and tool-call cards with readable outcomes,
  clear progress, and deliberate access to exact inputs and results.
- Ship matching client, bridge and Windows desktop 3.3.5 artifacts. UI LIB stays
  1.3.0 and SDK 1.0.0; the mobile companion is unchanged.

## 3.3.1 — October 17, 2026 — Live bridge previews and interface fixes

- Move native temperature controls to Models → Options → Temperature so they
  no longer squeeze the model list. Soften free-model outlines in Roblox.
- Restore the queued-message count and review action above the native composer.
- Give bridge tool calls compact summaries, clear status and readable errors,
  with full inputs and results available on demand.
- Deliver real bridge text and reasoning previews to Roblox while inference is
  still running. Keep the completed response authoritative and avoid replaying
  buffered Gemini responses as live output.
- Stop counting waiting relay jobs as native HTTP connections. Concurrent bridge
  agents retain capacity for their short polls without inheriting the executor's
  inference deadline. Provider errors and Stop still settle the original job.

## 3.3.0 — October 17, 2026 — MCP, bridge redesign and queued follow-ups

- Connect Claude Code, Codex, Cursor, OpenCode and other MCP clients to UAI's
  Roblox tools over authenticated Streamable HTTP or stdio. The standalone
  desktop executable supports `--mcp-stdio` and discovers the running bridge.
  Tool calls use normal UAI permissions and isolated sessions, with cancellation
  and receipts that prevent replaying uncertain effects.
- Copy an agent setup prompt from Settings → MCP, with the detected connection
  details and instructions to configure and verify the connection.
- Rebuild the bridge workspace and assistant responses. Open Connection,
  Settings and the other management screens as modal workspaces. Improve
  model selection and reasoning controls, show context estimates and compaction
  limits, and remove superseded styles.
- Send follow-up messages while the agent works in Roblox or the bridge. Queue
  them in order for a safe boundary after the current response or tool batch,
  with visible pending status and a separate Stop action.
- Adaptively route included HCNSEC access using small verified tool probes and a
  ten-second request target. Keep provider `auto` when no compatible fast route
  is known; real user prompts are never raced or replayed to measure speed.
  Automatic free routing is enabled by default and can be disabled under
  Settings → Agent → Automatic free routing. A routed request names the selected
  model and points to that setting; disabling it preserves already active work.
- Give free models noticeable rounded green outlines in Roblox and the bridge.
- Support Google's native Gemini protocol, including paginated model discovery,
  image inputs, tool calls/results, thinking controls and scoped signature replay.
  Route OpenCode Go Gemini models through the same adapter.
- Choose Auto, Send or Omit for each model's temperature policy. Honor documented
  restrictions and remember explicit unsupported-temperature refusals within the
  provider/model scope without treating ordinary range errors as compatibility.
- Inspect subagent progress, task, tool activity and results in richer preview
  modals in Roblox and the bridge, with contextual follow-ups for finished work.
- Expand the environment guide with capabilities, permissions, native workflows,
  shared state, cleanup and official sUNC references. Strengthen main and worker
  instructions while loading detailed guidance on demand.
- Prevent removed pictures from returning when an in-flight upload completes.
- Select scripts or actions in Code Library and remove them with one batch
  confirmation. Preserve hidden selections and reject stale deletion previews.
- Improve Explorer subtree navigation, search, multi-selection and field-value
  inspection. Give Remote Spy visible capture duration, scope, filters and call
  summaries with direct caller and Explorer actions.
- Use native text and selection together while dragging or selecting code.
  Calibrate syntax line spacing from native font bounds and stop caret-follow
  scrolling from shifting the canvas during a drag.
- Set client, bridge and Windows desktop to 3.3.0. UI LIB and SDK stay at 1.3.0
  and 1.0.0. See [focused verification](docs/TESTING_3.3.0.md).

## 3.2.0 — October 15, 2026 — Project UAI Free and OpenCode desktop

- Start empty provider setups with Project UAI Free, using included public HCNSEC
  access and its verified `auto` router. Preserve existing providers and credentials.
- Improve the welcome with thanks for continued support, variable capacity/speed,
  possible future free providers and https://discord.gg/9xYyyYuKap.
- Strengthen the direct OpenCode desktop workaround with the live-verified desktop
  identity, retaining compatibility tools and Chat/Responses recovery without a bridge.
  Add an optional desktop bridge path using a separately installed official CLI
  server, with live model discovery, owned sessions and tool handoff to Roblox.
  The CLI binary is not packaged.
- Remove retired OpenCode proxy targeting/recovery, migrate old URLs to Zen and
  retain only AgentRouter on the proper proxy domain, without a Workers.dev fallback.
- Add a separate OpenCode Go preset, catalog and model-specific Chat, Responses
  and Messages routing. Preserve canonical and legacy Go paths, keep paid Go
  outside the free CLI backend, and distinguish subscription, privacy-region
  and retired-proxy refusals. Gemini's native Go protocol is not implemented.
- Clearly mark OpenCode free models unsupported on mobile, including the Android
  companion. Add Discord help to provider, conversation, tool and bridge errors.
  (Corrected October 18, 2026: mobile OpenCode requires the UAI Relay app from Discord.)
- Refresh provider-specific model prices and context/reply limits. Account for
  documented cache rates and long-context tiers, keep unknown prices unknown,
  and show included Project UAI Free usage at zero cost.
- Set client, bridge and Windows desktop to 3.2.0. UI LIB and SDK versions remain
  1.3.0 and 1.0.0. See [focused verification](docs/TESTING_3.2.0.md).


## 3.1.0 — October 14, 2026 — Bridge improvements

- Replace the bridge's UAI logo with a text-only Cowork identity and redesign the
  full workspace: navigation, conversations, connection, providers, tools, agents,
  loops, activity and settings. Rebuild dialogs with stable headers and actions, scrollable content,
  mobile layouts, focus restoration, and protected asynchronous actions. Improve
  provider, model, tool, conversation, import and composer-option workflows.
- Keep mobile navigation compact when conversation text is enlarged. Refine
  dialog, drawer and page transitions while respecting browser system motion
  preferences.
- Reduce sidebar navigation and profile text in the Roblox mobile client, keeping
  touch targets and the text-scale preference intact.
- Select Web runtime on authenticated bridge connection and restore Game runtime
  on disconnect. Show the connection-driven runtime in both Cowork interfaces.
- Quiet routine companion discovery, back off unavailable probes, reject stale
  pairing results, and bound mobile command polls to short waits.
- Remove the overall Cowork request deadline and its setting. Bridge jobs wait
  for completion, Stop or a real failure; short polling calls recover a stalled
  executor request without resubmitting inference.
- Carry OpenCode Responses inference through the bridge, including streamed text,
  reasoning, tool events and image input. Preserve the four October 13 OpenCode
  fixes and selected keys across protocol recovery. Direct requests retain their
  original deadline; Cowork requests have no overall duration limit.
- Keep provider stream errors terminal even when a later completion marker arrives.
- Permanently enable client animations and remove the motion configuration from
  settings, browser controls, commands and saved/imported preferences.
- Highlight deadline errors with a link to the official Discord tutorial help.
- Automatically verify and stage new GitHub bridge releases, activate them only
  after work is idle, retain the pairing token and restore a working version if
  the update cannot start.
- Redesign the Windows desktop app with connection, runtime and update status.
  Detect installed Node.js or download a verified LTS runtime inside the app;
  keep Node.js separate from the app and retain a manual installation link.
- Ship one independent Windows executable with embedded bridge, browser, client
  and license files. Prepare verified files in a private cache automatically;
  no ZIP extraction or adjacent support folder is needed.
- Fetch desktop app updates from GitHub releases automatically, apply on restart,
  and retain the previous installation for rollback.

See [focused verification and limitations](docs/TESTING_3.1.0.md).
UI LIB remains 1.3.0; the embedding SDK remains 1.0.0.

## 3.0.0 — October 13, 2026

Less repeated work when agents inspect, edit and verify scripts, with more
precise tool outcomes and bounded runtime work.

### Script authoring and inspection

- Cache lexical outlines and syntax outcomes by exact source and compiler
  identity. Recheck saved bytes and dependencies; compile execution wrappers
  fresh. Read Code line ranges without splitting the complete source.
- Add `file_find` for filename-only discovery and `script_test` module/case
  selectors for focused verification. Zero matching cases is a failure.
- Verify exact file edits after writing, reuse staged patch hashes, page saved
  actions and templates, and expose typed action/template inputs more clearly.
- Honor advertised script/Explorer page sizes. Retain HTTP and readable web
  responses for contiguous continuation without refetching. Hidden GUI ancestors,
  skipped source files and unavailable retained details remain explicit.

### Agents and runtime

- Rotate ready API keys across successful requests, including model discovery
  and request snapshots. Preserve the selected key during proxy recovery and
  skip rate-limited keys without advancing twice.
- Avoid repeated growing-string copies in fragmented SSE parsing and repeated
  batch rescans during tool-result repair. Prose previews skip tool arguments.
  Responses assembly unifies call identities and enforces call/argument limits.
- Bound recursive schema validation, preserve valid union values, and return
  useful small result receipts immediately. Conversation search adds explicit
  scopes and bounded traversal; product metadata uses a short refreshable cache.
- Include all Anthropic prompt-token categories in context accounting and
  restore persisted lifetime model/hour statistics.
- Coalesce debounce bursts into one scheduled wakeup, skip ASCII runs during
  UTF-8 processing, chunk bytecode encoding, and evict captured calls through a
  private queue. Summary reads avoid copying unrequested argument graphs.

### Tool outcomes and lifecycle

- Report observed clamped/partial property writes. Validate camera batches
  before writing and resolve exact player usernames before display-name matches.
- Own held input until release succeeds; Stop, revocation and unload attempt
  cleanup without claiming to undo native effects. Performance samples and
  temporary interaction listeners release their resources.
- Page IY discovery, accept saved plugin source paths, verify installations,
  and reuse bounded official Gravity source snapshots. Chat history uses stable
  backward cursors and channel filters.
- Cancel unavailable confirmation dialogs, verify embedded icon files
  individually, and reject stale mascot animation callbacks.
- Continue queued questions after cancelling one conversation's prompt, and
  release the composer's parent-size listener when its shell is destroyed.
- Cancel provider connection tests when their editor closes or connection/model
  changes. Ignore stale model discovery after provider selection or lifetime changes.

UI LIB remains 1.3.0 and the embedding SDK remains 1.0.0. Bridge, desktop and
companion changes are outside this release workstream. The site build refreshes
published version metadata, the tool catalog and the documentation mirror.
See [focused verification](docs/TESTING_3.0.0.md) and the
[agent](docs/AUDIT_3.0.0_AGENT.md), [runtime](docs/AUDIT_3.0.0_RUNTIME.md) and
[scripting](docs/AUDIT_3.0.0_SCRIPTING.md) audit records. Work counters and offline
fixtures are evidence of avoided work, not native performance benchmarks.

## 2.8.0 — October 12, 2026

Reliable scripting, clearer failures, larger attachments, and focused audit fixes.

### Script execution and projects

- Distinguish source, compilation, wrapper and stale-revision failures in
  structured tool results. Preserve canonical source paths and reject oversized
  sources before instrumentation. Capture managed-task arguments and multiple
  returns on hosts that expose `table.unpack` without the legacy global.
- Preserve runtime errors and disclose omitted output. Ordinary script errors
  no longer receive a blanket do-not-retry warning when no work remains pending;
  native calls and unmanaged continuations retain their cooperative limits.
- Report project test discovery failures per module and retain completed results
  when the case limit is reached. Invalid test exports no longer erase earlier
  results or prevent unrelated modules from reporting their failures.
- Validate template values, quote string data, clean up temporary monitoring
  connections, and preserve the dispatched tool's success or failure status.
  Reject stale Code proposals before storing them and isolate action inputs.

### Agent and provider behavior

- Deliver structured tool results to the model, including instance/source IDs,
  listings, revisions and continuation cursors. Previously, native tools could
  return those fields successfully while the model saw only a generic sentence.
  Preserve bounded result delivery and retained-detail access.
- Add an on-demand scripting reference with a short quickstart, exact tool
  examples, saved-file and editor workflows, focused debugging, cleanup,
  source inspection and UI LIB guidance. Main and subagents can read the
  relevant sections without adding the whole manual to every request.
- Preserve the required OpenCode compatibility tool declarations and streaming.
  Add clear guidance explaining which declared names are compatibility
  placeholders and point failed calls to the available Project UAI tools,
  without treating them as aliases or expanding a conversation's permissions.
- Give main and subagents concise Luau and source-path guidance matched to their
  available tools. Distinguish syntax compilation from API or behavior checks,
  and stop suggesting memory, naming or task-list tools outside their scope.
- Restrict the default read subagent preset to read-risk tools. Reject unknown
  presets, classify conversation/memory/task-list mutations as writes, and keep
  client diagnostics under `client_status` without replacing `agent_status`.
- Reject truncated JSON arguments for every tool instead of guessing missing
  targets or filters. Normalize memory keys consistently when writing, reading
  and deleting them.
- Keep token-truncated batches out of the repeated-call streak because they did
  not execute. A later complete, repaired call can run instead of being blocked
  as a repeated action.
- Honor supported sampling settings in the Messages adapter. Limit transient
  retry classification inside successful HTTP responses to explicit error
  fields, so ordinary response text cannot accidentally trigger a retry.
- Support Zen models that only speak the Responses protocol. A request for one
  switches to that lane automatically on a protocol refusal, carries the
  standard tool declarations, and is remembered per endpoint and model.
  Free-tier lockout and unsupported-protocol refusals no longer count toward
  provider benching.

### Larger attachments

- Raise text and code attachments and browser uploads to 10 MiB per file, with
  a larger per-draft budget and a matching pending-upload allowance. Large
  inputs still become verified `pastes/` files read with the file tools, and a
  failed save never falls back to sending the source inline.

### Readable results and permission review

- Keep Code editing and previews readable when syntax highlighting fails;
  render run output literally so logs do not depend on the Lua lexer.
- Show complete permission arguments and source with expandable previews and
  a full-argument viewer. Allow, Deny and dismissal settle once and release
  the prompt before presenting the next queued request.
- Retain complete orphaned tool results, count unread failures in Latest, and
  provide Show failures to open the relevant result bodies. Existing disclosure
  and scroll choices remain under the reader's control.

### Source inspection and decompilation

- Validate decompiler output before accepting or caching it. Reject empty or
  comment-only notices, invalid UTF-8, oversized source and service documents;
  continue to the next available fallback when native output is unusable.
- Stop starting fallbacks after a source request expires or all its readers
  cancel. Bound bytecode requests and retry waits, discard late completions,
  and keep native operations counted until they actually return.
- Install luacid in a private environment without replacing executor globals.
  Remove its unbounded response cache so explicit Refresh can obtain fresh
  source. Distinguish an unavailable decompiler from a service that was tried
  and failed, without exposing raw service or host error bodies.

### Runtime tools and release maintenance

- Correct typed remote prefixes such as `vec3:` and document `string:` for
  literal prefix text. Parse numeric components as complete finite values,
  including exponents, without silently accepting extra coordinates.
- Report failed input adapters accurately, verify hierarchy changes, and restore
  the previous Gravity selection when an update fails where restoration is possible.
  Bound fallback world/performance scans and disclose incomplete results.
- Protect executor capability probes, retain fractional wall-clock deadlines
  during temporary clock failures, preserve nil callback arguments, and validate
  calendar keys. Redact more credential formats in logs, including source labels.
- Add bundle-to-source line ranges to the generated manifest, fix website risk
  filtering and the bulk-read example, and synchronize animated catalog counts
  with their generated text. Update active release references to 2.8.0 while
  preserving historical reports. UI LIB remains 1.3.0 and embedding SDK 1.0.0.

Verification scope and recorded results are in
[the 2.8.0 checklist](docs/TESTING_2.8.0.md).

## 2.7.0 — October 9, 2026

Portable files, faster routine work, and clearer reasoning and provider feedback.

### October 11 update

- Stop presenting a failed decompile as script source. A decompiler that fails
  returns a comment notice rather than raising, so the notice is rejected, the
  bundled luacid fallback is tried, and its own failure is reported with the
  reason instead of being cached or displayed as code.
- Install the bundled luacid fallback with the executor's bytecode and HTTP
  functions pinned behind the host's own globals, and refuse unreadable or empty
  bytecode before a request. It now works where a host compiles chunks into a
  narrower environment. `lune run test/luacid_fallback.luau` covers it with the
  real Luau compiler.
- Retry an empty success from the decompile service instead of storing it as an
  empty script, so a transient empty response cannot stick for the session.
- Add the ByteFall service as a second bundled decompiler fallback, so a host
  that cannot run the compiled luacid client still has a plain-HTTP path.

### October 10 update

- Refresh model/provider identity on fallback requests. Isolate request-hook
  edits from saved conversation history, registered tool schemas and later attempts;
  honor cancellation and replacement frame callbacks before dispatch.
- Release tool waiters promptly on Stop or permission/scope revocation without
  closing native continuations. Discard late progress/results and prevent old
  invocations from reviving after a new turn or restored permission. Invalid dynamic
  timeouts use a finite fallback, and fractional deadlines are reported accurately.
- Shorten and share main/subagent instructions, remove conflicting workflow rules,
  and include specialized guidance only for the tools offered in that request.
  Routine work no longer requires a task list, delegation, or repeated planning.
- Read relevant or explicitly requested skills and reuse unchanged bodies still
  in context. Bound the enabled skill inventory to 3 KiB with an omission notice;
  the complete inventory and bodies remain available through paginated reads.
- Replace injected memory values with a 2 KiB key index. Search saved keys/values
  or read exact keys with continuation offsets, keeping old workarounds available
  without treating them as current instructions or reordering stored entries.
- Give subagents the current model, host instructions, reply language, tool scope
  and their own task list. Let follow-up requests take precedence over the original
  assignment while retaining useful evidence.
- Clarify ordinary Roblox client actions and distinguish local effects from
  server-confirmed results. Direct agents to inspect available actions and report
  specific limits; game rules or anticheat alone do not justify blanket refusals
  of ordinary scripting requests.
- Make tool discovery match execution permissions, including explicit allow/ask
  rules in read-only mode. Preserve capability checks and conversation scopes.
- Distinguish permission rules and user declines from unanswered approval timeouts
  or cancelled prompts. Late answers cannot execute a settled call or save a rule;
  agents continue other allowed work without an extra confirmation.

### Earlier 2.7.0 changes

- Use one concise filesystem contract for file tools, search, compilation and
  execution. Preserve canonical paths and existing nested folders; generate ASCII
  game folders and recover from inaccessible saved Unicode paths without moving data.
- Resolve different executor listing bases against actual files. Keep leading
  spaces, reject ambiguous paths, and retain usable entries from incomplete listings.
- Preserve damaged or future-format game-folder identity files instead of silently
  replacing them during prompt construction.
- Default new configurations to Low reasoning effort. Preserve saved choices,
  expose Provider default, and explain the real request and output limits.
- Show the same global effort control in the model modal when Reasoning support
  is enabled for any model. Preserve documented scales, expose Provider default,
  and follow external setting changes without leaving subscriptions after close.
- Default new access settings to Allow everything while preserving saved modes
  and explicit tool rules. Use the same label in the composer.
- Label clipped reasoning as an excerpt instead of showing an apparent 5,999-token
  limit. Retain that label across replay; format folded reasoning only when opened,
  reuse parsed text during resizing, and keep plain text readable if formatting fails.
- Keep standing instructions ahead of live metadata for a more reusable prompt
  prefix, and guide routine work toward focused actions and relevant checks.
- Add the existing Project UAI brand mark to its profile-menu entry and support modal.
- Preserve bounded, redacted provider error details from JSON and plain-text SSE
  failures. Failed streams remain terminal, including after partial output.
- Keep live answer and reasoning preview limits independent, and probe each
  unreadable game folder only once during recursive discovery.
- Repair an output-ceiling refusal that names the field in the gateway's own
  spelling (for example HCNSEC's `field MaxTokens invalid`): lower the ceiling to
  the bound it states, retry, and remember it for later turns.
- Point OpenRouter app attribution, the Cowork bridge download and the published
  loader and site links at the project's new Project-Ptolemy repository after the
  move from the personal account. Saved OpenRouter providers are updated on the
  next start; a referer set by hand is left alone.

## 2.6.0 — October 4, 2026

Reliable context, consistent game files, and theme controls.

- Compact older complete tool exchanges within a long task while preserving the
  current user request and recent full evidence. Bound rolling summaries and
  reserve space for them; require a smaller context before committing changes.
- Include tool arguments, exact paths, search cursors, previous summaries, and
  active-task context in bounded summary input. Preserve history on cancellation
  or failed manual compaction; explain the result in Compact now. Automatic
  unavailable summaries retain labelled bounded excerpts instead of only drop notes.
- Count summary calls in usage, count structured tool arguments in estimates,
  and retire historical tokenizer-error overhead after context shrinks. Bound
  replies to remaining known context, enforce temporary caps after provider
  overrides, and let smaller fallback models attempt compaction once.
- Keep internal subagent coordination reminders from displacing the actual user
  task. Recognize equivalent consecutive tool batches despite JSON key order or
  whitespace, while preserving distinct argument types.
- Make reads, listings, search, writes, appends, edits, and deletes share reusable
  `files/...` paths. Remove the inconsistent prefix handling that created extra
  `files/` directories. Real nested directories and legacy paths remain reachable.
- Select game workspaces deterministically by PlaceId, reuse existing folders,
  and keep display names separate from safe filesystem names. Preserve readable
  Unicode and emoji, use host NFC normalization when available, handle reserved
  Windows names, and bound long names. Existing folders are not renamed or merged.
- Verify migration destinations before deleting originals. Preserve conflicting
  files, failed/partial copies, nested content, and incompletely listed directories.
- Add bounded pagination to `file_list`; increase default bulk-read slices within
  the existing shared result budget and reuse equivalent path reads within a batch.
  Keep existing search cursors and ordered exact-edit validation; add no new tools.
- Use cached game metadata and exact workspace paths in main/subagent prompts.
  Guide scoped inspection and related bulk reads without requiring whole-game
  scans, decompilation, or preparatory file creation.
- Add a separate ProjectUAI section to the player profile menu, with project
  information and Star us on GitHub. Open the repository when supported, with
  clipboard and selectable-link fallbacks. Keep the existing What's New section.
- UI LIB v1.3.0 builds on its existing Light/Dark palettes and live bindings:
  add a built-in sun/moon mode icon beside the window controls, `GetTheme`, `ToggleTheme`, optional
  `ThemeToggle=false`, appearance persistence in existing profiles, and improved
  custom-accent foreground contrast. Preserve controls, drafts, overlays, and layout.
- Validate with focused context, filesystem, tool, provider, subagent, and UI
  checks. The complete native test suite was not run. See the
  [investigation and validation report](docs/INVESTIGATION_2026_10.md).

## 2.5.6 — October 3, 2026

Live subagent monitoring and lower client overhead.

- Start delegated work in the background by default, returning an agent ID
  immediately. The main agent continues independent work and checks progress
  periodically with `agent_status`, using bounded waits only when it needs a
  child's result. Collect reports before the final answer; Stop and terminal
  parent exits stop unfinished children. Explicit blocking dispatch remains available.
- Revamp subagent details with the current step, provider/model, tool progress
  and results, latest delivered text and reasoning, elapsed time, and final
  report. Keep Stop available while working. Buffered connections show output
  when the provider response arrives.
- Update existing subagent cards and detail rows at a bounded rate, preserving
  reading position and controls. Limit retained activity and previews; release
  view subscriptions when closed and reset current activity on follow-up runs.
- Fix modal fitting that could trigger `Maximum re-entrancy depth (80) exceeded
  calling task.defer`. Coalesce layout events into one pending fit across frames,
  skip unchanged dimensions, reuse header measurements, and cancel work on close.
- Remove per-event listener-list copies while preserving nested events,
  subscription changes and yielding callbacks. Idle code editors and previews
  blink their caret without rescanning syntax or measuring unchanged text.
- Refresh the sidebar subagent count only when the count changes. Tighten the
  spacing between the profile name and provider, including larger text settings.
- UI LIB remains v1.2.1; the embedding SDK remains v1.0.0.

## 2.5.5 — October 3, 2026

Tighter client spacing and calmer modal transitions.

- Open modals, Settings and Quick Chat with a short fade at their final size.
  Remove entrance scaling that repeatedly reflows text and controls. Closing or
  reopening during a transition settles cleanly, and reduced motion is immediate.
- Reduce modal header padding and remove unused body space from confirmations
  that contain only a description. Keep actions and fields reachable above the
  keyboard.
- Group settings labels, inputs and help text together, use consistent section
  spacing, and keep compact rows side by side when their contents fit.
- Tighten provider form notes, welcome cards and release-note groups; hide empty
  provider hints. Keep starter actions readable as the available width changes.
- Remove doubled gaps around fenced code blocks and the empty sidebar space
  below collapsed navigation. Align conversation headings and folder actions
  with the other sidebar rows.
- UI LIB remains v1.2.1; the embedding SDK remains v1.0.0.

## 2.5.0 — October 2, 2026

The desktop interface on mobile, clearer small text, working layout choices, and
ten tools for creating modular scripts.

- Use the original desktop interface on mobile with layout dimensions, spacing
  and radii reduced to 55%. Keep the normal sidebar, header, welcome view,
  composer, Quick Chat, Settings, Providers and Code tabs. Remove the separate
  mobile navigation and destination, document, category and provider pickers.
- Keep the compact layout while raising the text baseline to at least 10px
  before the user's text scale and standard icons to at least 12px. Give tiny
  drawn icon strokes whole-pixel bounds and a minimum one-pixel thickness.
- Make the Layout setting take effect on mobile: Sheet uses the bottom, Panel
  the right edge, and Window the centre. Each explicit layout remembers its own
  placement per orientation. Auto retains its compact placement, and desktop
  window settings remain independent.
- Preserve live fields, drafts, selections and scroll positions through rotation,
  keyboard changes and sidebar toggles. Keep Minimize, Maximise and Close in the
  shared header, with the launcher available after minimizing.
- Scroll the original Code and inspector composition when height is limited,
  keeping its normal tabs, action rows and native inputs. Keep shared menus and
  form actions bounded above the keyboard, and retain Settings category drafts.
- Add `project_scaffold` and `project_map` to stage a working modular script and
  inspect saved file hashes, function outlines and literal dependencies.
- Add `project_patch`, `project_patch_read` and `project_patch_apply` for reviewed,
  coordinated file changes with version checks and verified writes. Refuse
  conflicting files and unsaved bound editor drafts before applying.
- Add `project_patch_restore` and `project_patch_discard` for conditional recovery
  and checkpoint cleanup. Checkpoints belong to the conversation and expire after
  ten minutes or unload. Multi-file writes are not atomic; partial results are
  reported and unknown or externally changed bytes are never blindly restored.
- Add `script_analyze` for host syntax diagnostics and literal project dependency
  checks. Report missing compilers explicitly; full Luau type and Roblox API
  analysis are not included.
- Add `script_test` for declared behavioral tests with assertions, fixture data,
  fresh module caches per case and failure reports. Tests use managed client
  execution and share native game state; they are not an isolated test process.
- Add `project_build` to compile and export a deterministic standalone `.lua`
  bundle with source line locations and a recovery checkpoint, without running it.
- Update the main and subagent prompts for source review, coordinated edits,
  build inspection and focused testing. Document the manifest, tool API and limits
  in the [script project guide](docs/SCRIPT_PROJECTS.md).

## 2.4.0 — October 1, 2026

Mobile spacing, touch workflows, provider recovery, and community access.

- Keep ordinary mobile typing in one compact composer row in either orientation;
  expand explicitly for longer drafts. Reduce nested card, dialog, header and
  navigation padding while preserving full touch targets. Return more space to
  history results when a keyboard is open.
- Keep Quick Chat drafts and selection through rotation; mobile Return inserts
  a newline. Vertical swipes across sliders scroll the page without changing the
  setting, and cancelled gestures release their input ownership.
- Give mobile Code navigation and document selection dedicated pickers, retain
  editing space above the keyboard, and adapt Find controls to narrow widths.
  Settings categories retain their forms and scroll positions when revisited.
- Tighten source-block and reasoning insets. Keep Copy reachable beside long
  metadata, and resize nested code, table and reasoning viewports above keyboards.
- Retry explicit unauthorized-client refusals from official OpenCode and
  AgentRouter endpoints once through `puai-proxy.davidzk.tech`, then retain the
  new Base URL. Requests and keys pass through the proxy, which has a shared
  90,000-request daily limit. Invalid keys, unrelated errors and custom endpoints
  do not cause a switch; cancellation and the request deadline still apply.
- Offer an optional community HCNSEC key in provider setup, without replacing a
  user's saved provider. Discover available models or enter an ID manually.
- Add a Discord invitation after five minutes of use and an idle pause, at most
  once per client load and every two weeks. It waits for a visible idle chat or
  home screen, with no draft, keyboard, active request, reading position or other
  dialog to interrupt. Not now keeps the cooldown; Don't show again or successful
  Copy invite stops reminders. The menu remains available for manual access.

## 2.2.0 — October 1, 2026

Modal polish, workspace cleanup, agent-named conversations, and donations.

- Keep modal and dialog cards rounded at the bottom, and show a description-only
  confirmation in full instead of clipping it to one line. Opaque footers, the
  settings navigation bar, and mobile navigation no longer square the card's
  edge: each inner edge stays straight against the body while the outer corners
  follow the card's radius.
- Let the agent name a conversation from the user's request once its subject is
  clear, so the list reads as topics rather than opening lines. A conversation
  the user has named keeps its title -- the rename tool is not offered there, a
  direct call is refused, and subagents have no title to set.
- Delete files and folders from the Files pane, from the toolbar, the right-click
  menu, or the row's close control, behind one confirmation. Deleting drops the
  file's binding, and the workspace root is never deletable.
- Fall back to the bundled luacid decompiler when the host has none or its
  decompiler fails, so `script_source` still reaches source through the
  executor's own bytecode and HTTP functions.
- Add a Donate entry to the profile menu: Donate with Robux opens the Project
  Ptolemy donation place after a confirmation, and Ko-fi copies its link.
- Rebuild model pricing and the model directory from the OpenRouter and LiteLLM
  datasets, covering current and newly released model ids.

## 2.1.1 — September 30, 2026

Long streaming and Remote Spy reliability.

- Keep long streamed replies: the frame budget no longer discards a valid answer,
  frames are assembled as they decode, and a long response no longer benches the
  provider after three attempts.
- Restore the client's thread identity for deferred work, so a capture-view refresh
  scheduled from a Remote Spy hook is not refused when an executor drops the
  injected identity on scheduled threads.
- Report a failed capture-view refresh once instead of aborting the view and
  repeating several times a second.

## 2.1.0 — September 30, 2026

Native mobile improvements, conversation folders, UI LIB v1.2.1, and embedding SDK 1.0.0.

- Add conversation folders: choose a game, Universal, or a custom folder when
  creating a chat; optionally name the chat, move existing chats, rename folders,
  and remove folders while keeping their conversations in Universal.
- Improve the native mobile client in short keyboard layouts: keep form actions
  scrollable at full touch size, reveal focused fields through clipping and nested
  scrolling, and filter/search mobile conversation history by folder. Keep New
  conversation and workspace actions reachable by scroll above a keyboard.
- Polish UI LIB on mobile with slimmer content padding, wrapped section titles
  and dialog actions, pinned dropdown search when space permits, and picker
  targets that reflow while open. Vertical swipes no longer change horizontal
  sliders or color bars; hide, rotation, and cancellation release scroll ownership.
- Add embedding SDK 1.0.0 with UI-free boot (`ui = false`), reuse without toggling
  (`reuse = true`), public hooks/permissions, and explicit native conversation
  navigation. Existing standalone loading still mounts the application.
- Add owned integration scopes for cleanup, UAI/Roblox subscriptions, hooks, and
  custom tools. Unregistering an owned tool releases its pending approvals and
  invalidates cooperative calls without removing a later replacement.
- Add structured requests with exactly one success, failure, or cancellation
  outcome, protected progress/completion callbacks, cooperative Stop, and waiting
  with optional timeout. Session removal and client unload settle pending requests.
- Add named conversation lookup/open without implicit selection, duplicate-ID
  rejection, and creation options for activation and ephemeral history.
- Validate session options, copy tool filter maps, and preserve conversation tool
  policy and budgets across persistence. Skip unsupported or invalid saved policy
  while retaining its file; older histories keep their legacy defaults.
- Expand the [embedding guide](docs/EMBEDDING.md), add a
  [UI-free SDK example](examples/embedding/sdk.lua), and migrate workbench lifetime
  handling to owned scopes. Add focused offline SDK and example coverage.

## 2.0.5 — September 27, 2026

Responsive long chats, real image input, and UI LIB v1.2.0.

- Mount nearby messages and Markdown chunks while measured spacers preserve
  scroll position. Minimize and navigation suspend rendering and release timers;
  restoring keeps the measured rows and reconciles retained updates without
  losing the draft or reading anchor.
- Batch browser snapshot layout, preserve reading position, and defer
  streaming preview paints while the browser document is hidden.
- Send actual PNG/JPEG/WebP content through the bridge to Chat Completions and
  Anthropic Messages image blocks. Keep compact, conversation-owned references
  in Lua; preserve retry identity and report expired current attachments explicitly.
  Reload the updated client and restart the updated bridge. A vision-capable model
  is required; older clients cannot accept these image sends.
- Add a pinned UI library sidebar profile with the local player's headshot,
  display name, username, and game. Keep readable fallbacks during Roblox lookups.
- Use text for library navigation and action labels, including dropdown selection
  states and disclosure buttons. The frame-drawn Project UAI mark and the
  minimize/close/resize window glyphs remain. Legacy tab Icon fields are ignored;
  the fixed `Project UAI | UI LIB.` attribution stays.
- Add owned, reversible transitions and reduced-motion support for library
  entrances, controls, pickers, and notifications. Settle interrupted animations,
  retain visible focus, and stop remeasuring every control during window dragging.
- Update the public guide, examples, in-game notes, and regression coverage for
  viewport lifecycle, provider image payloads, profile layout, and motion cleanup.
- Add a comprehensive [embedding reference](docs/EMBEDDING.md) and
  [assistant workbench example](examples/embedding/README.md) for custom host UIs,
  sessions, tools, hooks, provider setup, state binding, and cleanup. Expand the
  UI library's embedded agent guide with application and extension patterns.

## 2.0.0 — September 26, 2026

Project UAI UI LIB and shared script interface guidance.

- Introduce the standalone [UI library](docs/UI_LIBRARY.md), loaded from this
  repository through `loadstring`. Project UAI is now 2.0.0; the new library's
  independently versioned API starts at 1.0.0.
- Provide buttons, toggles, checkboxes, sliders, text and numeric inputs,
  searchable single/multi-select dropdowns, segmented controls, keybinds, color
  pickers, labels, paragraphs, dividers, badges, and progress indicators.
- Include responsive tabs and sections, search, dark/light themes, text scaling,
  dialogs, notifications, minimize/restore, and desktop resizing. Compact layouts
  account for safe areas and keyboard obstruction.
- Guide main agents and subagents to declare controls and write application logic.
  The bundled `ui_library_docs` reference supplies the exact API offline; starter
  and showcase scripts demonstrate it without custom GUI construction.
- Own control state, validated configuration import/export, optional profiles,
  callback tasks, input listeners, and script cleanup in the library. Reusing a
  window Id releases its previous window and registered resources.
- Keep the fixed `Project UAI | UI LIB.` footer without a leading separator and
  draw the mark and icons from frames, so no uploaded asset is required. Dropdown
  options accept a player profile image at the start of the row and in the closed
  field, the minimize/close controls carry no resting fill, and minimize leaves a
  draggable, branded restore pill. The existing agent client UI is preserved.
- Publish both bundles and manifests with the 2.0.0 release. The
  [manual audit and validation record](docs/UI_LIBRARY_AUDIT.md) documents library
  coverage and the remaining native Roblox rendering/input checks.

## 1.9.0 — September 26, 2026

Cowork browser workspace, executor installation, and UI reliability.

- Rework the browser workspace with quieter surfaces, responsive navigation,
  clearer setup, local themes, accessible controls, and restrained motion.
- Download bridge packages with `.txt` extensions for restricted executor
  filesystems. Verify pinned packages, restore filenames with Node, and preserve
  the previous launcher after failed downloads or reinstalls.
- Render incremental responses without rebuilding stable Markdown blocks.
  Reconcile saved replies, show provider errors and replay gaps, and bound
  command, response, and preview memory.
- Add validated PNG/JPEG/WebP previews with upload progress, cancellation, retry,
  ownership, and reload recovery. The model receives text markers only.
- Preserve full text/code drafts asynchronously, guard repeated sends, and show
  delivery recovery when an acknowledgement is lost.
- Organize bridge tests under `bridge/tests/`; replace obsolete plans and handoff
  logs with the [bridge guide](bridge/README.md) and lasting native documentation.
- Keep the composer and task controls reachable on short screens, wrap long
  provider URLs and dialog titles, and anchor Jump to latest above the composer.
- Preserve pending answers, permission choices, open tasks, and keyboard focus
  during live updates. Show each permission request's conversation and refresh
  provider, model, and permission selections without discarding active edits.
- Keep errors inside their dialog, recover token entry after authentication
  failures, and correct light-theme contrast, code hover states, and high-contrast
  focus and Stop controls.
- Number this Cowork release consistently in the changelog, in-game notes,
  client bundle, and generated website.

## 1.8.0 — September 25, 2026

Chat stability, provider compatibility, and native client improvements.

Available in game under **App menu → What's new**, also reachable from
**About → What's new**. Reload the updated native bundle to see the bundled notes.

- Correct provider URLs for loopback/LAN hosts, IPv6, custom prefixes and query
  strings. Scope discovered model lists and learned request repairs to their
  connection; preserve manual models after discovery/auth failures.
- Default vLLM to optional auth, add llama.cpp/SGLang presets, avoid unsupported
  Ollama tool defaults, preserve object-shaped tool arguments and recognize small
  local context/output limits. Honor bearer auth for Messages gateways.
- Apply local identity/auth defaults when choosing a preset inside Add Provider.
  Connection edits discard fetched model choices and cancel obsolete discovery
  without losing manual ids. Switching presets clears the previous gateway URL.
- Preserve full paths and identity/auth headers in gateway sockets, accept split
  and combined SSE events, clean up late connections, and allow HTTP fallback only
  before dispatch. Document the custom gateway contract and remove obsolete
  transport-ceiling claims. See [provider compatibility](docs/PROVIDER_COMPATIBILITY.md)
  and [native release evidence](docs/NATIVE_COMPLETION.md).
- Preserve dialogue during long tool/subagent runs with independent history
  budgets. Keep call/result pairs and worker summaries together, save the same
  retained history, disclose history limits, and recover surviving dialogue from
  older context-only or activity-only saves.
- Draw the window directly on every device and maximize it without rebuilding
  the interface. Preserve reading position across refreshes and layout changes.
- Replay long conversations in bounded slices while queuing incoming events;
  cancel stale replay on switch, clear and destruction. Release expired GUI rows,
  nested code rows, timers and replay buffers as history rolls over.
- Add **Message options → Refresh conversation** for recovery during live work.
  Fall back to readable source when Markdown rendering fails, preserve original
  worker timings/counts, and search retained dialogue after model compaction.
- Record native behavior and validation in
  [the implementation report](docs/NATIVE_COMPLETION.md).
- Include these changes in the in-game notes and restore the unread marker when
  notes change within the same client version.
- Remove the 8,192-token executor reply ceiling from both provider adapters,
  including native HTTP fallback. Keep configured output budgets and model limits.
  Render buffered replies immediately, forward real socket previews, and request
  concise progress messages between work steps. Center Add in the horizontal
  provider list, including after resizing.
- Repair the token context breakdown's category widths and shared accounting.
  Estimate prepared system/schema overhead, calibrate against dispatched history,
  invalidate measurements after provider/endpoint/model changes, and coalesce
  live refreshes with cleanup on close.
- Unify source/decompile provenance, explicit errors, deduplicated bounded requests,
  refresh generations, display pinning and expiry. Inspected Source and decompiled
  documents are read-only; editable extraction is explicit and never runs source.
- Guard Explorer hierarchy actions with the displayed selection identity/revision;
  distinguish primary, focus, anchor and clicked objects. Cancel stale queries,
  retain canonical pages and show runtime/display limits and incomplete counts.
- Reuse shifted syntax and line measurements, bound long-line drawing, share UTF-8
  coordinates, show multiline selection and search matches, and recover source
  expiry. Improve compact layouts, scoped shortcuts, autosave retry and conflicts.
- Use one Remote Spy target resolver, selected-target/30-second defaults, neutral
  hook attribution and explicit retained-wrapper status. Require portable-script
  review, open caller source outside hooks, and export frozen capture/source
  provenance. Account for late pinned completions and revoke agent capture promptly.
- Bound native workers, logs, callbacks and response parsing. Clean up after errors
  and preserve cancellation. Native timeout/unknown-outcome requests are terminal;
  this supersedes the historical smaller-request timeout retry described below.
- Keep transient progress out of retained transcripts, restore the newest saved
  conversations, and preserve unsaved threads beyond the memory retention target.
  Reject repeated run dispatch and stale Library removal confirmations.
- Reset stopped subagents for follow-up, keep queued follow-ups cancellable and
  reject duplicate dispatch. Honor the displayed concurrency range and prevent
  unlimited workers from inheriting the disabled finite queue budget.
- Add a fail-fast native verification command, performance contracts, actual Luau
  syntax compilation, deterministic module manifests and generated-output checks.
  Current features/limits: [native contract](docs/NATIVE_CLIENT.md). The bundle,
  generated site and in-game notes identify this release as **1.8.0**.

## Workspace organization — September 24, 2026

- Guide the agent to organise game work under `files/<place name> (<PlaceId>)/`, with authored and edited scripts in the game folder root and decompiled or dumped source in its `dump/` subfolder. Reserved path characters in the place name are dropped so the folder stays valid.
- Keep the per-game layout a default rather than a boundary: the file tools still reach shared utilities, other places' folders, cross-game notes, and `pastes/`, so the agent reads and writes outside the current game's folder whenever the work calls for it or the user names a path.

## 1.7.0 — September 24, 2026

- Rebuild the Coding tab around shared Luau documents, native multiline editing, line numbers, Find/Go to line, indentation, explicit Run/Stop, retained output, a script/action library, and typed action inputs.
- Add a workspace file browser rooted at `UAI`, with expandable folders, file opening, Save/Save as, and disk-conflict checks that preserve edited drafts.
- Keep syntax highlighting visible while editing, show the caret and selection, and restore each document's cursor position. Keep Run and Save adjacent, with Stop shown while a run is active.
- Stabilize Explorer selection and expansion during live refreshes, keep context actions attached to the clicked object, and retain horizontal scrolling for deep trees.
- Make remote capture available directly from Start/Pause/Stop, expand incoming event discovery, and preserve filtered calls and edited replay drafts as results arrive.
- Replace History and Game changes with searchable timelines and inline reviews, including before/after values and conflict-aware Restore/Undo actions.
- Add consistent inner padding and outer spacing to Coding buttons, toolbars, document tabs, search controls, and dialog actions. Crowded toolbars scroll, focused actions stay reachable, and tree rows allow room for larger text and touch targets.
- Verify Coding layouts at 320, 390, 620, and 960 px with pointer/touch input, comfortable/compact density, and enlarged text. Native game testing remains separate from these source and geometry checks.
- Add verified Code persistence with two snapshots, preserved legacy/damaged data, explicit save status, revision checks and changed-build protection. Closing a view retains its document; navigation and rebuild retain drafts.
- Add native Explorer with lazy hierarchy, cancellable search, stable object IDs, desktop/touch multiple selection, typed supported properties/attributes/tags, guarded hierarchy actions, source opening, bookmarks, world picker and metadata export. Recorded property/attribute changes support conflict-aware Undo.
- Add native Remotes with explicit capture scopes/lifetimes, incoming events, host-dependent outgoing capture, pause/stop, bounded typed values, view/admission filters, traffic rules, reviewed one-shot replay, generated scripts, offline import and verified split exports. Capture state remains visible on the minimized launcher.
- Converge instance/script/remote tools on shared services, preserve native-call arity, reject stale references/revisions, and paginate source/capture/result details. Direct calls work without a compiler; timed-out calls report outstanding status and are never retried automatically.
- Add lifecycle cleanup and agent-authorization revocation without changing model tool limits or concurrency. No third-party Dex/SimpleSpy window is downloaded or launched.
- Document native client workflows and capability limits, including source access, capture backends, and the scope of Game changes Undo.

## Context and provider improvements — September 23, 2026

- Learn model context windows from provider refusals, persist them in `agent.forceContext`, and compact then retry the same turn once before provider fallback.
- Merge previous rolling summaries with newer history, preserving earlier facts if a summary request fails.
- Add **Message options → Context breakdown** with distinct colors for system prompt and tools, messages, rolling summary, and unused space, plus the model window and compaction point.
- Show before/after token estimates in compaction notices and align their status dots with the text.
- Add a delete button for each saved memory while retaining **Forget everything** and live list updates.
- Feature AgentRouter with its registration requirement highlighted, the Anthropic Messages protocol, and its required Claude Code identity enforced for requests and model discovery.

## Documentation — September 23, 2026

- Document the planned native Explorer and Remotes integration, including provenance, shared services, controls, capability fallbacks, and verification. Those features subsequently shipped in 1.7.0; the old plan has been retired in favor of the current native documentation.

## 1.6.0 — September 23, 2026

- Save inputs over 8,000 bytes intact as verified files in `UAI/pastes/`, up to 2 MiB each. Send a compact file reference instead of copying the source into the conversation. Short inputs remain inline.
- Upload long browser inputs and code attachments separately in ordered chunks. Native and browser composers support attachment-only sends, preserve surrounding instructions, and keep drafts when saving or sending fails.
- Read saved pastes in UTF-8-safe slices of at most 6,000 source bytes, including batch reads. `file_search` accepts explicit `pastes/` paths; explicit file scopes cannot be shadowed by similarly named workspace files.
- Add Project Gravity integration: inspect the live shape catalog and settings, start/stop/pause, target players, configure formations and controls, and invoke real shape buttons through Gravity's native handlers.
- Complete Gravity controls with paginated held-part inspection and session-scoped IDs; native selection, pin/manual/shape assignments, group movement, rideability, physics overrides, and release actions. Stale IDs, changed selections during shape loading, invalid batches, and unsupported runtimes are rejected before mutation.
- Add native core/shape keybinding edits with conflict checks, favorites, manual Slingshot launch/charge, and a complete settings reset. Expose interface, FPS, visual performance, core color, ignore tags, and Part Control panel defaults with live effects and refreshed controls on desktop and mobile.
- Add `gravity_plugin_read` for the module guide, working template, and local/official source. `gravity_plugin_write` accepts saved source paths, verifies files, validates setup once, and registers or reloads custom shapes with cleanup. Desktop and mobile Gravity launchers pass their live context; the integration follows reloads and unloads.
- Add `gravity_launch` to download and run the official Project Gravity loader from UAI when it is not already present, report the live status, and reload it on `force`. Shape inspection and the plugin guide now cover the `FrameTracking` flag.
- Keep loaded plugin callbacks usable after setup while respecting explicit task cancellation. Verify restored source after a failed plugin write before reporting recovery.
- Guide the main agent and subagents toward successive batches of normally 1–4 independent tool calls, instead of emitting dozens at once. Tool-call limits and concurrency settings are unchanged.
- Size automatic compaction to the model: when a model's context window is known, older turns are summarised starting at `agent.contextFraction` (80% by default) of it, with `agent.contextTokens` as a hard ceiling. Context pressure is calibrated against each provider's reported prompt-token count, so the system prompt and tool schemas are counted rather than estimated. A **Compact now** action in the composer's message-options menu folds older turns on demand, and the **Summarise old turns** switch now gates only the paid summary while the conversation is still trimmed to fit.
- Show a live context-window counter beside the model in the composer -- the share of the budget the next request will spend. Give the agent a proper way to review earlier conversations: `conversation_list` triages threads with their opening request, `conversation_read` returns a condensed digest by default (or the verbatim transcript with `full=true`), and `conversation_search` now returns each thread's id so it can be opened.

- Replace the temporary mobile dragging fix with a landscape-focused touch layout: compact multiline input, searchable conversation navigation, wider action sheets, and full-width settings forms.
- Preserve drafts, selections, open forms, and separate landscape/portrait placement through rotation. Keep the keyboard clear of input and focused form fields, and restore the launcher when minimized.
- Keep attachments in a bounded horizontal strip and retain access to them from Message options when keyboard space is tight. Mobile Enter adds a line; Send submits.
- Keep desktop styling, layout, and saved placement independent of the mobile changes.

## 1.5.0 — September 20, 2026

### Added

- `iy_players` resolves IY selectors to live player names before targeting commands, with bounded text and a complete structured name list.
- `iy_control` manages native IY events, keybinds, aliases, waypoints, settings, and repeat loops. Alias and waypoint inspection includes pagination; waypoint removal and clearing default to the current place, with `all_places=true` for clearing every place.
- IY settings now include `gui_scale` and `logs_webhook`, applied through native commands with asynchronous dispatch and saving reported explicitly.
- Add `iy_plugin_read` and `iy_plugin_write` for custom plugins with shared globals, multiple commands, aliases, syntax checks, returned-table validation, and live reloads.

### Improved

- The desktop profile control shows your Roblox headshot beside a clearer name and provider hierarchy. Its menu adds a matching identity header, a live provider summary, roomier actions, and visible hover and open states, with an initial fallback while avatars load.
- `iy_cmds` shows native argument signatures and short descriptions alongside names, aliases, and plugin origins, retaining compatibility with older IY versions.
- Buffered HTTP uses an 8,192-token default reply ceiling through `agent.executorReplyCeiling`, without changing the saved `agent.maxTokens` setting. Configured WebSocket streams, the enabled web relay, and explicit token overrides bypass this default; set the new option to `0` to disable it.
- Both provider adapters can retry a request that returns nothing after 20–130 seconds with a smaller reply and reduced reasoning effort when available. A valid completion saves the working ceiling for that provider and model so later turns can start smaller.
- File-writing guidance favors targeted `file_edit` and `file_edit_many` changes to keep replies within executor request windows.
- `check_luau` accepts saved scripts by `path`, matching `run_luau` and saved-paste reads. Large-script guidance uses small sequential writes and checks/runs by path to avoid sending source repeatedly.
- Main and subagent prompts require reading every enabled skill first in every new or resumed conversation. Skill bodies and inventories paginate within the result budget; restricted subagents gain read access without skill mutation tools.

### Fixed

- Alias and waypoint edits validate inputs before changing live state, refresh IY's GUI, and clear tables in place. Coordinate waypoints use validated, floored values instead of IY's buggy coordinate command; deletion preserves other places' waypoints.
- Failed WebSocket connections apply the safer ceiling when falling back to HTTP. Cancellations and already-minimal requests skip recovery retries, and malformed or empty replies do not create learned token caps.
- `file_write` and `file_append` reject content over 2 MiB per call before writing, preserving existing files.
- Interrupted write arguments cannot be repaired into partial edits or scripts. Token-limited tool batches run no calls and ask the model for smaller complete requests.
- Profile headshots explicitly resolve and preload with bounded retries. Images remain renderable while loading; closing a view discards late results while native requests finish on live coroutines.
- Managed script stopping uses cancellation flags instead of closing native coroutines, removing UAI cancellation paths that can leave Roblox callbacks trying to resume a dead thread. Self-cancellation, finished handles, long delays, and callbacks after a successful run use the same guarded lifecycle. External engine waits retain an explicit cancellation limitation.
- Failed turns release their busy state and invalidate old tool contexts; starting another main or subagent turn cannot revive failed or stopped workers.
- The minimize/restore launcher preserves the grab offset, waits for a drag threshold, tracks one pointer, and separates dragging from activation. Focus loss and rebuild clean up listeners; temporary viewport and keyboard changes preserve the preferred placement.
- Align task markers and notification content across text sizes and input modes. Preserve task disclosure choices, cap long plans, and exclude skipped tasks from completion progress.
- Add conversation titles and Open chat actions to notifications. Preserve other unread conversations, keep notification stacks within the available viewport, and stop the busy pulse when work finishes.

## 1.4.0 — September 19, 2026

### Added

- `instance_query` combines name, class, and tag filtering with selected property and attribute reads. `instance_get_many` inspects up to 20 known paths, retaining successful results when another path is missing.
- `file_search` searches literal text across workspace files with filename globs, case selection, line numbers, byte offsets, and resumable cursors.
- `file_read_many` reads up to 12 workspace files or saved pastes within one shared output budget. `file_edit_many` preflights up to 20 ordered edits to one file before a single write.
- The public showcase includes copyable starter prompts and a searchable catalog generated from the real bundled tool registry.

### Improved

- Instance searches traverse incrementally, stop when a page fills, and cooperate with Stop. A one-result query in the regression fixture inspects one node in a 3,000-node subtree without calling `GetDescendants`.
- File-search cursors can resume directly at a byte offset. Repeated file slices share a bounded cache within a batch; the cache ends with the call.
- The agent prompt guides combined queries, selected fields, batch reads, exact edits, and continuation handling to reduce unnecessary tool round trips.
- The public website has a new responsive layout, stronger text contrast, keyboard focus styles, a skip link, reduced-motion support, and video that plays on request.
- `node tools/build_site.js` generates the public catalog and release counts and synchronizes the root and `docs/` publishing copies. It refuses a stale Lua bundle; `--check` verifies without writing.

### Fixed

- Parsed, JSON-quoted instance path segments preserve names containing dots, brackets, quotes, control characters, or surrounding whitespace. Known Character, CurrentCamera, and PrimaryPart references resolve as instance links.
- String property coercion preserves whitespace; scalar numeric conversion rejects nonfinite values. Schema validation enforces batch array limits.
- Search results expose unreadable files and incomplete inventories. File searches bound directory, file, and line scans and count skipped files toward their whole-file read budget. Stopped edits report cancellation; stale files are preserved and unchanged edits avoid writes.
- Repeated website copy clicks retain their original labels. Clipboard failures offer text selection and visible feedback. Mobile navigation resets on link clicks, Escape, outside interaction, and viewport changes.
- Public tool names and counts match the shipped registry. The site no longer describes managed execution as a security sandbox or claims a fixed setup time.

## 1.3.0 — September 19, 2026

### Added

- `check_luau` compiles source without executing it.
- `file_edit` performs exact replacements, including empty replacements and explicit replace-all. It refuses missing, ambiguous, overlapping, or stale matches and bounds edited files to 2 MB.
- `file_read` and `script_source` return contiguous slices with byte offsets for reading the remainder. Saved-paste references work with bare, `pastes/`, and `UAI/pastes/` paths.

### Improved

- `run_luau` reports print/warn output, readable tables, cycles, and multiple return values, with bounded UTF-8 output. Loop checkpoints preserve source literals and line numbers.
- Execution deadlines are configurable from 1 to 60 seconds, defaulting to 10. The call waits for functions scheduled through its `task.spawn`, `task.defer`, and `task.delay` wrappers; Stop, deadlines, errors, and unload cancel managed tasks.
- Parallel tool results reach the transcript as each finishes while retaining the original order in model context. Progress updates identify their call.
- Roblox and Cowork show distinct execution states; exact edits have Before/After listings. Cowork includes multiline code fields, typed controls, validation, copyable output, and improved small-screen and keyboard behavior.

### Fixed

- Compile/runtime failures now produce failed tool results. JSON repair only changes syntax outside quoted strings and refuses unfinished string arguments.
- Explicitly canceled Luau tasks stay canceled after their parent succeeds, including on hosts without working native cancellation; self-cancellation stops the current task immediately.
- Dispatch rechecks tool-group and conversation restrictions after approval and skips stopped calls. Failed and stopped turns return to Ready.
- Explicit filesystem refusals and listing failures are reported. Append fallback preserves existing contents when reading fails. Windows path suffixes and control characters cannot bypass scope validation.
- Send acknowledgements preserve newer drafts and attachments, including edits that return to the original text. IME confirmation does not submit; unavailable browser storage does not break chat; asynchronous attachments remain with their original conversation.
- Tool-only restored transcripts stay visible; missing saved results stop displaying “Running.” Child summaries and scoped progress render correctly.
- Targeted Lua checks retain canonical module IDs and resolve imports outside the selected subtree.

### Execution limits

Managed execution is not a security sandbox or a rollback mechanism. Dynamically loaded code, engine calls, and callbacks registered on engine signals are outside its cancellation guarantee. On hosts without usable `task.cancel`, managed waits cooperate with cancellation and the result explains any remaining uncertainty. Successful scripts may still register persistent engine callbacks; their later work is outside the completed tool call.

Earlier release notes remain in `src/runtime/changelog.lua` and the in-app **What's New** view.
