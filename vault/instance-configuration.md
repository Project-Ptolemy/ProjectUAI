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
