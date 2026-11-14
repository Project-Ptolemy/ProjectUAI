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
