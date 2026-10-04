# Changelog

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
  add a built-in text mode switch, `GetTheme`, `ToggleTheme`, optional
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
