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
