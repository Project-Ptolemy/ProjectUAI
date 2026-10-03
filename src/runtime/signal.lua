-- A signal that does not depend on BindableEvent. The client fans a lot of small
-- events out to the interface, and going through Roblox instances for that costs
-- a round trip per fire and loses non-serialisable payloads such as functions --
-- which the permission prompt relies on.
return function(env)
	local M = {}

	local Signal = {}
	Signal.__index = Signal

	function M.new(name)
		return setmetatable({ name = name or "signal", handlers = {}, firing = false, dirty = false }, Signal)
	end

	function Signal:connect(fn)
		if type(fn) ~= "function" then return function() end end
		local entry = { fn = fn, alive = true }
		self.handlers[#self.handlers + 1] = entry
		return function()
			if not entry.alive then return end
			entry.alive = false
			entry.fn = nil; self.dirty = true; self:compact()
		end
	end

	function Signal:once(fn)
		local disconnect
		disconnect = self:connect(function(...)
			disconnect()
			fn(...)
		end)
		return disconnect
	end

	-- Capture the array and its boundary: connections append, disconnections only
	-- mark entries while a dispatch is active, and clear replaces the array. This
	-- preserves snapshot ordering without allocating a list for every event.
	-- Errors in one subscriber must not stop the rest from seeing the event.
	function Signal:fire(...)
		self.depth = (self.depth or 0) + 1
		if self.depth > 32 then self.depth = self.depth - 1; self.dropped = (self.dropped or 0) + 1; return end
		self.firing = true
		local handlers, limit = self.handlers, #self.handlers
		for index = 1, limit do
			local entry = handlers[index]
			if entry.alive then
				local ok, err = pcall(entry.fn, ...)
				if not ok and self.onError then pcall(self.onError, err) end
			end
		end
		self.depth = self.depth - 1; self.firing = self.depth > 0; self:compact()
	end

	function Signal:compact()
		if self.firing or not self.dirty then return end
		local handlers, kept = self.handlers, 0
		for _, entry in ipairs(handlers) do
			if entry.alive then kept = kept + 1; handlers[kept] = entry end
		end
		for index = #handlers, kept + 1, -1 do handlers[index] = nil end
		self.dirty = false
	end

	function Signal:count()
		local total = 0
		for _, entry in ipairs(self.handlers) do
			if entry.alive then total = total + 1 end
		end
		return total
	end

	function Signal:clear()
		for _, entry in ipairs(self.handlers) do entry.alive, entry.fn = false, nil end
		self.handlers = {}
		self.dirty = false
	end

	return M
end
