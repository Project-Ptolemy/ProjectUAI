-- External behavior of the exact neural-network source shipped in the Master Vault recipe.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F, json = require("workspace_fixture"), require("json")
local suite = F.suite("Master Vault neural network recipe")
local check, case = suite.check, suite.case
local file = assert(io.open("vault/neural-network.md", "rb")); local markdown = file:read("*a"); file:close()
local code = assert(markdown:match("```lua\r?\n(.-)\r?\n```"), "network source is missing")
local Network = assert(loadstring(code, "@vault/neural-network.md#network"))()
local samples = {
	{ input = { 0, 0 }, target = { 0 } }, { input = { 0, 1 }, target = { 1 } },
	{ input = { 1, 0 }, target = { 1 } }, { input = { 1, 1 }, target = { 0 } },
}
local function fails(fn) return not pcall(fn) end
local function close(first, second) return math.abs(first - second) < 1e-10 end
case("one analytic gradient step uses the prior output weights", function()
	local model = Network.fromWeights({ version = 1, inputs = 1, hidden = 1, outputs = 1,
		inputWeights = { { 0 } }, hiddenBias = { 0 }, outputWeights = { { 0 } }, outputBias = { 0 } })
	model:train({ { input = { 1 }, target = { 1 } } }, 1, 0.5)
	local weights = model:export()
	check("output weight follows the independent gradient", close(weights.outputWeights[1][1], 0.03125))
	check("output bias follows the independent gradient", close(weights.outputBias[1], 0.0625))
	check("hidden weights use the old zero output weight", weights.inputWeights[1][1] == 0 and weights.hiddenBias[1] == 0)
end)
case("deterministic initialization preserves the host random generator", function()
	math.randomseed(881); local expectedFirst, expectedSecond = math.random(), math.random()
	math.randomseed(881); local first = math.random()
	local a, b = Network.new(2, 4, 1, 7), Network.new(2, 4, 1, 7)
	local second = math.random()
	check("new models leave random state untouched", first == expectedFirst and second == expectedSecond)
	check("same seed has identical predictions", a:predict({ 0, 1 })[1] == b:predict({ 0, 1 })[1])
end)
case("XOR converges and saved JSON weights reproduce inference", function()
	local model = Network.new(2, 4, 1, 7)
	local loss = model:train(samples, 20000, 0.5)
	check("bounded training reduces XOR error", loss == loss and loss < 0.01)
	local predictions = {}
	for index, sample in ipairs(samples) do
		predictions[index] = model:predict(sample.input)[1]
		check("XOR output " .. index .. " is separated", sample.target[1] == 0 and predictions[index] < 0.1 or sample.target[1] == 1 and predictions[index] > 0.9)
	end
	local exported = model:export(); local decoded = json.decode(json.encode(exported)); local restored = Network.fromWeights(decoded)
	for index, sample in ipairs(samples) do check("saved-weight inference matches " .. index, close(restored:predict(sample.input)[1], predictions[index])) end
	exported.inputWeights[1][1] = 20; decoded.outputWeights[1][1] = 20
	check("export and restore detach caller arrays", close(model:predict(samples[2].input)[1], predictions[2]) and close(restored:predict(samples[2].input)[1], predictions[2]))
end)
case("invalid numeric data and excessive work are rejected before training", function()
	local model = Network.new(2, 4, 1, 7); local before = model:predict({ 0, 1 })[1]
	check("nonfinite input is refused", fails(function() model:predict({ 0 / 0, 1 }) end) and fails(function() model:predict({ math.huge, 1 }) end))
	check("unscaled input and invalid target are refused", fails(function() model:predict({ 2, 1 }) end) and fails(function() model:train({ { input = { 0, 1 }, target = { 2 } } }, 1) end))
	check("invalid dimensions and epochs are refused", fails(function() Network.new(0, 4, 1) end) and fails(function() model:train(samples, 20001) end))
	check("invalid late samples make no partial updates", fails(function() model:train({ samples[1], { input = { 0, 1 }, target = { math.huge } } }, 1) end) and model:predict({ 0, 1 })[1] == before)
	local large = Network.new(16, 32, 16, 1); local input, target = {}, {}
	for index = 1, 16 do input[index], target[index] = 0, 0 end
	check("large weighted workloads stay bounded", fails(function() large:train({ { input = input, target = target } }, 20000) end))
	local broken = model:export(); broken.inputWeights[1][1] = math.huge
	check("nonfinite saved weights are refused", fails(function() Network.fromWeights(broken) end))
end)
case("finite state remains bounded after training and extreme valid weights", function()
	local model = Network.fromWeights({ version = 1, inputs = 1, hidden = 1, outputs = 1,
		inputWeights = { { 20 } }, hiddenBias = { -20 }, outputWeights = { { 20 } }, outputBias = { -20 } })
	local loss = model:train({ { input = { -1 }, target = { 1 } } }, 100, 1)
	check("loss stays finite", loss == loss and math.abs(loss) < math.huge)
	local weights = model:export()
	for _, vector in ipairs({ weights.inputWeights[1], weights.hiddenBias, weights.outputWeights[1], weights.outputBias }) do
		for _, value in ipairs(vector) do check("saved value is finite and bounded", value == value and math.abs(value) <= 20) end
	end
	local output = model:predict({ 1 })[1]
	check("sigmoid inference stays in range", output == output and output >= 0 and output <= 1)
end)
suite.finish()
