---
uai_vault: 1
title: "Train a small numeric neural network in Luau"
description: "A deterministic sigmoid MLP with bounded backpropagation, XOR training and portable saved weights."
kind: recipe
scope: global
tags: ["neural-network", "numeric", "training"]
sources: [{"label":"Backpropagation reference","url":"https://en.wikipedia.org/wiki/Backpropagation"},{"label":"Project UAI source review and behavioral tests","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/SCRIPT_PROJECTS.md"}]
status: draft
verification: "Reference implementation authored for Project UAI 4.0.0. External convergence and saved-weight checks are required; no native Roblox verification is claimed."
---
# Train a small numeric neural network in Luau

Use this recipe when the user explicitly requests a small trainable numeric
model. It implements a feed-forward network with one hidden layer and sigmoid
activations, trained by stochastic backpropagation on squared error.

Save the first code block as `network.lua` in a reviewed UAI script project.
Inputs must be normalized to [-1, 1]; targets must be in [0, 1]. The model permits
1–16 inputs, 1–32 hidden neurons and 1–16 outputs. Training caps at 20000 epochs,
100000 sample updates, with
`epochs * samples * hidden * (inputs + outputs) <= 4000000` per call. Weight
clipping to [-20, 20] keeps numeric state bounded. Initialization is deterministic
and leaves the host's random generator untouched.

```lua
local M = {}
local Model = {}
Model.__index = Model

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function count(value, maximum)
	assert(finite(value) and value >= 1 and value <= maximum
		and value == math.floor(value), "invalid network dimensions")
	return value
end
local function dense(value, size)
	assert(type(value) == "table" and #value == size, "invalid vector shape")
	for key in pairs(value) do
		assert(type(key) == "number" and key >= 1 and key <= size
			and key == math.floor(key), "invalid vector shape")
	end
end
local function vector(value, size, minimum, maximum)
	dense(value, size)
	local out = {}
	for index = 1, size do
		assert(finite(value[index]) and value[index] >= minimum
			and value[index] <= maximum, "invalid numeric value")
		out[index] = value[index]
	end
	return out
end
local function sigmoid(value)
	if value >= 0 then return 1 / (1 + math.exp(-value)) end
	local exponential = math.exp(value)
	return exponential / (1 + exponential)
end
local function clip(value) return math.max(-20, math.min(20, value)) end
local function forward(model, input)
	local hidden, output = {}, {}
	for h = 1, model.hidden do
		local sum = model.hiddenBias[h]
		for i = 1, model.inputs do sum = sum + model.inputWeights[h][i] * input[i] end
		hidden[h] = sigmoid(sum)
	end
	for o = 1, model.outputs do
		local sum = model.outputBias[o]
		for h = 1, model.hidden do sum = sum + model.outputWeights[o][h] * hidden[h] end
		output[o] = sigmoid(sum)
	end
	return hidden, output
end
function M.new(inputs, hidden, outputs, seed)
	inputs, hidden, outputs = count(inputs, 16), count(hidden, 32), count(outputs, 16)
	seed = seed or 1
	assert(finite(seed) and math.abs(seed) <= 1000000, "invalid seed")
	local index = 0
	local function weight()
		index = index + 1
		return math.sin(seed + index * 12.9898) * 0.5
	end
	local model = setmetatable({ inputs = inputs, hidden = hidden, outputs = outputs,
		inputWeights = {}, hiddenBias = {}, outputWeights = {}, outputBias = {} }, Model)
	for h = 1, hidden do
		model.inputWeights[h] = {}
		for i = 1, inputs do model.inputWeights[h][i] = weight() end
		model.hiddenBias[h] = weight()
	end
	for o = 1, outputs do
		model.outputWeights[o] = {}
		for h = 1, hidden do model.outputWeights[o][h] = weight() end
		model.outputBias[o] = weight()
	end
	return model
end
function Model:predict(input)
	input = vector(input, self.inputs, -1, 1)
	local _, output = forward(self, input)
	return output
end
function Model:train(samples, epochs, learningRate)
	assert(type(samples) == "table" and #samples >= 1 and #samples <= 256, "invalid dataset")
	dense(samples, #samples)
	epochs = count(epochs or 10000, 20000)
	learningRate = learningRate or 0.5
	assert(finite(learningRate) and learningRate > 0 and learningRate <= 1, "invalid learning rate")
	local updates = epochs * #samples
	assert(updates <= 100000 and updates * self.hidden * (self.inputs + self.outputs) <= 4000000,
		"training workload exceeds limit")
	local data = {}
	for index, sample in ipairs(samples) do
		assert(type(sample) == "table", "invalid dataset sample")
		data[index] = { input = vector(sample.input, self.inputs, -1, 1),
			target = vector(sample.target, self.outputs, 0, 1) }
	end
	for epoch = 1, epochs do
		for _, sample in ipairs(data) do
			local hidden, output = forward(self, sample.input)
			local outputDelta, hiddenDelta = {}, {}
			for o = 1, self.outputs do
				outputDelta[o] = (sample.target[o] - output[o]) * output[o] * (1 - output[o])
			end
			-- Hidden gradients use the output weights before this update.
			for h = 1, self.hidden do
				local sum = 0
				for o = 1, self.outputs do sum = sum + self.outputWeights[o][h] * outputDelta[o] end
				hiddenDelta[h] = hidden[h] * (1 - hidden[h]) * sum
			end
			for o = 1, self.outputs do
				for h = 1, self.hidden do
					self.outputWeights[o][h] = clip(self.outputWeights[o][h] + learningRate * outputDelta[o] * hidden[h])
				end
				self.outputBias[o] = clip(self.outputBias[o] + learningRate * outputDelta[o])
			end
			for h = 1, self.hidden do
				for i = 1, self.inputs do
					self.inputWeights[h][i] = clip(self.inputWeights[h][i] + learningRate * hiddenDelta[h] * sample.input[i])
				end
				self.hiddenBias[h] = clip(self.hiddenBias[h] + learningRate * hiddenDelta[h])
			end
		end
	end
	local loss = 0
	for _, sample in ipairs(data) do
		local _, output = forward(self, sample.input)
		for o = 1, self.outputs do loss = loss + (sample.target[o] - output[o]) ^ 2 end
	end
	return loss / (#data * self.outputs)
end
function Model:export()
	local out = { version = 1, inputs = self.inputs, hidden = self.hidden, outputs = self.outputs,
		inputWeights = {}, hiddenBias = vector(self.hiddenBias, self.hidden, -20, 20),
		outputWeights = {}, outputBias = vector(self.outputBias, self.outputs, -20, 20) }
	for h = 1, self.hidden do out.inputWeights[h] = vector(self.inputWeights[h], self.inputs, -20, 20) end
	for o = 1, self.outputs do out.outputWeights[o] = vector(self.outputWeights[o], self.hidden, -20, 20) end
	return out
end
function M.fromWeights(snapshot)
	assert(type(snapshot) == "table" and snapshot.version == 1, "invalid saved model")
	local model = M.new(snapshot.inputs, snapshot.hidden, snapshot.outputs, 1)
	dense(snapshot.inputWeights, model.hidden); dense(snapshot.outputWeights, model.outputs)
	model.hiddenBias = vector(snapshot.hiddenBias, model.hidden, -20, 20)
	model.outputBias = vector(snapshot.outputBias, model.outputs, -20, 20)
	for h = 1, model.hidden do model.inputWeights[h] = vector(snapshot.inputWeights[h], model.inputs, -20, 20) end
	for o = 1, model.outputs do model.outputWeights[o] = vector(snapshot.outputWeights[o], model.hidden, -20, 20) end
	return model
end
return M
```

An XOR entry module can train a separate numeric model and return its predictions
and exported weights:

```lua
local Network = require("network")
local samples = {
	{ input = { 0, 0 }, target = { 0 } },
	{ input = { 0, 1 }, target = { 1 } },
	{ input = { 1, 0 }, target = { 1 } },
	{ input = { 1, 1 }, target = { 0 } },
}
local model = Network.new(2, 4, 1, 7)
local loss = model:train(samples, 20000, 0.5)
local predictions = {}
for index, sample in ipairs(samples) do predictions[index] = model:predict(sample.input)[1] end
return { loss = loss, predictions = predictions, weights = model:export() }
```

Save the weight table as JSON through a reviewed workspace write, read it back,
and call `Network.fromWeights(decodedWeights)` for inference without retraining.
Export and restore copy numeric arrays so later caller edits do not change an
existing model. Train only on suitable numeric data and validate separate data
for real tasks; XOR is a deterministic demonstration, not a quality benchmark.

The recipe runs through the existing reviewed script workflow and managed
execution limits. It performs no game, remote, filesystem or network operations
itself. Training produces a small separate model; provider inference and native
runtime behavior still depend on their existing contracts.
