-- SHA-256 (FIPS 180-4), HMAC (RFC 2104) and PBKDF2 (RFC 8018).
-- Internal binary primitives for the password vault. No host crypto or randomness.
-- PBKDF2 caches keyed SHA states and keeps intermediate digests as 32-bit words.
return function(env)
	local M = { error = "Credential cryptography failed.", maxIterations = 2000000, available = false }
	if type(bit32) ~= "table" or type(bit32.band) ~= "function" or type(bit32.bxor) ~= "function"
		or type(bit32.bnot) ~= "function" or type(bit32.rshift) ~= "function" or type(bit32.rrotate) ~= "function" then
		function M.digest() return nil, M.error end
		function M.hmac() return nil, M.error end
		function M.derive64() return nil, M.error end
		return M
	end
	M.available = true
	local band, bxor, bnot = bit32.band, bit32.bxor, bit32.bnot
	local rshift, rotate = bit32.rshift, bit32.rrotate
	local byte, char, concat = string.byte, string.char, table.concat
	local MOD = 4294967296
	local INITIAL = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
		0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
	local K = {
		0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
		0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
		0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
		0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
		0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
		0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
		0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
		0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
	}
	local function copy(state)
		local out = {}
		for index = 1, 8 do out[index] = state[index] end
		return out
	end
	local function word(value)
		return char(rshift(value, 24), band(rshift(value, 16), 255), band(rshift(value, 8), 255), band(value, 255))
	end
	local function readWord(text, offset)
		local a, b, c, d = byte(text, offset, offset + 3)
		return ((a * 256 + b) * 256 + c) * 256 + d
	end
	local function raw(state)
		local out = {}
		for index = 1, 8 do out[index] = word(state[index]) end
		return concat(out)
	end
	local function compress(state, words)
		for index = 17, 64 do
			local a, b = words[index - 15], words[index - 2]
			local s0 = bxor(rotate(a, 7), rotate(a, 18), rshift(a, 3))
			local s1 = bxor(rotate(b, 17), rotate(b, 19), rshift(b, 10))
			words[index] = (words[index - 16] + s0 + words[index - 7] + s1) % MOD
		end
		local a, b, c, d, e, f, g, h = state[1], state[2], state[3], state[4], state[5], state[6], state[7], state[8]
		for index = 1, 64 do
			local sum1 = bxor(rotate(e, 6), rotate(e, 11), rotate(e, 25))
			local choice = bxor(band(e, f), band(bnot(e), g))
			local t1 = (h + sum1 + choice + K[index] + words[index]) % MOD
			local sum0 = bxor(rotate(a, 2), rotate(a, 13), rotate(a, 22))
			local majority = bxor(band(a, b), band(a, c), band(b, c))
			local t2 = (sum0 + majority) % MOD
			h, g, f, e, d, c, b, a = g, f, e, (d + t1) % MOD, c, b, a, (t1 + t2) % MOD
		end
		state[1], state[2], state[3], state[4] = (state[1] + a) % MOD, (state[2] + b) % MOD, (state[3] + c) % MOD, (state[4] + d) % MOD
		state[5], state[6], state[7], state[8] = (state[5] + e) % MOD, (state[6] + f) % MOD, (state[7] + g) % MOD, (state[8] + h) % MOD
	end
	local function block(state, text, offset, words)
		for index = 1, 16 do words[index] = readWord(text, offset + (index - 1) * 4) end
		compress(state, words)
	end
	local function finish(initial, text, preceding, onProgress)
		local state, words = copy(initial), {}
		local complete = #text - #text % 64
		local function progress(completed)
			if not onProgress then return true end
			local ok, keepGoing = pcall(onProgress, completed, #text)
			return ok and keepGoing ~= false
		end
		if not progress(0) then return nil end
		for offset = 1, complete, 64 do
			block(state, text, offset, words)
			if onProgress and (offset + 63) % 16384 == 0 and not progress(offset + 63) then return nil end
		end
		local bits = ((preceding or 0) + #text) * 8
		local tail = text:sub(complete + 1) .. "\128" .. string.rep("\0", (55 - #text) % 64)
			.. word(math.floor(bits / MOD)) .. word(bits % MOD)
		for offset = 1, #tail, 64 do block(state, tail, offset, words) end
		if onProgress and #text % 16384 ~= 0 and not progress(#text) then return nil end
		return state
	end
	function M.digest(text, onProgress)
		if type(text) ~= "string" or (onProgress ~= nil and type(onProgress) ~= "function") then return nil, M.error end
		local state = finish(INITIAL, text, 0, onProgress)
		if not state then return nil, M.error end
		return raw(state)
	end
	local function keyed(key)
		if #key > 64 then key = M.digest(key) end
		key = key .. string.rep("\0", 64 - #key)
		local inner, outer = {}, {}
		for index = 1, 64 do
			inner[index], outer[index] = char(bxor(byte(key, index), 0x36)), char(bxor(byte(key, index), 0x5c))
		end
		local inside, outside, words = copy(INITIAL), copy(INITIAL), {}
		block(inside, concat(inner), 1, words)
		block(outside, concat(outer), 1, words)
		return inside, outside
	end
	local function authenticate(inside, outside, text)
		return finish(outside, raw(finish(inside, text, 64)), 64)
	end
	function M.hmac(key, text)
		if type(key) ~= "string" or type(text) ~= "string" then return nil, M.error end
		local inside, outside = keyed(key)
		return raw(authenticate(inside, outside, text))
	end
	-- Exactly one remaining block for a 32-byte message after a 64-byte HMAC pad.
	local function digestBlock(words)
		words[9] = 0x80000000
		for index = 10, 15 do words[index] = 0 end
		words[16] = 768
	end
	function M.derive64(password, salt, iterations, onProgress)
		if type(password) ~= "string" or #password > 1024 or type(salt) ~= "string" or #salt > 1024
			or type(iterations) ~= "number" or iterations < 1 or iterations > M.maxIterations or iterations % 1 ~= 0
			or (onProgress ~= nil and type(onProgress) ~= "function") then return nil, M.error end
		local completed, total = 0, iterations * 2
		local function progress()
			if not onProgress then return true end
			local ok, keepGoing = pcall(onProgress, completed, total)
			return ok and keepGoing ~= false
		end
		if not progress() then return nil, M.error end
		local inside, outside = keyed(password)
		local output, intermediate, words = {}, {}, {}
		for counter = 1, 2 do
			local u = authenticate(inside, outside, salt .. word(counter))
			local aggregate = copy(u)
			completed = completed + 1
			for iteration = 2, iterations do
				-- Reuse both digest states and the message schedule. No digest strings
				-- or fresh tables are allocated in the expensive stretching loop.
				for index = 1, 8 do words[index], intermediate[index], u[index] = u[index], inside[index], outside[index] end
				digestBlock(words)
				compress(intermediate, words)
				for index = 1, 8 do words[index] = intermediate[index] end
				digestBlock(words)
				compress(u, words)
				for index = 1, 8 do aggregate[index] = bxor(aggregate[index], u[index]) end
				completed = completed + 1
				-- Keep cancellation responsive in native Luau; the vault separately
				-- throttles frame yields by elapsed time rather than every batch.
				if completed % 128 == 0 and not progress() then return nil, M.error end
			end
			output[counter] = raw(aggregate)
		end
		if not progress() then return nil, M.error end
		return concat(output)
	end
	return M
end
