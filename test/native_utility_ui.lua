-- Recovery and release utilities keep native focus and honest clipboard behavior.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Native utility UI")
local case, check = suite.case, suite.check

case("release search filters cards and latest copy stays complete", function()
	local f = F.ui(430, 700)
	local modal = assert(f.env.require("ui/changelog").show())
	f.h.settle(0.3)
	local search = f.h.byName("ReleaseSearch"):FindFirstChildWhichIsA("TextBox")
	search.Text = "no-such-release-phrase"
	check("empty search is visible", f.h.byName("ReleaseSearchCount").Text == "No matching releases.")
	f.h.click(f.h.byName("CopyLatestRelease"))
	local latest = f.env.require("runtime/changelog").latest()
	check("copy includes version and title independent of search", f.h.sandbox.__clipboard:find(latest.version, 1, true)
		and f.h.sandbox.__clipboard:find(latest.title, 1, true))
	local complete = true
	for _, section in ipairs(latest.sections) do
		if not f.h.sandbox.__clipboard:find(section.label or section.category, 1, true) then complete = false end
		for _, item in ipairs(section.items) do
			if not f.h.sandbox.__clipboard:find(item, 1, true) then complete = false end
		end
	end
	check("copy includes every latest section and change", complete)
	f.h.click(f.h.byName("ClearReleaseSearch"))
	check("clear restores release cards", f.h.byName("Release_" .. latest.version).Visible)
	modal.close(); f.h.settle(0.2); f.healthy(); f.close()
end)

case("password Enter moves to confirmation and reveal hides on focus loss", function()
	local f = F.ui(430, 700)
	local modal = assert(f.env.require("ui/credentialvault").open("setup"))
	f.h.settle(0.3)
	local first = f.h.byName("VaultPassword"):FindFirstChildWhichIsA("TextBox")
	local confirm = f.h.byName("VaultConfirmPassword"):FindFirstChildWhichIsA("TextBox")
	first.Text = "synthetic test passphrase"
	first:CaptureFocus(); first:ReleaseFocus(true)
	check("enter focuses confirmation without dispatch", f.env.uis:GetFocusedTextBox() == confirm and not modal.operationPending)
	first:CaptureFocus(); first.CursorPosition, first.SelectionStart = 6, 2
	f.h.click(f.h.byName("VaultPasswordShow"))
	check("show preserves selection", first.TextTransparency == 0 and first.CursorPosition == 6 and first.SelectionStart == 2)
	f.env.uis.WindowFocusReleased:Fire()
	check("leaving the app remasks password", first.TextTransparency == 1)
	modal.close(true); f.h.settle(0.2); f.healthy(); f.close()
end)

case("hiding a window releases only input owned by that window", function()
	local f = F.ui()
	local window = f.env.require("ui/window").new(f.host)
	local P = f.env.require("ui/primitives")
	local field = P.field(window.body, { text = "Draft retained" })
	window.show(); field.focus(); f.env.guisvc.SelectedObject = field.instance
	window.hide()
	check("hidden window releases native input", f.env.uis:GetFocusedTextBox() == nil and f.env.guisvc.SelectedObject == nil)
	check("hiding keeps the draft", field.get() == "Draft retained")
	window.show()
	local other = P.field(f.host, { text = "Another surface" }); other.focus()
	window.hide()
	check("other surfaces retain their focus", f.env.uis:GetFocusedTextBox() == other.instance)
	window.destroy(); f.host:Destroy(); f.h.settle(0.2); f.healthy(); f.close()
end)

suite.finish()
