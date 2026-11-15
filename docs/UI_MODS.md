# Native UI mods

UI mods let you customize Project UAI and share the resulting definition as
portable JSON, inspired by [Claude Code Mods](https://code.claude.com/docs/en/plugins/mods/overview).
**Visual** mods provide appearance preferences and small panels.
**Script** mods contain full Lua source for native UI changes, custom controls,
integrations or other behavior supported by the client, Roblox and executor.

Script source executes with full native access. The execution context includes
the UAI handle, environment, mounted application, root GUI and module loader;
raw available APIs remain accessible. Script mods are not sandboxed. Importing,
saving, previewing and sharing a package do not execute its source.

## Create, inspect and apply

Open **UI Mods** in the native client and choose **New visual**, **New script**
or **Import JSON** to open a draft. Edit its complete portable JSON, including
the name, description and script source. Use **Preview** to inspect a draft
when needed. Visual previews show the declared appearance and panel contents.
Script previews show the source and compiler diagnostics; compiler checks compile only, without
calling the resulting chunk or returned factory.
Workspace forms fit their measured content and available viewport height, with
scrolling for long source, metadata and version history.

**Save disabled** stages a disabled definition. Saving an **Import JSON** draft
creates a new disabled record; an existing portable ID must be changed or
explicitly replaced using its current revision. Editing the active definition
stages its new version disabled so that changed source does not start
automatically. **Read current** reviews current storage before a conflicted or
unconfirmed draft is saved again.

**Apply** directly activates the exact saved revision under normal high-impact
tool permissions. There is no separate `ask_user` source-review question or
automatic preview dialog. **Allow everything** permits authorized agents to
Apply immediately; Full access workers retain the parent's authorized scope
and explicit denials. Script source must compile without execution, the
selection must persist, and appearance preparation must finish before source
starts. Cancellation, Disable, or a changed source/revision invalidates pending
preparation. Host context `safeMode=true` makes Apply unavailable and prevents
restoration of either mod kind for that client run. Saved definitions and
previously selected metadata remain available for inspection and export.

One mod is active at a time. A previously selected script loads disabled in a
fresh client and needs a new explicit Apply before any source starts. A known,
validated visual selection can restore its exact saved version. **Disable mods**
clears the active identity, invokes owned cleanup and returns visual appearance
to ordinary saved preferences. Mod appearance never rewrites those preferences.

An agent can author and stage a mod with `ui_mod_save`, inspect it with
`ui_mod_read`, then call `ui_mod_apply` with `expected_revision` set to the
returned `revision`.
Saving and importing keep the proposal disabled. Genuine questions,
clarifications and missing user choices still use `ask_user`, including under
**Allow everything**; an authorized Apply needs no additional question.

## Share a portable package

Choose **Export JSON** for a saved mod, then **Import JSON** on another client.
Script exports contain the complete original source, including CRLF and Unicode,
plus authored metadata/references. Visual exports contain their complete structured
definition. Exporting itself writes no executor file and sends no HTTP request.

Portable fields exclude the client's active/selected state, local version
history, credentials, conversations, previews and internal storage paths. UAI
does not append those values to a shared package. Source and authored references
are copied verbatim, including any literals the author chose to place there.

The [reviewed examples](../mods/README.md) include a visual project workbench,
a native workbench with editable controls, and a native lifecycle marker.
They are examples to review and import, with no claimed in-game verification.

## Portable schema

Every definition includes `version: 1`, `kind`, a stable lowercase ASCII `id`,
and `name`. Optional `description`, `author` and `sources` supply provenance.
Each source has a nonblank `label` and optional `url` or document reference;
references are stored as text and are not fetched automatically. Runtime
revisions, version history and enabled state belong to local storage rather than
the portable definition.

A minimal scripted package is:

```json
{
  "version": 1,
  "kind": "script",
  "id": "my-native-mod",
  "name": "My native mod",
  "description": "An owned native extension.",
  "source": "return function(context)\n  context:OnDestroy(function()\n    -- Release this mod's additional resources.\n  end)\nend"
}
```

Script packages use `source`; that source may use any available native API.
Visual packages use `appearance` and `panels`:

```json
{
  "version": 1,
  "kind": "visual",
  "id": "project-workbench",
  "name": "Project workbench",
  "appearance": {
    "accent": "indigo",
    "density": "compact",
    "fontScale": 1.05,
    "transcriptWidth": "wide"
  },
  "panels": [
    {
      "id": "progress",
      "title": "Progress",
      "widgets": [
        {"id":"intro","type":"text","body":"Keep the current goal and verification evidence visible."},
        {"id":"goals","type":"metric","label":"Micro goals","selector":"goals"},
        {"id":"vault","type":"action","label":"Open Master Vault","action":"vault"}
      ]
    }
  ]
}
```

Visual mod names, panel titles and action/metric labels are plain text without
markup or decorative icon glyphs. Text widget bodies display literal text and
can contain multiple lines. Stable panel IDs are unique; widget IDs are unique
across the whole mod.

| Visual field | Supported values |
| --- | --- |
| `theme` | `default`, `newyear`, `valentine`, `earthday`, `pride`, `peace`, `halloween`, `christmas` |
| `accent` | `claude`, `aurora`, `indigo`, `amber`, `rose` |
| `density` | `comfortable`, `compact` |
| `fontScale` | A finite number from `0.85` to `1.4` |
| `interfaceFont` | `montserrat`, `builder`, `arimo`, `roboto`, `nunito`, `titillium`, `ubuntu`, `source`, `gotham` |
| `codeFont` | `code`, `roboto` |
| `codeTheme` | `dark`, `light` |
| `transcriptWidth` | `narrow`, `medium`, `wide` |
| Metric `selector` | `tokens`, `context`, `goals`, `tools`, `requests`: safe aggregate readouts supplied by the renderer |
| Action `action` | `chat`, `code`, `vault`, `agents`, `providers`, `tools`, `settings`, `logs`, `micro_goals`, `commands` |

Font availability follows the existing native fallback chain. Standard theme
retains the existing automatic seasonal preference. Visual definitions do not
accept raw sizes, colors, instance selectors, code callbacks or permission/tool
hooks. Native scripted mods can implement broader customization through source.

Metric values belong to the active conversation. Tokens include delegated usage
and show an estimated marker when applicable; context is estimated pressure
against the current compaction budget. Goals show completed/total tasks, tools
count available scoped actions, and requests count observed inference dispatches.

## Script lifecycle and context

A source chunk may run top-level code and return an optional factory function.
If it returns a factory, UAI calls `factory(context)`. The factory may return a
cleanup resource, which the runner registers. Source has unrestricted native
access in both forms; using a factory makes its context and lifetime explicit.

Context fields are `uai`, `env`, `app`, `root`, `require`, `scope`, `id` and
`revision`. `context.require("ui/primitives")` and other module/client functions
use their normal dot calls. Context ownership methods use colon calls:

| Method | Behavior |
| --- | --- |
| `context:Give(resource)` | Own a cleanup function, connection or destroyable/cancelable resource; return its early-release function. |
| `context:OnDestroy(callback)` | Register owned cleanup, equivalent to `Give`. |
| `context:Connect(signal, callback)` | Register a scope-owned connection. |
| `context:Delay(seconds, callback, ...)` | Schedule scope-owned delayed work. |
| `context:CreatePanel(options)` | Register an owned native panel in Mod workspace; retain its domain values across window rebuilds. |
| `context:OnMount(callback)` | Call with the current/new root and app; release prior mount cleanup before remounting. Early release closes further mounts and releases current cleanup. |
| `context:IsAlive()` | Check whether this mod/client lifetime remains active. |
| `context:GetRoot()` | Obtain the current mounted root after an app rebuild. |

For an interface inside UAI, use `CreatePanel` and declare sections, values and
domain callbacks. UAI supplies its existing settings sections, buttons, switches,
inputs, sliders and anchored menus, with the current appearance and mobile metrics.
New script templates create an actual workspace panel within this native composition:

```lua
return function(context)
	local panel = assert(context:CreatePanel({
		id = "workbench", title = "Project workbench",
		description = "Keep working notes and project actions together.",
	}))
	local section = assert(panel:Section({ id = "project", title = "Current project" }))
	section:Input({ id = "notes", text = "Working notes", multiline = true,
		value = "", placeholder = "Keep notes for this run" })
	section:Button({ id = "vault", text = "Open Master Vault",
		callback = function() context.app.show("vault") end })
	panel:Show()
end
```

`panel:Show()` opens Mod workspace and selects that panel. Creation alone does not
change the selected page. Panels automatically release when their mod stops;
`panel:Destroy()` releases one early and removes its owned scope resource.
Do not recreate the panel in `OnMount`:
the existing declaration and values survive appearance rebuilds. This state is
local to the loaded mod and is not implicitly saved to disk.

| Native panel method | Options or behavior |
| --- | --- |
| `panel:Section(options)` | `id`, `title`, optional `description`; returns a section. |
| `section:Text(options)` | `id`, literal `text`; optional initial `value`. |
| `section:Button(options)` | `id`, `text`, optional `callback(value, control)`. |
| `section:Toggle(options)` | `id`, `text`, optional boolean `value`, `hint`, `callback`. |
| `section:Input(options)` | `id`, `text`, optional string `value`, `placeholder`, `multiline`, `hint`, `callback`. |
| `section:Select(options)` | `id`, `text`, `options = {{value="code",label="Code"}}`, optional `value`, `hint`, `callback`. |
| `section:Slider(options)` | `id`, `text`, finite increasing `min`/`max`, optional usable positive `step`, `value`, `hint`, `callback`; callback commits on gesture release. |
| `panel:Get(id)` | Return the original control handle for that stable ID. |
| `control:Get()` | Read the retained value. |
| `control:Set(value, notify?)` | Validate and update the existing control; invoke its domain callback only with `notify = true`. |
| `control:SetEnabled(boolean)` | Set whether the user can interact with the control. |
| `control:Activate()` | Invoke the control's callback once when available. |
| `panel:IsAlive()` | Return whether its mod and panel lifetimes are active. |

Native panels accept four panels per active mod, eight sections and 32 controls
per panel, and 1–32 distinct select options. IDs use the portable mod ID format;
section/control IDs are unique across a panel. Panel/section titles, control labels
and select labels are plain text within 100 UTF-8 bytes; they do not accept icons,
markup, colors or sizing options. Descriptions/hints hold 500 bytes, text readouts
4,000 bytes and editable inputs 8,000 bytes. Slider bounds have magnitude at most
one billion and a supplied step must resolve at most one billion increments.
Builders return the handle or `nil, reason` on invalid admission;
value setters return `true` or `nil, reason`.

Callback execution participates in the mod runner's native ownership. A running
callback disables its own control and rejects overlapping requests. Disabled or
released panels reject new callbacks; existing native calls remain cooperative.
Keep input/toggle callbacks brief, and check `context:IsAlive()` after yielding.
Value changes refresh existing widgets and preserve field focus/drafts. Unrelated
readout updates preserve pending slider gestures; explicit value changes reconcile
them. Hidden panels suspend drawing and reconcile values when shown again. Use `context:Give`,
`Connect`, `Delay` and `OnDestroy` for application connections and resources.

Use current root references after remounts and check `IsAlive` after yielding.
Register resources that should end with the mod. Existing native UAI primitives
can extend the established application. New standalone script-owned interfaces
follow [Project UAI UI LIB](UI_LIBRARY.md) and its ownership contract.

If startup remains outstanding after ten seconds, the runner invalidates the
context, releases registered resources and reports the outstanding work. It
keeps native activity tracked until the call actually finishes, so another
startup or source/runtime restart cannot overlap it. **Disable mods** likewise
invalidates the context and releases registered resources. Already-running
native calls and context helper callbacks may continue until they return; that
owned work still blocks another activation or runtime replacement. Raw unregistered
callbacks and effects on files, shared client state
or servers can outlive that cleanup. UAI reports cleanup/persistence warnings and does not claim
to roll back arbitrary scripted effects. A source/runtime restart must respect
outstanding runner or storage work.

Use this loader for a recovery execution:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/main/dist/uai.lua"))({ safeMode = true })
```

When the same build is already running, it calls `getgenv().UAI.recoverUi()`.
You can also call that method directly. Safe mode clears live mods and rebuilds
ordinary appearance; saved definitions remain available. It lasts for that
client lifetime. Unload UAI, then run the loader normally for a fresh execution
that can apply mods again. Recovery cannot undo arbitrary external effects.

## Storage, revisions and recovery

Definitions live in `UAI/ui_mods/store.json` in the executor workspace. The store
retains up to three prior complete versions per mod. A read returns an opaque
current-runtime revision plus the persisted integer version. Repeated resident
reads of unchanged records keep their token. Fresh runtimes and changed disk
observations produce new tokens, while stored versions/history remain available.

Replacing, deleting or activating a record requires its current exact revision.
The store checks complete original storage bytes before writing, rechecks just
before dispatch and verifies resulting bytes afterward. Writes serialize. A
failed/unconfirmed write retains the previous known-good live record and
appearance; it does not quietly publish a partially persisted source version.

Ordinary reads expose resident known-good state. Use **Refresh** in **UI Mods**,
**Read current** in a draft, or `refresh=true` on `ui_mod_read`/`ui_mod_list` to
resolve a conflict or uncertain write. An unreadable or malformed file stays on
disk. Supported records in a partially supported initial file remain readable
with incomplete coverage; writes stay disabled until the storage problem is resolved. An invalid reload
retains existing known-good live records.

Disable always clears the live selection and notifies owned cleanup, even if
storage is busy or unavailable. In that case `persisted=false` explicitly reports
that the choice could not be remembered. A native whole-file API has no portable
atomic compare-and-write or streaming guarantee; another application can race
inside the host call. Save important packages through your usual backup tools.

| Resource | Bound |
| --- | --- |
| Script source | 262,144 UTF-8 bytes |
| Portable visual / script JSON | 32,768 / 786,432 bytes |
| Mod / panel / widget ID | 1-48 lowercase ASCII letters, digits, underscores or hyphens |
| Name / panel title / widget label | 100 UTF-8 bytes |
| Description / author | 500 / 160 UTF-8 bytes |
| Source references | Eight, each with label 160 bytes and optional reference 500 bytes |
| Visual panels / widgets | Four panels and twelve widgets total |
| Text widget body | 2,000 UTF-8 bytes |
| Saved collection | Sixteen mods, three prior versions per mod, four MiB total JSON |
| JSON nesting | Eight portable levels; twelve storage levels for history |
| JSON admission | 160 portable / 8,192 storage collections and members, counted before native decoding |
| Tool listing / read pages | Up to sixteen rows / twelve thousand UTF-8 bytes, reduced by result budget |

Imports and saves validate these bounds without executing source. Missing native
compiler support is reported by **Preview** and prevents script activation, while
staging/sharing remains possible. Without a filesystem, resident definitions
can still be read/exported and disabled; new persistence needs executor file
support.

Preview compilation is tracked until the native compiler returns, including
after disposal is requested. It never calls the compiled chunk. An unloaded
runtime refuses new checks and reports a stopped late result; it does not replay
native compiler work.

## Tool and runtime references

The `ui_mods` group follows normal conversation filters and permissions.
Agents can read `scripting_docs` section `native_ui_mods` for the execution
context and lifecycle offline, in ordinary UTF-8 pages.
`ui_mod_list`, `ui_mod_read` and `ui_mod_export` are read tools.
`ui_mod_save` and `ui_mod_import` need filesystem writes; `ui_mod_delete` uses
high-impact permission because it removes a definition and its retained history.
`ui_mod_disable` is a write action with live recovery independent of filesystem
capability. `ui_mod_apply` uses normal high-impact permission and exact-revision
preflight; Full access workers can apply within their authorized parent scope.

Read sections are `spec` (portable JSON), `source` (script body), and `history`
(prior complete versions). Preserve `revision` with every page after the first
and follow `nextOffset` exactly. Existing save/delete and Apply arguments use
`expected_revision`. Export includes the current definition rather than local
history. **Restore as draft** copies a prior historical spec into an editable
draft; **Save disabled** creates a new version using the current revision.
The same workflow is available through a revision-guarded `ui_mod_save`.

`runtime/ui_mod_document` exposes `validate`, `parse`, `format`, `validId`, `validLabel`, the preference
enums, action/metric lists and limits. `runtime/ui_mods` exposes `list`, `read`,
`save`, `import`, `export`, `delete`, `activate`, `disable`, `getActive`,
`appearance`, `reload`, `state`, `isBusy`, `checkScript` and `changed`.
`checkScript(spec)` returns `ok, reason, diagnostic`; diagnostic records
`executed=false`, compiler availability and source identity. `activate` selects
an exact saved revision; execution belongs to the root activation/runner
layer. The runner exposes `start`, `stop`, `state`, `isBusy`, `notifyMount`,
`mounted` and `changed`.
`runtime/ui_mod_panels` retains the native declarations and supplies detached
`list`/`snapshot` data to `ui/mod_panel`; callbacks execute through the owning
runner context, not through serialized portable data.

Review every changed document, source, example and test before building. Rebuild
with `luajit tools/bundle.lua --native`, inspect generated output, then run
`luajit test/ui_mods_runtime.lua` and `luajit test/ui_mods_tools.lua` with the
applicable runner/UI tests. `luajit test/ui_mod_panels.lua` covers bounded native
declarations, shared controls, detached state and cooperative callbacks.
`luajit test/ui_mod_activation.lua` covers direct
Apply, normal permissions, exact-source preflight and owned execution.
`luajit test/ui_mod_bridge_apply.lua` covers native/Cowork question separation;
`node bridge/tests/browser-mod-apply.js` covers normal tool/permission receipts,
explicit questions, retained answer drafts and mobile width in Chromium.
The browser suite also runs with `node bridge/tests/run.js --browser`.
Manually review every repair before rebuilding
and retesting. Offline checks and compiler validation establish their stated
coverage; they do not verify native Roblox rendering, input or host behavior.
