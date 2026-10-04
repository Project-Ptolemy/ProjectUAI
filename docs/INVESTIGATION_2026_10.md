# Context, workspaces, tool efficiency, and UI investigation

This pass traced source behavior and exercised focused offline regressions. No
production user session traces were supplied, so it does not claim measured
end-to-end Roblox or provider latency improvements.

## Findings and changes

| Area | Actual finding | Change |
| --- | --- | --- |
| Compaction | Rolling summaries already replaced history on subsequent requests. Whole-user-turn removal could not compact a long single-task tool loop; an emergency path silently cut tool results to 400 bytes instead. | Fold older complete assistant/tool exchanges while retaining the current user request and recent full evidence. Keep tool/result pairing and signed recent reasoning intact. |
| Summary quality | The summarizer saw tool names without arguments, only the first 700 bytes of each message, and no retained active-task context. History was removed before the summary returned. | Supply bounded arguments, paths, result excerpts, cursors, earlier summary, and active request. Commit only after cancellation and reduction checks. Manual failure preserves history and reports its reason. |
| Repeated compaction | Summary output was not bounded, failure notices accumulated, and no space was reserved for the replacement summary. | Bound summaries to 4 KiB and input to 48 KiB or less for small models; reserve summary space and target 75% of the remaining history budget. Automatic failure/disabled summarization uses labelled bounded excerpts. |
| Context pressure | Existing system/schema accounting and provider calibration worked, but historical tokenizer error remained fixed overhead after history shrank. Table-form tool arguments were not counted. | Retire the historical correction proportionally after compaction and count encoded table arguments. Keep the same inspector calculation. Tokens remain estimates. |
| Reply budgets | Configured output could exceed the space remaining beside the prompt; raw provider settings could override a calculated ceiling. | Apply a temporary known-window allowance with margin, enforce it after adapter overrides, retain smaller output limits, and give a smaller fallback one compaction opportunity. No temporary allowance becomes a saved provider limit. |
| Workspace recursion | Reads/search stripped `files/` or `UAI/files/`; several mutations and listings reapplied the same prefix. Prompt and write results encouraged reusing these incompatible paths. | All existing file tools accept and return the same canonical `files/...` namespace. Strip its prefix once and preserve actual nested directories. |
| Game names | Folder construction/sanitization was model guidance, not a deterministic runtime conversion. Prompt construction also called product-info on every step despite an existing place cache. | Supply an exact game path from `runtime/workspace` and cached place metadata on every main/subagent request, including after compaction. Persist selection by PlaceId and reuse existing game folders. |
| Unicode | The model could invent different names or invalid paths for emoji, accents, CJK, symbols, or long names. | Preserve valid Unicode, use host NFC when available, remove forbidden/control characters, bound new name labels to 72 UTF-8 bytes, handle Windows device names including superscript digits, and suffix PlaceId. Keep display names separate. |
| Existing recursion and migration | Existing repeated `files/` directories needed safe access. Legacy migration could delete originals after failed or conflicting copies, or mistake a shallow/incomplete directory listing for emptiness. | Discover bounded legacy game locations without flattening or merging. Verify destination bytes before deleting sources; preserve conflicting originals and incompletely listed directories. |
| File round trips | `file_list` stopped at 60 entries without continuation. `file_read_many` defaulted to 1,000-byte slices even when the result budget had room; path aliases missed its existing per-call cache. | Paginate listings within the result budget; allow 6,000-byte default slices shared fairly across a batch; reuse one native read for equivalent paths within that batch. |
| Repeated investigation | Consecutive identical-batch detection compared raw JSON, so whitespace/key order could evade it. Broad exploration was encouraged by manually constructed paths and lost evidence. | Canonicalize non-ambiguous JSON signatures, supply stable paths, and guide both agents from named targets through scoped queries and bulk slices. Internal delegation reminders no longer replace the real task during compaction or persistence. |
| Player interface | The existing profile menu already led to What's New and About. | Add a separate ProjectUAI support entry using the same modal/components. Star us on GitHub opens the real repository, with clipboard/selectable-link fallback. No automatic star, unsolicited popup, or duplicate changelog. |
| UI library | Complete Dark/Light palettes, live token bindings, and `SetTheme` already existed. | Retain that architecture; add a built-in text switch, `GetTheme`, `ToggleTheme`, profile persistence, and linear-sRGB custom-accent foreground contrast. Existing controls, overlays, drafts, and layout remain mounted. |

## Representative workflows

- A write to `files/Game (77)/main.lua`, followed by append, exact edits, read,
  list, search, and delete, now reuses the same path without another `files/`.
  `files/files/...` remains a distinct, explicitly addressable legacy location.
- A synthetic long request with ten file-reading exchanges now reduces the next
  wire-context estimate by more than 25%, preserves its original task and newest
  evidence, and does not immediately invoke summarization again.
- Twenty repeated compactions, including unavailable or oversized summaries,
  remain bounded and retain the tested prior constraint. Summaries are not exact
  source snapshots: editing still requires reading the necessary original slice.
- Two 1,500-byte sources fit one default bulk read at a 6,000-byte result cap;
  three slices using relative, canonical, and old physical aliases use one host
  read within the batch. All 75 listing entries remain reachable at a 600-byte cap.
- Rebuilding main and child prompts repeatedly makes no product-info calls.
  Game analysis is not a required initialization step. Existing instance queries
  can already stop after inspecting one node in a 3,000-node subtree.

## Deliberate non-changes and limits

No new tool names were added. `file_search` already had literal matching, globs,
bounded scanning, UTF-8 snippets, byte offsets, and continuation cursors.
`file_edit_many` already validated ordered edits, checked staleness/cancellation,
and wrote once. These mechanisms remain; their path handling was corrected.

Parallel tools (default concurrency four), background subagents, source/decompiler
snapshot caching, transcript retention, the existing changelog, and the client UI
framework remain. No blanket cross-call file cache was added because external
writes would make it stale. Enabled-skill reading requirements remain unchanged.

Existing folders are never automatically flattened, renamed, or merged. When
multiple folders have the same PlaceId, selection is deterministic and the others
remain intact. A name first selected before metadata resolves stays stable.
Discovery is bounded; deeply nested/unreadable legacy data may need an explicit
path. Without host NFC support, valid combining Unicode is preserved unchanged;
there is no claimed full normalization fallback or grapheme-aware truncation.

Native executor APIs still read whole files/listings. Mock checks do not verify
Roblox rendering, OS/browser permissions, host input, or real model search quality.
Context estimation and summaries remain approximate and potentially lossy; a
prompt dominated by fixed instructions may require a larger model window.

## Verification

Source, documentation, examples, and tests were manually reviewed before builds.
Generated bundles, manifests, embedded guide, and site catalog were inspected
before targeted verification. Test corrections were reviewed before rerunning.
The complete native suite was not run.

All 16 selected suites passed:

| Command | Checks/assertions |
| --- | ---: |
| `luajit test/context_compaction.lua` | 185 |
| `luajit test/agent_efficiency.lua` | 22 |
| `luajit test/workspace_paths.lua` | 158 |
| `luajit test/tool_workflows.lua` | 375 |
| `luajit test/provider_output_budget.lua` | 33 |
| `luajit test/attachments.lua` | 64 |
| `luajit test/execution_tools.lua` | 208 |
| `luajit test/script_projects.lua` | 53 |
| `luajit test/reasoning_replay.lua` | 34 |
| `luajit test/subagent_background.lua` | 35 |
| `luajit test/subagent_coordination.lua` | 31 |
| `luajit test/project_support.lua` | 43 |
| `luajit test/ui_library.lua` | 158 |
| `luajit test/ui_library_theme.lua` | 50 |
| `luajit test/ui_library_mobile.lua` | 16 |
| `luajit test/ui_library_agent.lua` | 22 |

Initial failures exposed three fixture assumptions: the fallback test had not
enabled fallback; an existing subagent test checked liveness after completion;
and a timeout test left unlimited mode enabled. A bulk-read continuation test
also needed an explicit small slice now that its entire file fits by default.
These were corrected and rerun without weakening the behavior being tested.

Builds: `node tools/build_ui_lib.js`, `luajit tools/bundle.lua --native`,
and `node tools/build_site.js`. Additional checks: `luajit test/check.lua --native`
(193 files, no failures/warnings), official `luau-compile.exe --null` on changed
Lua sources/examples plus the bootstrap and both generated bundles, and the UI,
client-bundle and site builders' `--check` modes. Release notes were updated only
after the implementation's targeted tests passed, then affected artifacts were
rebuilt and inspected again.
