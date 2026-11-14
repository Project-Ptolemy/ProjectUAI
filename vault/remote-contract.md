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
