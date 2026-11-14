// Normalization regressions: provider identity, zero prices, precision, failure.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { normalize, render, snapshotText, validateOfficial, capturedSource, verifyOfficialCapture } = require('../tools/sync_pricing');
const clone = value => JSON.parse(JSON.stringify(value));
const raw = { modelsdev: {}, litellm: {}, openrouter: { data: [] }, kilo: { data: [] },
	cline: { free: [{ id: 'vendor/promotion' }], recommended: [{ id: 'vendor/paid' }] } };
for (const provider of ['openai', 'anthropic', 'google', 'deepseek', 'opencode', 'opencode-go', 'groq', 'togetherai', 'mistral', 'xai', 'fireworks-ai', 'cerebras']) {
	raw.modelsdev[provider] = { models: { fixture: { cost: { input: 3, output: 6 }, limit: { context: 10000, output: 2000 }, tool_call: true } } };
}
for (let index = 0; index < 100; index++) raw.openrouter.data.push({ id: 'vendor/model-' + index, pricing: { prompt: '0.000000091', completion: '0.000000182', input_cache_read: '0.0000000182' } });
raw.kilo.data = raw.openrouter.data.map(model => ({ ...model, context_length: 32000 }));
raw.kilo.data.push({ id: 'vendor/free', isFree: true, pricing: { prompt: '0', completion: '0' } });
raw.kilo.data.push({ id: 'vendor/dynamic', context_length: 64000, pricing: { prompt: '0', completion: '0' } });
raw.openrouter.data.push({ id: 'vendor/model-0:free', pricing: { prompt: '0', completion: '0' } });
raw.openrouter.data.push({ id: 'vendor/unpriced', context_length: 64000, pricing: { prompt: '-1', completion: '-1' } });
raw.openrouter.data.push({ id: 'vendor/tiered', context_length: 200000,
	pricing: { prompt: '0.000001', completion: '0.000002', input_cache_read: '0.0000001', overrides: [
		{ min_prompt_tokens: 100000, prompt: '0.000002', completion: '0.000003' },
	] } });
raw.openrouter.data.push({ id: 'vendor/scheduled', context_length: 64000,
	pricing: { prompt: '0.000001', completion: '0.000002', overrides: [
		{ utc_start: 0, utc_end: 1600, prompt: '0.000002', completion: '0.000004' },
	] } });
raw.litellm['openai/fixture'] = { litellm_provider: 'openai', mode: 'chat', input_cost_per_token: 0.000009, output_cost_per_token: 0.000018 };
raw.litellm['anthropic/vendor/retained'] = { litellm_provider: 'anthropic', mode: 'chat', input_cost_per_token: 0.000002, output_cost_per_token: 0.000010 };
const providers = normalize(raw);
assert.equal(providers.openai.fixture.price.input, 3, 'models.dev takes precedence over supplemental rates');
assert.equal(providers['opencode-go'].fixture.price, undefined, 'catalog rates do not establish an additional subscription charge');
assert.equal(providers['opencode-go'].fixture.context, 10000, 'Go retains its own model limits');
assert.equal(providers.anthropic['vendor/retained'].price.input, 2, 'only the known LiteLLM provider prefix is removed');
assert.equal(providers.openrouter['vendor/model-0'].price.input, 0.091);
assert.equal(providers.openrouter['vendor/model-0'].price.cacheRead, 0.0182, 'sub-microtoken prices retain precision');
assert.equal(providers.openrouter['vendor/model-0:free'].price.input, 0);
assert.equal(providers.openrouter['model-0'], undefined, 'model namespaces are not erased');
assert.equal(providers.openrouter['vendor/unpriced'].price, undefined);
assert.equal(providers.openrouter['vendor/unpriced'].context, 64000, 'unpriced routes retain independent limits');
assert.equal(providers.openrouter['vendor/tiered'].price.tiers[0].above, 99999, 'inclusive upstream thresholds match the strict runtime boundary');
assert.equal(providers.openrouter['vendor/tiered'].price.tiers[0].input, 2);
assert.equal(providers.openrouter['vendor/tiered'].price.tiers[0].cacheRead, 0.1, 'omitted tier cache categories retain the published base category');
assert.equal(providers.openrouter['vendor/scheduled'].price, undefined, 'UTC overrides cannot become a fixed base estimate');
assert.match(providers.openrouter['vendor/scheduled'].pricingNote, /UTC schedule/);
assert.equal(providers.kilo['vendor/model-0'].price.input, 0.091, 'Kilo uses its own declared token prices');
assert.equal(providers.kilo['vendor/free'].price.input, 0, 'explicit Kilo free models have zero token rates');
assert.equal(providers.kilo['vendor/dynamic'].price, undefined, 'unverified zero placeholders do not imply free access');
assert.equal(providers.kilo['vendor/dynamic'].context, 64000, 'unpriced models retain documented limits');
assert.equal(providers.cline['vendor/promotion'].price.input, 0, 'only exact official Cline promotions are free');
assert.equal(providers.cline['vendor/paid'], undefined, 'recommended models are not implicitly free');
assert.equal(providers.cline['vendor/promotion'].context, undefined, 'promotion names do not invent model limits');
assert.throws(() => normalize({ ...raw, openrouter: { data: [] } }), /incomplete model list/);
assert.throws(() => normalize({ ...raw, kilo: { data: [] } }), /incomplete model list/);
assert.throws(() => normalize({ ...raw, cline: {} }), /Incomplete catalog sources/);
assert.throws(() => normalize({ ...raw, cline: { free: [{ id: 'invalid model' }] } }), /invalid free model ID/);
assert.throws(() => normalize(raw, [{ id: 'paid', cost: [{ input: 1, output: 1 }] }]), /verified free rates/);

const ambiguous = clone(raw);
ambiguous.openrouter.data.find(model => model.id === 'vendor/tiered').pricing.overrides.push(
	{ min_prompt_tokens: 100000, prompt: '0.000004', completion: '0.000005' });
assert.equal(normalize(ambiguous).openrouter['vendor/tiered'].price, undefined, 'duplicate thresholds are explicitly unknown');
const conditional = clone(raw);
conditional.openrouter.data.find(model => model.id === 'vendor/tiered').pricing.overrides[0].region = 'fixture';
assert.equal(normalize(conditional).openrouter['vendor/tiered'].price, undefined, 'unknown rate conditions do not borrow a base price');
const malformed = clone(raw);
malformed.openrouter.data[0].pricing.overrides = {};
assert.throws(() => normalize(malformed), /Invalid openrouter pricing overrides/);
malformed.openrouter.data[0].pricing = [];
assert.throws(() => normalize(malformed), /Invalid openrouter model row/);
const malformedDirect = clone(raw);
malformedDirect.modelsdev.openai.models.fixture.cost = [];
assert.throws(() => normalize(malformedDirect), /Invalid models.dev model row/);

const official = { schema: 1, reviewed: '2026-11-14', sources: {
	'fixture-official': { url: 'https://official.fixture/models', sha256: 'b'.repeat(64), retrievedAt: '2026-11-14T00:00:00.000Z' },
}, providers: {
	openai: {
		fixture: { source: 'fixture-official', price: { input: 2, output: 8, expiresAt: 1796083200000,
			tiers: [{ above: 272000, input: 4, output: 12 }] }, context: 80000, output: 2000 },
		'new-exact-model': { source: 'fixture-official', price: { input: 1, output: 2 }, context: 65000, tools: true },
	},
	deepseek: { fixture: { source: 'fixture-official', price: null, pricingNote: 'Scheduled UTC rates.' } },
} };
const corrected = normalize(raw, undefined, official);
assert.equal(corrected.openai.fixture.price.input, 2, 'reviewed primary rates win last');
assert.equal(corrected.openai.fixture.context, 80000);
assert.equal(corrected.openai.fixture.price.expiresAt, 1796083200000, 'promotion end dates survive normalization');
assert.equal(corrected.openai['new-exact-model'].tools, true);
assert.equal(corrected.openai['new-exact-model-2099'], undefined, 'official rows do not invent snapshot aliases');
assert.equal(corrected.deepseek.fixture.price, undefined, 'an explicit null correction removes an obsolete fixed price');
assert.equal(corrected.deepseek.fixture.context, 10000, 'deleting a rate keeps independently documented limits');
assert.equal(raw.modelsdev.openai.models.fixture.cost.input, 3, 'corrections leave captured input unchanged');
assert.equal(validateOfficial(official), official);
function invalidOfficial(edit, expected) {
	const candidate = clone(official); edit(candidate); assert.throws(() => validateOfficial(candidate), expected);
}
invalidOfficial(value => { value.schema = 2; }, /Invalid official model input/);
invalidOfficial(value => { value.reviewed = '2026-02-30'; }, /Invalid official model input/);
invalidOfficial(value => { value.sources['fixture-official'].retrievedAt = '2026-11-15T00:00:00.000Z'; }, /reviewed date/);
invalidOfficial(value => { value.sources['fixture-official'].retrievedAt = '2026-11-14T24:00:00.000Z'; }, /reviewed date/);
invalidOfficial(value => { value.sources['fixture-official'].sha256 = 'bad'; }, /response hash/);
invalidOfficial(value => { value.sources['fixture-official'].url = 'http://official.fixture/models'; }, /HTTPS|reviewed date/);
invalidOfficial(value => { value.sources['fixture-official'].url = 'https://credential@official.fixture/models'; }, /reviewed date/);
invalidOfficial(value => { value.providers.openai.fixture.price.input = Number.MAX_VALUE; }, /token rate/);
invalidOfficial(value => { value.providers.openai.fixture.price.expiresAt = 1794614400000; }, /already expired/);
invalidOfficial(value => { value.providers.openai.fixture.price.expiresAt = 1796083200000.5; }, /Invalid official price field/);
invalidOfficial(value => { value.providers.openai.fixture.price.tiers.push({ above: 200000, input: 3, output: 9 }); }, /must increase/);
invalidOfficial(value => { value.providers.openai.fixture.tools = 'yes'; }, /Invalid official capability/);
invalidOfficial(value => { value.providers.openai.fixture.source = 'missing'; }, /model ID or source/);
invalidOfficial(value => { value.providers.openai['inferred alias'] = value.providers.openai.fixture; }, /model ID or source/);

// Reused captures must match both their receipt and the authored official input.
// Only these explicitly created files are removed; no recursive deletion occurs.
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'uai-model-pricing-'));
const key = 'fixture-official', url = 'https://official.fixture/models';
const receiptPath = path.join(directory, key + '.receipt.json');
const jsonPath = path.join(directory, key + '.json'), textPath = path.join(directory, key + '.txt');
try {
	const bytes = Buffer.from('{"data":[]}');
	const receipt = { url, sha256: crypto.createHash('sha256').update(bytes).digest('hex'), retrievedAt: '2026-11-14T00:00:00.000Z' };
	fs.writeFileSync(jsonPath, bytes); fs.writeFileSync(textPath, bytes); fs.writeFileSync(receiptPath, JSON.stringify(receipt));
	assert.deepEqual(capturedSource(directory, key, url).data, { data: [] });
	const capturedOfficial = clone(official); capturedOfficial.sources[key] = { ...receipt };
	assert.doesNotThrow(() => verifyOfficialCapture(directory, capturedOfficial));
	capturedOfficial.sources[key].sha256 = 'a'.repeat(64);
	assert.throws(() => verifyOfficialCapture(directory, capturedOfficial), /differs from its reviewed capture/);
	capturedOfficial.sources[key] = { ...receipt, retrievedAt: '2026-11-14T00:00:01.000Z' };
	assert.throws(() => verifyOfficialCapture(directory, capturedOfficial), /differs from its reviewed capture/);
	assert.throws(() => capturedSource(directory, key, 'https://different.fixture/models'), /URL\/date\/hash/);
	fs.writeFileSync(jsonPath, '{"data":[1]}');
	assert.throws(() => capturedSource(directory, key, url), /URL\/date\/hash/);
	fs.writeFileSync(jsonPath, bytes);
	fs.writeFileSync(receiptPath, JSON.stringify({ ...receipt, retrievedAt: '2026-11-31T00:00:00.000Z' }));
	assert.throws(() => capturedSource(directory, key, url), /URL\/date\/hash/);
} finally {
	for (const file of [jsonPath, textPath, receiptPath]) if (fs.existsSync(file)) fs.unlinkSync(file);
	fs.rmdirSync(directory);
}
assert.doesNotThrow(() => validateOfficial(JSON.parse(fs.readFileSync(path.join(__dirname, '../tools/data/model_official.json'), 'utf8'))));
const snapshot = { schema: 1, updated: '2026-10-15T00:00:00.000Z', sources: {}, providers };
assert.equal(render(JSON.parse(snapshotText(snapshot))), render(snapshot), 'offline generation is deterministic');
console.log('Model pricing normalization and reviewed provenance: all assertions passed.');
