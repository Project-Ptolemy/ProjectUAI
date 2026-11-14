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
