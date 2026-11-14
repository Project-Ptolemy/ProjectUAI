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
