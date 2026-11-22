-- Export real production schemas for the Node adapter's credential-free test.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local f = require("workspace_fixture").new()
local declarations = f.env.require("provider/openai").opencodeTools
io.write(f.h.json.encode(declarations))
f.healthy()
f.close()
