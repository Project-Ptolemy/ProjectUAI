-- Content modals fit native measurements and keep readable insets on every side.
-- The offline mock does not solve AutomaticSize: publish list measurements as
-- Roblox would, then exercise the real modal fitting and application callers.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Modal content layout")
local check, case = suite.check, suite.case

local surfaces = {
	{ name = "Discord", open = function(f) return f.env.require("ui/community").open() end, inset = "CommunityCard" },
	{ name = "Tutorial", open = function(f) return f.env.require("ui/tutorial").open().modal end },
	{ name = "Donation", open = function(f)
		f.env.require("ui/app").donate()
		local overlays = f.env.require("ui/overlay").open
		return overlays[#overlays]
	end, inset = "DonationOptions" },
	{ name = "Context", open = function(f)
		return f.env.require("ui/chat/context").open(f.env.require("agent/session").current())
	end },
	{ name = "Master Vault editor", workspace = true, open = function(f)
		return f.env.require("ui/vault_editor").open({ title = "Workspace note", content = "A reusable local reference." })
	end },
	{ name = "Micro-goals", workspace = true, open = function(f)
		return f.env.require("ui/goals").open(f.env.require("agent/session").current())
	end },
	{ name = "UI mods", workspace = true, open = function(f) return f.env.require("ui/mods").open() end },
}

for _, size in ipairs({ { 1000, 800 }, { 320, 568 }, { 844, 220 } }) do
	for _, surface in ipairs(surfaces) do
		case(surface.name .. " fits content at " .. size[1] .. "x" .. size[2], function()
			local f = F.ui(size[1], size[2])
			local mobile = size[1] ~= 1000
			f.env.uis.TouchEnabled, f.env.uis.MouseEnabled = mobile, not mobile
			local responsive, theme = f.env.require("ui/responsive"), f.env.require("ui/theme")
			responsive.init(f.env.root)
			theme.rebuild()
			local modal = assert(surface.open(f))
			local padding = modal.scroll.instance:FindFirstChildOfClass("UIPadding")
			check("body content has breathing room above and below", padding.PaddingTop.Offset >= theme.space.md
				and padding.PaddingBottom.Offset >= theme.space.md)
			check("body content aligns to inset header edges", padding.PaddingLeft.Offset >= theme.space.lg
				and padding.PaddingRight.Offset >= theme.space.lg)
			if surface.inset then
				local inner = assert(f.h.byName(surface.inset, modal.card)):FindFirstChildOfClass("UIPadding")
				check("the inset card separates text from every edge", inner and inner.PaddingTop.Offset >= theme.space.md
					and inner.PaddingBottom.Offset >= theme.space.md and inner.PaddingLeft.Offset >= theme.space.md
					and inner.PaddingRight.Offset >= theme.space.md)
			end
			local bodyLayout = modal.content:FindFirstChildOfClass("UIListLayout")
			bodyLayout.AbsoluteContentSize = f.h.dt.Vector2.new(240, 160)
			f.h.sched.advance(0.2)
			local shortHeight = modal.card.Size.Y.Offset
			if not mobile then
				check("a short body leaves no reserved empty height", math.abs(modal.scroll.instance.Size.Y.Offset
					- 160 - padding.PaddingTop.Offset - padding.PaddingBottom.Offset) <= 1)
			end
			bodyLayout.AbsoluteContentSize = f.h.dt.Vector2.new(240, 1600)
			f.h.sched.advance(0.2)
			local bounds, position = modal.card.AbsoluteSize, modal.card.AbsolutePosition
			check("overflowing content stays inside the visible viewport", position.X >= 0 and position.Y >= 0
				and position.X + bounds.X <= size[1] + 1 and position.Y + bounds.Y <= size[2] + 1)
			check("long content retains scrolling", modal.scroll.instance.ScrollingEnabled ~= false
				and modal.scroll.instance.Size.Y.Offset < 1600)
			if not mobile and surface.workspace then
				check("workspace forms use the available height for long content", modal.card.Size.Y.Offset > theme.size.modalTall)
			end
			bodyLayout.AbsoluteContentSize = f.h.dt.Vector2.new(240, 160)
			f.h.sched.advance(0.2)
			check("shrinking content releases the extra height", modal.card.Size.Y.Offset == shortHeight)
			modal.close(); f.h.sched.advance(0.2)
			check("closing releases the content modal", #f.env.require("ui/overlay").open == 0)
			f.healthy(); f.close()
		end)
	end
end

case("workspace fitting honors an explicit height ceiling", function()
	local f = F.ui(1000, 800)
	f.env.require("ui/responsive").init(f.env.root)
	local overlay, P = f.env.require("ui/overlay"), f.env.require("ui/primitives")
	local modal = assert(overlay.modal({ title = "Bounded workspace", scroll = true, fitContent = true, height = 260 }))
	P.text(modal.content, { text = "Retained workspace content", auto = "Y" })
	P.button(modal.footer, { text = "Close", onClick = modal.close })
	local layout = modal.content:FindFirstChildOfClass("UIListLayout")
	layout.AbsoluteContentSize = f.h.dt.Vector2.new(240, 1600)
	f.h.sched.advance(0.2)
	check("an explicit ceiling limits a populated workspace form", modal.card.Size.Y.Offset <= 260
		and modal.scroll.instance.Size.Y.Offset > 0 and modal.scroll.instance.Size.Y.Offset < 1600)
	layout.AbsoluteContentSize = f.h.dt.Vector2.new(240, 30)
	f.h.sched.advance(0.2)
	check("short content can shrink below the explicit ceiling", modal.card.Size.Y.Offset < 260)
	modal.close(); f.h.sched.advance(0.2); f.healthy(); f.close()
end)

suite.finish()
