-- Release notes, as data.
--
-- Every release this client has shipped, from the initial commit forward, in
-- the shape the changelog modal renders: one entry per version, one section
-- per category, one line per change. The list is chronological with the
-- newest first because that is how a "what's new" is read -- the top entry
-- is the one a returning user has not seen.
--
-- Version and note revision track what the user opened, so updates within a
-- version restore the menu's "new" marker. Nothing is fetched remotely --
-- the notes a client can show offline are the notes it shipped with, and a
-- version that has to be downloaded to learn what it contains is a version
-- that cannot say anything on a bad network day.
return function(env)
	local config = env.require("runtime/config")

	local M = {}
	-- New capabilities first, then improvements and fixes.
	local CATEGORY_ORDER = { "added", "improved", "fixed" }
	local ENTRIES = {
		{
			version = "3.8.0",
			revision = "2026-10-31-conversation-layout",
			date = "October 31, 2026",
			title = "Everyday work, easier",
			highlights = "Saved script goals, compact tool families, a stronger Code workspace, Obsidian notes, conversation recovery, general UI LIB styling and a new loading screen. Open the sections for the complete release notes.",
			sections = {
				{ category = "added", label = "Script goals and tool discovery", items = {
					"New installations use the Focused tool profile: available actions fit into at most nine families plus seven direct workflow tools. Saved profiles remain selected.",
					"Each family lists exact action names and supplies full schemas on demand. Calls retain the original action's validation, approvals, hooks, deadlines and conversation/request scope.",
					"All, Lean and task-specific profiles remain available. Hidden permitted actions can still be reached through tool_search.",
					"On-demand tool help includes validated, copyable examples for 25 core workflows without executing them or adding their full detail to every request.",
					"Script goals persist with the conversation and follow Define, Inspect, Plan, Build, Validate and Review stages.",
					"Goals contain 1–16 acceptance criteria, stage evidence and explicit block, resume and rewind actions. Code shows the saved goal and copyable progress.",
					"Validation records actual compiler and test receipts. Source changes invalidate prior checks; checks that began before an edit or a replacement goal cannot validate the new work.",
					"A failed final check reopens validation. Completion requires current successful syntax checks and evidence for every acceptance criterion.",
					"Typing invalidates goal state immediately and coalesces its save after a short pause; explicit goal actions save immediately.",
				} },
				{ category = "added", label = "Code workspace and project creation", items = {
					"Create a basic project or a UI LIB interface starter from Code, with a manifest, settings and tests. The interface starter separates its view from a testable domain model and owns cleanup.",
					"Review every proposed new file before applying a project. Existing files and unsaved bound Code drafts are protected.",
					"Project setup drafts survive cancelled previews. Untouched proposals are discarded, while applied or partial checkpoints remain available for recovery.",
					"Cancelled or stale previews cannot resume writes after a yielded read; opening another turn, clearing a conversation or unloading invalidates the captured operation.",
					"Quick-open scripts with Ctrl+P and search retained workspace source with Ctrl+Shift+F. Results show source lines and reject stale revision locations.",
					"Jump to a line and Unicode column with Ctrl+G. Navigation is guarded against a document changing before the delayed focus operation.",
					"Toggle comments, duplicate or delete selected lines, trim trailing spaces and convert indentation between tabs and four spaces as undoable source changes.",
					"Reopen recently closed script views with Ctrl+Shift+T, cycle open tabs with Ctrl+Tab, close other views and copy a script's name from its tab menu.",
					"Reload a clean draft from disk while preserving edits or bindings changed during the read. An unavailable existence probe cannot be treated as a missing file.",
					"Document details show lines, bytes, line-ending style and selection size. Library, file and history search support words, phrases and excluded terms.",
					"Source comparisons copy bounded change summaries and identify the current change region. Previous change starts at the final region correctly.",
					"Clear completed run output while retaining running work. Empty output and omitted printed lines are described explicitly.",
					"Typed forms retain detached drafts, validate required and whole-number values, focus invalid fields, support Enter submission and reject repeated in-flight submissions.",
					"Virtual lists support page and edge navigation and handle empty selections safely.",
				} },
				{ category = "added", label = "Obsidian vaults", items = {
					"Connect up to 16 local Obsidian or Markdown vault folders through the bridge. Connections start read-only; disconnecting preserves notes.",
					"Vault paths reject traversal, hidden entries, symbolic links or junctions, hard-linked notes and non-Markdown files. Replaced roots become unavailable.",
					"Read UTF-8 Markdown notes up to 1 MiB in explicit bounded pages. Native full-note assembly verifies one revision, byte count and advancing offset throughout.",
					"Create, replace or append notes with revision checks. Stale revisions and uncertain writes require reading current state before another explicit save.",
					"Search paths and note content with bounded traversal and visible incomplete-coverage notices.",
					"Inspect titles, headings, inline tags, raw frontmatter and supported scalar properties. Frontmatter inspection does not claim complete YAML parsing.",
					"Explore wiki links, local Markdown links and backlinks with explicit resolved paths and ambiguous matches; code examples are excluded from backlinks.",
					"Browser vault controls include connection management, vault selection, paginated browse/search, new-note drafts, editing, copy and download.",
					"Native Settings opens the note browser, editor, metadata and link navigation directly, including folder/text filters and pagination.",
					"Native saves preserve existing CRLF style and verify the returned path, revision and size. Unconfirmed saves cannot be blindly repeated.",
					"Conflict review offers Keep draft or Use file after reading the current note. Neither review action writes.",
					"Closing an editor keeps up to eight unsaved or uncertain note drafts in memory. A ninth is refused without evicting edits; recovery clears on unload.",
					"Agent vault tools retain UAI permissions and each vault's read-only policy. Models cannot connect arbitrary folders or enable editing; listings omit absolute folder paths.",
					"Damaged vault configuration is preserved for recovery, filesystem errors are sanitized and bridge packages include the required vault modules.",
				} },
				{ category = "added", label = "Conversation organization and recovery", items = {
					"Pin conversations within folders. Pinned histories also receive priority when restoring the bounded set of loaded conversations.",
					"Unread reply and failure counts follow actual background output. Viewing or marking a conversation read clears them; minimized windows do not silently mark output read.",
					"Browse All, Pinned, Unread or failed, Running and Has draft views, with title, folder and recent-transcript search.",
					"Conversation browsing and transcript results fill the dialog width, wrap long titles and size to their contents. Blank searches retain all conversations, and closing the browser releases its filter menu.",
					"Find in conversation supports words, quoted phrases, exclusions, message/reply/error filters and older-result continuation, then opens the stable transcript event.",
					"Composer drafts recover from existing conversation storage after a typing pause. Oversized updates preserve the previous complete recovery, and restoring never sends.",
					"Draft recovery follows the conversation's existing storage choice and adds no separate recovery file. Draft details show word/byte counts and offer Copy text.",
					"New file references retain SHA-256 fingerprints where supported, detecting same-size edits before sending restored follow-ups. Older references retain their size checks.",
					"Large attachment fingerprints check cancellation in bounded batches and yield by elapsed CPU time, keeping other work responsive without forcing frame delays on fast hashes.",
					"Attachment details show paths, sizes and validation state, copy paths and remove references without deleting files.",
					"Task plans and bounded notes persist per conversation. Active tasks restore as pending; completed and dropped tasks retain their state.",
					"Queued follow-up messages and plan details can be copied. Home continuation cards show retained messages, pending work and draft state without switching the worker.",
					"Markdown export previews retained dialogue before copying or saving, excludes tool internals and hidden reasoning, and verifies saved output.",
					"Conversation search offers further result pages and preserves Unicode excerpts instead of presenting system/tool context as an ordinary reply.",
				} },
				{ category = "fixed", label = "Conversation and delegated-work lifetime", items = {
					"Conversation checkpoints serialize overlapping writes and retain newer dirty revisions.",
					"Burst creation of background conversations coalesces sidebar refreshes into one owned update, avoiding repeated full-list layouts.",
					"Deleting a conversation or choosing Not saved cleans up an already-running old checkpoint and reserves its ID until that write finishes.",
					"Stale callbacks cannot change the storage choice of a removed conversation or recreate deleted history.",
					"Delegated workers intersect the parent's available original actions and request-local exclusions. Full presets and later follow-ups cannot widen an earlier child's scope.",
					"Stopped or replaced tool contexts remain cancelled even when a later send clears the conversation's ordinary abort flag.",
				} },
				{ category = "improved", label = "Provider setup and key management", items = {
					"Project UAI Free is an optional Providers library preset. Fresh, reset and empty imported configurations no longer insert a provider automatically.",
					"HCNSEC remains separate for personal keys. Community authentication is restricted to the official Free endpoint and historical mixed setups migrate separately.",
					"Preset transitions remove incompatible community authentication while preserving supported user settings and labels.",
					"Free availability distinguishes schedule closure, paused keys and locked access. Countdown refreshes preserve the favorite label and actionable status.",
					"Exact model IDs share trimmed UTF-8 validation, a 160-byte limit and rejection of control characters.",
					"Catalog parsing deduplicates IDs, bounds processing and reports invalid, non-chat or partial results without caching an unusable empty catalog.",
					"Model selections and list edits restore the previous in-memory state when saving fails.",
					"Model lists support search, favorites-only filtering, up to 100 favorites and the last 12 unique successful selections per provider.",
					"Favorite and recent-model changes reorder existing controls, preserving focused search and scrolling instead of rebuilding the catalog.",
					"Public configuration transfers retain model shortcuts without keys, validate provider buckets and limits, and detach applied preference snapshots.",
					"Key management searches names and status without searching secrets, and refreshes preserve focused edits.",
					"Replacing a key pool preserves surviving key names, pause state, accounting identities and selected-key position; removing a pinned key restores rotation.",
					"Provider cards expose sanitized health, availability, paused-key counts and effective API/transport explanations.",
					"Duplicate setup opens an unsaved draft with safe connection/model settings and omits credentials and custom header/body maps.",
					"Reset learned compatibility clears inferred API/output behavior while preserving quota cooldowns, health and accepted request ownership.",
					"Browser provider forms validate model IDs, headers and preset transitions. Stale forms cannot recreate removed providers.",
				} },
				{ category = "fixed", label = "Network and model compatibility", items = {
					"A shared deadline begins before WebSocket setup. HTTP fallback, provider retries and proxy recovery spend the original remaining request budget.",
					"Deadline parsing rejects invalid or nonfinite inputs while retaining the explicit unlimited relay policy.",
					"Retry-After accepts bounded numeric seconds and GMT HTTP dates for cooldown scheduling.",
					"Custom HTTP header names, values and counts, plus URL and User-Agent input, are bounded and validated before dispatch.",
					"Vendor pricing requires the documented HTTPS vendor route; arbitrary paths and stacked API suffixes no longer inherit vendor pricing.",
					"Bearer authorization matching is case-insensitive for per-key accounting without treating unrelated header formats as Bearer credentials.",
					"OpenCode, Cline and Kilo capabilities require supported schemas and coherent states; malformed or stale snapshots show unavailable.",
					"Model refreshes and bridge callbacks reject results from replaced provider settings or obsolete connection generations.",
				} },
				{ category = "improved", label = "UI LIB 1.6 appearance", items = {
					"Neutral is the default palette, with Graphite, Ocean, Forest and Rose alternatives across Dark and Light themes.",
					"Built-in Appearance offers Standard/High contrast, Comfortable/Compact/Spacious density, Rounded/Soft/Square shape and Sans/System/Mono typography.",
					"Simple tab headings are the default. Detailed shows section/control counts; Hidden removes the introduction and remains hidden during search.",
					"Appearance changes preserve field drafts, focus and validation, and remeasure text using the selected font.",
					"The library retains fixed Project UAI | UI LIB. attribution, text-only navigation/actions and its frame-drawn brand and window controls.",
				} },
				{ category = "added", label = "UI LIB controls and script workflow", items = {
					"NumberInput combines typed finite values, bounds, step quantization, Less/More actions and form validation.",
					"TextView supplies selectable read-only text, bounded append, scroll-to-end and honest clipboard failure results.",
					"ItemList provides stable item IDs, search and explicit pages for up to 500 entries, retaining only a still-valid selection after replacement.",
					"ActionGroup exposes one to eight named actions with independent busy states and owned asynchronous work.",
					"Callout presents a semantic message with an optional owned action. KeyValue displays up to 64 ordered responsive facts with copied snapshots.",
					"Complete-form GetValues/SetValues, per-field drafts, required/pattern/custom validation, commit and reset support larger script forms.",
					"Named profiles store values and appearance through supplied storage callbacks and validate the full data before application.",
					"Window-owned tasks, delayed work and debounce are cancelled during cleanup, including same-ID window replacement.",
					"Stable-ID Reveal and search open the correct tab/section, expand collapsed content and scroll to a control without activating it.",
					"Seven runnable examples and focused appearance, forms, lifecycle, profiles, collections and readout guides accompany the generated bundle and embedded reference.",
				} },
				{ category = "improved", label = "Native settings, focus and everyday controls", items = {
					"Both settings surfaces search public labels, categories and exact paths, then reveal the matched control. Saved values and credentials never enter the index.",
					"Settings search/category changes preserve field instances, unfinished drafts and reading position where the pane remains valid.",
					"Sliders support keyboard/controller steps, Home/End and Page Up/Down with a single commit; hidden controls and text-entry focus suppress slider shortcuts.",
					"Disabled switches, rows and buttons ignore activation. Busy buttons remain unavailable across enable refreshes, and read-only fields support select-all.",
					"Hiding the main window releases text/gamepad focus while retaining drafts. Quick Chat preserves caret/selection across appearance rebuilds and keeps rejected sends.",
					"Password setup Enter advances to confirmation, Show/Hide preserves selection and leaving the app remasks visible passwords.",
					"What's new searches release notes and copies the entire latest release even with an active filter.",
					"Failed invite copies select the existing read-only link for manual copying. Cached ready headshots avoid repeated resolution during view rebuilds.",
					"Timeout messages explain uncertain completion and link directly to request-wait settings.",
					"Find a command reaches actions, settings and conversation titles. Ctrl+K, Ctrl+Shift+P, Ctrl+comma and Ctrl+L provide common navigation and focus shortcuts.",
					"Shared clipboard workflows report host refusals instead of claiming a successful copy.",
				} },
				{ category = "improved", label = "Script loading screen", items = {
					"A responsive branded startup card replaces the plain loading pill.",
					"Prepare, Restore and Open stages follow real startup boundaries. Actual loaded-component counts remain separate from stage progress.",
					"Elapsed time and a hint after eight seconds without progress explain slow startup without inventing an overall percentage.",
					"Failures retain a readable failed stage until dismissed; full exceptions remain in the console.",
					"Successful completion waits until the bridge, embedding SDK and final initialization finish. Pulse, listeners and delayed exit work are owned and cleaned up.",
					"The native reduced-motion setting remains retired.",
				} },
				{ category = "improved", label = "Desktop 3.8.0 and embedding SDK 1.1.0", items = {
					"The standalone Windows app packages the 3.8.0 client, bridge and required Obsidian browser assets, retaining extraction manifests and hash validation.",
					"Desktop capability parsing matches native rules, clears stale details on disconnect and ignores delayed update callbacks from an obsolete bridge generation.",
					"Ctrl+1 through Ctrl+5 navigate Workspace, Connections, Updates, Settings and Tunnels through the existing commands.",
					"SDK request events, completion data, snapshots and await results are detached from internal state.",
					"SDK scopes own delayed callbacks, cancel them on destruction, release completed resources and expose active resource counts.",
					"SDK tool registration bounds descriptions and schema depth/size while preserving validated union argument types.",
					"The Android companion remains unchanged at 3.7.1.",
				} },
				{ category = "improved", label = "Website, guides and release preparation", items = {
					"Website tool filters have shareable query/group/risk URLs, restore on load and update browser history without adding unrelated parameters.",
					"Website setup distinguishes optional Project UAI Free from personal-key HCNSEC and links Obsidian and getting-started guidance.",
					"The README is a short introduction with focused setup, conversation, provider, Code, UI LIB and troubleshooting guides.",
					"Startup and settings/accessibility guides explain the new native controls; SDK documentation clarifies authentication, reruns and resource lifetime.",
					"Release notes include a file-by-file change ledger that separates authored source, regression tests, examples and generated outputs.",
					"Client, bridge, browser workspace and desktop target 3.8.0, with independently versioned UI LIB 1.6.0 and SDK 1.1.0. Local preparation does not publish a release.",
				} },
			},
		},
		{
			version = "3.7.2",
			revision = "2026-10-29-credential-choice-and-compact-progress",
			date = "October 29, 2026",
			title = "Password vault and scheduled free access",
			highlights = "Choose password encryption or explicitly continue without it. Encryption and unlocking show a compact corner percentage, and password prompts fit their contents. The Claude Code Settings tab is now Project UAI.",
			sections = {
				{ category = "added", label = "Credential storage", items = {
					"First setup offers password encryption or a red Continue without encryption option. The unprotected choice is saved and skips future password prompts. Encrypted vaults still require their password on every execution; existing keys and pool settings carry over after verified storage.",
					"The vault uses AES-256-SIV and PBKDF2-HMAC-SHA256 entirely in Luau. Setup and password changes verify the encrypted save before switching. Cancel and failed writes preserve live keys; scripts sharing the executor can still intercept credentials during use.",
					"New passwords use 100,000 PBKDF2 iterations. Older vaults retain their stored work factor until a password change rewrites them. Encryption and unlocking share a compact corner percentage with Cancel; startup password work leaves the game visible and interactive.",
					"Privacy provides password changes, Lock now and the deliberate unprotected storage choice after unlocking. Forgotten-password removal discards saved vault credentials before returning to setup.",
					"Older byte encoding is reversible and remains supported for migration. Replace exposed keys in the provider dashboard and revoke the old ones; UAI's Rotate keys only selects between existing keys. A forgotten vault password cannot be recovered.",
				} },
				{ category = "improved", label = "Copies and included access", items = {
					"Normal configuration copies and diagnostics exclude connection credentials. Private copies retain encryption only when the vault is enabled; unprotected copies remain recoverable. Encrypted imports ask for their password before review. This device keeps its own storage choice and vault password.",
					"Project UAI Free opens daily during 20:00–06:00 UTC+8 (Beijing/Singapore). Off-hours requests explain the schedule, and accepted replies continue after closing. Personal HCNSEC keys are unaffected.",
					"The included community key has been replaced. Old included credentials migrate on the official endpoint; saved configs and exports use a reference. Bundle encoding deters simple searches but cannot make a client-held key secret.",
				} },
				{ category = "fixed", label = "Duplicate credential copies", items = {
					"Custom headers, query/body overrides, URL credentials and learned scopes are protected with the key pool. Temporary rotation maps are never saved, because they can contain API keys.",
					"Failed storage updates keep live keys and report the failure. Unreadable encoded records are preserved and cannot silently become anonymous requests. Older exports and backups remain under your control and may still contain plaintext credentials.",
				} },
				{ category = "fixed", label = "Reasoning levels", items = {
					"Enabling reasoning support keeps its level buttons visible in short model pickers. Provider details and the caption compact first; extremely limited keyboard space keeps the levels available through Options.",
				} },
				{ category = "improved", label = "Settings", items = {
					"The Claude Code Settings tab is now named Project UAI.",
				} },
			},
		},
		{
			version = "3.7.1",
			revision = "2026-10-25-key-usage-and-pausing",
			date = "October 25, 2026",
			title = "UI polish and individual API keys",
			highlights = "Manage named API keys, pause individual entries and see their usage. Each conversation shows its AI request count. Rotation stays on by default, and modals have clearer spacing and fitted heights.",
			sections = {
				{ category = "added", label = "Individual API keys", items = {
					"Manage API keys opens a dedicated modal from provider details or connection setup. Name each masked entry, replace or remove it, and add more keys individually or in one paste.",
					"Rotate keys is the default. Choose Use one key to send this provider's requests through a specific entry; other keys stay saved. Removing the selected key restores rotation.",
					"Apply saves key changes from provider details or returns them to an unfinished connection draft. Cancel keeps the original keys, names and request preference. Configuration transfers preserve the complete setup.",
					"Pause a key without deleting its name or usage, then resume it when needed. Paused keys are skipped in rotation; a paused selected key stays pinned until you resume it or change your selection.",
					"Each key shows locally recorded requests and input/output tokens, with estimates marked. Renaming or pausing keeps its usage; replacing the credential starts fresh.",
				} },
				{ category = "added", label = "Conversation requests", items = {
					"The conversation header shows its AI request count. Retries, tool follow-ups, summaries and subagents are included; model discovery and relay polling are excluded.",
					"Counts persist on this device from this update. Context breakdown explains the total; earlier untracked requests are not reconstructed.",
				} },
				{ category = "improved", label = "Modals and setup", items = {
					"Log details and context usage fit their contents and scroll when needed. Modal bodies have balanced padding, including the tutorial, Discord invitation and donation options.",
					"Provider setup groups access, model and connection settings, with the setup guide expanded by default. The gallery adapts its card columns to the available width.",
					"Model search and actions remain reachable while the catalog scrolls. Settings, conversation controls and log previews have clearer spacing and wrapping on narrow screens.",
				} },
				{ category = "improved", label = "Code workspace", items = {
					"Syntax colors stay visible while selecting code. Selection fills, preview line spacing, tabs, history and comparison views follow the active type size and code palette.",
				} },
				{ category = "fixed", label = "Keys and compact layouts", items = {
					"Replacing one API key preserves the other entries. Duplicate or empty replacements leave the pool intact, and short credentials stay masked in both entry rows and the pool summary.",
					"Compact controls reserve enough room for larger text. Multiline fields adjust their padding without replacing the field, draft or selection when keyboard space changes.",
				} },
			},
		},
		{
			version = "3.7.0",
			revision = "2026-10-25-models-tunnels-workflows",
			date = "October 25, 2026",
			title = "Models, tunnels and faster workflows",
			highlights = "Find providers and models faster, use AgentRouter's supported GPT models, and manage desktop tunnels in one place. Tools, logs and usage history are clearer across the coordinated 3.7.0 apps.",
			sections = {
				{ category = "added", label = "Provider choices", items = {
					"Add Vercel AI Gateway, Perplexity Orchestrator, FriendliAI, Venice, Nscale, Arcee AI and AI/ML API with current setup instructions. Vercel's free credits apply to eligible models; the other new presets require paid API access.",
					"AgentRouter selects the supported GPT Responses route and reasoning controls while retaining Claude Messages. Fetch the models available to your account; a catalog entry does not guarantee capacity.",
				} },
				{ category = "added", label = "Tunnels and Cline", items = {
					"The Windows app's Tunnels tab brings OpenCode, Kilo and Cline status and controls together. Install Cline separately, enable it and sign in, then choose Cline in the provider gallery and fetch its current free models.",
					"Cline uses your existing Cline profile through the connected desktop bridge and supports text only. Missing sign-in or a disconnected bridge gives a clear setup message. Its credentials stay on the desktop.",
				} },
				{ category = "added", label = "Kilo recovery", items = {
					"Kilo recovery is enabled by default in the Windows and Android apps and starts only after an explicit anonymous quota refusal. The original request stays within its deadline and can be stopped.",
					"Change Kilo tunnel in the app's settings while the bridge or relay is stopped. Cowork in Roblox and the browser shows the helper's current status; direct executor requests need a connected helper to recover.",
				} },
				{ category = "improved", label = "Model selection", items = {
					"The model picker shows your current provider and model together, with connection and free-model information. Search saved providers in the new switcher without losing your model search, effort controls or custom model options.",
					"The picker gives touch controls more room and keeps reasoning settings reachable above the keyboard. Model menus and large saved catalogs support multiword search, with refresh and manual entry available when no models match.",
					"Refresh pricing and context information for 1,760 model entries. Known non-chat API types are omitted from supported mixed catalogs, while manual model IDs stay available.",
				} },
				{ category = "improved", label = "Tools, logs and usage", items = {
					"Search Tools and Logs with multiple words and open full details when needed. Tool discovery respects the current conversation's permissions and available tool groups.",
					"Usage history distinguishes unknown prices from zero-cost work and keeps cache-write usage in cost estimates. Older history retains its known totals without inventing missing prices.",
				} },
				{ category = "improved", label = "Coordinated apps", items = {
					"The client, bridge, Windows app and Android companion all ship as 3.7.0. The desktop app checks installed tunnel helpers before Cowork starts and shows their setup status.",
					"Browser model dialogs cancel closed requests and ignore results from a previous provider. Unrelated status updates preserve the current model selection, focus and scroll position.",
				} },
				{ category = "fixed", label = "Bounded retries", items = {
					"One alternate connection and one circuit retry are allowed after a complete quota refusal. Exhausted exits pause recovery for 60 seconds. Signed-in requests, other providers, partial replies and uncertain outcomes never switch connections.",
					"Honor provider instructions not to retry a terminal refusal. Shared connections still have provider allowances, so recovery cannot guarantee unlimited requests.",
				} },
			},
		},
		{
			version = "3.6.6",
			revision = "2026-10-23-provider-gallery",
			date = "October 23, 2026",
			title = "A provider gallery and a clearer queue",
			highlights = "Adding a provider becomes a searchable gallery of free, paid and hybrid routes, the message queue becomes a readable Up next list, and Settings opens from one place.",
			sections = {
				{ category = "added", label = "Provider gallery", items = {
					"Add a provider opens a gallery with Recommended, Paid and Local tiers and a search field that spans them. Each card says what the provider is, what access costs and how to start; the custom endpoint is the last card in every tier.",
					"The catalog grows to 66 presets. Recommended begins with Project UAI Free, AgentRouter, OpenCode Zen, OpenRouter and OpenCode Go, followed by the free-tier and no-key routes.",
				} },
				{ category = "improved", label = "Provider labels", items = {
					"Hybrid services are recommended and labelled by their free half: Free models for OpenCode Zen and OpenRouter, Free CLI for OpenCode Go. Included marks the distributed community key, Free tier and No key describe the other free routes, and no hybrid is labelled Paid.",
					"Choosing a card seeds the editor, which repeats the tier and description. The Preset row reopens the gallery without discarding a typed name, key or model, and a dismissed draft resumes on the next Add.",
					"The accent border follows highlighted providers in the catalog, so it stays on Project UAI Free, AgentRouter and OpenCode Zen rather than on whichever card happens to be first.",
					"The gallery has more room: wider card gaps, a taller dialog and bottom padding so the last card clears the edge.",
				} },
				{ category = "improved", label = "Queue and settings", items = {
					"Queued messages open as Up next: a state line, numbered cards with the next message marked, and edit, reorder and remove controls on a quiet row. An empty queue explains itself, and the edit dialog counts bytes as they are typed.",
					"The composer's queue strip is tinted and carries the held state as a dot instead of only in words.",
					"The sidebar's Customize row is now Settings and opens the settings modal on the General pane; the duplicate Settings entry under More is removed. The profile menu's Tutorial row has its icon.",
				} },
				{ category = "fixed", label = "Catalog", items = {
					"Remove LLM7. GitHub Models stays out because it was retired on 30 July 2026, and Perplexity and Databricks are not offered because this client's base-URL normaliser would send them to a path their APIs do not serve.",
					"Kilo and OVHcloud no longer send the Claude Code identity: a public no-key gateway is not a Claude endpoint and never asked to be treated as one.",
				} },
			},
		},
		{
			version = "3.6.5",
			revision = "2026-10-21-tool-context",
			date = "October 21, 2026",
			title = "Reliable connections and a refreshed desktop",
			highlights = "Matching client, bridge, Windows and Android releases with bounded mobile transport, a refreshed desktop launcher, network capture and a smaller opt-in tool catalogue.",
			sections = {
				{ category = "added", label = "Network capture", items = {
					"Add read-only network and payload capture. Start net_capture, run a loader, then read bounded HTTP records or the HTTP-to-chunk chain. UAI's own requests and compiles are excluded, and Stop restores the hooks.",
					"Records redact credentials, link responses to compiled chunks by hash or thread, and flag code-like responses that never compile. Nothing is rewritten, replayed or executed by the capture.",
				} },
				{ category = "added", label = "Tools and diagnostics", items = {
					"Choose an opt-in tool profile in Settings → Agent to declare a smaller catalogue. All tools remains the default; hidden tools stay callable through tool_search with their normal permissions and conversation scope.",
					"Retain large tool results in a per-conversation evidence ledger. The default 8 KiB threshold skips small results and already-persistent tools, deduplicates repeats and writes through a bounded queue instead of blocking each tool call. Switch to all or off in Settings. The evidence tool lists, searches and pages full text or structured data after compaction; evidence_clear removes a conversation's ledger.",
					"Create a local, redacted support bundle from Diagnostics. It excludes API keys, memory, custom instructions, conversation text, file contents and captured payloads.",
				} },
				{ category = "improved", label = "Desktop", items = {
					"A refreshed Cowork launcher brings clearer connection status, setup and update controls. Open the executable once to start; an existing window can be brought forward during startup.",
					"Client, bridge, Windows app and Android companion now share version 3.6.5 in one release. Existing update flows retain their verified downloads and production identity.",
				} },
				{ category = "fixed", label = "Mobile transport", items = {
					"Unfinished mobile native HTTP calls keep ownership across discovery, Stop, new requests and supported client reloads. A separate bounded cancellation lane keeps Stop responsive.",
					"Always use relay stays enforced after a failed health check. Oversized or malformed replies stop polling without resubmitting inference; the companion checks the complete encoded reply before sending it.",
					"Expanded thinking on touch-only devices draws a bounded excerpt while retaining the original reasoning in conversation context and saved history.",
				} },
				{ category = "fixed", label = "OpenCode", items = {
					"Includes the verified OpenCode execution gate from bridge 3.6.2. Desktop tool selections return blocked-action feedback so the Roblox conversation can continue with available tools.",
				} },
			},
		},
		{
			version = "3.6.1",
			revision = "2026-10-20-opencode-tool-recovery",
			date = "October 20, 2026",
			title = "OpenCode tunnel tool recovery",
			highlights = "OpenCode desktop tool choices become recoverable feedback so Roblox conversations can continue.",
			sections = {
				{ category = "fixed", label = "OpenCode tunnel", items = {
					"When OpenCode selects a desktop tool, block execution and return feedback that guides the next agent step to an available Roblox tool. The conversation keeps its tool scope and history.",
					"Preserve mixed tool call order even when remote calls arrive out of order. Cancellation and invalid handoffs still stop the request; desktop actions are never approved.",
				} },
				{ category = "improved", label = "Patch update", items = {
					"Existing desktop 3.6.0 automatically fetches bridge 3.6.1 and its web files when idle. Refresh the browser and reload the published Roblox client for the complete fix.",
				} },
			},
		},
		{
			version = "3.6.0",
			revision = "2026-10-19-clear-conversations",
			date = "October 19, 2026",
			title = "Clearer conversations and reliable connections",
			highlights = "A new interactive website, answer-focused bridge conversations, better OpenCode detection, and a simpler companion with compressed-request support.",
			sections = {
				{ category = "improved", label = "Project UAI website", items = {
					"A redesigned responsive page brings UAI to life with an interactive 3D centerpiece and animated SVGs. Explore tools, install the client and download the apps, with motion controls and reduced-motion support.",
				} },
				{ category = "improved", label = "Bridge conversations", items = {
					"Each response has one heading and an uninterrupted answer. Tools, thinking and delegated work are grouped into a collapsed activity drawer; approvals and failures stay visible.",
					"Reasoning opens into a formatted view with its own Copy action. Errors explain what happened and offer recovery actions, with technical details available separately.",
				} },
				{ category = "fixed", label = "OpenCode discovery", items = {
					"Find installed native CLI files behind npm and Bun launchers, in common Windows installation folders and macOS app resources. Quoted PATH entries and active nvm installations are supported.",
					"Show the detected CLI version and useful setup guidance when its server API is incompatible.",
				} },
				{ category = "fixed", label = "Companion message decoding", items = {
					"Read compressed POST messages before JSON validation, fixing invalid executor request errors for gzip submissions even when pairing already works. Request size limits, authentication and the original job identity remain enforced.",
					"Invalid encodings give clear guidance without exposing message contents. Resetting pairing is not a remedy for a message-decoding failure.",
				} },
				{ category = "improved", label = "UAI Relay setup", items = {
					"A redesigned companion puts connection status, Start/Stop and short setup steps first. Request activity stays compact, with advanced settings and diagnostics available when needed.",
					"Install the matching 3.6.0 companion and desktop releases. Production Android updates preserve the existing signing identity and pairing.",
				} },
			},
		},
		{
			version = "3.5.6",
			revision = "2026-10-18-mobile-relay-supported",
			date = "October 18, 2026",
			title = "Mobile relay reliability and automatic updates",
			highlights = "Fix companion request admission and deadline handling, show real connection activity, and add verified automatic Android update downloads.",
			sections = {
				{ category = "added", label = "Android companion updates", items = {
					"UAI Relay checks official releases at startup and every 15 minutes while running, downloads compatible updates automatically, and verifies the APK's hash, package, version and signing certificate.",
					"Install updates after active requests and retained replies finish. Android asks for installation approval; an interrupted installation retains its admission pause until resolved.",
				} },
				{ category = "fixed", label = "Companion requests and deadlines", items = {
					"Finite request timeouts use integer seconds so the Android relay accepts them. Updated clients and companions can keep normal inference running beyond five minutes while each executor poll stays within five seconds.",
					"Explicit deadlines, Stop and provider failures still end the original request. Lost polls keep the same request ID and never start a second inference.",
					"Abandoned requests cancel after two minutes without their owner's polls, releasing the provider connection and idle wake lock.",
				} },
				{ category = "improved", label = "Connection and activity", items = {
					"Authenticate saved pairing, repair a rejected token, and check again when sending after the companion starts. The app separates saved pairing from live contact and shows requests, received bytes and safe error categories.",
					"OpenCode text, tool calls and tool-result replay passed with the companion's HTTP library on Windows. A user then confirmed OpenCode inference on a Delta Android phone through the UAI Relay app after one manual retry; mobile OpenCode now requires the UAI Relay app from Discord. Phone tool execution, tool-result replay and background survival remain unverified.",
				} },
			},
		},
		{
			version = "3.3.5",
			revision = "2026-10-18-prompt-bridge-queue",
			date = "October 18, 2026",
			title = "Stronger agents and desktop bridge",
			highlights = "More reliable tool use, a refreshed desktop dashboard, richer bridge responses and editable queued follow-ups.",
			sections = {
				{ category = "improved", label = "Agent reliability", items = {
					"Main and worker prompts require precise function calls, observed targets, complete arguments and real results before reporting success. Detailed guides remain available when needed.",
					"Tools beyond a provider's 128-declaration ceiling remain accessible through a bounded catalog adapter, with normal scope and permissions.",
				} },
				{ category = "improved", label = "Desktop and OpenCode", items = {
					"The refreshed desktop dashboard offers persistent OpenCode tunnel, MCP server, browser-open and automatic app-update switches. Minimize stays on the taskbar; closing stops Cowork and exits.",
					"OpenCode reports the installed CLI version and distinguishes disabled, missing and failed setups. Required native API routes are checked before use.",
				} },
				{ category = "improved", label = "Conversation and follow-ups", items = {
					"Review, edit, reorder and clear pending follow-ups in Roblox and the browser. Stale edits are rejected and attachments stay with their message.",
					"Bridge assistant replies and tool cards give outcomes, progress, exact inputs and results a clearer presentation.",
				} },
			},
		},
		{
			version = "3.3.1",
			revision = "2026-10-17-native-preview-layout-fixes",
			date = "October 17, 2026",
			title = "Live bridge previews and interface fixes",
			highlights = "Roomier model selection, visible queued messages, readable tool errors and live bridge progress in Roblox.",
			sections = {
				{ category = "fixed", label = "Model picker and queued messages", items = {
					"Temperature settings now live under Models → Options → Temperature, leaving more room for the model list. Free-model outlines are softer in Roblox.",
					"Queued messages show their count and review action above the composer instead of an empty bar.",
				} },
				{ category = "fixed", label = "Bridge progress and tool results", items = {
					"Roblox receives real text and reasoning previews during bridge inference through short status polls. The browser keeps its live provider stream, and the full reply replaces the preview once.",
					"Waiting bridge jobs no longer occupy native HTTP connection slots. Concurrent agents leave room for their polls; connected inference has no local overall deadline, while Stop and provider errors remain effective.",
					"Bridge tool calls use compact status summaries and readable errors, with full inputs and results available when opened.",
				} },
			},
		},
		{
			version = "3.3.0",
			revision = "2026-10-17-mcp-gemini-followups",
			date = "October 17, 2026",
			title = "MCP, bridge redesign and queued follow-ups",
			highlights = "Connect your external agent to Roblox with MCP, use the rebuilt bridge, and send follow-ups while UAI works. Free access learns compatible fast routes.",
			sections = {
				{ category = "added", label = "MCP connections", items = {
					"Use UAI's Roblox tools from Claude Code, Codex, Cursor, OpenCode and other MCP clients through the desktop bridge. HTTP and stdio connections retain normal UAI permissions and isolated tool sessions.",
					"Copy an agent setup prompt from Settings → MCP. It includes the detected connection details and asks your agent to configure and verify its connection.",
				} },
				{ category = "added", label = "Follow-ups while working", items = {
					"Send follow-up messages in Roblox or the bridge while the agent is running. They queue in order for the next safe response or tool boundary. Pending messages stay visible and Stop remains a separate action.",
				} },
				{ category = "added", label = "Gemini and temperature controls", items = {
					"Use native Gemini model discovery, image inputs, tool calls and results, thinking controls and saved signature replay, including OpenCode Go Gemini models.",
					"Choose Auto, Send or Omit temperature for each model. Auto honors documented restrictions and learns explicit provider refusals without retrying ordinary range errors.",
				} },
				{ category = "improved", label = "Subagents and environment guidance", items = {
					"Review each subagent's task, progress, tools and results in richer preview modals, and send a contextual follow-up when its work finishes.",
					"Use a detailed environment guide covering capabilities, permissions, native workflows, shared state and cleanup, with official sUNC references. Stronger main and worker instructions load detailed guidance on demand.",
				} },
				{ category = "improved", label = "Bridge workspace", items = {
					"Use a rebuilt workspace with Connection, Settings and management screens in modals, clearer assistant responses and improved model and reasoning controls. Context usage shows estimated messages, system/tools, summary and the compaction point.",
					"Find free models by their rounded green outlines in both Roblox and the bridge.",
				} },
				{ category = "improved", label = "Adaptive free routing", items = {
					"Included HCNSEC access measures small synthetic tool requests and prefers compatible fast models, targeting requests under ten seconds. Unknown or incompatible routes retain provider auto; your messages are never raced to benchmark models.",
					"Automatic free routing is on by default. Routed requests show the selected model and where to disable it: Settings → Agent → Automatic free routing. Turning it off applies to future requests without stopping active work.",
				} },
				{ category = "fixed", label = "Picture attachments", items = {
					"Removing an uploading picture keeps it removed when the upload or a delayed event finishes, including after a browser reload.",
				} },
				{ category = "improved", label = "Code workspace", items = {
					"Select several Library scripts or actions and delete them with one confirmation. Changed items are checked before the whole batch is removed.",
					"Navigate Explorer subtrees, search, select multiple instances and inspect field values with clearer controls. Remote Spy makes capture duration, scope, filters, call details and caller navigation visible.",
				} },
				{ category = "fixed", label = "Editor selection", items = {
					"Native text and selection share one layer while dragging or selecting code. Syntax returns when selection collapses. Native line measurements reduce vertical drift, and caret-follow yields during a drag.",
				} },
			},
		},
		{
			version = "3.2.0",
			revision = "2026-10-16-intro-tour",
			date = "October 15, 2026",
			title = "Project UAI Free and OpenCode desktop",
			highlights = "Start with included free access, keep the OpenCode desktop workaround, and add an optional installed CLI bridge path. OpenCode free models are unsupported on mobile. (Corrected October 18, 2026: mobile OpenCode requires the UAI Relay app from Discord.)",
			sections = {
				{ category = "added", label = "Project UAI Free", items = {
					"Project UAI Free is ready by default when no provider is configured. Included public HCNSEC access uses its verified auto router; existing providers and credentials stay intact.",
					"Thank you for your continued use and support. Shared capacity and speed vary, and more free providers may become available soon. Join https://discord.gg/9xYyyYuKap for help and updates.",
				} },
				{ category = "added", label = "Getting started", items = {
					"A six-step introduction covers included free access, the workspace and permissions, with direct links to Chat and Providers. It waits for an available window; reopen it from Tutorial in the profile menu.",
					"Clicks inside a dialog stay inside it, including empty form space. Dismissed Add provider forms retain their unsaved details for the session; Start over clears the draft.",
				} },
				{ category = "improved", label = "OpenCode desktop", items = {
					"Strengthen the direct desktop workaround with a live-verified desktop identity, retaining required compatibility tool declarations and Chat/Responses fallback without the bridge.",
					"The desktop bridge can also use a separately installed OpenCode CLI server for verified free models. It discovers models, owns temporary sessions and returns UAI tool calls to Roblox. The CLI binary is not packaged.",
				} },
				{ category = "improved", label = "Model pricing and limits", items = {
					"Refresh provider-specific model prices and context/reply limits, including documented cache rates and long-context tiers. Unknown prices stay unknown; included Project UAI Free access has zero cost.",
				} },
				{ category = "fixed", label = "Provider routes and help", items = {
					"Add a separate OpenCode Go preset with its own catalog and Chat, Responses or Messages routing. Keep Go outside the free CLI backend and explain subscription and Privacy region refusals. Gemini's native Go protocol is not implemented.",
					"Remove the retired OpenCode proxy and migrate saved URLs back to Zen. Only AgentRouter uses the proper proxy domain; no Workers.dev fallback remains.",
					"OpenCode free models are unsupported on mobile, including the Android companion. Use Project UAI Free there. Error messages include Discord support. (Corrected October 18, 2026: mobile OpenCode works with the UAI Relay app from Discord.)",
				} },
			},
		},
		{
			version = "3.1.0",
			revision = "2026-10-14-bridge-improvements",
			date = "October 14, 2026",
			title = "Bridge improvements",
			highlights = "A redesigned Cowork workspace and desktop app, automatic updates, unlimited bridge request time, smaller mobile sidebar text and complete OpenCode Responses relay support.",
			sections = {
				{ category = "improved", label = "Cowork workspace", items = {
					"Use the redesigned Cowork workspace with text-only branding, clearer navigation and rebuilt connection, provider, tool, agent, activity and settings views.",
					"Use scrollable dialogs with stable headers and actions, clearer provider/model forms, reliable focus restoration and smoother transitions on desktop and mobile.",
					"Keep navigation compact when conversation text is enlarged. Show Web runtime automatically after the bridge connects and Game runtime after it disconnects.",
					"Use smaller sidebar text in the Roblox mobile client while retaining touch targets and text scaling. Cowork requests wait without a configurable time limit until completion, failure or Stop.",
					"Client animations are always enabled. Older saved or imported motion preferences no longer disable them; the motion setting has been removed.",
					"Deadline errors highlight the official Discord tutorial help. Automatic bridge updates preserve pairing, wait for idle work and restore the previous version if startup fails.",
					"The redesigned Windows app is one executable with no ZIP to extract. It detects installed Node.js or downloads it for your account. Desktop app updates download from GitHub and apply on restart.",
				} },
				{ category = "fixed", label = "Connections and inference", items = {
					"Keep routine mobile relay probes quiet, back off failed discovery and ignore stale pairing completions. Mobile command polls use short waits.",
					"Relay OpenCode Responses text, reasoning, tools and pictures through Cowork. Preserve the existing OpenCode session and protocol workarounds and the selected key. Direct requests keep their original deadline.",
					"Keep failed or incomplete provider streams terminal and protect dialog actions from duplicate submission and stale completions.",
				} },
			},
		},
		{
			version = "3.0.0",
			revision = "2026-10-13-agent-and-script-efficiency-key-rotation",
			date = "October 13, 2026",
			title = "Less repeated work, clearer tool outcomes",
			highlights = "Reuse unchanged source analysis, discover files by name, run focused project tests, and continue useful result pages without repeated requests. Agent, capture and scheduling paths avoid duplicate work while preserving ownership and explicit limits.",
			sections = {
				{ category = "added", label = "Focused script workflows", items = {
					"Find workspace files by filename glob without reading their contents. Select declared test modules and case-name filters; a run with no matching cases cannot pass.",
					"Continue immutable HTTP and readable web responses without fetching them again. Script, Explorer, action, template and IY discovery return useful bounded pages.",
				} },
				{ category = "improved", label = "Less repeated work", items = {
					"Reuse exact-source outlines and syntax outcomes while rechecking saved bytes and dependencies. Fresh execution wrappers preserve run isolation; Code line reads avoid splitting whole documents.",
					"Avoid repeated SSE string copies and tool-result batch rescans. Bound schema validation, unify Responses call identities, and show useful small result receipts immediately.",
					"Coalesce debounce bursts, process UTF-8 spans, chunk bytecode encoding and evict captured calls through a private queue. Summary reads skip unrequested argument graphs.",
					"Filter conversation/skill discovery, reuse short-lived product metadata and official Gravity source snapshots, and include all Anthropic prompt-token categories in context accounting.",
				} },
				{ category = "fixed", label = "Observed outcomes and cleanup", items = {
					"Rotate pooled API keys across successful requests and model discovery. Share rotation with request snapshots, preserve keys during proxy recovery and skip rate-limited keys without double advancement.",
					"Verify edited file bytes, report observed clamped or partial property writes, validate camera fields before changes, and resolve exact usernames before ambiguous display names.",
					"Track held input through release, Stop and revocation. Release performance and temporary interaction listeners; native effects are not described as rolled back.",
					"Keep hidden GUI ancestry, skipped search files and missing retained details explicit. Verify IY installations and restore persisted lifetime model/hour statistics.",
					"Cancel unavailable confirmations, verify embedded icon files individually and ignore stale mascot callbacks. UI LIB remains 1.3.0 and embedding SDK 1.0.0.",
					"Continue queued questions after cancelling one conversation's prompt and release composer listeners on destruction. Cancel stale provider tests and model discovery when their editor, selection or connection changes.",
				} },
			},
		},
		{
			version = "2.8.0",
			revision = "2026-10-12-scripting-guide-zen-responses-and-10-mib-attachments",
			date = "October 12, 2026",
			title = "Reliable scripting and clearer failures",
			highlights = "An on-demand scripting guide, more reliable decompiler fallbacks, clearer execution results and OpenCode guidance, support for Response-protocol Zen models, larger attachments, and focused runtime fixes from the client audit.",
			sections = {
				{ category = "added", label = "Script development reference", items = {
					"Read the scripting guide on demand: a short quickstart, exact tool examples, saved-file and editor workflows, focused debugging, cleanup, source inspection and UI LIB guidance. Main and subagents can request only the sections they need.",
				} },
				{ category = "fixed", label = "Script execution and projects", items = {
					"Distinguish source, compiler, wrapper and stale-revision errors. Keep canonical paths, reject oversized source before execution, and support managed arguments and multiple returns when only table.unpack is available.",
					"Retain runtime errors and disclose omitted output. Ordinary failures without pending work no longer receive a blanket do-not-retry warning; native continuations retain their cooperative limits.",
					"Keep completed project test results when another module has invalid exports or the case limit is reached. Report incomplete runs and discovery failures without discarding earlier evidence.",
					"Validate and quote template data, clean up temporary monitoring, and preserve nested tool failures. Reject stale Code proposals and isolate action inputs.",
				} },
				{ category = "improved", label = "Agents and providers", items = {
					"Give the model structured tool results with the IDs, listings, revisions and continuation cursors needed for its next action. Native results previously exposed these fields only to the interface while the model could receive a generic sentence.",
					"Preserve the required OpenCode compatibility tool declarations and streaming. Explain placeholder names and guide failed calls toward available UAI tools without adding aliases or expanding permission scopes.",
					"Give agents concise Luau guidance and distinguish saved files, pasted source and editor drafts. Guidance follows the offered tools and separates syntax checks from API or behavior verification.",
					"Read subagents receive read-risk tools only. Mutations use write permissions, unknown presets fail early, and client_status reports diagnostics without replacing delegated agent_status.",
					"Reject truncated arguments instead of guessing missing targets. Normalize memory keys consistently and honor supported Messages sampling settings. Successful response text no longer triggers transient retries unless explicit error fields identify one.",
					"Do not count token-truncated batches as repeated actions when no tool ran. A later complete, repaired call can execute without inheriting a false repeat warning.",
					"Support Zen models that only speak the Responses protocol. A request for one switches to that lane automatically on a protocol refusal, carries the standard tool declarations, and is remembered per endpoint and model. Free-tier lockout and unsupported-protocol refusals no longer count toward provider benching.",
				} },
				{ category = "improved", label = "Attachments and uploads", items = {
					"Raise text and code attachments and browser uploads to 10 MiB per file, with a larger per-draft budget and a matching pending-upload allowance. Large inputs still become verified pastes/ files read with the file tools, and a failed save never falls back to sending the source inline.",
				} },
				{ category = "improved", label = "Code and failure review", items = {
					"Keep Code editing and previews readable when syntax highlighting fails. Render run logs literally without requiring the Lua lexer.",
					"Review complete permission arguments and source through expandable previews and the full-argument viewer. Allow, Deny and dismissal settle once and release the prompt before the next queued request.",
					"Retain complete orphaned tool results, count unread failures in Latest and use Show failures to open their result bodies. Preserve the reader's disclosure and scroll choices.",
				} },
				{ category = "fixed", label = "Source and decompiler fallbacks", items = {
					"Reject unusable native output and service documents before caching; continue to available decompiler fallbacks. Report missing capabilities separately from failed attempts without exposing raw host or service error bodies.",
					"Stop starting fallbacks after cancellation or expiry, bound bytecode requests and retry waits, and discard late completions. Native operations retain their worker slots until they return.",
					"Install luacid in a private environment without replacing executor globals. Remove its unbounded response cache so explicit Refresh can request fresh source.",
				} },
				{ category = "fixed", label = "Runtime tools", items = {
					"Correct typed remote prefixes and finite numeric parsing. Report failed input adapters accurately, verify hierarchy changes, and recover previous Gravity selections when a failed update permits restoration.",
					"Bound fallback world and performance scans and label incomplete results. Protect host capability probes, preserve fractional fallback deadlines and nil callback arguments, and redact more credential formats from logs.",
					"Map generated bundle lines to source in the manifest. Fix website risk filters, the bulk-read example and animated catalog counts. UI LIB remains 1.3.0 and the embedding SDK 1.0.0.",
				} },
			},
		},
		{
			version = "2.7.0",
			revision = "2026-10-10-request-isolation-and-tool-cancellation",
			date = "October 9, 2026",
			title = "Focused agents and portable files",
			highlights = "Smaller prompts, relevant skill and memory reads, clearer Roblox capability guidance, consistent permissions, and one path contract across file and code tools.",
			sections = {
				{ category = "improved", label = "October 10: focused agent work", items = {
					"Shorter shared main/subagent instructions remove conflicting workflow rules and include specialized guidance only for the tools offered. Routine work needs no mandatory task list, delegation or repeated planning.",
					"Read relevant or explicitly requested skills and reuse unchanged bodies still in context. The enabled inventory fits within 3 KiB and names omissions; full inventories and bodies remain available through paginated reads.",
					"Prompts include a 2 KiB memory-key index instead of saved values. Search keys/values or read exact keys with continuation offsets; old workarounds remain available without becoming standing instructions or reordering saved entries.",
					"Subagents receive the current model, host instructions, reply language, tool scope and their own task list. Follow-ups take precedence over the original assignment while retaining useful evidence.",
					"Roblox guidance distinguishes local effects from server-confirmed results and directs agents to inspect available actions before reporting specific limits. Game rules or anticheat alone do not justify blanket refusals of ordinary scripting requests.",
				} },
				{ category = "fixed", label = "October 10: permission handling", items = {
					"Stop and permission/scope revocation release tool waiters promptly while native continuations remain safe to resume. Late progress/results are discarded, old calls stay cancelled, and invalid dynamic timeouts use a finite fallback.",
					"Tool discovery and execution use the same permission rules, including explicit allow/ask overrides in read-only mode. Capability checks and conversation scopes still apply.",
					"Unanswered approval timeouts and cancelled prompts are reported separately from user declines, saved rules and mode restrictions. Late answers cannot execute a settled call or save a rule; agents continue other allowed work without an extra confirmation.",
				} },
				{ category = "fixed", label = "October 10: provider attempts", items = {
					"Fallback prompts identify the provider/model actually receiving the request. Request hooks use fresh message and schema copies, preserving saved history and preventing edits from accumulating across attempts. Hook cancellation and replacement frame callbacks are honored.",
				} },
				{ category = "improved", label = "Routine work and response speed", items = {
					"New configurations start at Low reasoning effort. Existing saved choices are kept; change Effort in Agent settings to lower them. Provider default is now selectable and omits the effort field.",
					"The model modal exposes global effort for any model with Reasoning support enabled, includes Provider default, and follows setting changes. Known model scales remain constrained.",
					"New access settings default to Allow everything. Existing saved modes and explicit tool rules are kept; the composer names the active mode.",
					"Keep standing prompt instructions before changing environment facts so compatible providers can reuse more of their prompt cache. Routine work favors focused actions and only the relevant checks.",
					"Folded reasoning waits until opened to format and measure its text. Reopening and resizing reuse parsed text; formatting failures retain readable plain text.",
				} },
				{ category = "fixed", label = "Paths and provider feedback", items = {
					"File tools, search, check_luau and run_luau share unchanged files/... paths. New game folders use ASCII names; accessible existing and nested legacy folders remain in place.",
					"Resolve different executor listing formats against actual paths. Keep usable entries from incomplete listings and preserve leading spaces. Inaccessible saved Unicode folders receive a portable default without moving their files.",
					"Damaged or future-format game-folder identity files are preserved instead of silently replaced during prompt construction.",
					"Recursive discovery probes each unreadable game folder only once. Live answer and reasoning previews show separate truncation notices, so one long channel cannot mislabel the other.",
					"Thinking text clipped for transcript storage is labelled Excerpt. Other estimates say tokens shown; the old apparent 5,999-token limit was a display estimate, not a thinking budget.",
					"Stream errors show bounded, redacted provider details, including plain-text errors. Partial output never turns a failed stream into success or causes a duplicate request. Native requests remain capped at 300 seconds.",
					"A 400 that names a field the gateway's own way (HCNSEC: \"field MaxTokens invalid\") is repaired like any other: the reply ceiling is lowered to the bound it states, retried, and remembered for later turns.",
				} },
				{ category = "added", label = "Project identity", items = {
					"The ProjectUAI profile-menu entry and support modal now show the existing frame-drawn brand mark without an image download. What's New remains separate.",
					"UI LIB remains v1.3.0 and the embedding SDK v1.0.0.",
				} },
				{ category = "improved", label = "Project links and app attribution", items = {
					"OpenRouter app attribution, the Cowork bridge download and the published loader and site links now use the project's new Project-Ptolemy repository after the move from the personal account. Saved OpenRouter providers pick up the new URL on the next start; a referer set by hand is left alone.",
				} },
				{ category = "fixed", label = "October 11: script source fallback", items = {
					"A failed decompile is no longer shown as script source. A decompiler that fails returns a comment notice rather than raising, so the notice is rejected, the bundled luacid fallback is tried, and its own failure is reported with the reason instead of being cached or displayed as code.",
					"The bundled luacid fallback is installed with the executor's bytecode and HTTP functions pinned behind the host's own globals, and unreadable or empty bytecode is refused before a request. It now works where a host compiles chunks into a narrower environment.",
					"An empty success from the decompile service is retried instead of being stored as an empty script, so a transient empty response cannot stick for the session.",
					"Add the ByteFall service as a second bundled decompiler fallback, so a host that cannot run the compiled luacid client still has a plain-HTTP path to source.",
				} },
			},
		},
		{
			version = "2.6.0",
			revision = "2026-10-04-context-workspaces-themes",
			date = "October 4, 2026",
			title = "Reliable context, game files and theme controls",
			highlights = "Long tasks compact with recent evidence intact. File tools share consistent paths, game folders preserve Unicode, and UI LIB has a built-in Light/Dark switch.",
			sections = {
				{ category = "added", label = "Project and appearance", items = {
					"Open ProjectUAI from the player profile menu for project information and Star us on GitHub, with browser, clipboard and selectable-link support. What's New stays separate.",
					"UI LIB v1.3.0 adds a sun/moon mode icon beside the window controls, GetTheme and ToggleTheme to its existing Light/Dark system. Existing configuration profiles can retain the mode and custom accent; older profiles remain supported.",
					"Theme changes preserve controls, drafts and open overlays. Custom accent foregrounds use sRGB contrast; ThemeToggle=false keeps a script's existing appearance control.",
				} },
				{ category = "improved", label = "Context and tool work", items = {
					"Fold older complete tool exchanges inside long tasks, retain the current request and recent full evidence, and bound merged summaries with room reserved for them. Summary input includes paths, arguments, cursors and the active task.",
					"Count summary requests and structured tool arguments, reduce stale estimation overhead after compaction, and fit reply budgets beside the prepared prompt. Smaller fallback models get one compaction attempt.",
					"Paginate file listings, use available bulk-read space, and share reads across equivalent paths within a batch. Reuse cached game metadata and scoped inspection guidance instead of repeated game-name lookups.",
				} },
				{ category = "fixed", label = "Files and conversation reliability", items = {
					"Use the same files/... paths across every file tool, preventing accidental extra files directories. Preserve real nested paths and existing game folders, including legacy recursive locations.",
					"Keep PlaceId as game identity while preserving readable Unicode and emoji in bounded filesystem-safe names. Use host NFC normalization when available and handle Windows reserved names.",
					"Verify migrated copies before deleting sources. Preserve conflicts, failed writes and incompletely listed directories. Manual compaction failure and Stop preserve conversation history and explain the outcome.",
					"Keep internal subagent reminders from replacing the actual task and detect repeated equivalent JSON tool batches. The embedding SDK remains v1.0.0.",
				} },
			},
		},
		{
			version = "2.5.6",
			revision = "2026-10-03-live-subagents-performance",
			date = "October 3, 2026",
			title = "Live subagents and lower client overhead",
			highlights = "The main agent keeps working while subagents run and checks their progress periodically. Watch their work in a live monitor, with lower modal, editor and event overhead.",
			sections = {
				{ category = "added", label = "Live subagent details", items = {
					"Delegation starts in the background by default. The main agent continues independent work, checks progress with agent_status and collects reports before answering. Stop and terminal parent exits stop unfinished children.",
					"See the current step, provider and model, tool progress and results, latest delivered text and reasoning, elapsed time and final report. Stop remains available while an agent works.",
					"Cards and details update in place with bounded activity and previews. Buffered connections display output when the provider response arrives; follow-up runs start with fresh current activity.",
				} },
				{ category = "improved", label = "Client performance", items = {
					"Deliver events without copying the listener list on every event. Preserve nested events, subscription changes and yielding callbacks.",
					"Blink editor and code-preview carets without rescanning syntax or measuring unchanged text. Update the sidebar subagent count only when the count changes.",
				} },
				{ category = "fixed", label = "Modal layout and profile", items = {
					"Prevent modal fitting from chaining task.defer calls past Roblox's re-entrancy limit. Coalesce layout changes across frames, skip unchanged sizes, reuse header measurements and cancel pending fits on close.",
					"Keep the sidebar profile name and provider together, with room for larger text settings. UI LIB remains v1.2.1 and the embedding SDK remains v1.0.0.",
				} },
			},
		},
		{
			version = "2.5.5",
			revision = "2026-10-03-client-spacing-motion",
			date = "October 3, 2026",
			title = "Tighter spacing and calmer dialogs",
			highlights = "Modals, Settings and Quick Chat fade in at their final size. Forms, welcome cards, release notes and the sidebar use tighter, more consistent spacing.",
			sections = {
				{ category = "improved", label = "Dialog transitions", items = {
					"Replace entrance scaling with a short fade so text and controls keep their final geometry. Rapid close and reopen settle cleanly; reduced motion is immediate.",
					"Tighten modal headers and remove the unused body band from description-only confirmations. Fields and actions remain reachable above the keyboard.",
				} },
				{ category = "improved", label = "Layout and spacing", items = {
					"Keep settings labels, inputs and help text together, use consistent section spacing, and keep compact rows side by side when they fit.",
					"Tighten provider notes, welcome cards and release-note groups. Empty provider hints no longer take up space, and starter actions adapt to the available width.",
				} },
				{ category = "fixed", label = "Chat and navigation", items = {
					"Remove doubled gaps around fenced code blocks and the blank sidebar gap below collapsed navigation.",
					"Align conversation headings and folder actions with the other sidebar rows. UI LIB remains v1.2.1 and the embedding SDK remains v1.0.0.",
				} },
			},
		},
		{
			version = "2.5.0",
			revision = "2026-10-02-script-projects",
			date = "October 2, 2026",
			title = "Desktop layout on mobile and script projects",
			highlights = "The desktop interface fits mobile with clearer text, working layout choices and retained drafts. Ten new tools help create, review, test and bundle modular scripts.",
			sections = {
				{ category = "added", label = "Script creation tools", items = {
					"project_scaffold stages a working modular script; project_map reads saved file hashes, function outlines and literal dependencies.",
					"project_patch, project_patch_read and project_patch_apply stage, review and apply coordinated file edits with version checks and verified writes. Conflicting files and unsaved bound editor drafts are protected.",
					"project_patch_restore conditionally recovers recorded versions; project_patch_discard releases a checkpoint. Checkpoints expire after ten minutes or unload. Writes are not atomic, and partial results or external changes are reported.",
					"script_analyze reports host syntax errors and literal dependency problems. Compiler availability is explicit; full Luau type and Roblox API analysis are not included.",
					"script_test runs declared cases with assertions, fixture data, fresh module caches and failure reports. It uses managed client execution with shared native game state, not an isolated test process.",
					"project_build compiles and exports one deterministic Lua bundle with source line locations and a recovery checkpoint. Building never runs the script.",
					"Main and subagent prompts now explain source review, coordinated edits, build inspection and focused testing. The script project guide documents the manifest, tool API and limits.",
				} },
				{ category = "improved", label = "Shared mobile interface", items = {
					"Mobile uses the desktop layout at 55% dimensions, spacing and radii. Keep the normal sidebar, header, welcome view, composer, Quick Chat, Settings, Providers and Code tabs.",
					"Remove the separate mobile navigation and destination, document, category and provider pickers. Short Code and inspector panels scroll their original tabs, action rows and native inputs.",
					"Rotation, keyboard changes and sidebar toggles preserve live fields, drafts, selections and reading positions. The shared header keeps Minimize, Maximise and Close; the launcher appears after minimizing.",
					"Shared menus and form actions stay above the keyboard. Settings categories retain their drafts and scroll positions.",
				} },
				{ category = "fixed", label = "Clarity and layout settings", items = {
					"Handheld text starts at a 10px minimum before the user's text scale; standard icons start at 12px. Tiny drawn strokes keep whole-pixel bounds and at least one-pixel thickness.",
					"The mobile Layout setting now changes placement: Sheet at the bottom, Panel at the right, and Window in the centre. Each explicit layout remembers its own placement per orientation.",
					"Auto retains its compact placement. Changing mobile layouts keeps the same fields and drafts and leaves desktop window settings independent.",
				} },
			},
		},
		{
			version = "2.4.0",
			revision = "2026-10-01",
			date = "October 1, 2026",
			title = "Mobile spacing, touch workflows and provider recovery",
			highlights = "More room for mobile chat and Code, reliable touch gestures, automatic recovery from supported unauthorized-client errors, and optional community access.",
			sections = {
				{ category = "improved", label = "Mobile interface", items = {
					"Tighter card, form, header and navigation spacing keeps full touch targets. Ordinary typing stays compact in portrait and landscape; expand explicitly for longer drafts.",
					"Short keyboard layouts prioritize conversation results. Code uses destination and document pickers, keeps editing full width, and fits Find into one mobile row.",
					"Quick Chat preserves drafts and selections through rotation. Mobile Return inserts a newline, and vertical swipes over sliders scroll without changing settings.",
					"Settings categories retain their forms and scroll positions. Code, tables and reasoning fit above the keyboard, with narrower insets and space reserved for Copy.",
				} },
				{ category = "fixed", label = "Provider connections", items = {
					"An explicit unauthorized-client error from official OpenCode or AgentRouter endpoints switches to the Project UAI proxy and retries once. Saved providers retain the new Base URL; drafts change only when saved.",
					"The proxy forwards requests and API keys and has a shared 90,000-request daily cap. Invalid keys and custom endpoints do not cause an automatic switch; cancellation and deadlines still apply.",
				} },
				{ category = "added", label = "Community", items = {
					"HCNSEC setup offers Use free key for the shared community key. Choose it explicitly, fetch models or enter a model ID, then save; existing providers are preserved.",
					"An optional Discord invitation waits for five minutes of use and an idle pause, with a two-week cooldown. Not now postpones it; Don't show again or copying the invite stops reminders. Join Discord stays in the menu.",
				} },
			},
		},
		{
			version = "2.2.0",
			revision = "2026-10-01",
			date = "October 1, 2026",
			title = "Modal polish, workspace cleanup and donations",
			highlights = "Modal and dialog cards keep their full rounded silhouette, the agent can name a conversation by what it became, Files can delete workspace entries, the profile menu links the Project Ptolemy donation place and Ko-fi, and a failed host decompiler falls back to luacid.",
			sections = {
				{ category = "added", label = "Conversations", items = {
					"The agent sets a short, specific title from the user's request once the subject is clear, so the list reads as topics instead of opening lines.",
					"A conversation the user has named keeps its title: the rename tool is not offered there, a direct call is refused, and subagents have no title to set.",
				} },
				{ category = "added", label = "Workspace files", items = {
					"Delete a file or folder from the Files pane -- from the toolbar, the right-click menu, or the row's close control -- behind one confirmation.",
					"Deleting a file drops its binding, so a later save cannot report a change against a file that is gone. The workspace root is never deletable.",
				} },
				{ category = "added", label = "Script sources", items = {
					"When the host has no script decompiler, or its decompiler fails, script_source falls back to the bundled luacid service, using the executor's own bytecode and HTTP functions.",
				} },
				{ category = "added", label = "Support", items = {
					"The profile menu offers a Donate entry. Donate with Robux opens the Project Ptolemy donation place after a confirmation; Ko-fi copies its link for the browser.",
				} },
				{ category = "fixed", label = "Interface", items = {
					"Modal and dialog cards keep their rounded corners at the bottom. Opaque footers, the settings navigation bar, and mobile navigation no longer square the card's edge; each inner edge stays straight against the body while the outer corners follow the card.",
					"A confirmation that carries only a description shows its full wrapped text instead of clipping it to one line and forcing a scroll in a card with space to spare.",
				} },
				{ category = "improved", label = "Providers", items = {
					"Rebuilt model pricing and the model directory from the OpenRouter and LiteLLM datasets, covering current and newly released model ids.",
				} },
			},
		},
		{
			version = "2.1.1",
			revision = "2026-09-30",
			date = "September 30, 2026",
			title = "Long replies and capture-view reliability",
			highlights = "A long streamed reply is no longer discarded as an over-budget stream, and the Remote Spy view keeps refreshing when an executor drops the client's thread identity on scheduled threads.",
			sections = {
				{ category = "fixed", label = "Streaming", items = {
					"The frame budget no longer cuts off a long but valid reply. A token-per-event gateway can send tens of thousands of frames, and the old ceiling discarded the whole answer and benched the provider after three attempts.",
					"Frames are assembled as they decode rather than collected first, so a long answer no longer keeps a second copy of every frame in memory.",
				} },
				{ category = "fixed", label = "Remote Spy", items = {
					"Deferred client work restores the identity captured at boot, so a capture-view refresh scheduled from a remote hook is not refused when an executor drops the injected identity on scheduled threads.",
					"A failed capture-view refresh is reported once and can no longer abort the rest of the view or repeat several times a second.",
				} },
			},
		},
		{
			version = "2.1.0",
			revision = "2026-09-30",
			date = "September 30, 2026",
			title = "Mobile improvements and conversation folders",
			highlights = "Native mobile forms and navigation stay usable above the keyboard. Keep conversations in Universal or folders you name, with improved touch controls in UI LIB v1.2.1.",
			sections = {
				{ category = "added", label = "Conversation folders", items = {
					"New conversation lets you choose a game, Universal, or a custom folder and optionally name the chat before starting.",
					"Move existing chats from their conversation actions. Create or rename custom folders from Conversation folders; removing a folder keeps its chats in Universal.",
					"Folder names and membership survive reload. Existing chats retain their game grouping, and moving a chat preserves its messages, game context, and tool permissions.",
				} },
				{ category = "improved", label = "Project UAI on mobile", items = {
					"Short keyboard layouts move form actions into the body scroll region at full touch size. Keyboard dismissal pins the same buttons again without replacing inputs or losing drafts.",
					"Focused fields account for the reported keyboard edge and clipping ancestors. Nested panels avoid repeating an inner scroll, and hidden fields leave background views alone.",
					"Mobile history searches folder names and filters by folder. New conversation and workspace actions remain reachable by scroll while a keyboard is open.",
				} },
				{ category = "fixed", label = "UI LIB v1.2.1", items = {
					"Vertical swipes over sliders and color bars scroll without changing their values. Taps and horizontal drags edit values; cancellation, rotation, and hiding restore scrolling.",
					"Mobile layouts use slimmer content padding and wrapped section titles and dialog actions. Short dialogs keep their complete action targets in the scroll body.",
					"Dropdown search stays above the results when space permits. Open picker fields and buttons reflow with text size and rotation, and hiding releases text focus.",
				} },
				{ category = "added", label = "Embedding SDK 1.0.0", items = {
					"Hosts can boot without mounting the application, reuse a live client, and explicitly open provider setup or a conversation.",
					"Owned scopes clean up subscriptions, hooks, and custom tools. Structured requests settle once with success, failure, or cancellation.",
					"Named conversations validate and retain their tool policy and work budgets across reload. Unsupported saved policies keep their files without restoring unrestricted conversations.",
				} },
			},
		},
		{
			version = "2.0.5",
			revision = "2026-09-29",
			date = "September 29, 2026",
			title = "Smoother reading and organized activity",
			highlights = "Roblox chat keeps nearby text ready for backtracking and organizes tools and delegated tasks into compact summaries with details on demand.",
			sections = {
				{ category = "improved", label = "Roblox conversations", items = {
					"Nearby message renderers stay warm for backtracking. Visible chunks take priority, and long replies preserve the reading position during reflow.",
					"Small upward scrolls stop following immediately. New replies appear in the Latest control while you read earlier messages.",
					"Minimize and native tabs keep the visible text, live preview and expanded activity ready. Returning processes only new events instead of rereading and redrawing the whole conversation.",
					"Activity summaries show running, completed and failed work. Inputs and results render when opened, and completion leaves your chosen sections open or closed.",
					"Delegated tasks separate their goal, status and report from their tool activity. Returning to the conversation keeps completed work in its original card.",
					"The sidebar follows the window's rounded left corners while keeping its inner divider straight.",
					"Successful requests no longer show an invented transport failure. Select a request or application log to inspect and copy its recorded diagnostics.",
				} },
				{ category = "fixed", label = "Chat and images", items = {
					"Long chats mount nearby messages and Markdown chunks. Minimize suspends rendering; restoring keeps measured rows and preserves the draft, reading anchor, and retained updates.",
					"Browser snapshots avoid repeated layout and preserve reading position. Hidden documents defer live preview paints.",
					"PNG, JPEG and WebP attachments now send actual image content through the bridge to Chat Completions and Anthropic Messages models. Reload the client, restart the updated bridge, and choose a model with vision support.",
					"Image references stay scoped to their conversation. Expired current images request reattachment; duplicate relay submissions cannot dispatch twice.",
				} },
				{ category = "improved", label = "UI LIB v1.2.0", items = {
					"The desktop sidebar shows the local player's avatar, display name, username, and game, with readable loading fallbacks.",
					"Navigation and action labels use text; the frame-drawn Project UAI mark and minimize, close, and resize glyphs remain. Legacy tab Icon options are ignored, and the Project UAI | UI LIB. footer stays fixed.",
					"Owned transitions reverse cleanly and settle on hide or cleanup. Reduced motion follows the host preference when available and can be set per window.",
					"Dragging moves the window without remeasuring the full control list. Focus and loading states remain readable.",
				} },
			},
		},
		{
			version = "2.0.0",
			revision = "2026-09-26",
			date = "September 26, 2026",
			title = "Project UAI UI LIB",
			highlights = "A shared UI library for script tools. Agents declare controls and write application logic, while the library handles layout, input, configuration and cleanup.",
			sections = {
				{ category = "added", label = "Script interfaces", items = {
					"Load Project UAI UI LIB from our GitHub repository. Its independent API is at version 1.1.0 with buttons, toggles, checkboxes, sliders, inputs, dropdowns, segmented controls, keybinds and color pickers.",
					"Organize tools with tabs, sections, search, labels, badges, progress, dialogs and notifications. Dark/light themes and adjustable text sizes share UAI's visual language.",
					"Compact windows reflow for phones and keyboard space; desktop windows support dragging and resizing. Minimize keeps a draggable restore pill within reach.",
					"Dropdown options can show a player headshot at the start of the row and in the closed field. Library windows draw their own mark and keep the fixed Project UAI | UI LIB. footer. The existing agent client interface is preserved.",
				} },
				{ category = "added", label = "Agent guidance", items = {
					"Main agents and subagents read the bundled UI API reference before creating script interfaces. Scripts declare controls and application callbacks instead of building their own GUI components.",
					"Starter and showcase scripts cover the shared controls, configuration and cleanup. Stable window Ids replace previous script windows and release registered resources.",
					"Configuration imports validate values before applying them and stay silent by default. The library owns callback tasks, input listeners and window cleanup.",
				} },
			},
		},
		{
			version = "1.9.0",
			revision = "2026-09-26",
			date = "September 26, 2026",
			title = "Cowork browser workspace",
			highlights = "A refreshed browser workspace with verified bridge installation, live responses, picture previews and persistent drafts. Small screens and keyboard controls stay usable during live updates.",
			sections = {
				{ category = "added", label = "Browser workspace", items = {
					"Cowork provides responsive navigation, a step-by-step setup guide and system, light, dark or Match Roblox themes.",
					"Attach PNG, JPEG and WebP previews with upload progress, cancellation, retry and reload recovery. The AI receives text markers only; describe what matters in the image.",
				} },
				{ category = "improved", label = "Installation and conversations", items = {
					"Executor downloads use .txt files. Node verifies a pinned package and restores filenames before starting; a failed download preserves the previous launcher.",
					"Live replies retain stable Markdown blocks and reconcile with the saved response. Provider failures, replay gaps and uncertain delivery have visible recovery controls.",
					"Full text and code drafts persist per conversation, including attachments and edits made while a message is being delivered.",
				} },
				{ category = "fixed", label = "Layout and interaction", items = {
					"Task lists and attached drafts scroll within short screens. Long URLs, model names and dialog titles wrap, and Jump to latest stays above the composer.",
					"Pending answers, remembered permission choices, open tasks and keyboard focus survive updates. Permission requests identify their conversation and selected provider/model controls stay current.",
					"Dialog errors remain visible, expired tokens return focus to connection setup, and keyboard navigation reaches the selected conversation.",
					"Light-theme text and code-button hover states have readable contrast. Save failures use error colors, and high-contrast mode retains input focus and the Stop symbol.",
				} },
			},
		},
		{
			version = "1.8.0",
			revision = "2026-09-25",
			date = "September 25, 2026",
			title = "Chat stability, provider compatibility and native improvements",
			highlights = "Chat history survives busy workers and resizing. Local-server connections, model discovery and gateway streaming are more reliable, with clearer protocol and authentication settings.",
			sections = {
				{ category = "improved", label = "Providers and gateway streaming", items = {
					"Local URLs use HTTP by default and keep their path prefixes and query parameters. Model discovery reports auth failures and cannot reuse another connection's stale model list.",
					"vLLM no longer requires a key by default. Added llama.cpp and SGLang presets, corrected Ollama tool options, preserved object-shaped tool arguments and recognized small local context windows.",
					"Explicit auth choices work for compatible Messages gateways. Learned request repairs and output limits follow the endpoint and model that produced them.",
					"Connection edits discard stale model lists and cancel old fetches while preserving manual model ids. Switching presets applies their identity defaults and clears the previous gateway URL.",
					"Gateway sockets preserve provider paths and headers, accept split or combined SSE events and clean up late connections. HTTP fallback is allowed only before sending, so an uncertain socket outcome cannot duplicate the request.",
					"Socket settings explain UAI's custom gateway protocol. Normal local servers use HTTP; the socket does not implement OpenAI Responses or Realtime and does not remove transport limits.",
				} },
				{ category = "fixed", label = "Chat history and resizing", items = {
					"User messages and assistant replies have their own history budget. Tool activity cannot push them out; worker summaries and call/result pairs remain together.",
					"Maximize keeps the live interface in place. The window draws directly on every device, and refresh/layout changes preserve the reading position.",
					"Long conversations restore in short batches while new events keep arriving. Switching, clearing or closing a view cancels its unfinished replay and releases old rows and timers.",
					"Message options > Refresh conversation redraws messages and live activity without restarting the script. A Markdown failure falls back to readable text.",
					"Older saves recover conversation text still present in saved context. History limits are shown, worker timings and totals survive replay, and search finds dialogue after context compaction.",
				} },
				{ category = "improved", label = "Replies and progress", items = {
					"Removed the 8,192-token executor reply ceiling, including HTTP fallback. Your configured output budget and the model's own limits still apply.",
					"Buffered replies appear immediately instead of using simulated typing. Compatible streams show received text and reasoning as they arrive; buffered HTTP cannot show tokens before the response arrives.",
					"The agent is prompted to send one short progress message at a time between work steps and tool calls, then continue working.",
				} },
				{ category = "fixed", label = "Context and provider controls", items = {
					"Context breakdown labels have room to display. Totals include prepared instructions and tools, distinguish estimates from provider measurements, and refresh correctly when providers or models change.",
					"Add Provider is centered vertically in the horizontal provider strip, including after resizing or changing layouts.",
				} },
				{ category = "improved", label = "Source and decompilation", items = {
					"Source views identify where their text came from. Inspected and decompiled snapshots are read-only; Extract editable copy creates a separate document without running it or writing back to the live script.",
					"Source loading shares requests, supports refresh and reports unavailable, failed or expired snapshots. Switching or closing views prevents old requests from reopening them.",
				} },
				{ category = "fixed", label = "Explorer and editing", items = {
					"Explorer actions use the selection shown in the Inspector and reject stale targets. Search cancels old work, avoids duplicate results and explains partial scans, row limits and deep paths.",
					"Large documents reuse syntax colors and line measurements. Unicode selection, multiline highlights, horizontal caret reveal, Go to line, match counts, case and whole-word search, and searches across source pages are corrected.",
					"Autosave handles maximum-size documents and interrupted writes. Retry required, Conflict and expired-source states preserve drafts, while stale delete confirmations and repeated run requests are rejected.",
				} },
				{ category = "improved", label = "Remote Spy", items = {
					"Capture defaults to a selected remote and 30 seconds. Whole-game, subtree and continuous capture are explicit choices; selected-subtree capture uses the Explorer's primary object.",
					"Inspect a captured caller, open its source or decompile it after capture, and see likely remote call sites. Exported records include source provenance.",
					"Incoming calls offer diagnostics and caller actions. Outgoing calls also offer argument editing, reviewed one-shot replay and portable scripts that must be reviewed before copying or exporting.",
					"Capture shows unknown hook attribution and any forwarding wrappers retained after Stop. Late results count toward storage limits, and exports remain consistent while new calls arrive.",
				} },
				{ category = "fixed", label = "Conversation and subagent reliability", items = {
					"Recent saved chats restore correctly, progress updates preserve the transcript, and unsaved conversations remain available.",
					"Stopped subagents can resume. Queued follow-ups remain cancellable, duplicate dispatch is rejected, configured concurrency is honored, and finished workers clear their Stopping label.",
					"Unlimited subagents no longer inherit a disabled execution budget while waiting. Timed-out requests and remote replays are not automatically sent again when their outcome is unknown.",
				} },
			},
		},
		{
			version = "1.7.0",
			date = "September 24, 2026",
			title = "Code workspace",
			highlights = "Shared Luau documents, a native editor, workspace files, Explorer, Remotes, and recorded changes with guarded review and Undo.",
			sections = {
				{ category = "added", label = "Workspace", items = {
					"Shared Luau documents, native multiline input, syntax colors, line numbers, Find, Go to line, indentation, and Run/Stop with retained output.",
					"Script/action library, typed action inputs, source versions, source Undo/Redo, guarded proposals, and wide or compact source comparisons.",
					"Native Explorer with lazy hierarchy, search, exact object references, multiple selection, supported properties, attributes, tags, hierarchy actions, source opening, world picking, bookmarks, and metadata export.",
					"Native Remotes with explicit scoped capture, pause/stop, bounded argument/result trees, independent filters and traffic rules, reviewed one-shot replay, generated scripts, and offline capture import/export.",
				} },
				{ category = "improved", label = "Coding navigation and review", items = {
					"Browse UAI workspace folders, expand parents, open files, and use Save or Save as. Disk-conflict checks preserve edited drafts.",
					"History and Game changes use searchable timelines and inline reviews, with source diffs, before/after values, and guarded Restore or Undo actions.",
					"Run and Save stay adjacent. Stop appears during a run; document labels and close targets keep room in narrow layouts.",
					"Coding buttons, toolbars, searches and dialog actions have consistent padding. Crowded action strips scroll and reveal keyboard focus; tree rows accommodate larger text and touch targets.",
				} },
				{ category = "improved", label = "Shared behavior", items = {
					"UI and tools share source revisions, instance identities, typed edits and recorded property/attribute Undo. Changing a view never runs source or starts capture.",
					"Two verified Code snapshots protect drafts; damaged files are preserved. Missing filesystem/compiler/clipboard capabilities have explicit fallbacks.",
					"Capture survives navigation and shows a launcher indicator. Stop, unload, reset and authorization revocation clean up owned behavior; expired callbacks cannot restart it.",
					"Capture coverage reports the actual backend, subscribed events and omitted targets. Game Undo covers recorded property and attribute changes with conflict checks.",
				} },
				{ category = "fixed", label = "Editing and live inspection", items = {
					"Syntax colors remain visible while editing, with a visible caret and selection. Switching files restores the document's cursor and selection.",
					"Explorer refreshes preserve the pressed row's identity. Parent clicks expand children and context actions target the clicked object.",
					"Remote Start/Pause/Stop work directly. Incoming discovery covers larger remote collections, quiet filtered calls remain findable, and arriving results preserve replay edits.",
				} },
			},
		},
		{
			version = "1.6.0",
			date = "September 23, 2026",
			title = "File attachments and Project Gravity",
			highlights = "Long inputs become real files with compact references. Control Gravity's engine, parts, settings, shortcuts and plugins. The agent works in small tool batches.",
			sections = {
				{ category = "added", items = {
					"Inputs over 8,000 bytes are saved intact to UAI/pastes/ as verified files, up to 2 MiB. Short messages stay inline; long source is not copied into the prompt.",
					"Browser uploads use separate ordered chunks. Both composers support attachment-only sends and retain drafts after a failed upload or send.",
					"Project Gravity tools inspect shapes and settings, control the engine, target players, adjust formations and control values, and invoke real shape buttons on desktop and mobile.",
					"Gravity Part Control lists held parts with session-scoped IDs, selects and moves groups, assigns pin/manual/shape modes, changes ride and physics overrides, and releases selected or all overrides.",
					"Gravity keybinds, favorites, settings reset, manual Slingshot controls, interface, visual performance, FPS, core color and ignore tags use native handlers. Key conflicts and stale part IDs are refused.",
					"gravity_plugin_read provides the guide, template and real source. gravity_plugin_write saves verified files from source or a saved path, validates setup once, and registers custom shapes with reload cleanup.",
					"gravity_launch downloads and runs the official Project Gravity loader when it is not already connected, reports the live status, and reloads on force. Shape inspection and the plugin guide cover the FrameTracking flag.",
				} },
				{ category = "improved", items = {
					"The prompt asks for successive batches of normally 1–4 independent tool calls. Tool-call limits and concurrency settings are unchanged.",
					"Automatic compaction sizes itself to the model's context window (Compact at, 80% by default), with the Context budget as a hard ceiling, and measures pressure against the prompt tokens the provider actually reports. Compact now, in the composer's message-options menu, folds older turns on demand.",
					"A live context-window counter sits beside the model in the composer, and the agent can review earlier conversations with conversation_list (triage by opening request) and conversation_read (a condensed digest by default, or verbatim with full=true).",
					"Landscape touch layout uses a compact multiline composer, searchable conversation navigation, full-width settings and a bounded attachment strip.",
					"Drafts, attachments, open forms and orientation-specific placement survive rotation. Mobile Enter adds a line; Send submits. Desktop placement stays independent.",
				} },
				{ category = "fixed", items = {
					"A failed file save never falls back to sending the entire long input. Missing attachments or disabled file tools leave the draft available for correction.",
					"Saved-paste reads preserve UTF-8 and continuation offsets, with at most 6,000 source bytes per slice. Searches accept pastes/ paths and explicit scopes cannot be shadowed by workspace names.",
					"Gravity connections follow the current runtime after reload and stop using an unloaded session.",
					"Gravity's companion update adds mobile shape/hotkey parity, restores visual effects and bindings on reset, and refreshes Part Control sliders and toggles after external changes.",
					"Loaded plugin callbacks stay usable after setup and retain explicit task cancellation. Failed plugin writes verify restored source before reporting recovery.",
				} },
			},
		},
		{
			version = "1.5.0",
			date = "September 20, 2026",
			title = "IY controls and executor timeout recovery",
			highlights = "Resolve player selectors, manage aliases and waypoints, and discover command syntax. Buffered requests use a smaller default reply ceiling and remember successful timeout recovery.",
			sections = {
				{ category = "added", items = {
					"iy_players resolves IY selectors to live player names before targeting commands, with a bounded listing and complete structured results.",
					"iy_control manages native events, keybinds, aliases, waypoints, settings and repeat loops. Alias and waypoint inspection supports pagination; waypoint deletion and clearing default to the current place, with all_places=true to clear every place.",
					"gui_scale and logs_webhook settings use IY's native commands, with asynchronous dispatch and saving reported explicitly.",
					"iy_plugin_read and iy_plugin_write support custom plugins with shared globals, multiple commands, aliases, syntax checks, returned-table validation and live reloads.",
				} },
				{ category = "improved", items = {
					"Context-length refusals teach a persistent model window. The current turn compacts and retries once before provider fallback; repeated summaries retain earlier facts even if a later summary request fails.",
					"Message options now includes a colored Context breakdown with system/tools, messages, rolling summary, unused space, and the compaction threshold. Compaction notices show the token reduction.",
					"Delete individual saved facts from Settings > Skills > Memory. AgentRouter is now featured with its signup requirement highlighted and its required Claude Code identity always sent.",
					"The desktop profile control shows your Roblox headshot beside a clearer name and provider hierarchy. Its menu adds a matching identity header, a live provider summary, roomier actions and visible hover and open states, with an initial fallback while avatars load.",
					"iy_cmds includes native argument signatures and short descriptions alongside names, aliases and plugin origins, with a fallback for older IY versions.",
					"Buffered HTTP uses an 8,192-token default reply ceiling through agent.executorReplyCeiling, without changing agent.maxTokens. Configured WebSocket streams, the enabled web relay and explicit token overrides bypass this default; 0 disables it.",
					"Both provider adapters can recover after 20–130 seconds without a response by retrying a smaller reply and reducing reasoning effort when available. A valid completion saves the working ceiling for that provider and model.",
					"The agent favors targeted file_edit and file_edit_many changes to keep replies within executor request windows.",
					"check_luau accepts saved scripts by path, matching run_luau and saved-paste reads. Large scripts use small sequential writes and checks/runs by path to avoid sending source repeatedly.",
					"Main and subagent prompts require reading every enabled skill first in every new or resumed conversation. Skill bodies and inventories paginate, and restricted subagents gain skill reads without mutation tools.",
				} },
				{ category = "fixed", items = {
					"Alias and waypoint edits validate inputs, refresh IY's GUI and clear tables in place. Coordinate waypoints use validated, floored values instead of the buggy upstream command; deletion preserves other places' waypoints.",
					"Failed sockets use the safer ceiling on HTTP fallback. Cancellations and already-minimal requests skip recovery retries; malformed or empty replies do not teach a token cap.",
					"file_write and file_append reject content over 2 MiB per call before writing, preserving existing files.",
					"Interrupted write arguments cannot become partial edits or scripts. Token-limited tool batches run no calls and request smaller complete calls.",
					"Profile headshots resolve and preload with bounded retries and stay renderable while loading. Closing a view discards late results while its native requests finish on live coroutines.",
					"Managed script stopping uses cancellation flags instead of closing native coroutines, removing cancellation paths that can leave Roblox callbacks targeting dead threads. Self-cancellation, finished handles, long delays and later callbacks use the same guards; external engine waits retain an explicit limitation.",
					"Failed turns release their busy state and invalidate old tool contexts. A new main or subagent turn cannot revive a failed or stopped worker.",
					"The minimize/restore launcher preserves the grab offset, waits for a drag threshold and tracks one pointer without opening after a drag. Focus loss and rebuild clean up listeners; keyboard and viewport changes preserve preferred placement.",
					"Task markers and notification content align across text sizes and input modes. Task disclosure choices persist, long plans stay bounded, and skipped tasks do not count as completed.",
					"Notifications show conversation titles and Open chat actions, preserve other unread conversations, fit the viewport and stop the busy pulse when work finishes.",
				} },
			},
		},
		{
			version = "1.4.0",
			date = "September 19, 2026",
			title = "Batch tools and a refreshed public showcase",
			highlights = "Find and inspect together, read several files per call, and apply ordered edits in one write. The public website gains a responsive layout and a searchable catalog of the actual tools.",
			sections = {
				{ category = "added", items = {
					"instance_query combines name, class and tag filters with selected properties and attributes. instance_get_many inspects up to 20 known paths with individual failures.",
					"file_search searches literal text across workspace files and returns line numbers, byte offsets and a continuation cursor.",
					"file_read_many reads up to 12 files or saved pastes within a shared result budget. file_edit_many preflights up to 20 ordered edits before one write.",
				} },
				{ category = "improved", items = {
					"Instance searches walk incrementally and stop when a page fills, with cooperative cancellation and a bounded scan instead of collecting the entire subtree.",
					"Repeated file slices reuse a bounded cache within one batch. Search cursors resume directly at a byte offset without scanning earlier lines again.",
					"The agent is guided toward combined queries, selected fields, batch reads and exact edits to reduce unnecessary tool round trips.",
					"The public showcase has a responsive layout, real tool counts, a searchable tool catalog, copyable starter prompts, and accessible navigation and copy feedback.",
				} },
				{ category = "fixed", items = {
					"Instance names containing dots, brackets, quotes or surrounding whitespace have parsed, round-trippable paths. Character, camera and primary-part references resolve through known instance links.",
					"String property conversion preserves whitespace; scalar numeric conversion refuses nonfinite values. Batch arrays enforce their size limits before execution.",
					"Searches report incomplete inventories and unreadable files. Stopped edit batches report cancellation, stale files are preserved, and unchanged edits avoid writes.",
					"The website catalog is generated from the bundled registry, and a reproducible build keeps the root and docs publishing copies synchronized.",
				} },
			},
		},
		{
			version = "1.3.0",
			date = "September 19, 2026",
			title = "Reliable code execution and clearer tool workflows",
			highlights = "Cancellable Luau execution, syntax checks, exact file edits, resumable source reading, and a more dependable chat interface in Roblox and Cowork.",
			sections = {
				{ category = "added", items = {
					"check_luau validates source with the executor's compiler without running it.",
					"file_edit replaces exact text, rejects ambiguous or stale matches, and supports explicit replace-all and deletion.",
					"file_read and script_source provide contiguous UTF-8 slices with continuation offsets, including long saved pastes.",
				} },
				{ category = "improved", items = {
					"run_luau captures print/warn, readable tables, and multiple return values. Its configurable 1–60 second deadline includes tasks started with task.spawn/defer/delay.",
					"Cooperative loop checkpoints keep ordinary loops responsive; Stop, deadlines, and unload cancel managed execution and report cancellation limits honestly.",
					"Parallel tool results appear as each call finishes. Progress belongs to its own call, and the transcript distinguishes stopped, timed-out, and failed work.",
					"Exact edits display labelled Before and After code listings. Cowork adds multiline code inputs, typed parameter controls, inline validation, and copyable code and output.",
					"Cowork preserves reading position and newer drafts and attachments during sends; compact layouts and accessible control labels work down to 320px.",
				} },
				{ category = "fixed", items = {
					"Compile and runtime errors now fail the tool call. Loop guards and JSON repairs preserve quoted source, and incomplete string arguments are rejected.",
					"Explicitly cancelled Luau tasks stay cancelled after their parent succeeds, even on hosts without working native cancellation. Self-cancellation stops the current task immediately.",
					"Disabled groups and conversation tool restrictions are enforced again before execution, including calls waiting for approval.",
					"Failed and stopped turns return to Ready, including a Stop on the last allowed step. Child tool summaries and tool-only restored conversations remain visible.",
					"Filesystem errors no longer look like successful writes or empty listings; failed append reads preserve the file, and ambiguous Windows path segments are rejected.",
					"Cowork handles IME input and unavailable browser storage, retains empty replacement strings, and attaches asynchronously read files to their original conversation.",
					"Targeted source checks resolve dependencies against the full source tree and reject empty scan targets.",
				} },
			},
		},
		{
			version = "1.2.0",
			date = "September 19, 2026",
			title = "UI repair, Markdown tables, and managed chat loops",
			highlights = "A measured, compact chat interface with Markdown tables, a refined model picker, bounded thinking, and background quizzes and chat automation.",
			sections = {
				{ category = "added", items = {
					"Markdown tables: aligned headers and cells, escaped pipes and inline code, responsive columns, and scrollable wide or long tables without dropping content.",
					"Managed chat tools: quiz_bot hosts and scores quizzes, auto_chat rotates messages, and auto_reply handles keyword responses; chat_loop_status and chat_loop_stop expose progress and cancellation.",
					"Independent chat_bot: AI conversation in Roblox chat with its own memory, configurable personality and player scope, duplicate-safe replies, and shared status/stop controls.",
					"Chat loop status and Stop all controls, with per-conversation cleanup and automatic shutdown on unload.",
					"Prompt starters and per-conversation draft/attachment retention across navigation and UI rebuilds.",
				} },
				{ category = "improved", items = {
					"Compact composer with content-sized model chips, optional multiline input, and secondary controls in one menu. Message copy/reuse/quote action bars have been removed.",
					"Model picker: content-sized provider selector, stable search and model rows, clear selection, optional effort controls, and a single scroll owner on small screens.",
					"Thinking stays collapsed initially, renders readable inline formatting when expanded, and uses a bounded scroll area for long traces.",
					"Provider tabs size to their labels; settings, tool details, logs, subagent rows, and quick chat use more consistent spacing and preserve reading position.",
				} },
				{ category = "fixed", items = {
					"Modal headers and content no longer compete for flex height; footer space follows its visible actions and respects keyboard/safe-area bounds.",
					"Narrow menus, segmented controls, badges, key/value rows, and large-text layouts keep labels and touch targets inside their bounds.",
					"UI teardown releases subscriptions and stale animation callbacks; repeated layout changes no longer accumulate camera listeners or revive closed surfaces.",
					"Chat sending reports missing channels and rejected sends accurately. Loops honor stop, permission changes, channel selection, pacing, and session removal.",
					"Unicode response reveal avoids splitting emoji and CJK characters; structured replies render without repeated table/code layout jumps.",
				} },
			},
		},
		{
			version = "1.1.1",
			date = "September 2026",
			title = "OpenCode Zen workaround, compact composer and response polish",
			highlights = "OpenCode Zen free-tier workaround (big-pickle), 62px compact desktop composer bar, full clipboard config transfer, Claude asterisk brand styling and progressive response reveal.",
			sections = {
				{
					category = "added",
					items = {
						"OpenCode Zen free tier workaround: complete compatibility for free-tier models (including big-pickle) with canonical 30-character session and request IDs, global project scoping, enforced SSE streaming, and standard tool declarations.",
						"Config import and export: full clipboard configuration transfer under Settings -> Import & export, safely preserving and applying provider keys and settings.",
						"Progressive response reveal: smooth typewriter reveal on AI responses with terracotta accent cursor and adaptive reading cadence.",
						"Claude brand asterisk: assistant byline icon updated to the Claude orange asterisk in warm terracotta.",
					},
				},
				{
					category = "improved",
					items = {
						"Desktop composer bar: compact 62px height without permanent bottom rows for a clean, spacious transcript layout.",
						"Transparent icon styling: removed backgrounds behind assistant, thinking, tool, and subagent icons across all conversation message types.",
						"Blockquote styling: markdown quotes rendered as sleek callout cards with warm terracotta left accent border.",
						"Build reload safety: new script executions cleanly replace older idle client instances without duplicate mounting or orphaned threads.",
					},
				},
				{
					category = "fixed",
					items = {
						"OpenCode Zen FreeTierError 403: resolved Console edge restrictions for free models by matching official CLI session formatting and stream requirements.",
						"Headless test harness compatibility: instant DOM reveal in offline harness tests to guarantee synchronous regression assertions.",
					},
				},
			},
		},
		{
			version = "1.1.0",
			date = "September 2026",
			title = "Infinite Yield, key pools and skills",
			highlights = "Infinite Yield as an internal command engine with a hidden mode, "
				.. "multi-key rotation for providers, the community plugin store, and "
				.. "markdown skills the agent reads on demand.",
			sections = {
				{
					category = "added",
					items = {
						"Infinite Yield engine: the agent runs any IY command (fly, noclip, esp, tp, "
						.. "600+ more) through iy_cmd, with the command list searchable via iy_cmds.",
						"Hidden mode: IY loads with its interface parked -- every command and loop "
						.. "alive, nothing on screen. With GUI mode loads it untouched.",
						"CaptureService guard: screenshots no longer pop a hidden IY back on screen.",
						"Multi-key pools: paste several API keys, one per line, and a rate-limited "
						.. "key is benched and the next one tried with no delay -- 429s stop costing turns.",
						"Community plugin store: the agent searches iyplugins.pages.dev (560+ "
						.. "plugins), installs and loads one on request -- 'install dexrecontinued'.",
						"Markdown skills: .md playbooks under skills/ with Claude Code frontmatter. "
						.. "The prompt carries names and descriptions only; the body is fetched by a "
						.. "tool call when a task matches.",
						"Skills from GitHub: owner/repo or a URL installs a playbook into skills/.",
						"Changelog: What's New, from the app menu and About.",
					},
				},
				{
					category = "improved",
					items = {
						"Lazy IY loading: nothing is fetched at boot; the first iy_cmd call brings "
						.. "the engine up.",
						"System prompt awareness: the model is told each turn whether IY is loaded "
						.. "and how, and which skills exist.",
						"Ambient detection: an IY the user started themselves is latched onto and "
						.. "left alone -- its GUI, its settings.",
						"The settings toggle for IY applies to a loaded engine immediately.",
						"Key pool state is per-session, not persisted -- a stale index cannot "
						.. "start a rotation from the wrong key.",
					},
				},
				{
					category = "fixed",
					items = {
						"Ambient fallbacks for prefix and PARENT on executors without setfenv.",
						"File workspace split: agent files under files/, pastes under pastes/, "
						.. "with a first-run migration that shows its progress.",
						"Paste overflow: a long pasted message lands in a file and is referenced, "
						.. "not dropped.",
					},
				},
			},
		},
		{
			version = "1.0.9",
			date = "September 2026",
			title = "Asking, standing instructions and the workspace",
			highlights = "ask_user, custom instructions, the file workspace split, and prompt hardening.",
			sections = {
				{
					category = "added",
					items = {
						"ask_user: the agent can ask the person a question and wait, with a "
						.. "panel behind it that answers the running turn.",
						"Custom instructions: standing instructions appended to the system prompt "
						.. "after the built-in rules, so they win on conflict. Subagents inherit them.",
						"Copy system prompt: the assembled prompt, as the next request will carry it.",
					},
				},
				{
					category = "improved",
					items = {
						"Prompt hardening: quoting rules, anti-fabrication wording, and a style "
						.. "contract that prizes short answers.",
						"Ask sweeps: a question left unanswered is collected rather than parked "
						.. "forever.",
					},
				},
				{
					category = "fixed",
					items = {
						"Prompt-injection hardening around pasted content.",
					},
				},
			},
		},
		{
			version = "1.0.8",
			date = "September 2026",
			title = "The executor wall and provider polish",
			highlights = "Request timeouts, the smaller-ask retry at the executor wall, and provider setup with links.",
			sections = {
				{
					category = "added",
					items = {
						"Request timeout setting, defaulting to a day -- the one deadline nothing "
						.. "else can rescue, high enough for a reasoning model that thinks before "
						.. "its first byte.",
						"Smaller-ask retry: a request that dies at the executor's 60s transport "
						.. "wall is retried once with less thinking and half the reply ceiling, "
						.. "so the model finishes inside the wall instead of at it.",
					},
				},
				{
					category = "improved",
					items = {
						"Adding an inference provider links out to where each vendor issues keys.",
						"Notifications when minimized: a finished or failed turn toasts even with "
						.. "the window closed, alongside the launcher badge.",
						"OpenRouter attribution headers on the requests that go there.",
					},
				},
				{
					category = "fixed",
					items = {
						"Adding an inference provider on mobile.",
						"Randomly vanishing modals: the dismiss layer sits behind an Active card.",
						"Modal scroll stutter: stable top/bottom layout instead of UIFlexItem.",
					},
				},
			},
		},
		{
			version = "1.0.7",
			date = "September 2026",
			title = "Web bridge and the landing page",
			highlights = "The local web bridge revamp, OpenRouter app attribution, and a public face.",
			sections = {
				{
					category = "added",
					items = {
						"Landing page and showcase assets.",
						"OpenRouter app attribution: rankings and stats credit ProjectUAI.",
					},
				},
				{
					category = "improved",
					items = {
						"Bridge UI revamp and popup placement fixes; the login gate restored.",
						"Bridge token regenerated on every server start, so a stale one in config "
						.. "grants nothing.",
					},
				},
			},
		},
		{
			version = "1.0.6",
			date = "September 2026",
			title = "Chat, input and mobile",
			highlights = "In-game chat tools, virtual input, and a mobile panel that can actually be moved.",
			sections = {
				{
					category = "added",
					items = {
						"In-game chat tools: the agent reads recent chat and sends as the local player.",
						"Virtual input: key presses and mouse actions from a tool call.",
					},
				},
				{
					category = "fixed",
					items = {
						"Mobile panel dragging, resizing and the hamburger menu.",
						"Adding an inference provider on mobile.",
						"CanvasGroup blur in the transcript.",
					},
				},
			},
		},
		{
			version = "1.0.5",
			date = "September 2026",
			title = "Delegation that finishes",
			highlights = "Unbounded subagents, follow-up questions, and the model picker.",
			sections = {
				{
					category = "added",
					items = {
						"Unlimited subagents: a delegated job can run with no step limit, "
						.. "bounded still by Stop and its own timeouts.",
						"Subagent follow-ups: a dispatched agent keeps what it found and answers "
						.. "another question in the same conversation.",
						"Model picker in the header.",
					},
				},
				{
					category = "improved",
					items = {
						"Tool-call rows are grouped under one card; code blocks get air.",
						"Subagent reports are kept and shown, not summarised away.",
					},
				},
			},
		},
		{
			version = "1.0.4",
			date = "September 2026",
			title = "The interface revamp",
			highlights = "The modern interface: sidebar, panels, icons, and the responsive layouts.",
			sections = {
				{
					category = "added",
					items = {
						"Sidebar navigation and the panel system behind it.",
						"Icon set, drawn rather than assembled from emoji.",
						"Window and panel layouts that follow the viewport: window, panel, sheet.",
					},
				},
				{
					category = "fixed",
					items = {
						"Mobile support: touch targets, dragging, and the layout switch.",
						"Modal overlap with the menu.",
					},
				},
			},
		},
		{
			version = "1.0.3",
			date = "September 2026",
			title = "Open, embeddable, licensed",
			highlights = "MIT license, a working unload, and the Gemini provider.",
			sections = {
				{
					category = "added",
					items = {
						"MIT license.",
						"Working unload: every timer, input handler and thread is drained, config "
						.. "saved, interface removed. No half-loaded clients left behind.",
						"Gemini as a provider.",
					},
				},
				{
					category = "improved",
					items = {
						"Subagent visibility: work in progress is shown, reports are kept.",
					},
				},
				{
					category = "fixed",
					items = {
						"Deadline retry: a request that timed out is no longer re-sent to the "
						.. "same wall -- the sequence ends and says why.",
					},
				},
			},
		},
		{
			version = "1.0.2",
			date = "September 2026",
			title = "The Messages API and quick chat",
			highlights = "The Anthropic Messages API as a second protocol, quick chat, and type modernisation.",
			sections = {
				{
					category = "added",
					items = {
						"Anthropic Messages API: a record picks its wire protocol; tool calls are "
						.. "normalised between the two shapes automatically.",
						"Quick chat: a key opens a small composer without the full window.",
					},
				},
				{
					category = "improved",
					items = {
						"Retry on transient failures with a backoff curve; the type was "
						.. "modernised and the dropdown unburied.",
					},
				},
				{
					category = "fixed",
					items = {
						"Menu overlap with other surfaces.",
						"Flex width reserves replaced with real flex, and edges made visible.",
					},
				},
			},
		},
		{
			version = "1.0.1",
			date = "September 2026",
			title = "Making a turn visible",
			highlights = "The transcript shows work as it happens, and the schemas stop guessing.",
			sections = {
				{
					category = "fixed",
					items = {
						"A running turn is visible: tool rows stream in as they execute.",
						"The rebuild thrash that remounted the transcript on every update.",
						"Tool schemas: parameters validate before dispatch, so a malformed call "
						.. "is repaired or reported rather than raising.",
						"Collapsed labels and the header rule that ate the title bar.",
					},
				},
			},
		},
		{
			version = "1.0.0",
			date = "September 2026",
			title = "Initial release",
			highlights = "The universal AI agent copilot for Roblox executors: no game, no gateway, no host assumed.",
			sections = {
				{
					category = "added",
					items = {
						"The agent loop: a turn that plans, calls tools and reports, with token "
						.. "budgets and compaction.",
						"Subagents: fresh-context dispatch, parallel execution, and reports "
						.. "collected by the parent.",
						"The permission engine: read, write and danger risks, per-tool rules, "
						.. "and an interactive prompt that can be remembered.",
						"Native tool groups: instance tree, properties, remotes, virtual input, "
						.. "screen and aiming, world, chat, memory, files, HTTP and web search.",
						"Providers: OpenAI-compatible chat completions, with presets for a dozen "
						.. "endpoints and manual configuration for any other.",
						"Sessions: saved, resumable, searchable, grouped by place.",
						"The bridge: a local Node.js server relaying the conversation to a "
						.. "browser companion, with SSE and a token handshake.",
						"The loader: one loadstring, one file, no dependencies.",
					},
				},
			},
		},
	}

	-- Named sections keep their headings; other sections use shared category labels.
	local LABELS = { added = "New", improved = "Improved", fixed = "Fixed" }

	-- Newest first, as shipped above. Sorted rather than trusted so an edit in
	-- the middle cannot silently reorder the modal.
	M.ENTRIES = ENTRIES

	function M.all()
		local out = {}
		for _, entry in ipairs(ENTRIES) do
			local sections = {}
			for _, category in ipairs(CATEGORY_ORDER) do
				for _, section in ipairs(entry.sections or {}) do
					if section.category == category then
						sections[#sections + 1] = {
							category = category,
							label = section.label or LABELS[category] or category,
							items = section.items or {},
						}
					end
				end
			end
			-- A category not in the order list keeps its place, labelled as written.
			for _, section in ipairs(entry.sections or {}) do
				local known = false
				for _, category in ipairs(CATEGORY_ORDER) do
					if section.category == category then known = true end
				end
				if not known then
					sections[#sections + 1] = {
						category = section.category,
						label = section.label or LABELS[section.category] or section.category,
						items = section.items or {},
					}
				end
			end
			out[#out + 1] = {
				version = entry.version,
				revision = entry.revision,
				date = entry.date,
				title = entry.title,
				highlights = entry.highlights,
				sections = sections,
			}
		end
		table.sort(out, function(a, b) return a.version > b.version end)
		return out
	end

	function M.latest()
		return M.all()[1]
	end

	function M.isUnread()
		local latest = M.latest()
		if not latest then return false end
		if config.get("ui.lastSeenVersion", "0.0.0") ~= latest.version then return true end
		return latest.revision ~= nil and config.get("ui.lastSeenChangelog", "") ~= latest.version .. ":" .. latest.revision
	end

	function M.markRead()
		local latest = M.latest()
		if not latest then return false end
		config.set("ui.lastSeenVersion", latest.version)
		config.set("ui.lastSeenChangelog", latest.version .. ":" .. (latest.revision or ""))
		return true
	end

	return M
end
