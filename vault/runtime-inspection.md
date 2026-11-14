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
