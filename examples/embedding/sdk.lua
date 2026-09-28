-- UI-free executor entry point. Pin the same reviewed revision in this entry URL
-- and its dependency below. Configure a real provider/model before calling ask.
local revision = "main"
local root = "https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/" .. revision .. "/"
local downloaded, source = pcall(function() return game:HttpGet(root .. "dist/uai.lua") end)
assert(downloaded and type(source) == "string", "Could not download UAI: " .. tostring(source))
local chunk, compileError = loadstring(source, "@uai-sdk-example")
assert(chunk, "Could not compile UAI: " .. tostring(compileError))
local uai = chunk({ ui = false, reuse = true })
assert(uai and uai.alive, "UAI did not start; read its console error")
assert(uai.sdk and uai.sdk.features.requests and uai.sdk.features.resourceScopes,
	"Update the client to a build with embedding SDK support")

local scope, scopeError = uai.sdk.createScope("embedding-sdk-example")
assert(scope, scopeError)
local observedEvents, activeRequest = 0, nil
local registered, registerError = scope.registerTool({
	name = "sdk_example_status", group = "sdk_example", risk = "read",
	description = "Read this host SDK example's event count and whether its UAI application is mounted.",
	parameters = { type = "object", properties = {}, required = {} },
	run = function(args, ctx)
		if ctx.aborted() then return { ok = false, text = "Stopped" } end
		return { text = string.format("Observed %d conversation events. UAI application mounted: %s.",
			observedEvents, tostring(uai.uiMounted)),
			data = { observedEvents = observedEvents, uiMounted = uai.uiMounted } }
	end,
})
if not registered then scope.destroy(); error(tostring(registerError)) end
local session, created = uai.sessions.open("embedding-sdk-example", {
	title = "SDK example", ephemeral = true,
	toolFilter = { sdk_example_status = true },
})
if not session then scope.destroy(); error(tostring(created)) end
-- Existing conversations retain their original options. Refuse an unrelated
-- policy instead of assuming the open() options replaced it.
if not session.ephemeral or not session.toolFilter or not session.toolFilter.sdk_example_status then
	scope.destroy()
	error("The example conversation already exists with different settings; choose another ID")
end
for name, allowed in pairs(session.toolFilter) do
	if allowed and name ~= "sdk_example_status" then
		scope.destroy()
		error("The example conversation allows additional tools; choose another ID")
	end
end
scope.connect(session.events, function() observedEvents = observedEvents + 1 end)
scope.give(function() if activeRequest then activeRequest.cancel() end end)

local integration = { client = uai, scope = scope, session = session, created = created }
function integration.ask(text)
	if not scope.alive then return nil, "The example integration was destroyed" end
	local request, why = uai.sdk.request(session, text, {
		onEvent = function(event)
			if event.kind == "status" then print("SDK: " .. tostring(event.text)) end
		end,
		onComplete = function(result)
			if result.ok then print(result.text) else warn(result.error or result.status) end
		end,
	})
	if request then activeRequest = request end
	return request, why
end
function integration.destroy() return scope.destroy() end
return integration
