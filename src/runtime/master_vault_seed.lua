-- Generated from vault/catalog.json and its Markdown by tools/build_master_vault.lua; edit the sources.
return function(env)
	return {
		version = 1,
		release = "4.0.5",
		entries = {
			{ id = "starter:project-knowledge", markdown = [=[
---
uai_vault: 1
title: "Keep useful project knowledge"
description: "Turn observed work into scoped, sourced notes that later tasks can reuse."
kind: project
scope: global
tags: ["knowledge", "goals", "sources"]
sources: [{"label":"Project UAI Master Vault guide","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/MASTER_VAULT.md"},{"label":"Project UAI script project contract","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/SCRIPT_PROJECTS.md"}]
status: verified
verification: "Documentation recipe reviewed for Project UAI 4.0.0; no native Roblox or game-specific validation is claimed."
---
# Keep useful project knowledge

Write a note when the result will help a later task: a working configuration, an
observed remote contract, a resolved error, a project decision, or a reusable
source pattern. Give the note a searchable title and a few precise tags.

Choose the scope that matches the evidence:

- **Global:** a reusable UAI workflow or general source pattern.
- **Game:** observations associated with one positive PlaceId.
- **Project:** requirements and decisions for one named project.

A reusable record can follow this structure:

```markdown
# Result

## Problem and expected behavior
State the trigger and the desired result.

## Observed facts
Record exact paths, IDs, argument shapes and relevant source revisions.

## Working approach
Include the smallest useful source pattern or configuration.

## Verification
Identify who ran which check, on which source, and what the result established.

## Limits and next check
Record missing host coverage, changing game facts and the next useful test.
```

Keep a new or uncertain result in **Draft**. **Verified** requires nonblank,
attributed verification evidence; that status records a claim and does not mean
UAI independently tested it. Mark a superseded approach **Outdated** and explain
why. A current user instruction or new observation takes precedence over an old
note.

At the start of related work, search the relevant game/project plus global
recipes, read the useful bodies and their source metadata, then revalidate facts
that could have changed. Reuse unchanged source and receipts without rerunning
uncertain operations. Cite the exact note ID and source in the result.
]=] },
			{ id = "starter:script-lifecycle", markdown = [=[
---
uai_vault: 1
title: "Own a script's resources"
description: "Keep connections and created Instances under an explicit, repeatable cleanup function."
kind: recipe
scope: global
tags: ["cleanup", "connections", "scripts"]
sources: [{"label":"Execution and cleanup","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/SCRIPT_DEVELOPMENT.md#execution-and-cleanup"},{"label":"UI LIB lifecycle","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/UI_LIBRARY.md#lifecycle"}]
status: verified
verification: "Documentation recipe reviewed for Project UAI 4.0.0; native engine callbacks and cleanup behavior still need host checks."
---
# Own a script's resources

Give each connection, delayed task and created Instance one owner. A source
restore cannot undo a running script's effects, and a tool timeout does not
automatically disconnect persistent engine callbacks.

For a small non-UI module, keep ownership in local state:

```lua
local M = {}
local alive = false
local connection
local ownedPart

function M.stop()
	alive = false
	if connection then connection:Disconnect(); connection = nil end
	if ownedPart then ownedPart:Destroy(); ownedPart = nil end
end

function M.start(runService, parent)
	M.stop()
	local part = Instance.new("Part")
	ownedPart = part
	local ok, why = pcall(function()
		part.Name = "OwnedPreview"
		part.Anchored = true
		part.CanCollide = false
		part.Parent = parent
		alive = true
		connection = runService.Heartbeat:Connect(function()
			if not alive or not part.Parent then return end
			-- Perform bounded work on this module's owned object.
		end)
	end)
	if not ok then M.stop(); error(why, 0) end
	return M.stop
end

return M
```

The caller supplies the service and parent, and retains the returned stop
function. Do not delete unrelated objects just because their names match. If a
setup fails after creating an object, clean up that exact object.

For a script-owned interface, register the returned cleanup and application
connections with `window:Give` or `window:OnDestroy`. Hide and Minimize retain
the view's resources; Destroy and same-Id replacement release them.

Check repeated Start/Stop, setup failure, late callbacks and the actual lifetime
the user requested. Managed task deadlines cover managed work only; dynamically
loaded code, native calls and persistent callbacks retain their documented limits.
]=] },
			{ id = "starter:ui-library-lifecycle", markdown = [=[
---
uai_vault: 1
title: "Build a UI LIB tool with owned cleanup"
description: "Use stable declarative controls and attach domain cleanup to the library window."
kind: recipe
scope: global
tags: ["ui", "ui-lib", "lifecycle"]
sources: [{"label":"UI LIB Quickstart and Controls","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/UI_LIBRARY.md"},{"label":"Owned view work","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/UI_LIBRARY_LIFECYCLE.md"}]
status: verified
verification: "API recipe reviewed against UI LIB 1.6.0 documentation for Project UAI 4.0.0; native rendering and input are unverified."
---
# Build a UI LIB tool with owned cleanup

Read the library's Quickstart, Controls and Lifecycle before writing a new
script-owned interface. Load the published bundle once at the entry point and
pass the API into other modules. Scripts declare values and domain callbacks;
the library owns controls, layout, appearance, drag behavior and attribution.

```lua
local UI = loadstring(game:HttpGet(
	"https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/main/dist/uai-ui.lua"
))()
local window = UI:CreateWindow({
	Id = "my-project-observer", Title = "Project observer",
	Subtitle = "Inspect the current session",
})
local tab = window:Tab({ Id = "main", Title = "Main" })
local section = tab:Section({ Id = "actions", Title = "Actions" })
local enabled = section:Toggle({
	Id = "observer-enabled", Text = "Observe changes", Default = false,
})
local players = game:GetService("Players")
window:Give(players.PlayerAdded:Connect(function(player)
	if enabled:Get() then print("Player joined", player.Name) end
end))
window:OnDestroy(function()
	-- Release any additional domain state owned by this application.
end)
return window
```

Give different applications different stable window IDs; keep control IDs unique
within one window. Recreating the same window ID destroys the earlier view and
calls its cleanup. Keep navigation and action labels as plain text. Every library
window retains `Project UAI | UI LIB.` and the library-provided player profile.

For delayed work use owned `window:Delay`; for a trailing update after a burst,
use `window:Debounce`. Guard native asynchronous results with a request generation
and `window.Alive` after they return. Closing a view does not roll back domain
effects or destroy a shared client.

Review the source, build affected artifacts, inspect output, and run appropriate
offline checks. A mock preview establishes approximate layout; native rendering,
host input and side-effect behavior require their own evidence.
]=] },
			{ id = "starter:remote-contract", markdown = [=[
---
uai_vault: 1
title: "Document an observed remote contract"
description: "Record exact identities, typed arguments and observed outcomes before designing a remote-dependent script."
kind: remote
scope: global
tags: ["remote", "arguments", "evidence"]
sources: [{"label":"Native remote observation and replay","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/SCRIPT_DEVELOPMENT.md#native-workflows"},{"label":"Packed values and remote contract","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/SPEC.md"}]
status: verified
verification: "Documentation template reviewed for Project UAI 4.0.0; no game remote identity, argument shape or server result is supplied."
---
# Document an observed remote contract

Use a game-scoped copy for real observations. A remote's name does not establish
its argument shape, server validation or purpose.

```markdown
# Remote contract

- PlaceId: <observed place>
- Exact remote ID/path and class: <observed target>
- Direction and method: <incoming/outgoing, FireServer/InvokeServer/etc.>
- Observation source: <capture session, record ID, source revision>
- Argument count and positions: <including exact nil slots>
- Typed values: <packed argument graph or observed schema>
- Return values or outcome: <observed result, unknown if unavailable>
- Lifetime: <capture date, runtime epoch, known invalidation conditions>
- Coverage: <UAI traffic, incoming events, or unverified outgoing attribution>
- Validation: <who checked what; current server behavior still unknown if untested>
```

Inspect `remotes_state`, resolve the exact target, and choose only the necessary
capture scope. Native capture normally stops after 30 seconds; continuous work
needs an explicit lifetime and stop path. `remotes_calls` and detail readers
expose records, typed arguments and coverage; preserve session IDs and cursors.

A graph with omitted, unsupported, sparse or cyclic values can remain useful for
inspection while being ineligible for replay. Treat a displayed preview as a
preview. Preserve binary strings, Roblox types and nil positions through the
packed typed format rather than guessing a plain JSON replacement.

Reading metadata and preparing a replay plan sends no traffic. A replay dispatch
sends traffic, has separate authorization and may have irreversible server
effects. Unknown outcomes do not authorize a repeat. Imported captures are
offline until explicitly rebound to current targets.

This template is a documentation aid. Client-side inspection cannot prove the
absence of server-side checks or guarantee protection from bans.
]=] },
			{ id = "starter:remote-fixtures", markdown = [=[
---
uai_vault: 1
title: "Test remote-dependent logic with local fixtures"
description: "Inject a small transport interface so argument construction can be checked without live sends."
kind: recipe
scope: global
tags: ["remote", "fixtures", "tests"]
sources: [{"label":"Behavioral project tests and fixtures","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/SCRIPT_PROJECTS.md#review-build-and-test"},{"label":"Observed remote requirements","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/SCRIPT_DEVELOPMENT.md#environment-model"}]
status: verified
verification: "Documentation recipe reviewed for Project UAI 4.0.0; the fixture checks local argument construction, not a game's server contract."
---
# Test remote-dependent logic with local fixtures

Separate your domain logic from a live remote. Accept a transport callback and
construct arguments as ordinary data. The example action label is fixture data,
not a known command supported by any game.

`actions.lua`:

```lua
local M = {}
function M.submit(send, action, amount)
	assert(type(send) == "function", "transport required")
	assert(type(action) == "string" and action ~= "", "action required")
	assert(type(amount) == "number" and amount == amount
		and amount > 0 and amount < math.huge, "positive finite amount required")
	return send(action, amount)
end
return M
```

`tests/actions.lua`:

```lua
local actions = require("actions")
return {
	constructs_arguments = function(t, fixtures)
		local calls, observed = 0, nil
		local result = actions.submit(function(action, amount)
			calls = calls + 1
			observed = { action, amount }
			return "fixture-result"
		end, fixtures.action, 2)
		t.equal(calls, 1)
		t.equal(observed[1], fixtures.action)
		t.equal(observed[2], 2)
		t.equal(result, "fixture-result")
	end,
	rejects_invalid_amount = function(t)
		t.raises(function()
			actions.submit(function() error("must not dispatch") end, "fixture-action", 0)
		end, "positive finite amount")
	end,
}
```

Declare both modules and the test module in `uai.project.json`. Review their
source, analyze/build the project, inspect generated output, then run only the
relevant test with a fixture such as `{"action":"fixture-action"}`.

The fake callback above records only local data. It never calls `FireServer` or
`InvokeServer`. An arbitrary project test still shares the native client and is
not a security sandbox; inspect discovery and module initialization for effects.
Passing this fixture proves local call construction for its inputs. It does not
establish a real remote's server validation, rate limits, ownership or outcome.
]=] },
			{ id = "starter:instance-configuration", markdown = [=[
---
uai_vault: 1
title: "Record an instance configuration with expected values"
description: "Preserve exact target identity and typed before/after values for repeatable local edits."
kind: instance
scope: global
tags: ["instances", "configuration", "conflicts"]
sources: [{"label":"Typed native instance editing","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/SCRIPT_DEVELOPMENT.md#native-workflows"},{"label":"Native instance identity and Undo contract","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/SPEC.md"}]
status: verified
verification: "Documentation template reviewed for Project UAI 4.0.0; actual engine properties, replication and host behavior remain unverified."
---
# Record an instance configuration with expected values

Use a game-scoped note for a live target. Record the exact observed instance ID,
class, path, relevant parent and source revision. IDs are scoped to the current
runtime; re-resolve a saved path when returning to the game.

```markdown
# Configuration

- Target identity and class: <observed ID/path/class>
- Parent and ownership: <observed parent; who created the object>
- Needed properties/attributes: <exact fields only>
- Expected values: <typed values from current inspection>
- Desired values: <typed requested configuration>
- Result: <read-back values and any partial failure>
- Recovery: <recorded change batch ID and current-value requirements>
- Limits: <local-only observation, unavailable properties, replication unknown>
```

Inspect `explorer_state` and read only the needed `explorer_properties`. Preserve
their snapshot and coverage. `instance_edit_many` can guard an edit with either
that snapshot or an explicit expected value. A single `instance_set` accepts the
typed representation too:

```json
{"instance_id":"<observed-id>","property":"CanCollide","typed_value":{"kind":"boolean","value":false},"expected_value":{"kind":"boolean","value":true}}
```

Replace the placeholders and expected value with actual observations. This
example does not assert that a target exists or currently has `CanCollide=true`.

Read the result and inspect any partial outcome. A clamped setter or a setter
throwing after changing a value is not an untouched target. Recheck current
values before Undo. Supported field Undo does not rebuild destroyed hierarchies
or reverse remote/server effects.

Selection is shared presentation state, not a lock. Editing exact returned IDs
does not require changing the user's selection. If a script creates objects,
cleanup owns those exact objects and must not delete unrelated name matches.
]=] },
			{ id = "starter:bugfix-record", markdown = [=[
---
uai_vault: 1
title: "Save a failure and its verified correction"
description: "Retain the trigger, failed attempts, source change and useful verification evidence."
kind: bugfix
scope: global
tags: ["bugfix", "diagnostics", "evidence"]
sources: [{"label":"Review and verification workflow","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/SCRIPT_DEVELOPMENT.md"},{"label":"Source-aware script goals","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/SPEC.md"}]
status: verified
verification: "Documentation template reviewed for Project UAI 4.0.0; completing the template requires actual task evidence."
---
# Save a failure and its verified correction

A useful bugfix note explains how to recognize the problem and what evidence
supports the correction. Save failed approaches too when they would otherwise
be repeated after context compaction or a later session.

```markdown
# Bugfix record

## Trigger
Exact input, environment and action that produced the failure.

## Expected and observed behavior
Expected result, actual diagnostic and relevant source/target identity.

## Attempts
What was tried, its result, and why the next attempt changed the approach.

## Correction
Small source diff or configuration change, with the applicable revision.

## Verification
Who ran which compiler/behavioral check, against which source, and its result.

## Remaining limits
Missing game/renderer/input/server coverage and any invalidation conditions.
```

Distinguish syntax, local behavior and native/server outcomes. A compiler pass
does not prove that Instances or methods exist. A successful dispatch does not
prove a remote achieved its intended server effect. A timeout does not prove
that nothing happened.

After a failure, review the proposed fix before rebuilding or retesting. Repeat
a check when the source changed or the new attempt resolves an observed concern.
Keep unchanged receipts and finished work available instead of blindly retrying.

Use **Draft** while evidence is incomplete. When marking **Verified**, attribute
the evidence and state its scope. Mark obsolete instructions **Outdated** after a
new observation contradicts them. Never turn historical failure prose into a
standing instruction that overrides the user's current task or tool policy.
]=] },
			{ id = "starter:guarded-file-edits", markdown = [=[
---
uai_vault: 1
title: "Edit saved source without clobbering newer work"
description: "Use canonical paths, exact matches and read-back verification for focused file changes."
kind: recipe
scope: global
tags: ["files", "edits", "conflicts"]
sources: [{"label":"Canonical file namespace and exact edits","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/SCRIPT_DEVELOPMENT.md"},{"label":"Project patch conflict and recovery contract","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/SCRIPT_PROJECTS.md"}]
status: verified
verification: "Tool workflow reviewed from Project UAI documentation for 4.0.0; filesystem implementation behavior requires host-specific checks."
---
# Edit saved source without clobbering newer work

Use the exact canonical `files/...` path returned by UAI. Strip no additional
prefixes: `files/files/name.lua` can name a real nested folder. Decompiled dumps
belong under the current game's `dump/`; user scripts belong in its files folder.

Read the relevant source before editing. Preserve UTF-8 page offsets and read the
complete needed section. A truncated preview is not a complete replacement file.

For a small change, `file_edit` uses exact old/new text. The old text must match
uniquely unless replace-all is explicitly requested. `file_edit_many` stages
ordered edits to one file and checks all matches before one verified write. Empty
replacement text can remove the matched range.

Use a full write when creating a file or replacing most of its contents. A
single file write/append is bounded to 2 MiB; larger generated source uses small
sequential writes/appends, then a check by saved path. Do not repeatedly emit a
large existing file to make a few changes.

For multiple files, stage a project patch with current source hashes. Read its
before/after/diff, apply only after reviewing, and inspect the result. Project
patches recheck original bytes and verify writes, but executor file APIs do not
provide an atomic multi-file transaction. A partial result requires inspecting
its recovery checkpoint.

An unsaved Code draft bound to a target blocks a project patch. Clean editor
views retain Save conflict protection. Restore checks recorded current bytes
and does not overwrite another writer's changes. Source checkpoints restore
files, not previously executed native or server effects.

After the edit, review source, analyze/build when applicable, inspect generated
output, and run focused checks. Changed source needs fresh evidence before
reporting its current version as validated.
]=] },
			{ id = "starter:multi-file-project", markdown = [=[
---
uai_vault: 1
title: "Build a small multi-file Luau project"
description: "Declare modules and tests explicitly, review patches, then generate a deterministic bundle."
kind: recipe
scope: global
tags: ["projects", "modules", "build"]
sources: [{"label":"Script project manifests and loader","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/SCRIPT_PROJECTS.md"},{"label":"Script development guide","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/SCRIPT_DEVELOPMENT.md"}]
status: verified
verification: "Manifest and loader workflow reviewed for Project UAI 4.0.0; compilation and behavior must be checked for the user's actual source."
---
# Build a small multi-file Luau project

Use `project_scaffold` for a staged starter, or declare a version-1 manifest with
explicit source paths. Paths are relative to the project directory and remain
inside the executor's files area.

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

`settings.lua`:

```lua
return { name = "My helper", enabled = false }
```

`main.lua`:

```lua
local settings = require("settings")
return { name = settings.name, enabled = settings.enabled }
```

Read staged source before applying a patch. `script_analyze` reports host compiler
diagnostics, lexical outlines and literal dependencies. It does not provide type
inference, an LSP or Roblox API validation. Dynamic requires remain dependent on
the explicitly declared runtime module map.

`project_build` checks and exports a deterministic bundle with source locations;
it does not execute the entry. Inspect that output before applicable behavioral
tests. The loader memoizes modules, preserves `false`, turns a nil return into
`true`, rejects active cycles and never falls back to Roblox's global `require`.

Project limits include 64 modules, 16 test modules, 256000 bytes per source,
1 MiB total source, and 256000 bytes per editable bundle. No package install,
implicit directory scan or network import is part of the project loader.

Modules receive `require` and `fixtures`. Keep initialization free of unwanted
effects because test discovery loads modules too. For interfaces, use UI LIB at
the entry point and keep runtime logic separate from declarative presentation.
]=] },
			{ id = "starter:behavioral-testing", markdown = [=[
---
uai_vault: 1
title: "Write a focused behavioral project test"
description: "Use independent expectations and fixtures, and report exactly which behavior was checked."
kind: recipe
scope: global
tags: ["tests", "fixtures", "verification"]
sources: [{"label":"Behavioral assertions, selection and test limits","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/SCRIPT_PROJECTS.md#review-build-and-test"},{"label":"Review/build/inspect/verify order","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/DEVELOPMENT.md"}]
status: verified
verification: "Testing recipe reviewed for Project UAI 4.0.0; synthetic or fixture checks do not establish native Roblox behavior."
---
# Write a focused behavioral project test

Test an observable requirement using an independent expectation. Do not merely
repeat an implementation's calculations in the test. A configuration default,
an invalid-input refusal, a conflict, or a retained result are useful contracts.

For the `settings` module in the multi-file project recipe:

```lua
local settings = require("settings")
return {
	defaults = function(t, fixtures)
		t.equal(settings.name, fixtures.expectedName)
		t.equal(settings.enabled, false)
	end,
}
```

Save this as `tests/settings.lua`, declare it in the manifest, and pass
`fixtures={"expectedName":"My helper"}`. `t.equal` uses Lua equality rather than
deep table comparison. `t.truthy` checks truthiness and `t.raises` checks an
expected literal error substring.

Review source first. Analyze/build when needed, inspect generated output, then
call `script_test` with the relevant declared modules and a case-sensitive name
filter. A filter matching no cases is a failed incomplete run. Passing selected
cases establishes that selection's coverage; omitted cases were not checked.

Each case gets a fresh project module cache and copied fixture data, but tests
share native client state. Discovery loads module initialization, so inspect it
for effects. Test execution uses managed deadlines and normal high-impact tool
permissions; it is not an isolated process or security sandbox.

Record selected cases, source identity, diagnostics and the actual result. A
source change invalidates the claim that the current saved source passed. An
offline fixture checks local behavior; it does not validate live server state,
Roblox rendering, touch input or executor-specific continuation behavior.
]=] },
			{ id = "starter:runtime-inspection", markdown = [=[
---
uai_vault: 1
title: "Inspect the runtime with bounded evidence"
description: "Resolve a relevant target and retain provenance and coverage instead of guessing from names."
kind: reference
scope: global
tags: ["inspection", "source", "capabilities"]
sources: [{"label":"Environment and native workflows","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/SCRIPT_DEVELOPMENT.md"},{"label":"sUNC getgc reference","url":"https://docs.sunc.io/Environment/getgc/"}]
status: verified
verification: "Documentation guidance reviewed for Project UAI 4.0.0; executor introspection and game-specific conclusions remain unverified."
---
# Inspect the runtime with bounded evidence

Start from the task's known object, exact path or current selection. Use narrow
instance queries and paged children to locate only the relevant subtree. Preserve
returned IDs, revisions and incomplete coverage. A bounded search with no match
does not prove absence.

For source questions, use `script_source` and inspect its status and provenance.
Host-readable empty Source is valid; unavailable or failed decompilation is a
diagnostic, not recovered executable source. External decompiler fallbacks send
the selected bytecode to their service. Reading a snapshot never writes it back
into a live game script.

Capability discovery is separate from decompilation. Source snapshots and native
results have bounded lifetimes; reuse unchanged retained evidence and refresh
only after expiry, a source change, or an observed reason. Do not repeat the same
failed recovery without new evidence.

`getgc` exposes live garbage-collectable values where supported; it is not an
indexed source repository. `getsenv` can fail for an inactive script or another
Luau state. Introspection does not justify calling every returned function:
unknown functions may require their original context, yield or change state.

If a name or byte pattern suggests an anti-cheat candidate, preserve the exact
evidence and uncertainty. Client-side matches cannot reveal every server-side
check, prove a game safe, or guarantee protection from bans. A controlled task
should rely on explicit permitted actions, bounded work and observed outcomes.

Avoid collecting unrelated table contents or player data. Store only the facts
needed for the project, with their source and applicable game scope.
]=] },
			{ id = "starter:embedding-scopes", markdown = [=[
---
uai_vault: 1
title: "Give a host integration its own resource scope"
description: "Use SDK scopes and request handles to keep host work independent from a library view."
kind: recipe
scope: global
tags: ["embedding", "scopes", "cleanup"]
sources: [{"label":"Embedding SDK guide","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/EMBEDDING.md"},{"label":"UI LIB runtime integration","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/UI_LIBRARY.md#runtime-integration"}]
status: verified
verification: "Lifecycle guidance reviewed against SDK 1.1.0 documentation for Project UAI 4.0.0; actual host setup and input require separate checks."
---
# Give a host integration its own resource scope

Given an existing live UAI handle, `uai.sdk.createScope(id)` owns a host feature's
subscriptions, hooks, tools and scheduled work. Use a unique stable scope ID;
duplicate live IDs are rejected. Destroying a scope releases its resources once
and removes only the tool definitions it registered.

A scope's destruction does not delete conversations or unload a shared client.
Already-running callbacks and native calls remain cooperative. Tool removal
invalidates running work and denies pending approval; it does not undo applied
effects.

For a companion UI LIB window:

```lua
local scope = assert(uai.sdk.createScope("my-project-view"))
window:OnDestroy(function() scope.destroy() end)
```

Here `uai` and `window` are live handles supplied by the caller; this fragment
does not create or connect them. SDK/client functions use dot calls, while UI LIB
controls use colon calls. Read the SDK guide for the exact registration API.

Use `sdk.request(session, text, options)` when a host needs request identity,
cancellation and a terminal result. An accepted request settles once; admission
failure returns `nil, reason`. `await(timeout)` stops waiting at its own timeout
without cancelling the underlying request. A snapshot is detached from retained
state and does not mutate another observer's result.

The full client still owns provider setup, credential access and tool policy.
`context.ui=false` keeps its normal application hidden after access is granted;
it does not bypass required storage setup or password unlock. A custom host
interface uses UI LIB and explicit domain ownership without replacing the
established UAI application.
]=] },
			{ id = "starter:neural-network", markdown = [=[
---
uai_vault: 1
title: "Train a small numeric neural network in Luau"
description: "A deterministic sigmoid MLP with bounded backpropagation, XOR training and portable saved weights."
kind: recipe
scope: global
tags: ["neural-network", "numeric", "training"]
sources: [{"label":"Backpropagation reference","url":"https://en.wikipedia.org/wiki/Backpropagation"},{"label":"Project UAI source review and behavioral tests","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/SCRIPT_PROJECTS.md"}]
status: draft
verification: "Reference implementation authored for Project UAI 4.0.0. External convergence and saved-weight checks are required; no native Roblox verification is claimed."
---
# Train a small numeric neural network in Luau

Use this recipe when the user explicitly requests a small trainable numeric
model. It implements a feed-forward network with one hidden layer and sigmoid
activations, trained by stochastic backpropagation on squared error.

Save the first code block as `network.lua` in a reviewed UAI script project.
Inputs must be normalized to [-1, 1]; targets must be in [0, 1]. The model permits
1–16 inputs, 1–32 hidden neurons and 1–16 outputs. Training caps at 20000 epochs,
100000 sample updates, with
`epochs * samples * hidden * (inputs + outputs) <= 4000000` per call. Weight
clipping to [-20, 20] keeps numeric state bounded. Initialization is deterministic
and leaves the host's random generator untouched.

```lua
local M = {}
local Model = {}
Model.__index = Model

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function count(value, maximum)
	assert(finite(value) and value >= 1 and value <= maximum
		and value == math.floor(value), "invalid network dimensions")
	return value
end
local function dense(value, size)
	assert(type(value) == "table" and #value == size, "invalid vector shape")
	for key in pairs(value) do
		assert(type(key) == "number" and key >= 1 and key <= size
			and key == math.floor(key), "invalid vector shape")
	end
end
local function vector(value, size, minimum, maximum)
	dense(value, size)
	local out = {}
	for index = 1, size do
		assert(finite(value[index]) and value[index] >= minimum
			and value[index] <= maximum, "invalid numeric value")
		out[index] = value[index]
	end
	return out
end
local function sigmoid(value)
	if value >= 0 then return 1 / (1 + math.exp(-value)) end
	local exponential = math.exp(value)
	return exponential / (1 + exponential)
end
local function clip(value) return math.max(-20, math.min(20, value)) end
local function forward(model, input)
	local hidden, output = {}, {}
	for h = 1, model.hidden do
		local sum = model.hiddenBias[h]
		for i = 1, model.inputs do sum = sum + model.inputWeights[h][i] * input[i] end
		hidden[h] = sigmoid(sum)
	end
	for o = 1, model.outputs do
		local sum = model.outputBias[o]
		for h = 1, model.hidden do sum = sum + model.outputWeights[o][h] * hidden[h] end
		output[o] = sigmoid(sum)
	end
	return hidden, output
end
function M.new(inputs, hidden, outputs, seed)
	inputs, hidden, outputs = count(inputs, 16), count(hidden, 32), count(outputs, 16)
	seed = seed or 1
	assert(finite(seed) and math.abs(seed) <= 1000000, "invalid seed")
	local index = 0
	local function weight()
		index = index + 1
		return math.sin(seed + index * 12.9898) * 0.5
	end
	local model = setmetatable({ inputs = inputs, hidden = hidden, outputs = outputs,
		inputWeights = {}, hiddenBias = {}, outputWeights = {}, outputBias = {} }, Model)
	for h = 1, hidden do
		model.inputWeights[h] = {}
		for i = 1, inputs do model.inputWeights[h][i] = weight() end
		model.hiddenBias[h] = weight()
	end
	for o = 1, outputs do
		model.outputWeights[o] = {}
		for h = 1, hidden do model.outputWeights[o][h] = weight() end
		model.outputBias[o] = weight()
	end
	return model
end
function Model:predict(input)
	input = vector(input, self.inputs, -1, 1)
	local _, output = forward(self, input)
	return output
end
function Model:train(samples, epochs, learningRate)
	assert(type(samples) == "table" and #samples >= 1 and #samples <= 256, "invalid dataset")
	dense(samples, #samples)
	epochs = count(epochs or 10000, 20000)
	learningRate = learningRate or 0.5
	assert(finite(learningRate) and learningRate > 0 and learningRate <= 1, "invalid learning rate")
	local updates = epochs * #samples
	assert(updates <= 100000 and updates * self.hidden * (self.inputs + self.outputs) <= 4000000,
		"training workload exceeds limit")
	local data = {}
	for index, sample in ipairs(samples) do
		assert(type(sample) == "table", "invalid dataset sample")
		data[index] = { input = vector(sample.input, self.inputs, -1, 1),
			target = vector(sample.target, self.outputs, 0, 1) }
	end
	for epoch = 1, epochs do
		for _, sample in ipairs(data) do
			local hidden, output = forward(self, sample.input)
			local outputDelta, hiddenDelta = {}, {}
			for o = 1, self.outputs do
				outputDelta[o] = (sample.target[o] - output[o]) * output[o] * (1 - output[o])
			end
			-- Hidden gradients use the output weights before this update.
			for h = 1, self.hidden do
				local sum = 0
				for o = 1, self.outputs do sum = sum + self.outputWeights[o][h] * outputDelta[o] end
				hiddenDelta[h] = hidden[h] * (1 - hidden[h]) * sum
			end
			for o = 1, self.outputs do
				for h = 1, self.hidden do
					self.outputWeights[o][h] = clip(self.outputWeights[o][h] + learningRate * outputDelta[o] * hidden[h])
				end
				self.outputBias[o] = clip(self.outputBias[o] + learningRate * outputDelta[o])
			end
			for h = 1, self.hidden do
				for i = 1, self.inputs do
					self.inputWeights[h][i] = clip(self.inputWeights[h][i] + learningRate * hiddenDelta[h] * sample.input[i])
				end
				self.hiddenBias[h] = clip(self.hiddenBias[h] + learningRate * hiddenDelta[h])
			end
		end
	end
	local loss = 0
	for _, sample in ipairs(data) do
		local _, output = forward(self, sample.input)
		for o = 1, self.outputs do loss = loss + (sample.target[o] - output[o]) ^ 2 end
	end
	return loss / (#data * self.outputs)
end
function Model:export()
	local out = { version = 1, inputs = self.inputs, hidden = self.hidden, outputs = self.outputs,
		inputWeights = {}, hiddenBias = vector(self.hiddenBias, self.hidden, -20, 20),
		outputWeights = {}, outputBias = vector(self.outputBias, self.outputs, -20, 20) }
	for h = 1, self.hidden do out.inputWeights[h] = vector(self.inputWeights[h], self.inputs, -20, 20) end
	for o = 1, self.outputs do out.outputWeights[o] = vector(self.outputWeights[o], self.hidden, -20, 20) end
	return out
end
function M.fromWeights(snapshot)
	assert(type(snapshot) == "table" and snapshot.version == 1, "invalid saved model")
	local model = M.new(snapshot.inputs, snapshot.hidden, snapshot.outputs, 1)
	dense(snapshot.inputWeights, model.hidden); dense(snapshot.outputWeights, model.outputs)
	model.hiddenBias = vector(snapshot.hiddenBias, model.hidden, -20, 20)
	model.outputBias = vector(snapshot.outputBias, model.outputs, -20, 20)
	for h = 1, model.hidden do model.inputWeights[h] = vector(snapshot.inputWeights[h], model.inputs, -20, 20) end
	for o = 1, model.outputs do model.outputWeights[o] = vector(snapshot.outputWeights[o], model.hidden, -20, 20) end
	return model
end
return M
```

An XOR entry module can train a separate numeric model and return its predictions
and exported weights:

```lua
local Network = require("network")
local samples = {
	{ input = { 0, 0 }, target = { 0 } },
	{ input = { 0, 1 }, target = { 1 } },
	{ input = { 1, 0 }, target = { 1 } },
	{ input = { 1, 1 }, target = { 0 } },
}
local model = Network.new(2, 4, 1, 7)
local loss = model:train(samples, 20000, 0.5)
local predictions = {}
for index, sample in ipairs(samples) do predictions[index] = model:predict(sample.input)[1] end
return { loss = loss, predictions = predictions, weights = model:export() }
```

Save the weight table as JSON through a reviewed workspace write, read it back,
and call `Network.fromWeights(decodedWeights)` for inference without retraining.
Export and restore copy numeric arrays so later caller edits do not change an
existing model. Train only on suitable numeric data and validate separate data
for real tasks; XOR is a deterministic demonstration, not a quality benchmark.

The recipe runs through the existing reviewed script workflow and managed
execution limits. It performs no game, remote, filesystem or network operations
itself. Training produces a small separate model; provider inference and native
runtime behavior still depend on their existing contracts.
]=] },
		},
	}
end
