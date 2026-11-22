'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createOpenCode, official, nativeHeadersAllowed, findBinary, responseBody, promptInput, toolDefinitions } = require('../opencode');
const { createInference } = require('../inference');
const { sleep } = require('./helpers/bridge');

function native(t, environment = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'uai-native-fixture-'));
  const log = path.join(directory, 'events.jsonl');
  const backend = createOpenCode({ binary: process.execPath, binaryArgs: [path.join(__dirname, 'fixtures', 'opencode-cli.js')],
    env: { ...process.env, UAI_OPENCODE_DISABLED: '0', UAI_OPENCODE_FIXTURE_LOG: log, ...environment }, startupMs: 5000, pollMs: 10 });
  t.after(async () => { await backend.close(); fs.rmSync(directory, { recursive: true, force: true }); });
  return { backend, events: () => fs.readFileSync(log, 'utf8').trim().split('\n').map(JSON.parse) };
}
const input = text => ({ model: 'fixture-free', messages: [{ role: 'user', content: text }] });
const url = 'https://opencode.ai/zen/v1/chat/completions';

test('native server discovery confines process, Basic auth and temporary files', async t => {
  const { backend, events } = native(t);
  assert.equal(backend.capability().state, 'starting');
  const models = await backend.models(); assert.equal(models.data[0].id, 'fixture-free');
  assert.equal(models.data.length, 1, 'only verified zero-price models use the public native connection');
  assert.equal(backend.accepts(url, JSON.stringify(input('public')), { Authorization: 'Bearer public' }), true);
  for (const headers of [{ Authorization: 'Bearer fixture-personal-key' }, { 'x-api-key': 'fixture-private' },
    { Authorization: 'Bearer public', 'X-Org-Id': 'fixture-workspace' }, { Cookie: 'fixture-cookie' }]) {
    assert.equal(backend.accepts(url, JSON.stringify(input('credential precedence')), headers), false,
      'native free access must not discard provider or workspace credentials');
  }
  assert.equal(backend.accepts(url, JSON.stringify({ model: 'fixture-paid' })), false);
  for (const base of ['https://opencode.ai/inference/go/v1', 'https://opencode.ai/zen/go/v1']) {
    for (const route of ['/chat/completions', '/responses']) {
      assert.equal(backend.accepts(base + route, JSON.stringify(input('Go subscription request'))), false,
        'Go retains its keyed endpoint even when a model id also exists in the free catalog');
    }
  }
  assert.equal(backend.capability().state, 'ready');
  assert.equal(backend.capability().version, '2.0.32');
  assert.equal(backend.capability().binary, path.basename(process.execPath));
  assert.doesNotMatch(JSON.stringify(backend.capability()), /password|pid|directory|127\.0\.0\.1/);
  const ready = events().find(e => e.type === 'ready');
  assert.equal(ready.passwordLength, 64); assert.equal(ready.isolated, true);
  assert.equal((await fetch('http://127.0.0.1:' + ready.port + '/api/model')).status, 401);
  await backend.close(); assert.equal(backend.capability().available, false);
  assert.equal(fs.existsSync(ready.directory), false);
  await assert.rejects(fetch('http://127.0.0.1:' + ready.port + '/api/model'));
});

test('disabled native tunnel never starts even with a configured binary', async t => {
  const backend = createOpenCode({ binary: process.execPath, env: { UAI_OPENCODE_DISABLED: '1' } });
  t.after(() => backend.close());
  assert.equal(backend.capability().enabled, false);
  assert.equal(backend.capability().state, 'disabled');
  assert.equal(backend.capability().available, false);
  assert.match(backend.capability().message, /turned off/);
  await assert.rejects(backend.models(), /turned off/);
  assert.equal(backend.accepts(url, JSON.stringify(input('ignored'))), false);
});

test('a ready free CLI leaves personal provider credentials on the original HTTPS request', { concurrency: false }, async t => {
  const { backend, events } = native(t);
  await backend.models();
  const https = require('node:https'), { EventEmitter } = require('node:events'), { Readable } = require('node:stream');
  const calls = [];
  t.mock.method(https, 'request', (target, options, callback) => {
    const call = { url: target.href, options }; calls.push(call);
    const outbound = new EventEmitter();
    outbound.setTimeout = () => outbound;
    outbound.destroy = () => outbound;
    outbound.end = body => {
      call.body = body;
      queueMicrotask(() => {
        outbound.emit('finish');
        const response = Readable.from(['{"choices":[{"message":{"content":"PONG"}}]}']);
        response.statusCode = 200; response.headers = { 'content-type': 'application/json' }; callback(response);
      });
    };
    return outbound;
  });
  const relay = createInference({ opencode: backend }); t.after(() => relay.close());
  const headers = { Authorization: 'Bearer fixture-personal-key', 'x-org-id': 'fixture-workspace', 'X-Fixture': 'retained' };
  const body = JSON.stringify(input('Reply PONG.'));
  const submitted = { id: 'personal-key-precedence', instance: relay.instance, url, body, headers };
  relay.start(submitted);
  await sleep(10);
  assert.equal(relay.get(submitted.id).state, 'completed');
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, url);
  assert.equal(calls[0].body, body);
  for (const [name, value] of Object.entries(headers)) assert.equal(calls[0].options.headers[name], value);
  assert.equal(typeof calls[0].options.ciphers, 'string');
  assert.ok(!events().some(event => event.type === 'session'), 'the CLI did not create or replay an inference session');
  relay.start(submitted); await sleep(10);
  assert.equal(calls.length, 1, 'the existing accepted receipt prevents a second API send');
});

test('incompatible installed API fails before creating a session', async t => {
  const { backend, events } = native(t, { UAI_OPENCODE_FIXTURE_OLD_API: '1', UAI_OPENCODE_FIXTURE_VERSION: '1.19.3' });
  await assert.rejects(backend.start(), /incompatible server API/);
  assert.equal(backend.capability().state, 'failed');
  assert.equal(backend.capability().available, false);
  assert.match(backend.capability().message, /incompatible server API/);
  assert.equal(backend.capability().version, '1.19.3');
  assert.match(backend.capability().message, /1\.19\.3.*@opencode\/cli/);
  assert.ok(!events().some(event => event.type === 'session'));
});

test('an incompatible PATH CLI cannot hide the compatible installed npm CLI', async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'uai-native-discovery-'));
  let backend;
  t.after(async () => { await backend?.close(); fs.rmSync(directory, { recursive: true, force: true }); });
  const windows = process.platform === 'win32', name = windows ? 'opencode.exe' : 'opencode';
  const direct = path.join(directory, 'bin');
  const modules = path.join(directory, windows ? 'bin' : 'lib', 'node_modules');
  const legacy = path.join(direct, name), compatible = path.join(modules, '@opencode', 'cli', 'bin', name);
  for (const file of [legacy, compatible]) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    try { fs.linkSync(process.execPath, file); } catch { fs.copyFileSync(process.execPath, file); }
  }
  const log = path.join(directory, 'events.jsonl'), absent = path.join(directory, 'absent');
  const env = { ...process.env, PATH: direct, LOCALAPPDATA: absent, APPDATA: absent, USERPROFILE: absent, HOME: absent,
    ProgramFiles: absent, 'ProgramFiles(x86)': absent, BUN_INSTALL: absent, NVM_SYMLINK: absent, NVM_BIN: absent,
    NPM_CONFIG_PREFIX: absent, PNPM_HOME: absent, UAI_OPENCODE_BINARY: '', UAI_OPENCODE_DISABLED: '0',
    UAI_OPENCODE_FIXTURE_LOG: log, UAI_OPENCODE_FIXTURE_OLD_BINARY: fs.realpathSync(legacy) };
  assert.equal(findBinary(env), fs.realpathSync(legacy), 'the legacy executable is the first discovery candidate');
  backend = createOpenCode({ env, binaryArgs: [path.join(__dirname, 'fixtures', 'opencode-cli.js')], startupMs: 5000, pollMs: 10 });
  const models = await backend.models();
  assert.equal(models.data[0].id, 'fixture-free');
  assert.equal(backend.capability().state, 'ready');
  assert.equal(backend.capability().version, '2.0.32');
  const events = fs.readFileSync(log, 'utf8').trim().split('\n').map(JSON.parse);
  const ready = events.filter(event => event.type === 'ready');
  assert.deepEqual(ready.map(event => event.legacy), [true, false]);
  assert.throws(() => process.kill(ready[0].pid, 0), { code: 'ESRCH' }, 'the rejected server is stopped before replacement');
  assert.equal(events.filter(event => event.type === 'session' || event.type === 'prompt').length, 0,
    'candidate selection never submits inference');
});

test('native inference retains one job, translates tool handoff and cleans sessions', async t => {
  const { backend, events } = native(t), frames = [];
  await backend.start();
  const relay = createInference({ opencode: backend, publish: frame => frames.push(frame) }); t.after(() => relay.close());
  const body = { ...input('USE_TOOL'), tools: [{ type: 'function', function: { name: 'lookup', parameters: { type: 'object', properties: { value: { type: 'string' } } } } }] };
  const request = { id: 'native_tool_handoff', instance: relay.instance, url, sessionId: 'roblox_fixture', body: JSON.stringify(body), headers: { authorization: 'Bearer public' } };
  assert.equal(backend.accepts(url, request.body, request.headers), true, 'the public fixture qualifies for native handoff before dispatch');
  relay.start(request); relay.start(request);
  for (let i = 0; i < 300 && relay.get(request.id).state === 'running'; i++) await sleep(10);
  const result = relay.get(request.id); assert.equal(result.state, 'completed', result.error);
  const response = JSON.parse(result.body), tool = response.choices[0].message.tool_calls[0];
  assert.equal(tool.function.name, 'lookup'); assert.deepEqual(JSON.parse(tool.function.arguments), { value: 'fixture' });
  assert.equal(response.choices[0].finish_reason, 'tool_calls');
  relay.start(request);
  assert.equal(events().filter(e => e.type === 'prompt').length, 1);
  assert.equal(events().filter(e => e.type === 'delete').length, 1);
  const rules = events().find(e => e.type === 'session').permissions;
  assert.deepEqual(rules, [{ action: '*', resource: '*', effect: 'ask' }, { action: 'uai_lookup', resource: '*', effect: 'allow' }]);
  assert.ok(frames.some(e => e.kind === 'inference:delta' && e.text === 'Checking Roblox.'));
  assert.doesNotMatch(JSON.stringify(events()), /Bearer|Basic/);
});

test('native stop interrupts the owned session and never dispatches again', async t => {
  const { backend, events } = native(t); await backend.start();
  const controller = new AbortController();
  const pending = backend.request({ body: JSON.stringify(input('WAIT_FOREVER')), url, signal: controller.signal });
  const rejected = assert.rejects(pending, /Stopped|aborted/i);
  for (let i = 0; i < 200 && !events().some(e => e.type === 'prompt'); i++) await sleep(10);
  controller.abort(); await rejected;
  assert.equal(events().filter(e => e.type === 'prompt').length, 1);
  assert.ok(events().some(e => e.type === 'interrupt')); assert.ok(events().some(e => e.type === 'delete'));
});

test('native blocked host actions return correction receipts and the next request hands off Roblox tools', async t => {
  const { backend, events } = native(t), frames = [];
  const relay = createInference({ opencode: backend }); t.after(() => relay.close());
  await backend.start();
  const request = { id: 'native_host_receipt', instance: relay.instance, url, body: JSON.stringify(input('HOST_ACTION')) };
  relay.start(request); relay.start(request);
  for (let attempt = 0; attempt < 300 && relay.get(request.id).state === 'running'; attempt++) await sleep(10);
  const result = relay.get(request.id); assert.equal(result.state, 'completed', result.error);
  const response = JSON.parse(result.body), call = response.choices[0].message.tool_calls[0];
  assert.equal(response.choices[0].finish_reason, 'tool_calls');
  assert.equal(call.function.name, 'opencode_host_action');
  assert.deepEqual(JSON.parse(call.function.arguments), { name: 'bash' });
  assert.doesNotMatch(result.body, /never execute this host command/);
  relay.start(request);
  assert.equal(events().filter(e => e.type === 'prompt').length, 1, 'retained receipts never repeat provider inference');
  assert.ok(events().some(e => e.type === 'interrupt')); assert.ok(events().some(e => e.type === 'delete'));
  const tools = [{ type: 'function', function: { name: 'lookup' } }];
  const next = await backend.request({ body: JSON.stringify({ model: 'fixture-free', tools, messages: [
    { role: 'user', content: 'HOST_ACTION' }, { role: 'assistant', tool_calls: [call] },
    { role: 'tool', tool_call_id: call.id, content: 'No host action ran. Use the declared Roblox lookup tool.' },
    { role: 'user', content: 'HOST_THEN_TOOL' }
  ] }), url, onFrame: frame => {
    if (frame.choices?.[0]?.delta?.tool_calls) {
      const sessionID = events().filter(e => e.type === 'prompt').at(-1).id;
      assert.ok(events().some(e => e.type === 'interrupt' && e.id === sessionID),
        'the native session is interrupted before tool previews are delivered');
    }
    frames.push(frame);
  } });
  assert.equal(JSON.parse(next.body).choices[0].message.tool_calls[0].function.name, 'lookup');
  assert.deepEqual(frames.flatMap(frame => frame.choices?.[0]?.delta?.tool_calls || []).map(value => value.function.name), ['lookup']);
  assert.equal(events().filter(e => e.type === 'prompt').length, 2, 'each conversation request dispatches exactly once');
  assert.equal(events().filter(e => e.type === 'delete').length, 2);
  assert.ok(!events().some(e => e.type === 'permission-reply' || e.type === 'mcp-result'),
    'host permissions and held remote MCP results are never completed in OpenCode');
});

test('native Responses carries blocked host receipts and ordinary text', async t => {
  const { backend, events } = native(t);
  const blocked = await backend.request({ body: JSON.stringify(input('HOST_ACTION')), url: 'https://opencode.ai/inference/v1/responses' });
  const call = JSON.parse(blocked.body).output.find(part => part.type === 'function_call');
  assert.equal(call.name, 'opencode_host_action'); assert.deepEqual(JSON.parse(call.arguments), { name: 'bash' });
  assert.equal(call.id, call.call_id);
  const reply = await backend.request({ body: JSON.stringify({ model: 'fixture-free', input: 'Reply PONG' }), url: 'https://opencode.ai/inference/v1/responses' });
  const response = JSON.parse(reply.body);
  assert.equal(response.status, 'completed'); assert.equal(response.output[1].content[0].text, 'PONG');
  assert.equal(events().filter(e => e.type === 'prompt').length, 2);
});

test('native mixed tools preserve streamed order despite reverse MCP arrival and reordered argument keys', async t => {
  const { backend, events } = native(t), frames = [], tools = [{ type: 'function', function: { name: 'lookup' } }];
  const reply = await backend.request({ body: JSON.stringify({ ...input('MIXED_HOST_TOOL'), tools }), url, onFrame: frame => {
    if (frame.choices?.[0]?.delta?.tool_calls) assert.ok(events().some(e => e.type === 'interrupt'));
    frames.push(frame);
  } });
  const calls = JSON.parse(reply.body).choices[0].message.tool_calls;
  assert.deepEqual(calls.map(call => call.function.name), ['lookup', 'opencode_host_action', 'lookup', 'opencode_host_action']);
  assert.deepEqual(calls.map(call => JSON.parse(call.function.arguments)), [
    { nested: { b: 2, a: 1 }, value: 'first' }, { name: 'bash' }, { value: 'last' }, { name: 'read' }
  ]);
  assert.equal(new Set(calls.map(call => call.id)).size, 4);
  assert.deepEqual(events().filter(e => e.type === 'mcp-call').map(e => e.value), ['last', 'first']);
  assert.deepEqual(frames.flatMap(frame => frame.choices?.[0]?.delta?.tool_calls || []).map(call => call.index), [0, 1, 2, 3]);
  assert.doesNotMatch(reply.body, /never execute this host command|private-host-file/);
  assert.equal(events().filter(e => e.type === 'prompt').length, 1);
  assert.ok(!events().some(e => e.type === 'permission-reply' || e.type === 'mcp-result'));
});

test('native undeclared uai names produce blocked receipts without impersonating remote tools', async t => {
  const { backend, events } = native(t), tools = [{ type: 'function', function: { name: 'lookup' } }];
  const reply = await backend.request({ body: JSON.stringify({ ...input('UNKNOWN_UAI_TOOL'), tools }), url });
  const call = JSON.parse(reply.body).choices[0].message.tool_calls[0];
  assert.equal(call.function.name, 'opencode_host_action');
  assert.deepEqual(JSON.parse(call.function.arguments), { name: 'uai_not_declared' });
  assert.ok(!events().some(e => e.type === 'mcp-call' || e.type === 'permission-reply'));
});

test('native execute wrapper is gated before any confined code or HTTP effect', async t => {
  const { backend, events } = native(t);
  const reply = await backend.request({ body: JSON.stringify(input('EXECUTE_WRAPPER')), url });
  const call = JSON.parse(reply.body).choices[0].message.tool_calls[0];
  assert.equal(call.function.name, 'opencode_host_action');
  assert.deepEqual(JSON.parse(call.function.arguments), { name: 'execute' });
  assert.ok(events().some(event => event.type === 'guard-blocked' && event.tool === 'execute' && event.action === 'opencode_host_action'));
  assert.ok(!events().some(event => event.type === 'host-effect' || event.type === 'guard-allowed'));
  assert.doesNotMatch(reply.body, /host-effect\.invalid|fetch\(/);
  assert.equal(events().filter(event => event.type === 'prompt').length, 1);
});

test('native handoff waits for delayed guard permissions and streamed input without exposing partial batches', async t => {
  const { backend, events } = native(t), tools = [{ type: 'function', function: { name: 'lookup' } }];
  for (const marker of ['HOST_ACTION DELAY_PERMISSION', 'HOST_STREAMING STREAM_TRANSITION DELAY_PERMISSION', 'MIXED_HOST_TOOL DELAY_PERMISSION']) {
    const frames = [];
    const reply = await backend.request({ body: JSON.stringify({ ...input(marker), tools }), url, onFrame: frame => {
      if (frame.choices?.[0]?.delta?.tool_calls) {
        const session = events().filter(event => event.type === 'session').at(-1).id;
        assert.ok(events().some(event => event.type === 'interrupt' && event.id === session));
        assert.equal(events().filter(event => event.type === 'guard-blocked' && event.id === session).length, marker.includes('MIXED') ? 2 : 1);
      }
      frames.push(frame);
    } });
    const calls = JSON.parse(reply.body).choices[0].message.tool_calls;
    assert.deepEqual(calls.map(call => call.function.name), marker.includes('MIXED') ? ['lookup', 'opencode_host_action', 'lookup', 'opencode_host_action'] : ['opencode_host_action']);
    assert.equal(frames.flatMap(frame => frame.choices?.[0]?.delta?.tool_calls || []).length, calls.length);
  }
  assert.ok(!events().some(event => event.type === 'host-effect' || event.type === 'permission-reply'));
});

test('native per-location guard readiness is verified before inference admission', async t => {
  const { backend, events } = native(t, { UAI_OPENCODE_FIXTURE_PENDING_GUARD: '1' });
  const reply = await backend.request({ body: JSON.stringify(input('Reply PONG')), url });
  assert.equal(JSON.parse(reply.body).choices[0].message.content, 'PONG');
  assert.equal(events().filter(event => event.type === 'guard-pending').length, 2);
  const promptAt = events().findIndex(event => event.type === 'prompt');
  assert.ok(events().slice(0, promptAt).some(event => event.type === 'guard-loaded' && event.location !== events().find(event => event.type === 'ready').directory));
});

test('native inactive request-location guard rejects before submitting any prompt', async t => {
  const { backend, events } = native(t, { UAI_OPENCODE_FIXTURE_INACTIVE_GUARD: 'location' });
  await assert.rejects(backend.request({ body: JSON.stringify(input('EXECUTE_WRAPPER')), url }), /guard.*load/i);
  assert.ok(!events().some(event => event.type === 'prompt' || event.type === 'host-effect'));
  assert.equal(events().filter(event => event.type === 'delete').length, 1);
});

test('native desktop gate grants only the current session exact declared tools', async t => {
  const { backend, events } = native(t), tools = [{ type: 'function', function: { name: 'lookup' } }];
  const [declared, undeclared] = await Promise.all([
    backend.request({ body: JSON.stringify({ ...input('USE_TOOL'), tools }), url }),
    backend.request({ body: JSON.stringify(input('UNDECLARED_LOOKUP')), url })
  ]);
  assert.equal(JSON.parse(declared.body).choices[0].message.tool_calls[0].function.name, 'lookup');
  const refused = JSON.parse(undeclared.body).choices[0].message.tool_calls[0];
  assert.equal(refused.function.name, 'opencode_host_action');
  assert.deepEqual(JSON.parse(refused.function.arguments), { name: 'uai_lookup' });
  const allowed = events().filter(event => event.type === 'guard-allowed'), blocked = events().filter(event => event.type === 'guard-blocked');
  assert.equal(allowed.length, 1); assert.equal(blocked.length, 1); assert.notEqual(allowed[0].id, blocked[0].id);
  assert.ok(!events().some(event => event.type === 'host-effect'));
});

test('native host handoff fails closed without matching blocked permission and successful interruption', async t => {
  const { backend, events } = native(t), frames = [];
  const rejectedRequests = ['HOST_ACTION HOST_COMPLETED', 'HOST_ACTION HOST_ERROR', 'HOST_ACTION WRONG_PERMISSION',
    'HOST_ACTION WRONG_MESSAGE', 'HOST_ACTION WRONG_SESSION', 'HOST_ACTION WRONG_SOURCE', 'HOST_ACTION WRONG_ACTION', 'HOST_ACTION NO_PERMISSION',
    'HOST_ACTION PROVIDER_EXECUTED', 'HOST_STREAMING STREAM_STALLED', 'HOST_ACTION INTERRUPT_FAIL', 'HOST_ACTION FALSE_INTERRUPT'];
  for (const text of rejectedRequests) {
    await assert.rejects(backend.request({ body: JSON.stringify(input(text)), url, onFrame: frame => frames.push(frame) }),
      /hand off|not approved|handoff.*ready|permission.*matched|local API returned HTTP 500|interrupt/i, text);
  }
  assert.equal(events().filter(e => e.type === 'prompt').length, rejectedRequests.length);
  assert.equal(events().filter(e => e.type === 'delete').length, rejectedRequests.length);
  assert.ok(!frames.some(frame => frame.choices?.[0]?.delta?.tool_calls), 'failed interruption never exposes runnable handoff');
  assert.ok(!events().some(e => e.type === 'permission-reply' || e.type === 'host-effect'));
});

test('native Stop cancels unfinished host streams and blocked requests before any handoff', async t => {
  const { backend, events } = native(t); await backend.start();
  for (const text of ['HOST_STREAMING', 'HOST_PENDING', 'HOST_ACTION NO_PERMISSION', 'HOST_STREAMING STREAM_TRANSITION DELAY_PERMISSION']) {
    const controller = new AbortController(), frames = [], before = events().filter(e => e.type === 'prompt').length;
    const pending = backend.request({ body: JSON.stringify(input(text)), url, signal: controller.signal, onFrame: frame => frames.push(frame) });
    const rejected = assert.rejects(pending, /Stopped|aborted/i);
    for (let attempt = 0; attempt < 200 && events().filter(e => e.type === 'prompt').length === before; attempt++) await sleep(10);
    assert.equal(events().filter(e => e.type === 'prompt').length, before + 1);
    await sleep(60); controller.abort(); await rejected;
    assert.ok(!frames.some(frame => frame.choices?.[0]?.delta?.tool_calls));
  }
  assert.equal(events().filter(e => e.type === 'prompt').length, 4);
  assert.equal(events().filter(e => e.type === 'delete').length, 4);
  assert.ok(!events().some(e => e.type === 'permission-reply'));
});

test('native handoff waits for every streamed tool, indexes previews, and fails impossible handoffs', { timeout: 5000 }, async t => {
  const { backend, events } = native(t), frames = [];
  const tools = [{ type: 'function', function: { name: 'lookup' } }];
  const reply = await backend.request({ body: JSON.stringify({ ...input('USE_TOOL PARALLEL'), tools }), url, onFrame: frame => frames.push(frame) });
  const calls = JSON.parse(reply.body).choices[0].message.tool_calls;
  assert.equal(calls.length, 2); assert.notEqual(calls[0].id, calls[1].id);
  assert.deepEqual(frames.flatMap(frame => frame.choices?.[0]?.delta?.tool_calls || []).map(call => call.index), [0, 1]);
  assert.ok(events().filter(e => e.type === 'tools').every(e => !fs.existsSync(e.location)), 'request location released before completion');
  await assert.rejects(backend.request({ body: JSON.stringify({ ...input('BROKEN_TOOL'), tools }), url }), /could not hand off/);
  await assert.rejects(backend.request({ body: JSON.stringify({ ...input('USE_TOOL OVERSIZED'), tools }), url }), /oversized tool arguments/);
  await assert.rejects(backend.request({ body: JSON.stringify({ ...input('USE_TOOL MALFORMED'), tools }), url }), /invalid.*tool arguments/);
  await assert.rejects(backend.request({ body: JSON.stringify({ ...input('USE_TOOL MISMATCHED'), tools }), url }), /unmatched tool call/);
});

test('only official routes and external native binaries qualify', async () => {
  for (const route of [url, 'https://opencode.ai/inference/v1/responses', 'https://opencode.ai/inference/openai/v1/chat/completions']) assert.equal(official(route), true);
  for (const route of ['https://opencode.ai.evil.invalid/zen/v1/chat/completions', 'http://opencode.ai/zen/v1/chat/completions', 'https://opencode.ai/other/chat/completions', 'https://user:secret@opencode.ai/zen/v1/chat/completions', 'https://puai-proxy.davidzk.tech/opencode/v1/chat/completions', 'https://opencode.ai/inference/go/v1/chat/completions', 'https://opencode.ai/zen/go/v1/responses', url + '?', url + '#', url + '?tenant=fixture', url + '#fixture']) assert.equal(official(route), false);
  assert.equal(findBinary({ UAI_OPENCODE_DISABLED: '1', UAI_OPENCODE_BINARY: process.execPath }), null);
  assert.equal(findBinary({ UAI_OPENCODE_BINARY: 'relative.exe' }), null);
  const unavailable = createOpenCode({ binary: null });
  await unavailable.close();
  assert.equal(unavailable.capability().available, false); assert.match(unavailable.capability().message, /discord\.gg/);
  await assert.rejects(unavailable.models(), /stopped/);
  const response = responseBody('fixture', { content: [{ type: 'text', text: 'Done' }], finish: 'length' }, [], true);
  assert.equal(response.status, 'incomplete'); assert.equal(response.output[0].content[0].text, 'Done');
});

test('native routing admits only the official public token and preserves personal auth for HTTPS', () => {
  for (const headers of [undefined, {}, { Authorization: 'Bearer public' }, { authorization: 'Bearer public', Accept: '*/*' }])
    assert.equal(nativeHeadersAllowed(headers), true);
  for (const headers of [null, [], 'invalid', { Authorization: 'Bearer fixture-private' }, { authorization: 'public' },
    { Authorization: 'Bearer public', authorization: 'Bearer fixture-private' }, { 'Proxy-Authorization': 'fixture' },
    { 'X-Api-Key': 'fixture' }, { 'x-access-token': 'fixture' }, { 'X-Secret': 'fixture' },
    { Authentication: 'fixture' }, { 'X-Credential': 'fixture' },
    { 'X-Org-Id': 'fixture' }, { 'openai-organization': 'fixture' }, { cookie: 'fixture' }])
    assert.equal(nativeHeadersAllowed(headers), false);
});

test('image bytes use native attachments and genuine native-name UAI tools are preserved', () => {
  const uri = 'data:image/png;base64,aGVsbG8=';
  for (const content of [[{ type: 'image_url', image_url: { url: uri } }], [{ type: 'input_image', image_url: uri }]]) {
    const prompt = promptInput({ messages: [{ role: 'user', content }] });
    assert.equal(prompt.files[0].uri, uri); assert.match(prompt.text, /Attached image 1/); assert.ok(!prompt.text.includes(uri));
  }
  assert.throws(() => promptInput({ messages: [{ content: [{ type: 'input_image', image_url: 'file:///secret.txt' }] }] }), /reattach/);
  const declared = toolDefinitions({ tools: [{ type: 'function', function: { name: 'bash' } }, { type: 'function', function: { name: 'file_read' } }] });
  assert.deepEqual(declared.map(tool => tool.name), ['bash', 'file_read']);
});

test('all actual Lua compatibility schemas are filtered while real colliding tools remain', t => {
  const { spawnSync } = require('node:child_process');
  const result = spawnSync('luajit', [path.join(__dirname, 'fixtures', 'opencode-tools.lua')], {
    cwd: path.resolve(__dirname, '../..'), windowsHide: true, encoding: 'utf8', timeout: 10000, maxBuffer: 65536,
  });
  if (result.error?.code === 'ENOENT') { t.skip('LuaJIT is unavailable; source-produced schema check runs with the offline client harness'); return; }
  assert.equal(result.status, 0, 'the credential-free source fixture exports successfully');
  const current = JSON.parse(result.stdout);
  const names = ['bash', 'read', 'edit', 'glob', 'grep', 'list', 'shell'];
  assert.deepEqual(current.map(tool => tool.function.name), names);
  assert.deepEqual(toolDefinitions({ tools: current }), []);
  const descriptions = ['Execute bash command', 'Read file', 'Edit file', 'Find files', 'Search pattern', 'List files', 'Execute shell command'];
  const historical = current.map((tool, index) => ({ ...tool, function: { ...tool.function, description: descriptions[index] } }));
  assert.deepEqual(toolDefinitions({ tools: historical }), []);
  for (const declarations of [current, historical]) {
    const translated = declarations.map(tool => ({ type: 'function', ...tool.function }));
    assert.deepEqual(toolDefinitions({ tools: translated }), [], 'Responses placeholders share the exact filter');
    const genuine = declarations.map(tool => ({ ...tool, function: { ...tool.function, description: 'A real Project UAI remote tool',
      parameters: { type: 'object', properties: { value: { type: 'number' } }, required: ['value'] } } }));
    assert.deepEqual(toolDefinitions({ tools: [...declarations, ...genuine] }).map(tool => tool.name), names);
  }
  assert.deepEqual(toolDefinitions({ tools: [{ type: 'function', function: { name: 'constructor' } }] }).map(tool => tool.name), ['constructor']);
  assert.throws(() => toolDefinitions({ tools: [null] }), /unique UAI function tools/);
});

test('native usage includes cache and reasoning in both wire totals', () => {
  const message = { tokens: { input: 34, output: 3, reasoning: 29, cache: { read: 5632, write: 128 } } };
  const chat = responseBody('fixture', message, [], false).usage;
  assert.deepEqual(chat, { prompt_tokens: 5794, completion_tokens: 32, total_tokens: 5826,
    cache_creation_input_tokens: 128, prompt_tokens_details: { cached_tokens: 5632 },
    completion_tokens_details: { reasoning_tokens: 29 } });
  const responses = responseBody('fixture', message, [], true).usage;
  assert.deepEqual(responses, { input_tokens: 5794, output_tokens: 32, total_tokens: 5826,
    cache_creation_input_tokens: 128, input_tokens_details: { cached_tokens: 5632 },
    output_tokens_details: { reasoning_tokens: 29 } });
  assert.equal(responseBody('fixture', {}, [], false).usage, undefined);
});
