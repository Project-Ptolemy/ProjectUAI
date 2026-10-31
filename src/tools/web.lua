-- The public web: search, and turn a page into readable text.
--
-- These are the one place a browser User-Agent is sent instead of the client's
-- own. It is not a preference: DuckDuckGo's HTML endpoint and most CDNs answer 403
-- to an unfamiliar agent, so a search tool that presented the CLI identity would
-- simply never work.
return function(env)
	local util = env.require("runtime/util")
	local http = env.require("net/http")
	local H = env.require("tools/helpers")
	local clock = env.require("runtime/clock")

	local PAGE_CAP = 4000
	local pages, order, serial, retained = {}, {}, 0, 0
	local function prune()
		while #order > 0 and (#order > 4 or retained > 4 * 1024 * 1024 or clock.ms() - pages[order[1]].at > 300000) do
			local key = table.remove(order, 1); retained = retained - #pages[key].text; pages[key] = nil
		end
	end
	local function cancelled(ctx) return ctx and ctx.aborted and ctx.aborted() end
	env.require("runtime/dispose").add(function() pages, order, retained = {}, {}, 0 end, "Web text pages")

	-- Sanitised at the end, not only at encode time.
	--
	-- A third-party page can be served as Latin-1, CP1252 or nothing at all, and
	-- Roblox's HTTP client hands back the bytes as they arrived. Scrubbing here as well
	-- as in util.encode is not belt-and-braces: this text is also what the transcript
	-- paints, what the Logs panel keeps and what the bridge uploads, and a raw 0xA0 in
	-- a TextLabel is a visible replacement glyph rather than an error anyone can trace.
	local function toText(html)
		local text = tostring(html)
			:gsub("<!%-%-.-%-%->", " ")
			:gsub("<[sS][cC][rR][iI][pP][tT][^>]*>.-</[sS][cC][rR][iI][pP][tT]%s*>", " ")
			:gsub("<[sS][tT][yY][lL][eE][^>]*>.-</[sS][tT][yY][lL][eE]%s*>", " ")
			:gsub("<[nN][oO][sS][cC][rR][iI][pP][tT][^>]*>.-</[nN][oO][sS][cC][rR][iI][pP][tT]%s*>", " ")
			:gsub("<[sS][vV][gG][^>]*>.-</[sS][vV][gG]%s*>", " ")
			:gsub("<br%s*/?>", "\n")
			:gsub("</p>", "\n\n")
			:gsub("</h%d>", "\n\n")
			:gsub("</li>", "\n")
			:gsub("<[^>]+>", " ")
		text = util.htmlEntities(text)
		text = text:gsub("[ \t]+", " "):gsub(" ?\n ?", "\n"):gsub("\n\n\n+", "\n\n")
		return (util.sanitise(util.trim(text)))
	end

	return {
		{
			name = "web_search",
			examples = { { title = "Find an official API reference", arguments = { query = "Roblox Creator Hub CollectionService GetTagged", limit = 3 },
				note = "Prefer the official API documentation and inspect live host availability separately." } },
			risk = "read",
			needs = { "http" },
			description = "Search the web and return titles, URLs and snippets. Use when the answer depends on something current or outside the game.",
			parameters = {
				type = "object",
				properties = {
					query = { type = "string", minLength = 1, maxLength = 1000 },
					limit = { type = "integer", description = "Results to return, 1-10. Default 5.", minimum = 1, maximum = 10 },
				},
				required = { "query" },
			},
			run = function(args, ctx)
				local query = util.trim(args.query)
				if query == "" then return H.fail("Give a query.") end
				if cancelled(ctx) then return H.fail("Search cancelled") end

				local res, err = http.send({
					url = "https://html.duckduckgo.com/html/",
					method = "POST",
					identity = "browser",
					headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
					body = "q=" .. util.urlEncode(query) .. "&b=&kl=us-en",
					attempts = 2,
					timeout = 20, aborted = ctx and ctx.aborted,
					tag = "tool:web_search",
				})
				if not res then return H.fail(err) end
				if not res.ok then return H.fail("search returned status " .. tostring(res.status)) end
				if cancelled(ctx) then return H.fail("Search cancelled") end
				if #res.body > 2 * 1024 * 1024 then return H.fail("Search response exceeds the 2 MiB inspection limit") end

				local limit = H.limit(args.limit, 5, 10)
				local records = {}
				for attributes, title in res.body:gmatch('<a%s+([^>]*)>(.-)</a>') do
					if #records >= limit then break end
					local href = attributes:match('href="([^"]*)"') or attributes:match("href='([^']*)'")
					local class = attributes:match('class="([^"]*)"') or attributes:match("class='([^']*)'") or ""
					if href and (" " .. class .. " "):find(" result__a ", 1, true) then
						-- Results are wrapped in a redirect; the real URL is the uddg param.
						local link = href:match("[?&]uddg=([^&]+)")
						link = link and util.urlDecode(link) or href
						if link:match("^https?://") and not link:find("^https://duckduckgo%.com") then
							records[#records + 1] = { title = util.ellipsis(toText(title), 240), url = util.htmlEntities(link) }
						end
					end
				end

				local index = 1
				for snippet in res.body:gmatch('<a[^>]+class="result__snippet"[^>]*>(.-)</a>') do
					if records[index] then
						records[index].snippet = util.ellipsis(toText(snippet), 260)
						index = index + 1
					end
				end

				if #records == 0 then
					return "No results. The search endpoint may be blocking this host; try web_read on a known URL instead."
				end
				local blocks = {}
				for position, record in ipairs(records) do
					blocks[#blocks + 1] = string.format("%d. %s\n   %s\n   %s",
						position, record.title, record.url, record.snippet or "(no snippet)")
				end
				return { text = table.concat(blocks, "\n\n"), data = { results = records, count = #records } }
			end,
		},
		{
			name = "web_read",
			risk = "read",
			needs = { "http" },
			description = "Fetch a web page as readable text or JSON. Returns contiguous UTF-8 pages: continue with page_id and offset without downloading it again. Snapshots last five minutes; four pages / 4 MiB retained. Reading does not execute page scripts.",
			parameters = {
				type = "object",
				properties = {
					url = { type = "string", minLength = 1, maxLength = 4000 },
					page_id = { type = "string", description = "Returned snapshot ID for continuation; provide this or url." },
					offset = { type = "integer", minimum = 1, description = "One-based UTF-8 byte offset from nextOffset." },
					limit = { type = "integer", description = "Maximum bytes in this contiguous page, also bounded by the result budget. Default 4000.", minimum = 200, maximum = 64000 },
				},
				required = {},
			},
			run = function(args, ctx)
				if (args.url ~= nil) == (args.page_id ~= nil) then return H.fail("Provide url or page_id, not both") end
				if cancelled(ctx) then return H.fail("Page read cancelled") end
				prune()
				local page = args.page_id and pages[args.page_id]
				if args.page_id and not page then return H.fail("Web snapshot expired; fetch the URL again") end
				if not page then
					local url = util.trim(args.url)
					if url == "" then return H.fail("Give a URL") end
					if not url:find("^https?://") then
						if url:find("^[%a][%w+%.%-]*:") then return H.fail("Only HTTP(S) URLs are supported") end
						url = "https://" .. url
					end
					local res, err = http.send({
						url = url,
						method = "GET",
						identity = "browser",
						attempts = 2,
						timeout = 20, aborted = ctx and ctx.aborted,
						tag = "tool:web_read",
					})
					if not res then return H.fail(err) end
					if not res.ok then return H.fail("the page returned status " .. tostring(res.status)) end
					if cancelled(ctx) then return H.fail("Page read cancelled") end

					local body = tostring(res.body)
					if #body > 2 * 1024 * 1024 then return H.fail("Web response exceeds the 2 MiB inspection limit") end
					-- JSON text does not pass through an HTML stripper.
					local trimmed = util.trim(body)
					local looksJson = trimmed:sub(1, 1) == "{" or trimmed:sub(1, 1) == "["
					local text = looksJson and util.sanitise(trimmed) or toText(body)
					if text == "" then return "The page returned no readable text." end
					if #text > 4 * 1024 * 1024 then return H.fail("Readable text exceeds the 4 MiB snapshot limit") end

					local title = body:match("<[tT][iI][tT][lL][eE][^>]*>(.-)</[tT][iI][tT][lL][eE]>")
					serial = serial + 1
					page = { id = "web-page:" .. serial, url = url, title = title and util.ellipsis(toText(title), 200), text = text, at = clock.ms() }
					pages[page.id], order[#order + 1], retained = page, page.id, retained + #text
					prune()
				end
				local result = H.readSlice(page.title or page.url, page.text, args, PAGE_CAP)
				if result.data then result.data.pageId, result.data.url, result.data.title = page.id, page.url, page.title end
				return result
			end,
		},
	}
end
