# Project UAI 4.0.0 - a major release

Release dated November 14, 2026. Client, bridge package and Windows desktop use
**4.0.0**. UI LIB stays **1.6.0**, embedding SDK **1.1.0**, and Android companion
**3.7.2**.

The new update focus is a persistent, customizable agent workspace: reusable
technical knowledge, small tasks with clear outcomes, shareable extensions and
progress that survives a conversation restart.

## Master Vault

Open **Master Vault** from the app menu, sidebar or command search. It is a local
Markdown knowledge base that works without Cowork, an Obsidian installation or a
provider call. Browse bundled starters or your own notes, then search by text,
scope, type and status.

Notes cover recipes, bug fixes, remote contracts, instance configurations, project
decisions and references. Global notes apply across games; game notes carry an
exact PlaceId; project notes carry a project name. Sources and verification evidence
show where a result came from and what was actually checked.

The curated starter vault contains reusable patterns and templates for script
lifetime, UI LIB, instance edits, remotes, fixtures, diagnostics and modular
projects. The 13-note starter collection includes a deterministic numeric MLP
with bounded XOR training and portable saved weights. Copy a starter to adapt it.
User notes are ordinary Markdown files under
`UAI/vault/notes/`; client updates never replace them. Imported Markdown is data and
does not execute code or install dependencies.

Edits require the revision that was read and compare the full original bytes before
writing. Save verifies the resulting file. If another writer changes a note or a
save cannot be confirmed, the native editor retains the draft for explicit review.
Export notes as portable Markdown with their supported metadata and exact body.

See [Master Vault](MASTER_VAULT.md) for the format, workflow, bounds and tools.

## Micro-goals

Open **Micro-goals** for the current conversation. Set an objective and split it into
small tasks with completion criteria, dependencies, evidence and blockers. Tasks
retain stable IDs and support pending, active, blocked and done states.

Only one task is active at a time. Dependencies must be complete before dependent
work starts, and completion requires evidence. Reopening a prerequisite invalidates
affected dependent results. Revision checks prevent a stale tool or form from
replacing newer progress.

Pause, resume, reorder or revise the board explicitly. Goals persist with the
conversation and remain visible to the model after compaction. Reloading or resuming
a board does not dispatch tools or start inference. Existing task lists and the
script workflow retain their own purposes and state.

See [Micro-goals](MICRO_GOALS.md) for controls, transitions and tool examples.

## UI mods

Open **UI mods** in the sidebar or **Manage UI mods** in command search.
Visual mods change appearance and add workspace panels with text, live metrics
and navigation. Script mods contain unrestricted native Lua source with the
full UAI handle, environment, application, module loader and executor APIs.
Agents can author either kind through the existing tools.

Saving, importing and previewing stage data without executing it. Apply directly
activates the exact saved revision under normal high-impact tool permissions,
without a separate `ask_user` review or automatic preview dialog. Authorized
Full access workers can Apply within the parent's scope. Preflight compiles
script source without executing it and rechecks its full definition/revision;
selection persistence and appearance preparation must finish before startup.
Cancellation, Disable and stale or changed definitions prevent pending startup.

Export complete portable JSON/source for other users to import and review.
Keep up to three prior versions per saved mod, inspect them, and restore an old
version as a new draft. Client credentials, conversations, paths and active state
are not appended to exports; authored source literals remain verbatim.

Mods have owned cleanup, remount callbacks and tracked outstanding helper/native
work. Scripted selections remain disabled on a fresh load. Safe mode recovers
the ordinary interface without deleting definitions. Arbitrary external effects
and unregistered raw work cannot be rolled back automatically.
See [UI mods](UI_MODS.md) for the schema, source context and recovery loader.

## Delegation, response rate and desktop setup

The main agent can assign **Read only** or **Full access** subagents. Read-only
workers inspect and report; full workers can write and execute assigned work.
Both retain the parent tool scope, unavailable-capability checks and explicit
denials. Workers hand required user decisions back to the main agent.
Read only covers every available topic, including mod and source inspection.

Completed native and Cowork messages show a subdued **tk/s request avg** when
the provider reports output tokens and a valid successful request duration.
The average includes waiting and transport time. It does not infer generation
speed from buffered previews; missing measurements stay hidden.

Manual native bridging has been removed. Start Cowork in the Windows desktop
app and load UAI on the same computer. Discovery uses port 28791 with temporary
in-memory credentials. Disconnect suspends discovery; Reconnect resumes it.
Legacy manual ports, tokens and Enabled settings are discarded on load/save and
transfer. The mobile relay retains its own existing pairing flow.

Browser tools with an argument named `id` now submit to the intended form. Footer
actions keep their form association for tool runs and other workspace forms.
The new native sidebar entries use the existing book, check and sliders icons.
Workspace forms fit their content and available viewport height while retaining
scrolling for long source, note details and history.

## Models and pricing

The November 14 snapshot contains **1,855 exact model/provider entries across
15 providers**, with five catalog feeds and 22 reviewed official references.
It retains all 471 OpenRouter IDs, 473 Kilo IDs and the three current Cline free
IDs. Provider-specific rates, cache categories and context tiers stay attributed
to their actual routes.

Current OpenAI GPT-6/6.1, Claude Fable/Mythos 5.2 and Gemini 4 models have updated
limits and documented reasoning settings. Direct OpenAI tool routes that require
Responses use ordered signed reasoning history across turns and reloads.
Gemini Carbon/Argon use their documented 32K non-streaming or 64K streaming cap.

Introductory Gemini Carbon/Argon and GPT-5.6 Sol rates expire on December 1 UTC.
Scheduled DeepSeek and OpenRouter rates remain unknown when their conditions
cannot be represented accurately. Model discovery and account access remain
separate from catalog metadata. See [provider compatibility](PROVIDER_COMPATIBILITY.md#model-prices-and-limits)
for sources, rates and protocol details.

## Questions and evidence

The system instructions require `ask_user` for genuine questions, clarifications
and required user choices, including when **Allow everything** is enabled. The
permission mode governs tool approval; it does not answer a missing user decision.
Unanswered or dismissed questions explicitly supply no answer or consent.

Master Vault and goal actions use the existing tool families and permission checks.
Read-only workers can retrieve relevant knowledge without acquiring vault writes.
Notes remain historical evidence: current user instructions and observations take
precedence. A note's verified status records attributed evidence, not an automatic
guarantee about the current game.

## Verification and release artifacts

The verification record is [TESTING_4.0.0.md](TESTING_4.0.0.md). All validation for
this release uses external tests: offline behavior harnesses, deterministic artifact
checks, the official Luau compiler and local bridge/desktop checks. There is no
in-game validation, so rendering, native input, executor behavior and live server
effects remain outside the evidence.

| Artifact | Purpose |
| --- | --- |
| `dist/uai.lua`, `dist/uai.manifest.json` | Native client and deterministic module/build metadata |
| `dist/uai-bridge-package.json`, `dist/bridge-release.json` | Bridge package and updater metadata |
| `desktop/release/UAI-Bridge-4.0.0-win-x64.exe` and its SHA-256/release manifest | Windows launcher with the matching client and bridge embedded |
| `vault/` in the source archive | Reviewed starter Markdown and supporting examples |
| `mods/` in the source archive | Portable visual and script examples, staged disabled on import |
| Existing UI LIB artifacts | Independently versioned 1.6.0 library |

Providers, permission rules, conversations, Code documents and user files retain
their formats. Goals are an optional versioned addition to conversation records.
Vault and UI mod storage have protected client directories; changed builds wait
for outstanding writes/callbacks and unfinished editor forms. Master Vault remains
separate from the existing bridge-backed Obsidian folders.
