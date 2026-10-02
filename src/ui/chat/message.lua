-- Transcript message renderers.
--
-- Each kind of thing that can appear in a conversation gets its own builder, and
-- each returns a handle so the view can update it later -- a tool call is created
-- when the model asks for it and completed when the result arrives, which means the
-- row has to be mutable rather than a one-shot render.
return function(env)
	local util = env.require("runtime/util")
	local clock = env.require("runtime/clock")
	local config = env.require("runtime/config")
	local theme = env.require("ui/theme")
	local responsive = env.require("ui/responsive")
	local markdown = env.require("ui/markdown")
	local tableBlock = env.require("ui/chat/table")
	local icons = env.require("ui/icons")
	local P = env.require("ui/primitives")
	local C = env.require("ui/controls")
	local usage = env.require("agent/usage")

	-- How many lines of a block are shown before it folds. Generous, because the point
	-- of showing code at all is that it can be read; the fold is for a thousand-line
	-- file, not for a function.
	--
	-- A tool call's listing gets a much tighter one. Sixty lines of Luau between two
	-- paragraphs is the single largest thing in a transcript, and the model writes one
	-- of those per call: a turn that ran four scripts pushed the answer it was working
	-- towards several screens down. Twelve lines is enough to recognise what the call
	-- is doing, and "Show all N lines" is on the block.
	local CODE_LINES = 24
	local ARG_PREVIEW = 90

	-- Average glyph advance for the mono families, as a fraction of the font size.
	-- Used only to size the line-number gutter, which has to be wide enough for the
	-- largest number in the block and is the one width here that cannot come from a
	-- token: it depends on how many lines the block has.
	local MONO_RATIO = 0.62

	local M = {}

	-- Every row spans the reading column.
	--
	-- It used to leave a gutter -- 0.76 of the width for the user, 0.94 for the agent,
	-- the user's turn anchored to the right edge -- which is the chat-app convention of
	-- two speakers facing each other. This is not that: a turn here is a document with
	-- the questions marked in it, so both sides take the full measure and the
	-- difference between them is a fill, not a side. The column itself is what bounds
	-- the line length, and the panel caps that.
	local function wrapper(parent, props)
		return P.frame(parent, {
			name = props.name or "Message",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			layoutOrder = props.layoutOrder or 0,
		})
	end

	-- Shared disclosure states keep keyboard, pointer and touch feedback consistent.
	local function disclosure(header, stroke)
		local hovered, focused, pressed = false, false, false
		header.BorderSizePixel = 0
		header.Active = true
		header.BackgroundTransparency = 1
		stroke.Transparency = 1
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		local tone
		local function paint()
			local active = hovered or focused or pressed
			P.animate(header, pressed and "press" or "hover", {
				BackgroundColor3 = pressed and theme.color.surfaceActive or theme.color.surfaceHover,
				BackgroundTransparency = active and 0 or 1,
			})
			P.animate(stroke, "hover", {
				Color = focused and theme.color.accent or tone or theme.color.borderSubtle,
				Transparency = (focused or tone) and 0 or 1,
			})
		end
		header.MouseEnter:Connect(function() hovered = true; paint() end)
		header.MouseLeave:Connect(function() hovered = false; pressed = false; paint() end)
		header.MouseButton1Down:Connect(function() pressed = true; paint() end)
		header.MouseButton1Up:Connect(function() pressed = false; paint() end)
		header.SelectionGained:Connect(function() focused = true; paint() end)
		header.SelectionLost:Connect(function() focused = false; pressed = false; paint() end)
		return function(value) tone = value; paint() end
	end

	-- A left rule beside a column of wrapped text.
	--
	-- The obvious construction is a row holding a 2px frame sized (0, 2, 1, 0) and a
	-- filling label beside it. That is circular and it does not work: the row is
	-- AutomaticSize.Y, so its height comes from its children, and one of those children
	-- asks for one hundred percent of that height. Roblox excludes scale-sized children
	-- from the measurement, but the UIListLayout's flex pass has already run against an
	-- unsettled height -- which inflates the row and can leave the filling label with no
	-- width at all, so a long message renders as a tall empty box with a coral line down
	-- the side of it.
	--
	-- The holder here has no UIListLayout. The rule is positioned rather than laid out,
	-- nothing measures it, and the text sits in an ordinary column with an explicit
	-- width. Callers get the column.
	local function ruled(parent, props)
		local holder = P.frame(parent, {
			name = props.name or "Ruled",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			layoutOrder = props.layoutOrder,
			bg = props.bg,
			radius = props.radius,
			clip = props.clip,
		})
		if props.strokeColor then P.stroke(holder, props.strokeColor) end
		local width = props.width or theme.stroke.hair
		local body = P.column(holder, {
			name = "Body",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			gap = props.gap or theme.space.xs,
			padding = {
				left = width + (props.inset or theme.space.md),
				right = props.padRight or 0,
				top = props.padY or 0,
				bottom = props.padY or 0,
			},
		})
		P.frame(holder, {
			name = "Rule",
			size = UDim2.new(0, width, 1, 0),
			position = UDim2.new(0, props.ruleAt or 0, 0, 0),
			bg = props.color or theme.color.borderSubtle,
			radius = props.ruleRadius,
			zIndex = 2,
		})
		return body, holder
	end

	-- Code: monospace below the surface of the page, with the language, a line-number
	-- gutter, a copy control and horizontal scrolling.
	--
	-- Three things changed here and each was a real loss of information. Lines wrapped,
	-- so a Luau line past the reading column folded and the indentation of everything
	-- after it read as wrong; there were no line numbers, so an error naming line 40 had
	-- nothing to point at; and anything past the fold was replaced by a dead sentence
	-- saying how much had been hidden, with no way to see it. Code is now what the model
	-- actually wrote, scrolled rather than reflowed, and the fold opens.
	function M.codeBlock(parent, props)
		local caps = env.require("runtime/caps")
		local lines = util.lines(props.text)
		if #lines == 0 then lines = { "" } end
		local numbered = props.numbers ~= false
		local role = theme.textRole("mono")
		-- Looser than the rest of the mono text, and the one number in here that both
		-- labels and the row height have to agree on: the gutter is a separate label
		-- from the code, so a line height that is not shared puts number 11 beside line
		-- 9. Everything below reads `codeLine`; nothing recomputes it from the role.
		local codeLine = theme.line.code
		local lineHeight = math.ceil(role.size * codeLine)
		-- Air inside the block, on all four sides, and one number per axis.
		--
		-- It used to be neither. The vertical inset was a token here and the horizontal
		-- one was an accident of two other measurements: the left came out of the gutter's
		-- own width, which baked twelve pixels of margin into a column sized for digits,
		-- and the right came from padding on the scroll viewport. So the two edges never
		-- agreed with each other, the language bar above them agreed with neither, and a
		-- block with no gutter -- a result, a raw JSON envelope -- had its first character
		-- sitting on the border. Both axes are one padding on the body row now, the bar
		-- shares the horizontal one, and the gutter is only as wide as its digits plus the
		-- gap to the code.
		local padY = theme.space.md
		local padX = theme.space.lg

		local card = P.column(parent, {
			name = "Code",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			bg = theme.color.codeSurface,
			radius = theme.radius.md,
			gap = 0,
			layoutOrder = props.layoutOrder,
			clip = true,
		})
		P.stroke(card, theme.color.codeBorder)

		local bar = P.row(card, {
			name = "Bar",
			-- Match the actual copy button height, including the hit-target minimum.
			size = UDim2.new(1, 0, 0, math.max(theme.size.controlSmall, responsive.minTarget())),
			bg = theme.color.codeBar,
			gap = theme.space.xs,
			-- The same left inset the gutter gets, so the language names the column of code
			-- underneath it rather than floating four pixels to the left of it. The right is
			-- tighter because what sits there is a round ghost button with its own padding,
			-- and padX again would push it off the block's corner.
			padding = { left = padX, right = theme.space.xs },
			layoutOrder = 1,
		})
		local language = P.text(bar, {
			name = "Language",
			text = (props.label and (props.label .. " · ") or "")
				.. (props.lang and props.lang:lower() or "code") .. (props.unterminated and " (incomplete)" or ""),
			role = "caption",
			color = theme.color.codeGutter,
			-- Fill the space left by the actual copy button width.
			size = UDim2.new(0, 0, 1, 0),
			flex = "Fill",
			truncate = true,
			layoutOrder = 1,
		})
		-- What is in the block, on the right of its own bar. A line count is the one
		-- fact about a block of code that is worth reading before the code itself.
		local meta = P.text(bar, {
			name = "Meta",
			text = props.meta or util.pluralise(#lines, "line"),
			role = "caption",
			color = theme.color.codeGutter,
			align = "Right",
			auto = "X",
			layoutOrder = 2,
		})

		local copy
		if caps.clipboard then
			copy = P.button(bar, {
				name = "Copy",
				icon = "copy",
				text = "Copy",
				size = "sm",
				tight = true,
				variant = "code",
				iconColor = theme.color.codeGutter,
				layoutOrder = 3,
				onClick = function(handle)
					local ok, copied = pcall(caps.fn.clipboard, props.text)
					ok = ok and copied ~= false
					handle.setText(ok and "Copied" or "Retry")
					if not ok then env.require("ui/overlay").toast("Could not copy this code", "bad", 3) end
					clock.delay(2, function()
						if handle.instance.Parent then handle.setText("Copy") end
					end)
				end,
			})
			copy.instance.LayoutOrder = 3
		end
		local function fitBar()
			local copyWidth = copy and math.max(copy.instance.AbsoluteSize.X, responsive.minTarget()) or 0
			local wanted = math.min(theme.size.keyColumn, P.measureText(language.Text, { role = "caption" }).X)
				+ P.measureText(meta.Text, { role = "caption" }).X + copyWidth + padX + theme.space.xs * 3
			meta.Visible = bar.AbsoluteSize.X >= wanted
		end
		bar:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitBar)
		if copy then copy.instance:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitBar) end
		fitBar()

		-- Body. The gutter is outside the scroll so it stays put while the code moves,
		-- which is the whole reason a sticky gutter is worth the extra frame.
		local bodyScroll = { instance = P.frame(card, {
			name = "CodeScroll",
			size = UDim2.new(1, 0, 0, 0),
			gap = 0,
			bg = theme.color.codeSurface,
			layoutOrder = 2,
		}) }
		local bodyRow = P.row(bodyScroll.instance, {
			name = "Body",
			size = UDim2.new(1, 0, 0, 0),
			gap = 0,
			alignY = "Top",
			padding = { left = padX, right = padX, top = padY, bottom = padY },
			layoutOrder = 2,
		})

		local gutter, gutterLabel
		local gutterWidth = 0
		if numbered then
			-- Wide enough for the largest number in this block, plus the gap to the code
			-- beside it. It is the one width in here that cannot come from a token, because
			-- it depends on how many lines there are; the ratio is what keeps it in step
			-- with the text scale, and the gap is a token because it is a gap.
			gutterWidth = math.ceil(#tostring(#lines) * role.size * MONO_RATIO) + theme.space.md
			gutter = P.frame(bodyRow, {
				name = "Gutter",
				clip = true,
				size = UDim2.fromOffset(gutterWidth, 0),
				layoutOrder = 1,
			})
			gutterLabel = P.text(gutter, {
				name = "Numbers",
				text = "",
				role = "mono",
				line = codeLine,
				color = theme.color.codeGutter,
				align = "Right",
				alignY = "Top",
				size = UDim2.new(1, -theme.space.md, 1, 0),
			})
		end

		local viewport = P.scroll(bodyRow, {
			name = "Viewport",
			horizontal = true,
			size = UDim2.new(0, 0, 1, 0),
			flex = "Fill",
			gap = 0,
			bar = theme.size.scrollbar,
		})
		viewport.instance.ScrollingDirection = Enum.ScrollingDirection.XY
		viewport.instance.AutomaticCanvasSize = Enum.AutomaticSize.XY
		viewport.instance.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
		viewport.instance:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			if gutterLabel then
				gutterLabel.Position = UDim2.fromOffset(0, -viewport.instance.CanvasPosition.Y)
			end
		end)
		-- Not wrapped, and sized from the text: that is what makes the gutter line up
		-- with the code beside it. A wrapped body puts two visual lines against one
		-- number, and every number below it is then wrong.
		local body = P.text(viewport.instance, {
			name = "Source",
			text = "",
			rich = true,
			role = "mono",
			line = codeLine,
			color = theme.color.codeText,
			alignY = "Top",
			size = UDim2.new(0, 0, 1, 0),
			auto = "X",
		})

		local expanded = false
		local foldRow
		-- Where this block folds. A reply's code gets the generous default; a tool
		-- call's listing passes its own, because there are several of them per turn.
		local foldAt = math.max(tonumber(props.maxLines) or CODE_LINES, 1)

		local function paint()
			local shown = lines
			if not expanded and #lines > foldAt then
				shown = util.slice(lines, 1, foldAt)
			end
			body.Text = markdown.highlight(table.concat(shown, "\n"), props.lang)
			if gutterLabel then
				local numbers = {}
				for index = 1, #shown do numbers[index] = tostring(index) end
				gutterLabel.Text = table.concat(numbers, "\n")
			end
			local height = #shown * lineHeight
			local fullHeight = height + padY * 2 + theme.size.scrollbar
			local mobile = responsive.isMobile()
			local room = mobile and responsive.usableRect(env.root, 0).height or responsive.viewport.Y
			local minHeight = lineHeight * 4
			local capHeight = math.max(minHeight,
				math.min(theme.size.codeViewport, room * 0.45))
			local visibleHeight = math.min(fullHeight, capHeight)
			bodyRow.Size = UDim2.new(1, 0, 0, visibleHeight)
			bodyScroll.instance.Size = UDim2.new(1, 0, 0, visibleHeight)
			viewport.instance.Size = UDim2.new(0, 0, 0, visibleHeight - padY * 2)
			body.Size = UDim2.fromOffset(0, height + theme.size.scrollbar)
			if gutter then
				gutter.Size = UDim2.fromOffset(gutterWidth, visibleHeight - padY * 2 - theme.size.scrollbar)
				gutterLabel.Size = UDim2.new(1, -theme.space.md, 0, height)
			end
			if foldRow then
				foldRow.setText(expanded
					and "Show less"
					or string.format("Show all %s", util.pluralise(#lines, "line")))
			end
		end

		if #lines > foldAt then
			foldRow = P.button(card, {
				name = "Fold",
				-- Given its text up front, because P.button only builds a label when it
				-- has one to put in it -- an empty string leaves setText with nothing to
				-- write to.
				text = string.format("Show all %s", util.pluralise(#lines, "line")),
				variant = "code",
				size = "sm",
				fill = true,
				align = "Left",
				-- Starts where the code above it starts. On the button's own default inset
				-- the control read as belonging to the card's edge rather than to the
				-- listing it opens.
				padX = padX,
				radius = theme.radius.none,
				layoutOrder = 3,
				onClick = function()
					expanded = not expanded
					viewport.instance.CanvasPosition = Vector2.new(0, 0)
					paint()
				end,
			})
			foldRow.instance.LayoutOrder = 3
		end

		paint()
		local disconnect = responsive.changed:connect(paint)
		card.Destroying:Connect(disconnect)
		return card
	end

	-- Renders markdown blocks into an existing column. Returned so a streaming or
	-- edited message can clear and re-render.
	local function renderBlocks(column, text, supplied, first)
		local blocks = supplied or markdown.blocks(text)
		if #blocks == 0 then
			P.text(column, { text = "", role = "body", wrap = true, auto = "Y" })
			return
		end

		for position, block in ipairs(blocks) do
			local index = position + (first or 1) - 1
			if block.kind == "code" then
				-- A fenced block is an object in the prose rather than another paragraph of
				-- it, so it gets more air than the uniform paragraph gap -- above and below
				-- both. At the bare gap the sentence introducing the code sat exactly as
				-- close to it as the next paragraph did, which is what makes a reply read as
				-- one column with a slab dropped into it.
				local slot = P.column(column, {
					name = "CodeSlot",
					size = UDim2.new(1, 0, 0, 0),
					auto = "Y",
					gap = 0,
					padding = { y = theme.space.xs },
					layoutOrder = index,
				})
				M.codeBlock(slot, {
					text = block.text,
					lang = block.lang,
					unterminated = block.unterminated,
					layoutOrder = 1,
				})
			elseif block.kind == "table" then
				tableBlock.render(column, { block = block, layoutOrder = index })
			elseif block.kind == "heading" then
				-- A heading belongs to what is under it, so it needs more air above than
				-- the uniform paragraph gap gives it. Without this a section title sits
				-- exactly as far from the paragraph it introduces as from the one it ends,
				-- and a long reply reads as an undifferentiated run of text.
				local head = P.column(column, {
					name = "Heading",
					size = UDim2.new(1, 0, 0, 0),
					auto = "Y",
					gap = 0,
					padding = index > 1 and { top = theme.space.sm } or nil,
					layoutOrder = index,
				})
				local label = P.text(head, {
					text = markdown.inline(block.text),
					role = block.level == 1 and "title" or "heading",
					rich = true,
					wrap = true,
					auto = "Y",
				})
				label.Size = UDim2.new(1, 0, 0, 0)
			elseif block.kind == "rule" then
				P.divider(column, { layoutOrder = index })
			elseif block.kind == "quote" then
				local body = ruled(column, {
					name = "Quote",
					layoutOrder = index,
					color = theme.color.accent,
					width = theme.stroke.focus,
					bg = theme.color.surface,
					radius = theme.radius.sm,
					ruleRadius = theme.radius.xs,
					padY = theme.space.xs,
					padRight = theme.space.sm,
					inset = theme.space.sm,
					clip = true,
				})
				local quoted = P.text(body, {
					text = markdown.inline(block.text),
					role = "body",
					color = theme.color.textSecondary,
					rich = true,
					wrap = true,
					auto = "Y",
				})
				quoted.Size = UDim2.new(1, 0, 0, 0)
			elseif block.kind == "bullets" then
				local list = P.column(column, {
					name = "List",
					size = UDim2.new(1, 0, 0, 0),
					auto = "Y",
					gap = theme.space.xxs,
					layoutOrder = index,
				})
				-- One marker column for the whole list, wide enough for its longest
				-- marker, so "9." and "10." put their text at the same x.
				local markerWidth = theme.space.md
				for _, item in ipairs(block.items) do
					if item.marker then
						markerWidth = math.max(markerWidth,
							math.ceil(#item.marker * theme.text.body.size * MONO_RATIO))
					end
				end
				-- The marker is text, in the same role and on the same line height as the
				-- item beside it, and both are top-aligned inside boxes of that same
				-- height. That is what makes them line up: two labels with one role, one
				-- line height and one top edge put their first line on one baseline by
				-- construction. It used to be a 4px frame centred in a 23px slot next to a
				-- label centred in its own measured bounds -- two heights computed
				-- separately, agreeing only by luck, and they did not: every bullet in a
				-- reply sat low, near the descender of the line it belonged to.
				local bulletRole = theme.textRole("body")
				for position, item in ipairs(block.items) do
					local row = P.row(list, {
						size = UDim2.new(1, 0, 0, 0),
						auto = "Y",
						-- Closer to its own text than to the item above it. At sm the gap
						-- was wider than the mark, which reads as a stray dot rather than
						-- as the start of a line.
						gap = theme.space.xs,
						alignY = "Top",
						layoutOrder = position,
					})
					if (item.depth or 0) > 0 then
						P.frame(row, {
							name = "Indent",
							size = UDim2.fromOffset(item.depth * theme.space.lg, bulletRole.height),
							layoutOrder = 1,
						})
					end
					P.text(row, {
						name = "Marker",
						-- The middle dot rather than a bullet: it is Latin-1, so every family
						-- the engine offers has it, and at body size a round bullet next to
						-- 14px text is the loudest thing in the paragraph.
						text = item.marker or "\194\183",
						role = "body",
						line = bulletRole.line,
						color = theme.color.textTertiary,
						align = "Right",
						alignY = "Top",
						size = UDim2.new(0, markerWidth, 0, bulletRole.height),
						layoutOrder = 2,
					})
					P.text(row, {
						text = markdown.inline(item.text),
						role = "body",
						line = bulletRole.line,
						rich = true,
						wrap = true,
						alignY = "Top",
						auto = "Y",
						size = UDim2.new(0, 0, 0, 0),
						flex = "Fill",
						layoutOrder = 3,
					})
				end
			else
				local label = P.text(column, {
					text = markdown.inline(block.text),
					role = "body",
					rich = true,
					wrap = true,
					auto = "Y",
					layoutOrder = index,
				})
				label.Size = UDim2.new(1, 0, 0, 0)
			end
		end
	end

	-- Build a replacement before releasing the current reply/preview. An unusual
	-- Markdown block must not leave a byline above an empty, permanently broken row.
	function M.renderBlocks(column, text, viewport, state)
		local staged = P.column(column, { name = "Blocks", size = UDim2.new(1, 0, 0, 0),
			auto = "Y", gap = theme.space.md, visible = false })
		local ok, err = pcall(function()
			if not viewport then renderBlocks(staged, tostring(text or "")); return end
			local blocks = state and state.text == text and state.blocks or markdown.blocks(tostring(text or ""))
			if state then state.text, state.blocks = text, blocks end
			local order = 0
			for _, source in ipairs(blocks) do
				-- Long lists are several independent drawing chunks. Code and tables
				-- already have bounded, scrollable previews of their own.
				local pieces = { source }
				if source.kind == "bullets" and #source.items > 16 then
					pieces = {}
					for first = 1, #source.items, 16 do
						pieces[#pieces + 1] = { kind = "bullets", items = util.slice(source.items, first, first + 15) }
					end
				end
				for _, block in ipairs(pieces) do
					order = order + 1
					local slot = order
					local plain = block.text or ""
					if block.items then
						local lines = {}; for _, item in ipairs(block.items) do lines[#lines + 1] = item.text end
						plain = table.concat(lines, "\n")
					end
					viewport.add(staged, { order = slot, fallback = plain,
						estimate = function(width)
							if block.kind == "table" then return theme.text.body.height * math.min(12, #(block.rows or {}) + 2) end
							local height = env.require("ui/chat/viewport").estimate(plain, width, theme.space.sm)
							return block.kind == "code" and math.min(height, theme.text.body.height * 14) or height
						end,
						build = function(parent)
							local chunk = P.column(parent, { size = UDim2.new(1, 0, 0, 0), auto = "Y", gap = 0 })
							renderBlocks(chunk, "", { block }, slot)
							return { root = chunk }
						end,
					})
				end
			end
		end)
		if not ok then
			staged:Destroy()
			staged = P.text(column, { name = "PlainTextFallback", text = util.sanitise(tostring(text or "")),
				role = "body", wrap = true, auto = "Y", visible = false })
			env.require("runtime/log").warn("ui", "Markdown displayed as plain text", err)
		end
		for _, child in ipairs(column:GetChildren()) do
			if child ~= staged and not child:IsA("UIListLayout") and not child:IsA("UIPadding") then child:Destroy() end
		end
		staged.Visible = true
	end

	-- Who said it, above what they said.
	--
	-- One quiet line. It is the piece the transcript was missing: a turn was a tinted box
	-- followed by unmarked prose followed by another tinted box, so scrolling back
	-- through a long conversation meant inferring the speaker from the fill, and the
	-- reply's attribution existed nowhere at all -- a client that can switch model
	-- mid-conversation was rendering four different models' answers identically.
	--
	-- The role stays readable while the model attribution truncates independently.
	local function byline(parent, props)
		local row = P.row(parent, {
			name = "Byline",
			size = UDim2.new(1, 0, 0, math.max(theme.size.iconLarge, theme.text.label.height)),
			gap = theme.space.xs,
			layoutOrder = props.layoutOrder or 1,
		})
		if props.icon then
			local slot = P.frame(row, {
				name = "BylineIcon",
				size = UDim2.fromOffset(theme.size.iconLarge, theme.size.iconLarge),
				layoutOrder = 1,
			})
			icons.draw(props.icon, slot, theme.size.icon, props.iconColor or theme.color.textTertiary)
		end
		-- Fills rather than sizing to its text, so the byline is one full-width row and a
		-- long model id truncates instead of pushing the line past the reading column.
		P.text(row, {
			name = "Speaker",
			text = tostring(props.name or ""),
			role = props.mono and "monoSmall" or "label",
			color = props.color or theme.color.textSecondary,
			size = props.detail and UDim2.fromOffset(0, theme.text.label.height) or UDim2.new(0, 0, 1, 0),
			auto = props.detail and "X" or nil,
			flex = not props.detail and "Fill" or nil,
			truncate = true,
			layoutOrder = 2,
		})
		if props.detail then
			P.text(row, {
				name = "ModelAttribution", text = props.detail, role = "caption",
				color = theme.color.textTertiary, size = UDim2.new(0, 0, 1, 0),
				flex = "Fill", truncate = true, layoutOrder = 3,
			})
		end
		return row
	end

	-- Who the person at this client is, for the byline. The display name, because that
	-- is what they see everywhere else in the game.
	local function localName()
		local okName, display = pcall(function() return env.plr and env.plr.DisplayName end)
		if okName and type(display) == "string" and util.trim(display) ~= "" then
			return display
		end
		if env.plr and type(env.plr.Name) == "string" and env.plr.Name ~= "" then
			return env.plr.Name
		end
		return "You"
	end

	-- Sent prompts keep their byline inside one quiet, bordered surface.
	function M.user(parent, text, order, props)
		if props and props.viewport and not props.mounted then
			local options = util.copy(props); options.mounted, options.messageState = true, {}
			return props.viewport.add(parent, { name = "User", order = order, fallback = tostring(text),
				estimate = function(width) return env.require("ui/chat/viewport").estimate(util.truncate(tostring(text), 1200), width - theme.space.md * 2, theme.text.label.height + theme.space.lg) end,
				build = function(into) return M.user(into, text, 1, options) end })
		end
		local state = props and props.messageState or {}
		local holder = P.column(parent, {
			name = "User",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			gap = theme.space.xs,
			layoutOrder = order or 0,
		})
		local body = P.column(holder, {
			name = "Bubble", size = UDim2.new(1, 0, 0, 0), auto = "Y",
			bg = theme.color.bubbleUser, radius = theme.radius.md,
			padding = { x = theme.space.md, y = theme.space.sm }, gap = theme.space.xxs, layoutOrder = 1,
		})
		P.stroke(body, theme.color.bubbleUserBorder)
		byline(body, { name = localName(), color = theme.color.textTertiary, layoutOrder = 1 })

		local label = P.text(body, {
			text = state.expanded and tostring(text) or util.truncate(tostring(text), 1200),
			role = "body",
			layoutOrder = 2,
			wrap = true,
			auto = "Y",
		})
		label.Size = UDim2.new(1, 0, 0, 0)
		if #tostring(text) > 1200 then
			P.button(body, {
				name = "ExpandMessage",
				text = state.expanded and "Show less" or "Show full message",
				variant = "ghost",
				size = "sm",
				align = "Left",
				fill = true,
				padX = 0,
				layoutOrder = 3,
				onClick = function(button)
					state.expanded = not state.expanded
					label.Text = state.expanded and tostring(text) or util.truncate(tostring(text), 1200)
					button.setText(state.expanded and "Show less" or "Show full message")
				end,
			})
		end
		return { root = holder, label = label }
	end

	function M.agent(parent, text, order, attribution, props)
		if props and props.viewport and not props.mounted then
			local value, model, partial = text or "", attribution, false
			local options = util.copy(props); options.mounted, options.renderState = true, {}
			local item = props.viewport.add(parent, { name = "Agent", order = order, fallback = tostring(text or ""),
				estimate = function(width) return env.require("ui/chat/viewport").estimate(value, width, theme.text.label.height + theme.space.lg) end,
				build = function(into)
					local handle = M.agent(into, partial and "" or value, 1, model, options)
					if partial then handle.stream(value) end
					return handle
				end })
			function item.setModel(nextModel) model = nextModel or model; item.update("setModel", model) end
			function item.setText(nextText) value, partial = nextText or "", false; item.fallback = value; item.update("setText", value) end
			function item.stream(nextText) value, partial = tostring(nextText or ""), true; item.fallback = value; item.update("stream", value) end
			function item.finish(nextText, nextModel) item.setModel(nextModel); item.setText(nextText or value) end
			return item
		end
		local holder = P.column(parent, {
			name = "Agent",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			gap = theme.space.sm,
			layoutOrder = order or 0,
		})
		-- Keep response attribution when replaying or completing a live preview.
		local record = env.require("provider/registry").active()
		local model = attribution or (record and util.trim(tostring(record.model or "")) or "")
		if model == "" then model = record and record.label or "no model" end
		local attributionRow = byline(holder, {
			name = "Assistant",
			detail = model,
			icon = "brand",
			iconColor = theme.color.accent,
			color = theme.color.textSecondary,
			layoutOrder = 1,
		})
		local column = P.column(holder, {
			name = "Body",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			-- Paragraphs need more than eight pixels between them or a long reply
			-- arrives as one grey slab with no shape to it.
			gap = theme.space.md,
			layoutOrder = 2,
		})

		local currentText = text or ""
		local streamLabel = nil

		local handle = { root = holder, column = column }
		local modelLabel = attributionRow:FindFirstChild("ModelAttribution")

		function handle.setModel(value)
			local text = util.trim(tostring(value or ""))
			if text ~= "" then modelLabel.Text = text end
		end

		function handle.setText(value)
			currentText = value or ""
			streamLabel = nil
			M.renderBlocks(column, currentText, props and props.viewport, props and props.renderState)
		end

		function handle.stream(partial)
			currentText = tostring(partial or "")
			-- Incomplete tables/code fences stay in one label until the final render.
			if not streamLabel or streamLabel.Parent ~= column then
				for _, child in ipairs(column:GetChildren()) do
					if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then child:Destroy() end
				end
				streamLabel = P.text(column, { name = "StreamText", text = "", role = "body", wrap = true,
					auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = 1 })
			end
			streamLabel.Text = currentText .. " ●"
		end

		function handle.finish(finalText, finalModel)
			handle.setModel(finalModel)
			handle.setText(finalText or currentText)
		end

		handle.setText(text or "")
		return handle
	end

	-- Reasoning is a quieter register of the same page, not an object on it: a header
	-- row and muted body text, no card and no outline. It used to be a bordered panel,
	-- which gave a paragraph of thinking the same visual weight as a settings group.
	--
	-- The body now sits behind a rule and an indent. Flush left in the same measure as
	-- the reply, at 13px against the reply's 14 and one step down in colour, thinking
	-- and answer were two paragraphs that looked alike -- so a turn read as the model
	-- saying the same thing twice, which is exactly what it looks like when a model
	-- restates its conclusion in prose.
	function M.reasoning(parent, text, order)
		text = tostring(text or "")
		local holder = wrapper(parent, { name = "Reasoning", layoutOrder = order })
		local card = P.column(holder, {
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			gap = theme.space.xs,
		})

		local header = Instance.new("TextButton", card)
		header.Name = "ReasoningHeader"
		header.Text = ""
		header.AutoButtonColor = false
		header.BackgroundColor3 = theme.color.surface
		header.BackgroundTransparency = 0.45
		header.Size = UDim2.new(1, 0, 0, math.max(theme.size.rowSmall,
			responsive.minTarget()))
		header.LayoutOrder = 1
		header.Selectable = true
		Instance.new("UICorner", header).CornerRadius = UDim.new(0, theme.radius.sm)
		local thinkStroke = Instance.new("UIStroke", header)
		thinkStroke.Color = theme.color.borderSubtle
		thinkStroke.Thickness = theme.stroke.hair
		thinkStroke.Transparency = 0.4

		local row = P.row(header, {
			size = UDim2.fromScale(1, 1),
			gap = theme.space.sm,
			padding = { left = theme.space.sm, right = theme.space.sm },
			alignY = "Center",
		})
		local caret = P.frame(row, {
			name = "Caret",
			size = UDim2.fromOffset(theme.size.icon, theme.size.icon),
			layoutOrder = 1,
		})
		icons.chevron(caret, theme.size.icon, theme.color.textTertiary, "right")

		local sparkBadge = P.frame(row, {
			name = "SparkBadge",
			size = UDim2.fromOffset(theme.size.icon, theme.size.icon),
			layoutOrder = 2,
		})
		icons.spark(sparkBadge, theme.size.icon, theme.color.accent)

		local title = P.text(row, {
			text = "Thinking",
			role = "label",
			color = theme.color.textSecondary,
			auto = "X",
			layoutOrder = 3,
		})

		local tokenPill = P.frame(row, {
			name = "TokenPill",
			size = UDim2.fromOffset(0, theme.text.caption.height),
			padding = { x = theme.space.xxs },
			auto = "X",
			layoutOrder = 4,
		})
		local tokenText = P.text(tokenPill, {
			text = "~" .. util.formatNumber(usage.estimateText(text)) .. " tokens",
			role = "caption",
			color = theme.color.textTertiary,
			auto = "X",
		})
		local function fitHeader()
			local required = P.measureText(title.Text, { role = "label" }).X
				+ P.measureText(tokenText.Text, { role = "caption" }).X
				+ theme.size.icon * 2 + theme.space.sm * 5 + theme.space.xxs * 2
			tokenPill.Visible = header.AbsoluteSize.X >= required
		end
		header:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitHeader)
		fitHeader()

		local bodyRow = P.frame(card, { name = "Aside", size = UDim2.new(1, 0, 0, 0), layoutOrder = 2, visible = false })
		P.frame(bodyRow, { name = "Rule", size = UDim2.new(0, theme.stroke.hair, 1, 0),
			position = UDim2.fromOffset(theme.space.sm, 0), bg = theme.color.borderSubtle })
		local indent = theme.space.xl
		local viewport = P.scroll(bodyRow, { name = "ThoughtViewport", size = UDim2.new(1, -indent, 0, 0),
			position = UDim2.fromOffset(indent, 0), gap = theme.space.sm,
			padding = { right = theme.space.sm, y = theme.space.xxs } })
		local body = P.text(viewport.instance, { name = "ThoughtText", text = markdown.inline(text), role = "small",
			color = theme.color.textSecondary, rich = true, wrap = true, auto = "Y",
			alignY = "Top", size = UDim2.new(1, 0, 0, 0) })
		local open = config.get("ui.expandThinking", false) == true
		local fitting = false
		local function fit()
			if not bodyRow.Parent or fitting then return end
			fitting = true
			local width = math.max(1, viewport.instance.AbsoluteSize.X - theme.space.sm)
			local measured = math.max(body.TextBounds.Y, body.AbsoluteSize.Y,
				P.measureText(markdown.plain(text), { role = "small", width = width }).Y)
			local room = responsive.isMobile() and responsive.usableRect(env.root, 0).height or responsive.viewport.Y
			local height = math.min(math.max(theme.text.small.height, measured) + theme.space.xxs * 2,
				math.max(theme.text.small.height * 2, math.min(theme.size.thinkingViewport, room * 0.3)))
			bodyRow.Size = UDim2.new(1, 0, 0, height)
			viewport.instance.Size = UDim2.new(1, -indent, 0, height)
			fitting = false
		end
		body:GetPropertyChangedSignal("TextBounds"):Connect(fit)
		body:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		local lastWidth = 0
		viewport.instance:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			local width = viewport.instance.AbsoluteSize.X
			if width ~= lastWidth then lastWidth = width; fit() end
		end)
		local unsubscribe = responsive.changed:connect(fit)
		holder.Destroying:Connect(unsubscribe)
		local function setOpen(value)
			open = value
			bodyRow.Visible = open
			P.animate(caret, "hover", { Rotation = open and 90 or 0 })
			if open then fit() end
		end
		header.Activated:Connect(function() setOpen(not open) end)
		setOpen(open)
		disclosure(header, thinkStroke)
		-- The wrapper, not the card: hiding the card alone left its frame in the list
		-- layout, so a hidden reasoning row still pushed the reply down by its padding.
		if config.get("ui.showReasoning", true) == false then holder.Visible = false end

		local handle = { root = holder, body = body }
		function handle.setText(value)
			text = tostring(value or "")
			body.Text = markdown.inline(text)
			tokenText.Text = "~" .. util.formatNumber(usage.estimateText(text)) .. " tokens"
			fitHeader()
			if open then fit() end
		end
		function handle.append(value)
			value = tostring(value or "")
			if value ~= "" and value ~= text then handle.setText(text .. "\n\n" .. value) end
		end
		return handle
	end

	-- Which argument on a call is a listing rather than a value, and what language it
	-- is in.
	--
	-- Ordered, because a call can carry more than one: file_write takes a `path` and a
	-- `content`, run_luau takes only `code`. Anything matched here is drawn as code and
	-- kept out of the key/value list, so the same string is never shown twice.
	local CODE_KEYS = {
		{ key = "code", lang = "lua" },
		{ key = "source", lang = "lua" },
		{ key = "script", lang = "lua" },
		{ key = "expression", lang = "lua" },
		{ key = "patch", lang = "diff" },
		{ key = "diff", lang = "diff" },
		{ key = "old_text", label = "Before" },
		{ key = "new_text", label = "After" },
		-- Language from the path it is being written to, since a file_write is whatever
		-- the extension says it is.
		{ key = "content" },
		{ key = "body" },
		{ key = "text" },
	}

	local EXTENSION_LANGS = {
		lua = "lua", luau = "lua", json = "json", md = "markdown", markdown = "markdown",
		js = "javascript", ts = "typescript", py = "python", html = "html", css = "css",
		yml = "yaml", yaml = "yaml", toml = "toml", sh = "bash", xml = "xml", csv = "csv",
		rbxmx = "xml", rbxlx = "xml",
	}

	-- The fields worth putting on the header line, most identifying first. Raw JSON
	-- used to go here, which at ninety characters shows the shape of the payload and
	-- none of its meaning: `{"path":"notes/plan.txt","content":"# Pl`.
	local SUMMARY_KEYS = {
		"path", "file", "query", "url", "class", "property", "name", "id",
		"command", "task", "question", "key", "value",
	}

	local function langForPath(path)
		local extension = tostring(path or ""):match("%.([%w]+)$")
		if not extension then return nil end
		return EXTENSION_LANGS[extension:lower()]
	end

	-- Splits decoded arguments into the listings and the scalar facts.
	local function splitArguments(args)
		local code, facts = {}, {}
		if type(args) ~= "table" then return code, facts end
		local taken = {}
		local pathHint = args.path or args.file or args.name
		for _, spec in ipairs(CODE_KEYS) do
			local value = args[spec.key]
			if type(value) == "string" and (value ~= "" or spec.label) and not taken[spec.key] then
				-- Only a listing if there is something to look at. A one-line `text` is a
				-- value, and a code card around three words is more chrome than content.
				local multiline = value:find("\n") ~= nil
				if spec.lang or spec.label or multiline then
					code[#code + 1] = {
						key = spec.key,
						text = value,
						lang = spec.lang or langForPath(pathHint),
						label = spec.label,
					}
					taken[spec.key] = true
				end
			end
		end
		for _, key in ipairs(util.keys(args, true)) do
			if not taken[key] then
				local value = args[key]
				local kind = type(value)
				if kind == "string" or kind == "number" or kind == "boolean" then
					facts[#facts + 1] = { key = tostring(key), value = tostring(value) }
				elseif kind == "table" then
					-- A nested structure is still shown verbatim: it is what an
					-- instance_create property map and a remote_fire argument list are, and
					-- both were previously invisible.
					local ok, encoded = pcall(util.encode, value)
					facts[#facts + 1] = { key = tostring(key), value = ok and encoded or "(not encodable)" }
				end
			end
		end
		return code, facts
	end

	local function summarise(args, raw)
		local function preview(value)
			return (util.ellipsis(value == nil and "" or tostring(value), ARG_PREVIEW):gsub("[\n\r]+", " "))
		end
		if type(args) ~= "table" then
			return preview(raw)
		end
		local parts = {}
		for _, key in ipairs(SUMMARY_KEYS) do
			local value = args[key]
			if type(value) == "string" or type(value) == "number" then
				parts[#parts + 1] = preview(value)
			end
		end
		if #parts == 0 then
			for _, key in ipairs(util.keys(args, true)) do
				local value = args[key]
				local kind = type(value)
				if kind == "string" or kind == "number" or kind == "boolean" then
					parts[#parts + 1] = key .. " " .. preview(value)
				end
				if #parts >= 3 then break end
			end
		end
		return util.ellipsis(table.concat(parts, "  \194\183  "), ARG_PREVIEW)
	end

	-- Activity owns compact disclosures and lazy details; message rendering supplies
	-- the same code and argument presentation used by ordinary replies.
	local activity = env.require("ui/chat/activity").new({
		wrapper = wrapper, disclosure = disclosure, codeBlock = M.codeBlock,
		splitArguments = splitArguments, summarise = summarise,
	})
	M.toolRun, M.toolCall, M.subagent = activity.toolRun, activity.toolCall, activity.subagent

	-- An inline note: a retry, a provider switch, a compaction, an error.
	--
	-- Only a bad one gets a fill. The rest are ordinary events in the life of a turn
	-- and were each arriving as a tinted panel, so a conversation that retried twice
	-- and compacted once read as three warnings rather than as three footnotes.
	function M.notice(parent, props, order)
		local tone = props.tone or "info"
		local holder = wrapper(parent, { name = "Notice", layoutOrder = order })
		local bad = tone == "bad"
		local row = P.row(holder, {
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			bg = bad and theme.color.dangerSurface or nil,
			radius = bad and theme.radius.md or nil,
			gap = theme.space.xs,
			-- Padded either way, so a bad notice does not indent its own text eight pixels
			-- further than the plain one above it. The fill is what marks it, not the inset.
			padding = { x = bad and theme.space.sm or 0, y = bad and theme.space.xs or 0 },
			alignY = "Top",
		})
		-- The same slot width the tool and reasoning rows put their caret in, so every
		-- top-level row in the transcript starts its text at one x. This was a bare 4px
		-- dot: a notice's text began twelve pixels left of the tool call above it.
		local dotSlot = P.frame(row, {
			name = "DotSlot",
			size = UDim2.fromOffset(theme.size.icon, theme.text.small.size),
			layoutOrder = 1,
		})
		P.statusDot(dotSlot, {
			color = theme.toneColor(tone),
			diameter = theme.size.dot,
			anchor = Vector2.new(0.5, 0.5),
			position = UDim2.fromScale(0.5, 0.5),
		})
		local label = P.text(row, {
			text = tostring(props.text),
			role = "small",
			color = bad and theme.color.danger or theme.color.textTertiary,
			wrap = true,
			auto = "Y",
			size = UDim2.new(0, 0, 0, 0),
			flex = "Fill",
			layoutOrder = 2,
		})
		return { root = holder, label = label }
	end

	-- The working indicator: one row that reports the current status text, replaced
	-- by the answer when the turn ends. It carries the two signals that separate
	-- "thinking" from "hung" -- a label that moves and a clock that counts up --
	-- because the HTTP call it covers can take a minute and says nothing while it
	-- does.
	function M.working(parent, order, startedAt)
		local holder = wrapper(parent, { name = "Working", layoutOrder = order })
		local rowHeight = math.max(theme.size.row, theme.text.small.height + theme.space.md)
		local row = P.row(holder, {
			name = "WorkingStatus",
			size = UDim2.new(1, 0, 0, rowHeight),
			gap = theme.space.sm, padding = { x = theme.space.md },
		})
		C.spinner(row, { diameter = theme.size.iconLarge, layoutOrder = 1 })
		local label = P.text(row, {
			text = "Thinking",
			truncate = true,
			role = "small",
			color = theme.color.textSecondary,
			-- Fills, rather than subtracting the spinner and the clock by hand. That
			-- remainder was three numbers deep and one of them was a literal 52 that
			-- also appeared, separately, as the clock's own width.
			size = UDim2.new(0, 0, 1, 0),
			flex = "Fill",
			layoutOrder = 2,
		})
		local elapsed = P.text(row, {
			text = "",
			role = "caption",
			color = theme.color.textTertiary,
			align = "Right",
			layoutOrder = 3,
		})
		elapsed.Size = UDim2.fromOffset(theme.size.metaColumn, rowHeight)

		local handle = { root = holder, label = label }
		local started = tonumber(startedAt) or clock.ms()
		-- Elapsed time remains readable even with reduced motion enabled.
		local stop = clock.interval(1, function()
			local waited = clock.since(started)
			if waited >= 1000 then elapsed.Text = util.formatDuration(waited) end
		end)
		holder.Destroying:Connect(function() pcall(stop) end)

		-- Progress updates do not restart the spinner or elapsed timer.
		function handle.set(text)
			label.Text = tostring(text)
		end
		return handle
	end

	return M
end
