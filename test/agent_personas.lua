-- Persona selection is presentation guidance, never an execution policy.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("4.0.5 personas and Ponytail")
local case, check = suite.case, suite.check
local function has(text, value) return tostring(text):find(value, 1, true) ~= nil end

case("one bounded catalogue supplies detached choices and safe fallback", function()
	local f = F.new(); local personas = f.env.require("runtime/personas")
	local options, seen = personas.options(), {}
	check("nine distinct speaking styles are available", #options == 9)
	for _, option in ipairs(options) do
		check("each choice has an exact ID and readable preview", not seen[option.value]
			and personas.valid(option.value) and #option.label > 0 and #option.description > 0 and #option.sample > 0)
		seen[option.value] = true
	end
	options[2].label, options[2].sample = "Changed", "Changed"
	local entry = personas.get("femboy"); entry.instruction = "Changed"
	check("callers cannot change catalogue or prompt data", personas.options()[2].label == "Femboy"
		and not has(personas.prompt("femboy"), "Changed"))
	for _, value in ipairs({ false, {}, "unknown", "Femboy", "\nInjected instructions" }) do
		check("invalid stored styles fall back without becoming instructions", not personas.valid(value)
			and personas.get(value).value == "uai" and personas.prompt(value) == nil)
	end
	check("the standard voice adds no style payload", personas.prompt("uai") == nil)
	f.healthy(); f.close()
end)

case("main and delegated agents share Ponytail and the selected style", function()
	local f = F.new(); local config = f.env.require("runtime/config")
	local prompt, personas = f.env.require("agent/prompt"), f.env.require("runtime/personas")
	f.env.context.prompt = "Host: preserve the dock controller."
	config.set("agent.customInstructions", "Keep my replies calm and formal.")
	config.set("agent.replyLanguage", "Spanish")
	for _, option in ipairs(personas.options()) do
		config.set("agent.persona", option.value)
		check("every persona keeps unscoped standing instructions within budget",
			#prompt.build() < 12000 and #prompt.subagent("Inspect the source") < 12500)
		for _, text in ipairs({ prompt.build({ tools = {}, model = "fixture-model" }),
			prompt.subagent("Inspect the dock", { tools = {}, model = "fixture-worker" }) }) do
			check("Ponytail remains a complete coding workflow", has(text, "Ponytail workflow (UAI)")
				and has(text, "smallest change that fully solves") and has(text, "affected callers, tests, fixtures, config and exports")
				and has(text, "Preserve security, validation, error handling, data, accessibility")
				and has(text, "Review inputs, build, inspect outputs, then verify"))
			local personaAt = text:find("Persona: " .. option.label, 1, true)
			check("selection controls the shared standing style", option.value == "uai" and not has(text, "Persona:")
				or option.value ~= "uai" and personaAt ~= nil and personaAt < text:find("Environment:", 1, true))
			check("language, instructions and permissions stay authoritative", has(text, "Write replies in Spanish")
				and has(text, "Permission mode: full") and has(text, "Use only the model identity supplied")
				and has(text, "override workflow/style defaults, not tool permissions")
				and text:find("Keep my replies calm and formal.", 1, true) > (personaAt or 0))
		end
	end
	local chat = prompt.chat({ tools = {}, instructions = "Answer in the operator's own pirate voice." })
	check("public chat retains its independent operator brief", not has(chat, "Persona:") and not has(chat, "Ponytail workflow")
		and has(chat, "operator's own pirate voice"))
	f.healthy(); f.close()
end)

case("legacy imports default safely and Cowork validates exact persona IDs", function()
	local f = F.new(); local config = f.env.require("runtime/config")
	local util, transfer = f.env.require("runtime/util"), f.env.require("runtime/config_transfer")
	local snapshot = util.deepCopy(config.defaults); snapshot.agent.persona = nil
	check("older configuration remains compatible", assert(transfer.validate(snapshot)).agent.persona == "uai")
	snapshot.agent.persona = "femboy"
	check("configuration transfers preserve selected styles", assert(transfer.validate(snapshot)).agent.persona == "femboy")
	snapshot.agent.persona = "unknown"
	check("unknown imported styles are rejected", transfer.validate(snapshot) == nil)
	local commands = f.env.require("net/bridge_commands")
	commands.run({ type = "setting", path = "agent.persona", value = "gremlin" })
	check("Cowork writes the same native setting", config.get("agent.persona") == "gremlin")
	local ok = pcall(commands.run, { type = "setting", path = "agent.persona", value = "unknown" })
	check("invalid Cowork choices preserve prior selection", not ok and config.get("agent.persona") == "gremlin")
	local results = f.env.require("runtime/settings_catalog").search("femboy")
	check("persona search finds the native control", results[1] and results[1].path == "agent.persona")
	f.healthy(); f.close()
end)

case("native picker previews choices and follows external changes without losing drafts", function()
	local f = F.ui(900, 650); local config = f.env.require("runtime/config")
	local dialog = assert(f.env.require("ui/panels/settingsdialog").open("agent")); f.h.settle(0.4)
	local field = assert(f.h.byName("CustomInstructions")):FindFirstChildWhichIsA("TextBox")
	field.Text = "An unsaved custom instruction"
	f.h.click(assert(f.h.byName("Select_AgentPersona"))); f.h.settle(0.2)
	f.h.click(assert(f.h.byName("Option_femboy"))); f.h.settle(0.2)
	check("native selection updates the saved value and example", config.get("agent.persona") == "femboy"
		and has(f.h.byName("AgentPersonaPreview").Text, "uwu"))
	config.set("agent.persona", "goth"); f.h.settle(0.2)
	local control = assert(f.h.byName("Select_AgentPersona"))
	local selected = false
	for _, child in ipairs(control:GetDescendants()) do
		if child:IsA("TextLabel") and child.Text == "Goth" then selected = true end
	end
	check("external changes keep the picker and preview in sync", selected and has(f.h.byName("AgentPersonaPreview").Text, "buried"))
	check("changing style preserves the native field and its draft", f.h.byName("CustomInstructions"):FindFirstChildWhichIsA("TextBox") == field
		and field.Text == "An unsaved custom instruction")
	dialog.close(); f.h.settle(0.3); f.healthy(); f.close()
end)

suite.finish()
