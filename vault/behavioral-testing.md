---
uai_vault: 1
title: "Write a focused behavioral project test"
description: "Use independent expectations and fixtures, and report exactly which behavior was checked."
kind: recipe
scope: global
tags: ["tests", "fixtures", "verification"]
sources: [{"label":"Behavioral assertions, selection and test limits","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/SCRIPT_PROJECTS.md#review-build-and-test"},{"label":"Review/build/inspect/verify order","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/DEVELOPMENT.md"}]
status: verified
verification: "Testing recipe reviewed for Project UAI 4.0.0; synthetic or fixture checks do not establish native Roblox behavior."
---
# Write a focused behavioral project test

Test an observable requirement using an independent expectation. Do not merely
repeat an implementation's calculations in the test. A configuration default,
an invalid-input refusal, a conflict, or a retained result are useful contracts.

For the `settings` module in the multi-file project recipe:

```lua
local settings = require("settings")
return {
	defaults = function(t, fixtures)
		t.equal(settings.name, fixtures.expectedName)
		t.equal(settings.enabled, false)
	end,
}
```

Save this as `tests/settings.lua`, declare it in the manifest, and pass
`fixtures={"expectedName":"My helper"}`. `t.equal` uses Lua equality rather than
deep table comparison. `t.truthy` checks truthiness and `t.raises` checks an
expected literal error substring.

Review source first. Analyze/build when needed, inspect generated output, then
call `script_test` with the relevant declared modules and a case-sensitive name
filter. A filter matching no cases is a failed incomplete run. Passing selected
cases establishes that selection's coverage; omitted cases were not checked.

Each case gets a fresh project module cache and copied fixture data, but tests
share native client state. Discovery loads module initialization, so inspect it
for effects. Test execution uses managed deadlines and normal high-impact tool
permissions; it is not an isolated process or security sandbox.

Record selected cases, source identity, diagnostics and the actual result. A
source change invalidates the claim that the current saved source passed. An
offline fixture checks local behavior; it does not validate live server state,
Roblox rendering, touch input or executor-specific continuation behavior.
