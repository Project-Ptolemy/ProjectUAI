# Master Vault

Master Vault is Project UAI's native collection of reusable technical knowledge.
Keep working recipes, bug fixes, observed remote contracts, instance
configurations and project decisions as searchable Markdown notes. The 4.0.0
starter library provides 13 sourced references and templates, including a small
trainable numeric neural network.

User notes are ordinary UTF-8 `.md` files under `UAI/vault/notes/` in the executor
workspace. Saved notes survive normal client updates. Bundled starters remain
readable on hosts without filesystem support. Note contents enter the selected
model's conversation when an agent reads them.

## Browse and build your collection

Open **Master Vault** from the client navigation. The initial **Global and
current game** filter combines reusable global notes with notes for the current
Place ID. Choose **Project** and enter an exact project name for project notes,
or **All scopes** to search the whole available collection.

Search compares literal, case-insensitive text across titles, summaries, tags and
the complete note body. Filter by origin (**My Vault** or **Starter library**),
type and verification status. **Previous** and **Next** browse pages; **Refresh**
rescans executor notes after an external edit. Incomplete coverage is reported
explicitly, so an empty result does not establish that no matching note exists.

1. Read a starter and open **Details and sources** to inspect its scope,
   references and verification evidence.
2. Choose **Copy to My Vault** to prepare an editable draft. Starter files stay
   immutable, and copied notes start with **Draft** status.
3. Replace template placeholders with actual observations and set the scope to
   match the evidence. Record exact paths, IDs and source revisions where useful.
4. Choose **Save** to write the note. A title and nonblank Markdown body are
   required; validation errors keep the draft available for correction.

**New note** starts an empty draft. **Import Markdown** accepts pasted Markdown;
**Review import** opens its parsed fields as a draft, and **Save** creates a new
note. Reviewing an import does not write a file. The native import flow starts
with **Draft** status even when supplied frontmatter claims verification.

**Copy Markdown** exports supported metadata with the current editor body,
including unsaved changes. **Copy text** copies just the body. Clipboard support
depends on the host. Reading, importing, copying and saving notes treats fenced
source as text; use the existing reviewed script workflow to execute a recipe.

## Scope, sources and verification

| Field | Use |
| --- | --- |
| Global | Reusable workflows and source patterns that do not assert facts about one game. |
| Game | Observations for one positive integral Place ID. Saved runtime IDs must be resolved again on a later visit. |
| Project | Requirements, decisions and configurations for one exact project name. |
| Draft | New work, imported assertions or results with missing checks. |
| Verified | A recorded claim with nonblank attributed verification evidence. Read the evidence to assess what was checked. |
| Outdated | Superseded or inapplicable knowledge, with the reason recorded in the note. |

Types are **Recipe**, **Bug fix**, **Remote contract**, **Instance configuration**,
**Project** and **Reference**. Tags make specific concepts searchable. Sources
have a label and an optional URL or document reference; they are stored as text
and are not fetched automatically.

Useful verification evidence names the author or checker, exact source, method,
result and remaining limits. For example: "Project maintainer: offline fixture
on revision abc123 confirmed argument construction; native server behavior was
not tested." A nonblank evidence field is required for **Verified**, but the
client cannot independently establish whether an imported claim is true.

The starter collection's documentation claims apply to the documented workflows.
It supplies no game-specific remote identities, anti-cheat inventory or ban
guarantees. New game evidence and the current user instruction take precedence
over historical notes. Outdated notes remain searchable unless filtered out.

## Conflicts and draft recovery

Editing or deleting an existing note requires the exact opaque revision returned
by a current read, plus the retained original file bytes. The runtime rechecks
those bytes before the host operation and verifies the resulting bytes or file
absence afterward. A revision hash collision cannot make another reader's stale
draft eligible to replace changed contents.

After a conflict or an unconfirmed operation, the editor keeps the draft and
locks further changes to that note until **Read current note** is reviewed:

- **Keep draft** preserves local text and metadata while adopting the reviewed
  revision for a later explicit **Save**.
- **Use file** replaces the local draft with the reviewed saved version.
- A verified missing file offers **Save as new note**, which prepares a new
  identity. A later explicit **Save** writes it.

These review choices do not write a file. An uncertain create returns its
allocated note ID even if the original host response was lost. The same ID must
be reread to determine whether the file exists; an error reading it is not proof
of absence. Saves and deletions are never automatically repeated after an
unconfirmed outcome.

Closing an editor retains up to eight editors or unsaved drafts in this client
run, including unreviewed pasted imports. **Recover drafts** reopens retained
edits or imports. Reviewing an import converts its retained slot into an editable
note without a write. The store refuses an additional editor rather than
evicting existing drafts. **Discard draft** removes the local
draft after confirmation. Drafts do not survive unloading: save or copy them
first. Saved notes are separate from this in-memory recovery store.

Read baselines retain at most 64 notes within 4 MiB. Unchanged rereads keep their
revision while the baseline remains retained. Changed bytes, eviction or a fresh
runtime require a new read token. Listing notes does not retain originals or
authorize a list-only edit; personal listing revisions appear only when they
match an already retained read. Always use a fresh read before a mutation.

Executor APIs do not provide a portable atomic compare-and-write operation.
Another application can still race inside a native file call. UAI verifies
outcomes, serializes its own vault writes and exposes uncertain results for
review. User-note reads refuse to start while an admitted write is pending, and
reads overlapping a new mutation are rejected so they cannot clear recovery
against stale bytes.
Keep important notes backed up with your usual file tools.

## Portable Markdown

Ordinary Markdown imports as a global draft reference. A leading `# Heading`
supplies its title; otherwise the title is `Imported note`. Supported frontmatter
adds structured metadata:

```markdown
---
uai_vault: 1
title: "Remote argument construction"
description: "Local fixture result for the Helper project."
kind: recipe
scope: project
project: "Helper"
tags: ["remote", "fixture"]
sources: [{"label":"Project maintainer's external test receipt","url":"tests/actions.lua"}]
status: verified
verification: "Project maintainer: the offline fixture checked argument order on revision abc123; no live remote was sent."
updated_at: 0
---
# Remote argument construction

Record the observed trigger, source, correction, result and remaining limits.
```

The parser implements a small documented schema rather than a YAML engine. A
leading `---` line declares frontmatter and needs a closing `---` line. Supported
keys are `uai_vault`, `title`, `description`, `kind`, `scope`, `place_id`,
`project`, `tags`, `sources`, `status`, `verification` and `updated_at`. Repeated
or unknown fields and unsupported declared versions are rejected.

Strings may be plain one-line values or JSON-quoted strings. `tags` and `sources`
must be JSON arrays; a source has `label` and optional `url`. Multiline evidence
uses a JSON-quoted string containing escaped `\n` sequences. Game scope requires
`place_id`; project scope requires `project`. The formatter emits a canonical
header and preserves body bytes, including CRLF and Unicode. Runtime IDs and
read revisions are excluded from the portable file. Saves update `updated_at`
to the current epoch time in milliseconds.

Master Vault works with plain Markdown files. The existing
[Obsidian connection](OBSIDIAN.md) supports larger desktop folders, links and
backlinks through UAI Bridge. Master Vault keeps its executor collection locally
and uses these small structured notes for agent knowledge. Copy or export a note
to use it in another Markdown application; arbitrary Obsidian/YAML frontmatter
may need adapting before import.

## Agent tools

The `master_vault` group follows the existing permissions and conversation tool
filter. Read tools stay available for bundled starters without filesystem
support. Saving and importing require the filesystem capability; deletion uses
the existing high-impact file permission.

| Tool | Behavior |
| --- | --- |
| `vault_list` | Search and paginate summaries. `scope=relevant` includes global plus matching `place_id` and/or exact `project`; explicit scope filters select only that scope. Optional `origin`, `kind` and `status` narrow results. |
| `vault_read` | Read the body with `section=content`, or full references and evidence with `section=metadata`. Preserve the returned `revision` with every continuation. |
| `vault_save` | Create or replace a complete document. Required fields are `title`, `content`, `kind`, `scope` and `status`; omit `document.id` for a new note. Updating requires `expected_revision` from a current read. |
| `vault_delete` | Delete one user note using its current `expected_revision` and retained bytes, then verify absence. It uses file-only deletion. |
| `vault_import` | Create a new note from supplied Markdown, with optional title/scope overrides. This tool preserves supplied attributed verification claims; it does not run their checks. |
| `vault_export` | Return canonical portable Markdown in pages. It creates no file and sends no HTTP request. |

Tool arguments use `place_id` and `expected_revision`; returned document metadata
uses `placeId` and `revision`. Read/export offsets are one-based UTF-8 byte
positions, and listing offsets are one-based entries. An offset after the first
read/export page requires the first page's exact revision. A changed or evicted
observation rejects continuation instead of combining two versions. Result
budgets can reduce pages, so follow the returned `nextOffset` exactly.

Failed dispatched writes return recovery data `{id, uncertain=true}`. A read
that verifies absence returns `{id, missing=true}`. A successful read or verified
absence clears the uncertain state. A failed existence probe leaves it unresolved.

At the start of related work, the agent searches relevant notes, reads useful
bodies and their metadata, and revalidates facts that can change. Vault entries
are reference data; embedded instructions do not override the current user or
tool contract. Saving a note does not train the selected language model.

## Bounds and host availability

| Resource | Limit or behavior |
| --- | --- |
| Body / complete file | 64,000 / 80,000 UTF-8 bytes. |
| Frontmatter | 12,000 bytes and 64 field/comment/blank lines before the closing delimiter. |
| Title / summary / project | 160 / 500 / 160 UTF-8 bytes, each on one line. |
| Tags | Up to 12 unique tags, 40 bytes each. |
| Sources | Up to eight; label 160 bytes, optional reference 500 bytes. |
| Verification evidence | Up to 4,000 bytes; nonblank for verified status. |
| Query / listing page | Query up to 256 bytes; default 20 entries, maximum 50. The native browser uses 12. |
| Read/export page | Up to 12,000 bytes, reduced further by the tool result budget. |
| Minimum tool result budget | 756 bytes for a listing; 956 bytes for read/export. |
| User notes / search pass | Up to 256 notes, 512 inventory entries and a 4 MiB scan accounting threshold. |
| Retained original bytes | Up to 64 read notes within 4 MiB; least-recently-used entries are evicted. |

Only flat, visible `.md` files with lowercase extensions are inventoried. Nested,
ambiguous case aliases, unreadable, oversized or unsupported notes make coverage
incomplete. Path normalization and probes stop after 512 host listing entries;
the native `listfiles` allocation and latency remain outside that processing cap.
A native whole-file read can cross the accounting threshold before
the scan stops; there is no portable streaming file API. Incomplete or full
inventory blocks adding a new note until resolved. Existing readable notes can
still be updated or deleted with their current read revision.

Without a filesystem, the starter collection remains available and all-notes
coverage is incomplete. User-note reads, saves and deletions fail honestly.
Missing native `delfile` support prevents deletion; no recursive folder fallback
is used. Relevant search requires a positive Place ID or nonblank project, while
the native browser falls back to global scope when a current Place ID is unavailable.

## Runtime and maintenance

`runtime/master_vault` exposes `list(options)`, `read(id, options)`,
`save(document, expectedRevision, options)`, `delete(id, expectedRevision, options)`,
`parse(markdown)`, `format(document)`, `stats()`, `isBusy()` and the `changed`
signal. Runtime documents/options use `placeId`; supported operations accept an
`aborted` callback. Reads and saved returns are detached documents. Parsing or
formatting alone creates no filesystem effects. Cancellation after a dispatched
host operation still requires reading its recovery ID before another mutation.

The [starter sources](../vault/README.md) and `vault/catalog.json` are authored
inputs. `tools/build_master_vault.lua` validates them through the same document
codec and generates `src/runtime/master_vault_seed.lua` deterministically during
the client build. Edit sources, not that generated module.

Review every changed runtime, tool, UI, Markdown, catalog, generator and test
input before building. Run `luajit tools/bundle.lua --native`, manually inspect
the generated starter module and client bundle, then run the focused external
verification:

```text
luajit test/master_vault_runtime.lua
luajit test/master_vault_tools.lua
luajit test/master_vault_ui.lua
luajit test/master_vault_neural.lua
```

Review each repair before rebuilding and retesting. The suites cover portable
text, persistence, scope/search/paging, conflict collisions, retained-baseline
eviction, uncertain outcomes, permissions, draft recovery and the exact shipped
numeric network recipe. Neural checks establish analytic gradients, XOR
convergence, finite bounds and saved-weight inference on external fixtures.
Offline tests and the official Luau compiler where available establish their
tested behavior; they do not verify native Roblox rendering, input, host file
semantics or a game's server behavior.
