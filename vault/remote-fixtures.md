---
uai_vault: 1
title: "Test remote-dependent logic with local fixtures"
description: "Inject a small transport interface so argument construction can be checked without live sends."
kind: recipe
scope: global
tags: ["remote", "fixtures", "tests"]
sources: [{"label":"Behavioral project tests and fixtures","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/SCRIPT_PROJECTS.md#review-build-and-test"},{"label":"Observed remote requirements","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/SCRIPT_DEVELOPMENT.md#environment-model"}]
status: verified
verification: "Documentation recipe reviewed for Project UAI 4.0.0; the fixture checks local argument construction, not a game's server contract."
---
# Test remote-dependent logic with local fixtures

Separate your domain logic from a live remote. Accept a transport callback and
construct arguments as ordinary data. The example action label is fixture data,
not a known command supported by any game.

`actions.lua`:

```lua
local M = {}
function M.submit(send, action, amount)
	assert(type(send) == "function", "transport required")
	assert(type(action) == "string" and action ~= "", "action required")
	assert(type(amount) == "number" and amount == amount
		and amount > 0 and amount < math.huge, "positive finite amount required")
	return send(action, amount)
end
return M
```

`tests/actions.lua`:

```lua
local actions = require("actions")
return {
	constructs_arguments = function(t, fixtures)
		local calls, observed = 0, nil
		local result = actions.submit(function(action, amount)
			calls = calls + 1
			observed = { action, amount }
			return "fixture-result"
		end, fixtures.action, 2)
		t.equal(calls, 1)
		t.equal(observed[1], fixtures.action)
		t.equal(observed[2], 2)
		t.equal(result, "fixture-result")
	end,
	rejects_invalid_amount = function(t)
		t.raises(function()
			actions.submit(function() error("must not dispatch") end, "fixture-action", 0)
		end, "positive finite amount")
	end,
}
```

Declare both modules and the test module in `uai.project.json`. Review their
source, analyze/build the project, inspect generated output, then run only the
relevant test with a fixture such as `{"action":"fixture-action"}`.

The fake callback above records only local data. It never calls `FireServer` or
`InvokeServer`. An arbitrary project test still shares the native client and is
not a security sandbox; inspect discovery and module initialization for effects.
Passing this fixture proves local call construction for its inputs. It does not
establish a real remote's server validation, rate limits, ownership or outcome.
