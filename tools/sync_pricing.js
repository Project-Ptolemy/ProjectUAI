// Refresh a reviewable source snapshot, then generate model data offline.
// --refresh writes the snapshot only; default / --check generate / verify Lua.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const root = path.resolve(__dirname, '..');
const snapshotPath = path.join(__dirname, 'data', 'model_metadata.json');
const officialPath = path.join(__dirname, 'data', 'model_official.json');
const outputPath = path.join(root, 'src', 'provider', 'model_data.lua');
const SOURCES = {
	modelsdev: 'https://models.dev/api.json',
	litellm: 'https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json',
	openrouter: 'https://openrouter.ai/api/v1/models',
	kilo: 'https://api.kilo.ai/api/gateway/models',
	cline: 'https://api.cline.bot/api/v1/ai/cline/recommended-models',
};
const PROVIDERS = {
	openai: ['openai', 'openai'], anthropic: ['anthropic', 'anthropic'],
	google: ['google', 'gemini'], deepseek: ['deepseek', 'deepseek'],
	opencode: ['opencode', null], 'opencode-go': ['opencode-go', null], groq: ['groq', 'groq'],
	together: ['togetherai', 'together_ai'], mistral: ['mistral', 'mistral'],
	xai: ['xai', 'xai'], fireworks: ['fireworks-ai', 'fireworks_ai'],
	cerebras: ['cerebras', 'cerebras'],
};

function number(value, scale = 1) {
	if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) return undefined;
	const rounded = Math.round(value * scale * 1e9) / 1e9;
	return Number.isFinite(rounded) ? rounded : undefined;
}
function positive(value) { return number(value) > 0 ? Math.floor(value) : undefined; }
function id(value) { return typeof value === 'string' ? value.trim().toLowerCase() : ''; }
function clean(value) { return JSON.parse(JSON.stringify(value)); }
function object(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function timestamp(value) {
	return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value)
		&& Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === value;
}
function validateRate(rate, tier = false) {
	if (!object(rate) || number(rate.input) === undefined || number(rate.output) === undefined) throw Error('Invalid official token rate');
	const allowed = new Set(['input', 'output', 'cacheRead', 'cacheWrite', ...(tier ? ['above'] : ['tiers', 'expiresAt'])]);
	for (const [key, value] of Object.entries(rate)) {
		if (!allowed.has(key)) throw Error('Unknown official price field: ' + key);
		if (key === 'tiers') {
			if (!Array.isArray(value)) throw Error('Official price tiers must be an array');
			let previous = -1;
			for (const item of value) { validateRate(item, true); if (item.above <= previous) throw Error('Official price tiers must increase'); previous = item.above; }
		} else if (number(value) === undefined || ((key === 'above' || key === 'expiresAt') && !Number.isSafeInteger(value))) {
			throw Error('Invalid official price field: ' + key);
		}
	}
	if (tier && number(rate.above) === undefined) throw Error('Official tier needs its prompt threshold');
	if (!tier && rate.expiresAt !== undefined && rate.expiresAt <= 0) throw Error('Official price expiry must be UTC epoch milliseconds');
}
function validateOfficial(official) {
	if (!object(official) || official.schema !== 1 || !/^\d{4}-\d{2}-\d{2}$/.test(official.reviewed || '')
		|| !timestamp(official.reviewed + 'T00:00:00.000Z') || !object(official.sources) || !object(official.providers)) throw Error('Invalid official model input');
	for (const [key, source] of Object.entries(official.sources)) {
		if (!/^[a-z0-9][a-z0-9-]{0,79}$/.test(key) || Object.hasOwn(SOURCES, key) || !object(source)) throw Error('Invalid official source identity');
		let url; try { url = new URL(source.url); } catch (_) { throw Error('Official source needs its HTTPS URL'); }
		if (url.protocol !== 'https:' || url.username || url.password || !/^[a-f0-9]{64}$/.test(source.sha256 || '')
			|| !timestamp(source.retrievedAt) || source.retrievedAt.slice(0, 10) !== official.reviewed) throw Error('Official source needs its reviewed date and response hash');
	}
	const allowed = new Set(['source', 'price', 'context', 'input', 'output', 'tools', 'reasoning', 'released', 'pricingNote']);
	for (const [provider, rows] of Object.entries(official.providers)) {
		if (!Object.hasOwn(PROVIDERS, provider) || !object(rows)) throw Error('Unknown official provider: ' + provider);
		for (const [key, row] of Object.entries(rows)) {
			if (id(key) !== key || !/^[a-z0-9][a-z0-9_./:@-]{0,199}$/.test(key) || !object(row)
				|| !Object.hasOwn(official.sources, row.source)) throw Error('Invalid exact official model ID or source');
			for (const [field, value] of Object.entries(row)) {
				if (!allowed.has(field)) throw Error('Unknown official model field: ' + field);
				if (field === 'price' && value !== null) validateRate(value);
				else if (['context', 'input', 'output'].includes(field) && (!Number.isSafeInteger(value) || value <= 0)) throw Error('Invalid official model limit');
				else if (['tools', 'reasoning'].includes(field) && typeof value !== 'boolean') throw Error('Invalid official capability');
				else if (field === 'released' && !timestamp(value + 'T00:00:00.000Z')) throw Error('Invalid official release date');
				else if (field === 'pricingNote' && (typeof value !== 'string' || !value || value.length > 1000 || /[\u0000-\u001f\u007f]/.test(value))) throw Error('Invalid official price note');
			}
			if (row.price?.expiresAt && row.price.expiresAt <= Date.parse(official.reviewed + 'T00:00:00.000Z')) throw Error('Official promotional rate has already expired');
		}
	}
	return official;
}
function price(cost, scale = 1) {
	if (!cost || number(cost.input) === undefined || number(cost.output) === undefined) return undefined;
	return clean({ input: number(cost.input, scale), output: number(cost.output, scale),
		cacheRead: number(cost.cache_read, scale), cacheWrite: number(cost.cache_write, scale) });
}
function modelsdevRow(model) {
	const cost = model.cost || {}, limit = model.limit || {};
	const row = { source: 'modelsdev', price: price(cost), context: positive(limit.context),
		input: positive(limit.input), output: positive(limit.output),
		tools: typeof model.tool_call === 'boolean' ? model.tool_call : undefined,
		reasoning: typeof model.reasoning === 'boolean' ? model.reasoning : undefined };
	const tiers = (cost.tiers || []).filter(t => t.tier && t.tier.type === 'context' && positive(t.tier.size) && price(t))
		.map(t => ({ above: positive(t.tier.size), ...price(t) })).sort((a, b) => a.above - b.above);
	if (!tiers.length && price(cost.context_over_200k)) tiers.push({ above: 200000, ...price(cost.context_over_200k) });
	if (row.price && tiers.length) row.price.tiers = tiers;
	return clean(row);
}
function litellmRow(model) {
	return clean({ source: 'litellm', price: price({ input: model.input_cost_per_token,
		output: model.output_cost_per_token, cache_read: model.cache_read_input_token_cost,
		cache_write: model.cache_creation_input_token_cost }, 1e6),
		context: positive(model.max_input_tokens), output: positive(model.max_output_tokens),
		tools: typeof model.supports_function_calling === 'boolean' ? model.supports_function_calling : undefined,
		reasoning: typeof model.supports_reasoning === 'boolean' ? model.supports_reasoning : undefined });
}
function openrouterRow(model, source = 'openrouter') {
	if (!object(model) || model.pricing !== undefined && !object(model.pricing)
		|| model.top_provider !== undefined && !object(model.top_provider)) throw Error('Invalid ' + source + ' model row');
	const cost = model.pricing || {};
	const decimal = value => typeof value === 'string' && value.trim() !== '' && Number.isFinite(Number(value)) && Number(value) >= 0 ? Number(value) : undefined;
	const row = { source, price: price({ input: decimal(cost.prompt), output: decimal(cost.completion),
		cache_read: decimal(cost.input_cache_read), cache_write: decimal(cost.input_cache_write) }, 1e6),
		context: positive(model.context_length), output: positive((model.top_provider || {}).max_completion_tokens),
		tools: Array.isArray(model.supported_parameters) ? model.supported_parameters.includes('tools') : undefined,
		reasoning: Array.isArray(model.supported_parameters) ? model.supported_parameters.includes('reasoning') : undefined };
	if (cost.overrides !== undefined && !Array.isArray(cost.overrides)) throw Error('Invalid ' + source + ' pricing overrides');
	if (row.price && cost.overrides?.length) {
		const fields = new Set(['min_prompt_tokens', 'prompt', 'completion', 'input_cache_read', 'input_cache_write',
			'input_cache_write_1h', 'audio', 'input_audio_cache']);
		if (cost.overrides.some(t => object(t) && (Object.hasOwn(t, 'utc_start') || Object.hasOwn(t, 'utc_end')))) {
			delete row.price; row.pricingNote = 'Rates vary by UTC schedule; fixed text-token estimates are unavailable.';
		} else if (cost.overrides.some(t => !object(t) || !Number.isSafeInteger(t.min_prompt_tokens) || t.min_prompt_tokens < 1
			|| Object.keys(t).some(key => !fields.has(key)))) {
			delete row.price; row.pricingNote = 'The catalog uses unsupported price conditions; fixed text-token estimates are unavailable.';
		} else {
			const tiers = cost.overrides.map(t => ({ above: t.min_prompt_tokens - 1,
				rate: price({ input: decimal(t.prompt), output: decimal(t.completion),
					cache_read: decimal(t.input_cache_read), cache_write: decimal(t.input_cache_write) }, 1e6) }))
				.sort((a, b) => a.above - b.above);
			if (tiers.some((t, index) => !t.rate || index > 0 && t.above === tiers[index - 1].above)) {
				delete row.price; row.pricingNote = 'Context price tiers are incomplete or ambiguous; fixed text-token estimates are unavailable.';
			} else row.price.tiers = tiers.map(t => ({ ...row.price, ...t.rate, above: t.above }));
		}
	}
	if (!row.price && !row.pricingNote) row.pricingNote = 'No fixed text-token rate is published for this route.';
	return clean(row);
}
function normalize(raw, cliModels, official) {
	if (!object(raw) || !object(raw.modelsdev) || !object(raw.litellm) || !Array.isArray(raw.openrouter?.data)
		|| !Array.isArray(raw.kilo?.data) || !Array.isArray(raw.cline?.free)) throw Error('Incomplete catalog sources');
	const providers = {};
	for (const [provider, [modelsdevId, litellmId]] of Object.entries(PROVIDERS)) {
		const catalog = raw.modelsdev[modelsdevId];
		if (!object(catalog) || !object(catalog.models) || !Object.keys(catalog.models).length) throw Error('Missing models.dev provider: ' + modelsdevId);
		const rows = providers[provider] = {};
		for (const [key, model] of Object.entries(raw.litellm)) {
			if (!litellmId || !model || model.litellm_provider !== litellmId || model.mode !== 'chat') continue;
			const prefix = litellmId + '/';
			const keyId = id(key.startsWith(prefix) ? key.slice(prefix.length) : key);
			const row = litellmRow(model);
			if (keyId && row.price) rows[keyId] = row;
		}
		for (const [key, model] of Object.entries(catalog.models)) {
			if (!object(model) || model.cost != null && !object(model.cost)
				|| model.limit !== undefined && !object(model.limit)) throw Error('Invalid models.dev model row: ' + provider + '/' + key);
			if (model.modalities && Array.isArray(model.modalities.output) && !model.modalities.output.includes('text')) continue;
			const keyId = id(key), row = modelsdevRow(model);
			// Go uses subscription billing; token catalog rates alone do not establish
			// an additional per-request charge. Keep its independently documented limits.
			if (provider === 'opencode-go') delete row.price;
			if (keyId && (row.price || row.context)) rows[keyId] = row;
		}
	}
	providers.openrouter = {};
	for (const model of raw.openrouter.data) {
		const row = openrouterRow(model), keyId = id(model.id);
		if (keyId && (row.price || row.context)) providers.openrouter[keyId] = row;
	}
	if (Object.keys(providers.openrouter).length < 100) throw Error('OpenRouter returned an incomplete model list');
	providers.kilo = {};
	for (const model of raw.kilo.data) {
		const row = openrouterRow(model, 'kilo'), keyId = id(model.id);
		// A zero placeholder for a non-free route is not a published free rate.
		if (row.price && row.price.input === 0 && row.price.output === 0 && model.isFree !== true) {
			delete row.price; row.pricingNote = 'Zero catalog placeholders do not establish a free text-token rate.';
		}
		if (keyId && (row.price || row.context)) providers.kilo[keyId] = row;
	}
	if (Object.keys(providers.kilo).length < 100) throw Error('Kilo returned an incomplete model list');
	providers.cline = {};
	for (const model of raw.cline.free) {
		const keyId = id(model?.id);
		if (!keyId || !/^[a-z0-9][a-z0-9_./:-]{0,199}$/.test(keyId)) throw Error('Cline returned an invalid free model ID');
		// The official promotion feed establishes free text tokens only. It does
		// not establish limits or a relationship to a similarly named paid model.
		providers.cline[keyId] = { source: 'cline', price: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } };
	}
	if (cliModels !== undefined) {
		if (!Array.isArray(cliModels) || !cliModels.length) throw Error('OpenCode catalog must be a nonempty array');
		for (const model of cliModels) {
			const keyId = id(model.modelID || model.id), costs = model.cost;
			if (!keyId || !(keyId === 'big-pickle' || keyId.endsWith('-free') || keyId.endsWith(':free'))
				|| !Array.isArray(costs) || !costs.length || costs.some(c => c.input !== 0 || c.output !== 0
					|| !c.cache || c.cache.read !== 0 || c.cache.write !== 0)) throw Error('OpenCode snapshot contains a model without verified free rates');
			const limit = model.limit || {};
			if (!positive(limit.context) || !positive(limit.output)) throw Error('OpenCode model has no limits: ' + keyId);
			// models.dev is what OpenCode itself checks requests against, so its
			// server-enforced limits win over a possibly stale public CLI catalog.
			// The CLI snapshot still supplies verified free rates and tool support.
			const documented = providers.opencode[keyId] || {};
			providers.opencode[keyId] = clean({ source: 'opencode-cli', price: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
				context: documented.context || positive(limit.context),
				input: documented.input || positive(limit.input),
				output: documented.output || positive(limit.output),
				tools: model.capabilities && model.capabilities.tools === true,
				reasoning: documented.reasoning });
		}
	}
	if (official !== undefined) {
		validateOfficial(official);
		for (const [provider, rows] of Object.entries(official.providers)) {
			for (const [key, override] of Object.entries(rows)) {
				const row = { ...(providers[provider][key] || {}), ...clean(override) };
				if (row.price === null) delete row.price;
				if (Object.hasOwn(override, 'price') && !Object.hasOwn(override, 'pricingNote')) delete row.pricingNote;
				providers[provider][key] = row;
			}
		}
	}
	return providers;
}
function snapshotText(snapshot) {
	const lines = ['{', '\t"schema": 1,', '\t"updated": ' + JSON.stringify(snapshot.updated) + ',',
		'\t"sources": ' + JSON.stringify(snapshot.sources) + ',', '\t"providers": {'];
	const providers = Object.keys(snapshot.providers).sort();
	providers.forEach((provider, pi) => {
		lines.push('\t\t' + JSON.stringify(provider) + ': {');
		const rows = snapshot.providers[provider], keys = Object.keys(rows).sort();
		keys.forEach((key, i) => lines.push('\t\t\t' + JSON.stringify(key) + ': ' + JSON.stringify(rows[key]) + (i + 1 < keys.length ? ',' : '')));
		lines.push('\t\t}' + (pi + 1 < providers.length ? ',' : ''));
	});
	return lines.concat(['\t}', '}', '']).join('\n');
}
function lua(value) {
	if (typeof value === 'string') {
		if (/[\u0000-\u001f\u007f]/.test(value)) throw Error('Unexpected control character in model metadata');
		return JSON.stringify(value);
	}
	if (typeof value === 'boolean' || typeof value === 'number') return String(value);
	if (Array.isArray(value)) return '{ ' + value.map(lua).join(', ') + ' }';
	return '{ ' + Object.keys(value).sort().map(key => '[' + lua(key) + '] = ' + lua(value[key])).join(', ') + ' }';
}
function render(snapshot) {
	if (snapshot.schema !== 1 || !snapshot.updated || !snapshot.providers) throw Error('Unsupported model metadata snapshot');
	const lines = ['-- Generated by tools/sync_pricing.js; edit the source snapshot, then regenerate.',
		'-- Text-token USD rates per million; catalog snapshot ' + snapshot.updated + '.', 'return function(env)',
		'\treturn {', '\t\tupdated = ' + lua(snapshot.updated) + ',', '\t\tproviders = {'];
	for (const provider of Object.keys(snapshot.providers).sort()) {
		lines.push('\t\t\t[' + lua(provider) + '] = {');
		for (const key of Object.keys(snapshot.providers[provider]).sort()) lines.push('\t\t\t\t[' + lua(key) + '] = ' + lua(snapshot.providers[provider][key]) + ',');
		lines.push('\t\t\t},');
	}
	return lines.concat(['\t\t},', '\t}', 'end', '']).join('\n');
}
async function fetchSource(url) {
	const response = await fetch(url, { headers: { 'User-Agent': 'ProjectUAI-Metadata/4.0' }, signal: AbortSignal.timeout(30000) });
	if (!response.ok) throw Error(url + ': HTTP ' + response.status);
	const bytes = Buffer.from(await response.arrayBuffer());
	return { data: JSON.parse(bytes.toString('utf8')), sha256: crypto.createHash('sha256').update(bytes).digest('hex'),
		retrievedAt: new Date().toISOString(), lastModified: response.headers.get('last-modified') || undefined };
}
function capturedReceipt(directory, key, extension, url) {
	const bytes = fs.readFileSync(path.join(directory, key + '.' + extension));
	const receipt = JSON.parse(fs.readFileSync(path.join(directory, key + '.receipt.json'), 'utf8'));
	const sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
	if (!object(receipt) || receipt.url !== url || receipt.sha256 !== sha256 || !timestamp(receipt.retrievedAt)) throw Error('Captured source failed its URL/date/hash check: ' + key);
	return { bytes, sha256, retrievedAt: receipt.retrievedAt, lastModified: receipt.lastModified || undefined };
}
function capturedSource(directory, key, url) {
	const source = capturedReceipt(directory, key, 'json', url);
	return { ...source, bytes: undefined, data: JSON.parse(source.bytes.toString('utf8')) };
}
function verifyOfficialCapture(directory, official) {
	for (const [key, source] of Object.entries(official.sources)) {
		const captured = capturedReceipt(directory, key, 'txt', source.url);
		if (captured.sha256 !== source.sha256 || captured.retrievedAt !== source.retrievedAt) throw Error('Official correction differs from its reviewed capture: ' + key);
	}
}
async function main(args) {
	const flags = new Set(['--refresh', '--check']);
	let cliPath, cliVersion, sourcesDirectory;
	for (let i = 0; i < args.length; i++) {
		if (args[i] === '--opencode-catalog') cliPath = args[++i];
		else if (args[i] === '--opencode-version') cliVersion = args[++i];
		else if (args[i] === '--sources-dir') {
			sourcesDirectory = args[++i];
			if (!sourcesDirectory || sourcesDirectory.startsWith('--')) throw Error('--sources-dir needs its captured input directory');
		}
		else if (!flags.has(args[i])) throw Error('Unknown argument: ' + args[i]);
	}
	if (args.includes('--refresh')) {
		if (args.includes('--check')) throw Error('--refresh and --check are separate review steps');
		if (Boolean(cliPath) !== Boolean(cliVersion)) throw Error('Supply both --opencode-catalog and --opencode-version');
		const raw = {}, sources = {};
		const official = validateOfficial(JSON.parse(fs.readFileSync(officialPath, 'utf8')));
		if (sourcesDirectory) verifyOfficialCapture(path.resolve(sourcesDirectory), official);
		await Promise.all(Object.entries(SOURCES).map(async ([key, url]) => {
			const source = sourcesDirectory ? capturedSource(path.resolve(sourcesDirectory), key, url) : await fetchSource(url);
			raw[key] = source.data; sources[key] = { url, sha256: source.sha256, retrievedAt: source.retrievedAt,
				...(source.lastModified ? { lastModified: source.lastModified } : {}) };
		}));
		Object.assign(sources, official.sources);
		const cutoff = Math.max(...Object.values(sources).map(source => Date.parse(source.retrievedAt)));
		const updated = new Date(cutoff).toISOString();
		if (official.reviewed !== updated.slice(0, 10)) throw Error('Review model_official.json against the current official sources before refreshing this date');
		let cliModels;
		if (cliPath) {
			cliModels = JSON.parse(fs.readFileSync(cliPath, 'utf8'));
			sources['opencode-cli'] = { url: 'https://opencode.ai', version: cliVersion,
				description: 'Public plugin GET /api/model; only normalized free prices and limits retained' };
		}
		const snapshot = { schema: 1, updated, sources: Object.fromEntries(Object.keys(sources).sort().map(key => [key, sources[key]])),
			providers: normalize(raw, cliModels, official) };
		fs.mkdirSync(path.dirname(snapshotPath), { recursive: true });
		fs.writeFileSync(snapshotPath, snapshotText(snapshot));
		console.log('Updated tools/data/model_metadata.json. Review it before generating Lua.');
		return;
	}
	if (cliPath || cliVersion || sourcesDirectory) throw Error('Captured source and OpenCode catalog options require --refresh');
	const snapshot = JSON.parse(fs.readFileSync(snapshotPath, 'utf8'));
	const output = render(snapshot);
	if (args.includes('--check')) {
		if (!fs.existsSync(outputPath) || fs.readFileSync(outputPath, 'utf8') !== output) throw Error('Model data is stale; run node tools/sync_pricing.js after reviewing the snapshot');
		console.log('Model metadata matches its reviewed snapshot.');
	} else {
		fs.writeFileSync(outputPath, output);
		console.log('Generated src/provider/model_data.lua (' + Object.values(snapshot.providers).reduce((n, p) => n + Object.keys(p).length, 0) + ' provider/model entries).');
	}
}
module.exports = { normalize, render, snapshotText, validateOfficial, capturedSource, verifyOfficialCapture };
if (require.main === module) main(process.argv.slice(2)).catch(error => { console.error(error.message); process.exitCode = 1; });
