# Script projects

UAI's Code workspace tool group includes ten tools for building scripts from
saved files. They work in the executor without a desktop service. The user and
agent can still use the existing editor, file tools and single-file execution.

These tools provide lexical source maps, coordinated patches, compiler feedback,
managed behavioral tests and deterministic bundles. They do **not** include an
LSP, Luau type inference, Roblox API type definitions or an isolated test process.

## Start a project

In client 2.7.0, use the canonical Current game files path supplied to the agent.
File tools, search, `check_luau`, `run_luau` and project tools accept the same
`files/...` prefix once. Preserve returned legacy paths exactly, even when they
contain a real nested `files/` folder. New automatic game folders use ASCII names
plus PlaceId; project manifests still use paths relative to their project.

Call `project_scaffold` with a new `directory`, for example `files/My Game (123)/Helper`.
It stages these files and returns `patchId` and the manifest path:

```text
Helper/
  uai.project.json
  main.lua
  settings.lua
  tests/settings.lua
```

Read the proposed files with `project_patch_read`, then pass the ID as `patch_id`
to `project_patch_apply`. Scaffolding and reading do not write or execute source.
This template contains configuration and a passing behavioral test; it creates no
interface. New script interfaces must use Project UAI UI LIB and its lifecycle.

The manifest format is:

```json
{
  "version": 1,
  "entry": "main",
  "modules": {
    "main": "main.lua",
    "settings": "settings.lua",
    "tests/settings": "tests/settings.lua"
  },
  "tests": ["tests/settings"]
}
```

Module IDs use letters, digits, underscores, hyphens and slash-separated segments.
Paths are exact relative `.lua` or `.luau` paths below the manifest directory.
Absolute paths, traversal, duplicate paths and case aliases are rejected. There
is no implicit directory scanning, package installation or network import.

Authored modules return a value and use `require("settings")` for another declared
ID. Every module receives a local `require` and `fixtures`. The bundled loader
memoizes results, preserves `false`, turns a nil return into `true`, detects
active require cycles, and does not fall back to Roblox's global require. Dynamic
string IDs can resolve at runtime if declared; their dependencies cannot be
proven statically. Source that depends on a ModuleScript's `script` identity must
be adapted explicitly. Project entry is not executed by mapping, analysis or build.

## Tools

| Tool | Arguments and behavior |
| --- | --- |
| `project_scaffold` | `directory`: stage the four starter files; existing destinations are rejected. |
| `project_map` | `manifest`: read saved source hashes, function/local outlines, literal imports, and test IDs. Large results use `workspace_result_read`. |
| `project_patch` | `operations`: stage 1–20 creates, replacements or exact edits. Each names `path` and either `content` or `edits`. New files require `create=true`; existing files require `expected_hash`. |
| `project_patch_read` | `patch_id`; optional `path`, `section` (`before`, `after`, `diff`), `offset`, `limit`. Without path, read metadata. Source offsets are one-based bytes; diff offsets count rows. |
| `project_patch_apply` | `patch_id`: recheck every file before writing, then verify each write. Refuses an unsaved Code draft bound to a target. |
| `project_patch_restore` | `patch_id`: conditionally restore original files and remove files the checkpoint created. High-impact permission because restoration can delete files. |
| `project_patch_discard` | `patch_id`: release the proposal/checkpoint; files stay untouched. |
| `script_analyze` | Exactly one of `path` or `manifest`: host compiler diagnostics and source hashes; projects also check literal imports and cycles. No execution. |
| `script_test` | `manifest`; optional JSON `fixtures` and `timeout` (1–60 seconds, default 10). Execute declared test modules through the managed engine. |
| `project_build` | `manifest`, `output` ending in `.lua`; existing output also needs `expected_hash`. Check and export a deterministic bundle, source line locations, hash and recovery checkpoint. |

Exact edits have `old_text` and `new_text`. Matches must be unique, and each edit
sees the preceding edit's proposed result. Empty replacement text deletes a
matched range. Whole-file deletion and rename remain separate existing file
operations. Hashes identify content for conflict detection; they are not security
digests. Once a proposal is staged, apply checks the complete original bytes.

Paths may explicitly begin with `files/` or `UAI/files/`. Project writes are
restricted to the files area; they cannot address pastes or application state.
Maps/builds read saved files, not unsaved editor drafts. A clean open editor view
is not silently replaced by a file write; its existing Save conflict protection
remains active. Use `code_*` tools when editing a live shared document.

## Review, build and test

Review authored changes first. Use `script_analyze` to find syntax errors and
unresolved literal imports. For multi-file code, use `project_build`, inspect
its generated source, then run relevant `script_test` cases. Review any repair
before rebuilding and retesting. Building never starts the script.

For example, a test module can return:

```lua
local settings = require("settings")
return {
	defaults = function(t, fixtures)
		t.equal(settings.name, "My script")
		t.truthy(settings.enabled)
		t.equal(fixtures.expectedName, settings.name)
	end,
}
```

Pass `fixtures = { "expectedName": "My script" }` to `script_test` for this
example. Tests use dot calls: `t.equal(actual, expected, message?)`,
`t.truthy(value, message?)`, and `t.raises(callback, literalErrorSubstring?)`.
Equality uses Lua equality; it is not deep table comparison.

Test modules are loaded for discovery and freshly loaded again for each sorted
case, with a fresh project module cache and copied fixtures. Keep discovery and
module initialization free of side effects. Test execution shares the native
client and can have real game effects. It uses the same high-impact permission,
cooperative cancellation, deadline and task ownership as `run_luau`; it is **not
a security sandbox**. Native calls and dynamically loaded code retain that
engine's limitations. Failed/timed-out runs must not be blindly retried.

Results report passed/failed cases, errors and available stack traces. Bundle
line locations map generated lines back to original files. A source change during
execution invalidates the claim that the current saved project passed. Mock
fixtures do not establish native Roblox input, rendering or server behavior.

Analysis uses the current host compiler. If no compiler is available, results
explicitly say `compilerAvailable=false`; build and test require compilation.
Outlines skip comments and strings, but are lexical hints without scope inference.
Interpolated-string expressions are opaque, shadowed `require` can cause false
dependency reports, and literal dependency cycles are conservatively rejected.
Outline columns and offsets count bytes. Type/API validation is not claimed.

## Bounds and recovery

Projects allow 64 modules, 16 test modules, 256,000 UTF-8 bytes per source and
1 MiB of total source. Manifests and fixture JSON each cap at 32,000 bytes.
Generated editable bundles cap at 256,000 bytes. Inspection caps at 50,000 tokens
and 256 symbols/imports each per file; omitted outlines are reported. Symbol names
cap at 160 bytes with a truncation flag. Analysis retains 512 diagnostics and
reports omitted counts while preserving total error/warning counts. Tests allow
100 cases per run. Test code controls neither permission nor the execution deadline.

Up to eight proposals/checkpoints are kept in memory, with 2 MiB of before/after
source per proposal and 8 MiB total. They belong to their originating conversation
and expire after ten minutes or unload. Explicitly save important original source
before relying on a longer-lived backup; these checkpoints do not survive reload.

Every target is checked before the first write and again immediately before its
own write. Writes are read back. Executor file APIs provide no portable atomic
multi-file commit: cancellation or a failing host call can leave a partial result.
Inspect the returned status and original/proposed source before continuing.
Restore checks every current file and refuses external modifications or unknown
partial bytes. It never guesses whether another writer owns those bytes and never
claims to undo game effects. Project operations lock their targets against other
project operations; unrelated host/file writers are detected by byte checks, not
locked out by the executor filesystem.
