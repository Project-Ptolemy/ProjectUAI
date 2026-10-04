# Native client features and limits

Current native feature contract for **2.6.0**, October 4, 2026.
Internal APIs are described in
[SPEC.md](../SPEC.md); verification and native-device scenarios are in
[CODE_WORKSPACE_TESTING.md](CODE_WORKSPACE_TESTING.md).

In-game release notes are under **App menu → What's new**, also available from
**About → What's new**. Reload the updated native bundle to see the latest notes.
Revised notes restore the unread marker even when the client version stays the same.

Modals, Settings and Quick Chat enter and exit with short opacity transitions at
their final dimensions. They do not scale their text or reflow controls during
the animation. Reduced motion applies the final state immediately. Form labels,
inputs and help text stay grouped, with compact headers and consistent section
spacing; description-only confirmations reserve no empty content band.
Modal fitting coalesces layout signals across frames, skips unchanged dimensions
and releases pending work on close. The sidebar profile keeps its name and
provider lines together.

Subagent **Details** is a live monitor with the current step, provider/model,
tool progress and results, latest delivered text and reasoning, elapsed time,
final report and Stop. Existing cards update in place at most ten times per
second; hidden register views suspend drawing. Activity and message previews
are bounded. Streaming output appears when delivered; buffered connections
cannot show text before their response arrives.

`dispatch_agent` and `agent_followup` start background work by default and return
an ID immediately. The main agent continues independent work, checks
`agent_status` periodically, and reads the child's report before its final
answer. Status checks support bounded waits and paginated reports; explicit
`background=false` retains blocking dispatch. Stop and terminal parent exits
stop unfinished descendants, including queued work. Background admissions and
uncollected reports are bounded.

The optional Discord invitation waits for five minutes of use and at least 30
seconds without input. It appears only in visible idle Chat/Home, with no active
request, unsent draft, focused field, keyboard, other dialog or scrolled-back chat.
It appears at most once per client load and once per 14 days, with the cooldown
saved in configuration. **Not now** keeps that cooldown. **Don't show again** and
a successful **Copy invite** disable reminders; **Join Discord** in the menu
still opens the invitation. UI-free SDK clients never schedule the modal.

## Script UI library

The independent [UI LIB](UI_LIBRARY.md) is now v1.3.0. Agents declare script
controls and callbacks through its bundled reference. The library owns layout,
input, configuration, cleanup, and the fixed `Project UAI | UI LIB.` footer.
Navigation, action labels, and disclosure/selection states use text; the
frame-drawn brand mark and minimize/close/resize glyphs remain. The sidebar
profile supplies a Roblox headshot, display name, username, and game. Transitions
are owned and reversible, respect reduced motion, and settle during cleanup.
The agent client remains its own application.

## Chat viewport

**New conversation** lets you choose the current game, **Universal**, or a custom
folder and optionally name the chat. **Move to folder** is in each conversation's
actions. **Conversation folders** creates and renames custom folders; removing a
folder moves its chats to Universal and keeps their messages. Folders organize
history without changing game context or conversation tool permissions. Older
conversations retain their original game grouping.

Mobile uses the desktop interface at 55% of its native layout dimensions, spacing
and radii before density settings, with a 15px control minimum. Text starts at
10px minimum before text scaling, and standard icons at 12px, keeping their
strokes visible within the compact layout. Auto keeps the compact placement;
Sheet, Panel and Window select bottom, right and centred placement and retain
separate saved positions without replacing live fields. The header, sidebar,
welcome view, composer, Quick Chat and Code tabs share their desktop structure.
The normal sidebar collapse control, app menu and conversation search remain.
Settings categories and providers reflow between columns and scrolling strips.
Menus remain anchored to their controls and scroll within the available space.

Ordinary mobile typing stays compact in both orientations; explicit expansion
opens the longer draft editor. Mobile Return adds a newline in Chat and Quick
Chat. Rotation keeps the native fields, selections and drafts mounted. When a
landscape keyboard leaves too little space, form actions join the scrollable
body; dismissing it restores the pinned actions. Focused fields account for the
keyboard edge and clipping ancestors without repeating nested scroll movement.

Code, tables and reasoning resize their nested scroll areas above the keyboard.
Source metadata yields to Copy in narrow headers. Vertical swipes over settings
sliders scroll without changing values. Settings categories preserve their
mounted drafts and individual scroll positions when revisited.
When a Code surface is too short, the original arrangement scrolls as a whole.

Conversation history stays in the session while the view uses measured spacers
for offscreen messages and mounts nearby Markdown chunks. Recently read chunks
stay warm within a bounded nearby cache, so short backtracking reuses the same
renderers. Visible text is built before prefetch, and ordinary scrolling reuses
the layout index. Long lists split into small drawing batches; code and tables
retain their existing bounded previews.
At most four chunks are built in a scheduled slice, with an approximately 6 ms
cooperative budget between builds. This is not a hard limit on a single engine
layout or Markdown operation. Small upward scrolls immediately stop following.
Reflow anchors the visible chunk within a long reply; the Latest control reports
new replies received below the reader. Minimize and native tab navigation suspend
drawing while keeping the bounded text cache, live preview and expanded sections
ready. Returning immediately reveals the same renderers and queues only unseen
events; unchanged history takes no replay slices. Clear, conversation switches and
destruction still release old content. Retention limits and the composer draft
are unchanged.

Tool work appears in compact Activity summaries with counts and status. Open a
summary to inspect its calls, then open a call for its inputs and output. Hidden
details are built on demand. Opening an activity keeps its header in view, and
new results leave chosen sections open or closed. Delegated tasks have a distinct
goal, status and report with a separate folded activity feed. Completed outcomes
retain their original rows when returning from another panel.

The desktop sidebar rounds its own outer left corners to match the window;
its inner divider stays straight. The window remains a plain Frame.

## Request and application diagnostics

Successful HTTP responses keep an empty transport-error field. HTTP refusals and
actual transport failures remain distinct. Select a request or application log
entry to inspect its recorded details in a popup and copy the redacted evidence.
Request details include status, timing, transport and available server/trace
metadata. Opening a log never repeats its request.

The browser batches snapshot layout, preserves reading position, and defers
live preview painting while its document is hidden. Native
Roblox performance and input need live-client validation.

## Explorer

Explorer browses accessible hierarchy, supported properties, typed attributes and
tags. Lazy pages, literal/Lua-pattern search, class/tag/subtree filters, breadcrumbs,
reveal, copy path/ID, bookmarks and picking use stable runtime-scoped object IDs.
Selected IDs, primary, anchor, focus, clicked object, revision, epoch and selection
mode are distinct. Replace/add/remove/clear/range selection reconcile destroyed
objects and external updates. Inspector hierarchy actions validate the displayed
selection and expected parents before writing. A stale Inspector cannot silently
retarget a different object. Field drafts retain conflicts instead of overwriting.

Runtime services own branch/query cursors and merge returned pages. Cancelled or
superseded queries cannot publish completion. The UI shows filter chips, retry/error
states and partial/truncated/unreadable counts. Unknown totals stay unknown.
Visible Select mode and menus provide touch/gamepad alternatives to modifier keys.
Actual navigation, focus and hit targets still require native-device verification.

## Code and source

Documents, revisions, source history, proposals and saved actions are shared by UI
and tools. The native TextBox owns input/IME; escaped syntax overlays supply color,
caret, multiline selection and match highlights. Unchanged shifted lines reuse
syntax spans and widths. Long lines use chunked measurement and horizontal windows.
Syntax checks are coalesced/cancellable. Typing emits small revision events; delayed
autosave, rather than every keystroke, serializes the workspace.
Unvirtualized Markdown blocks above 32,000 bytes and unknown languages use escaped
plain text; the editor/reader keep their bounded syntax windows.

Find offers current/total matches, case sensitivity and whole-word matching.
Offsets are **one-based UTF-8 byte positions with exclusive ends**. Status columns
count Unicode code points. Case folding is ASCII; whole-word boundaries treat
ASCII letters/digits/underscore and non-ASCII bytes as word constituents. There is
no Unicode linguistic case folding, grapheme clustering or UTF-16 coordinate API.
Full-snapshot search finds matches across large-reader page boundaries. Native text
layout can still differ for combining characters, bidi, tabs and host fonts.

Source inspection uses one service for host-readable Source, decompiled text,
captured/generated source and file snapshots; authored documents expose the same
provenance model. Results identify the object/path, epoch, method, status, byte
count, hash, capture time and diagnostics. Empty source is successful. Unsupported
objects, unavailable source/decompiler, decompiler failure, invalid/oversized text,
stale requests and expired snapshots are distinct errors. Content hashes identify
snapshots, not authenticity or trust.

Only explicit requests can decompile. Requests deduplicate by object, method and
generation; refresh/cancellation/runtime changes discard stale results. Visible
editors/readers pin snapshots and release them when hidden or destroyed. Host
Source and decompiled documents remain read-only, including after restoration from
disk. Extract a selection or whole document into a separate editable script before
editing, running, proposing changes or saving an action. Opening/extracting never
runs source. There is no live write-back, server-source guarantee or automatic
execution of decompiled text. Expiry offers refresh/reopen recovery; persisted
read-only text can be extracted without recovering the old runtime handle.
Source refreshes and caller-source requests cannot reclaim navigation after their
view is hidden, replaced or destroyed.

Two verified workspace files protect autosave. Maximum-size editable documents
fit the ordinary write path. Interrupted writes retain drafts and release the save
lock; Retry can repair this runtime's partial write or verify a successful write
whose readback was interrupted. Temporarily unreadable files require Retry.
External changes produce
Conflict. Corrupt supported snapshots are preserved before replacement; unreadable
or future formats remain protected. Source Undo/Redo, revision-guarded proposals
and Game changes are separate histories. States include Saving, Saved, Retry
required, Conflict and Expired source snapshot. Compact layouts use one active
destination, scrolling action strips, visible overflow and scoped shortcuts; safe
areas, keyboard obstruction and reduced motion follow the shared native UI.
Editor and Library deletion require a current confirmation; edits made after that review
invalidate it. A retained run snapshot can dispatch only once, and read-only
protection is rechecked at dispatch.

## Conversation context

Provider connections implement Chat Completions and Anthropic Messages. The
[provider contract](PROVIDER_COMPATIBILITY.md) documents endpoint/auth handling,
the local-server matrix and offline protocol fixtures. Ordinary local servers use
HTTP. Native WebSockets require a separate gateway implementing UAI's envelope,
receive the same auth/identity headers as HTTP, and open once per completion.
Their full provider path/query is preserved; only failures before `Send` can fall
back to HTTP. Messages does not use this socket protocol. Socket and HTTP limits
remain in effect regardless of the output-token setting.

Requests use the configured output budget and provider/model limits. The old
8,192-token executor ceiling is removed from both adapters and native HTTP
fallback; an old saved `agent.executorReplyCeiling` has no effect. Output-limit
finishes are visible even when all generated text was reasoning. The horizontal
provider list centers its Add control and returns to top alignment in column mode.

Buffered HTTP cannot expose a response before the host returns it. Received replies
render immediately without simulated typing. The agent prompt requests brief
progress messages between work steps; it cannot force a provider to yield text
during its internal reasoning. When the configured native socket transport really
delivers chunks, text and reasoning previews update in place, survive reopening
the transcript, and reconcile to one final message. Previews are bounded to 64 KiB
per text/reasoning channel and coalesce at 100 ms; the full final response replaces
them. Cancelled, failed and completed requests cannot publish late previews.
Reply labels retain the model reported by the provider, including when it differs
from the requested model; missing model metadata falls back to the dispatched model.

The composer and context inspector use the same pressure calculation as automatic
compaction: messages, rolling summary, and system prompt/tool-schema overhead.
Prepared requests supply an initial overhead estimate before a provider reply.
Provider token usage calibrates against the history sent, scoped to provider ID,
endpoint and model. Prompt/schema changes adjust that estimate; switching providers
does not carry over the prior provider's calibration. Before any request is
prepared, totals are explicitly partial. The inspector shows its model/window,
compaction point, unused space and any over-limit amount. Counts remain estimates,
and visible category totals sum to the displayed pressure. Updates coalesce to
100 ms and subscriptions end when the inspector closes or its conversation is
removed.

## Remote Spy

Capture begins only with explicit Start. The UI defaults to selected-remote scope
and 30 seconds; no selection means Start stays idle. Game-wide/selected-subtree
scopes and continuous lifetime are explicit. The shared resolver uses the displayed
Explorer snapshot, with primary as the selected-remote/subtree target. Exact remote
targets remain independent of unrelated selection changes.

Passive incoming events, outgoing hook installation, admission filters, traffic
suppression, local function errors, replay and script generation are distinct
actions. Incoming function callbacks are unsupported. Outgoing attribution is
`hooked_unknown` unless verified. Detached routing probes do not invoke the
predecessor, but network behavior depends on the host. Stop removes owned behavior
and reports an inert forwarding wrapper when one must remain. Permission, group,
session and runtime revocation invalidate agent-owned behavior promptly. Failed
reconfiguration clearly reports that the previous capture was stopped.

Incoming records provide diagnostics, caller inspection/source/Explorer navigation
and metadata export. Outgoing records additionally provide argument editing,
review, generated scripts and one-shot replay. Caller identity is captured with
the record; resolution and decompilation run after capture, outside hooks. Caller
source opens read-only and highlights bounded remote name/path text matches. These
are likely sites, not proof of which call executed. Dynamic aliases may have no
match. Export carries capture and source provenance together.

Portable scripts preserve supported typed values and exact nil arity, use ordinary
Luau path resolution and do not depend on the UAI runtime. Copy/export requires a
current reviewed digest and revalidates target paths. Bound scripts expire with
their runtime bindings. Replay validates target/rules/record revision and consumes
its plan once. A dispatched timeout is outstanding, never retried automatically.
No client action can roll back remote server effects.

Capture states and following/paused views remain visible. Late outcomes update
byte accounting even for pinned records. Stop invalidates pending completion
acceptance. Export freezes record content and sequence boundaries before paging;
later traffic cannot enter the snapshot. Split files receive a completion manifest
only after verified writes. Offline imports are inert and require explicit rebind
and fresh replay review.

## Named resource budgets

| Resource | Bound |
| --- | --- |
| Documents / open views | 24 / 10 |
| Editable source / inspected source | 256,000 bytes / 2 MiB |
| Source versions / aggregate history / workspace envelope | 12 per document / 4 MiB / 12 MiB |
| Saved actions / proposals | 24 / 3 per document |
| Source cache / TTL | 8 snapshots, 8 MiB / 5 minutes when unpinned |
| Source workers / waiter deadline / display page | 4 / 15 seconds / 6,000 bytes |
| Editor rows / measurement chunks / search matches | 160 / 2 KiB / 10,000 retained |
| Explorer branches / query snapshots / matches per query | 64 / 8 / 1,000 |
| Branch children / scan visits / displayed rows / reveal depth | 20,000 / 20,000 / 4,000 / 64 |
| Selection / edit batch | 20 objects / 100 operations |
| Capture ring / pending outcomes / incoming subscriptions | 1,000 records within 4 MiB / 128 / 2,048 |
| Capture pins / frozen page | 10 within 1 MiB / 100 records |
| Typed graph / string / depth / values | 32 KiB / 16 KiB / 12 / 1,024 |
| Export part / replay and review lifetime | 2 MiB / 5 minutes |
| Native HTTP workers / body / request wall | 8 / 8 MiB / at most 300 seconds including retries |
| Native socket workers and connections | 4 each |
| Stream frame / chunks / tool calls / arguments | 1 MiB / 200,000 / 64 / 256,000 bytes per call |
| Restored conversations / idle persisted retention target / running workers | 64 / 64 / 8 |
| Subagent running workers / queue ceiling | Configurable 1–12 / 45 seconds |
| Transcript dialogue / worker summaries / detailed activity | 512 within 1 MiB / 128 within 256 KiB / 256 within 256 KiB |
| Transcript field target / replay slice | 24,000 bytes / 12 events or approximately 6 ms |
| Live text/reasoning preview / refresh | 64 KiB each / 100 ms, first chunk immediate |

These bound application work and retention, not engine allocations. GetChildren,
getnilinstances, TextBox updates and executor calls can still allocate or block
inside the host. Uncancellable host work continues to consume worker capacity
until it returns; its abandoned result is ignored. Text splitting remains linear
in the bounded document size. No hard real-time responsiveness is claimed.
The 64-thread memory target evicts only idle, successfully persisted conversations;
busy, preparing, ephemeral and unsaved/no-filesystem threads are preserved and can
exceed it. A hard resident-thread bound without losing unsaved conversations is
unsupported. Restore selects the newest 64 saved conversations by activity, keeps
older files on disk, and scans metadata from the host's full directory listing.
It does not expose an archive browser for those older files.

## Lifecycle and verification limits

Disposal continues after individual errors, disconnects listeners and invalidates
late callbacks. Signals bound recursive dispatch and release cleared callbacks.
Sessions bound durable logs and resident workers. Turn boundaries are retained;
progress/status and detailed tool events cannot spend the dialogue budget. Saved
transcripts use the same retention policy; call/result pairs and worker summaries
stay together. Limits/recovery are disclosed. Legacy files can recover dialogue
still in saved context, but cannot recover text absent from both stores.

Live transcript rows and nested code rows are released with expired activity.
Replay subscribes before rendering, queues new events, and cancels on switch,
clear and destruction. Maximize keeps the existing view mounted; all devices use a
plain window Frame. **Message options → Refresh conversation** redraws a busy chat
without changing its work or draft. Reading position and follow preference survive
refresh and layout rebuilds. Native texture/layout behavior still needs client testing.

Old/removed-session tool callbacks cannot
publish. Idle Stop invalidates old contexts while allowing fresh manual work;
clearing/removing a conversation cancels only its own child agents and clearing
starts a fresh context. Subagent follow-ups clear old stop state, register as queued
before waiting, reject duplicate dispatch and remain cancellable while queued.
Stopped or failed workers clear their pending Stop label on completion.
The concurrency setting is honored up to its displayed maximum of 12. Unlimited
subagents have no execution budget; their queue still has a 45-second ceiling.
Limited runs also charge queue time against their own budget.
Native HTTP and sockets
enforce deadlines, response limits, protected
retry callbacks and terminal malformed-stream errors. Timeouts/unknown outcomes
cannot trigger adaptive retries or provider fallback. Diagnostic errors are bounded
and redacted; raw decompiler/hook failures are omitted. File paths reject traversal,
control characters, trailing spaces/dots and reserved device names.

Automated evidence comes from synthetic Roblox fixtures, deterministic work/count
contracts and the official Luau compiler. Strict Roblox/executor type analysis is
unsupported without matching type definitions. Native renderer, IME, controller,
screen reader, font measurement, host hook coexistence, permission propagation and
server effects are not proven by these checks. Full-map export, hidden property
forcing, general game Undo and preemption of arbitrary native calls are unsupported.

Before publishing, run the isolated native-device scenarios in the testing guide,
record capabilities/device/input mode and check hook forwarding with an owned test
remote. Any implementation correction requires the complete native sequence again.
