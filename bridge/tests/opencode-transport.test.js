'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const https = require('node:https');
const { EventEmitter } = require('node:events');
const { Readable } = require('node:stream');
const { optionsFor } = require('../opencode-transport');
const { createInference } = require('../inference');

const chatURL = 'https://opencode.ai/zen/v1/chat/completions';
const responseURL = 'https://opencode.ai/inference/openai/v1/responses';
const inputHeaders = Object.freeze({
  Authorization: 'Bearer fixture-opencode-key', 'x-api-key': 'fixture-second-key',
  'User-Agent': 'opencode/latest/2.1.2/desktop', 'x-opencode-client': 'desktop',
  'x-opencode-session': 'ses_transport_fixture', Accept: '*/*',
  'Content-Type': 'application/json', 'X-Fixture': 'retained',
  Host: 'ignored.invalid', Connection: 'close', 'Content-Length': '1',
  'Accept-Encoding': 'gzip', 'X-Stainless-Timeout': '1',
});
const expectedHeaders = {
  Authorization: inputHeaders.Authorization, 'x-api-key': inputHeaders['x-api-key'],
  'User-Agent': inputHeaders['User-Agent'], 'x-opencode-client': 'desktop',
  'x-opencode-session': 'ses_transport_fixture', Accept: '*/*',
  'Content-Type': 'application/json', 'X-Fixture': 'retained', 'accept-encoding': 'identity',
};
const body = JSON.stringify({ model: 'fixture-free', messages: [{ role: 'user', content: 'Return PONG.' }], stream: true }, null, 2);
const responsesBody = JSON.stringify({ model: 'fixture-free', input: [{ role: 'user', content: 'Return PONG.' }], stream: true }, null, 2);
const tick = () => new Promise(resolve => setImmediate(resolve));

// Requests settle asynchronously, as real ClientRequest/IncomingMessage objects
// do. Every provider response is synthetic and no socket is opened.
function transportFixture(replies) {
  const calls = [];
  function request(url, options, callback) {
    const call = { url: url.href, options, timeouts: [] };
    calls.push(call);
    const outbound = new EventEmitter();
    let destroyed = false;
    outbound.setTimeout = value => { call.timeouts.push(value); return outbound; };
    outbound.destroy = () => { destroyed = true; return outbound; };
    outbound.end = payload => {
      call.body = payload;
      const reply = replies.shift();
      queueMicrotask(() => {
        if (destroyed) return;
        outbound.emit('finish');
        if (!reply) { outbound.emit('error', Error('Unexpected extra dispatch')); return; }
        if (reply.error) { outbound.emit('error', reply.error); return; }
        const response = Readable.from([Buffer.from(reply.body)]);
        response.statusCode = reply.status;
        response.headers = reply.headers || { 'content-type': 'application/json' };
        callback(response);
      });
    };
    return outbound;
  }
  return { calls, request };
}

test('OpenCode TLS options qualify only exact HTTPS Zen inference routes', () => {
  const paths = ['/zen/v1/chat/completions', '/zen/v1/responses',
    '/inference/v1/chat/completions', '/inference/v1/responses',
    '/inference/openai/v1/chat/completions', '/inference/openai/v1/responses'];
  for (const path of paths) {
    for (const host of ['opencode.ai', 'opencode.ai:443']) {
      for (const suffix of ['', '/']) {
        const url = 'https://' + host + path + suffix;
        const options = optionsFor(new URL(url));
        assert.deepEqual(Object.keys(options), ['ciphers'], url);
        assert.equal(typeof options.ciphers, 'string', url);
        assert.ok(options.ciphers.length > 0, url);
      }
    }
  }
  for (const url of [
    'http://opencode.ai/zen/v1/chat/completions',
    'https://opencode.ai:444/zen/v1/chat/completions',
    'https://opencode.ai:8443/inference/v1/responses',
    'https://opencode.ai.evil.test/zen/v1/chat/completions',
    'https://evil.opencode.ai/zen/v1/chat/completions',
    'https://opencode.ai./zen/v1/chat/completions',
    'https://opencode.ai@evil.test/zen/v1/chat/completions',
    'https://evil.test@opencode.ai/zen/v1/chat/completions',
    'https://user:password@opencode.ai/zen/v1/chat/completions',
    'https://opencode.ai/zen/v1/chat/completions?key=fixture',
    'https://opencode.ai/inference/v1/responses#fragment',
    'https://opencode.ai/inference/go/v1/chat/completions',
    'https://opencode.ai/inference/go/v1/responses',
    'https://opencode.ai/zen/go/v1/chat/completions',
    'https://opencode.ai/zen/go/v1/responses',
    'https://opencode.ai/zen/v1/models',
    'https://opencode.ai/inference/other/v1/chat/completions',
    'https://opencode.ai/inference/openai/v1/embeddings',
    'https://opencode.ai/v1/chat/completions',
    'https://opencode.ai/zen/v1/chat/completions/extra',
    'https://opencode.ai/zen/v1/chat%2Fcompletions',
    'https://example.test/inference/v1/responses',
  ]) assert.deepEqual(optionsFor(new URL(url)), {}, url);
  for (const invalid of [undefined, null, '', 'not-a-url']) assert.deepEqual(optionsFor(invalid), {});
});

test('the TLS profile leaves certificate validation, credentials and shared options intact', () => {
  const url = new URL(chatURL), original = url.href;
  const first = optionsFor(url), next = optionsFor(url);
  assert.equal(url.href, original);
  assert.notEqual(first, next, 'a caller cannot replace another request\'s options');
  assert.deepEqual(Object.keys(first), ['ciphers']);
  assert.equal(first.rejectUnauthorized, undefined);
  assert.equal(first.checkServerIdentity, undefined);
  assert.equal(first.agent, undefined);
  assert.equal(first.headers, undefined);
  const ciphers = next.ciphers;
  first.ciphers = 'fixture-mutated';
  first.rejectUnauthorized = false;
  assert.equal(optionsFor(url).ciphers, ciphers);
  assert.equal(optionsFor(url).rejectUnauthorized, undefined);
});

test('direct OpenCode dispatch applies TLS before the first send and retains request semantics', { concurrency: false }, async t => {
  const success = 'data: {"choices":[{"delta":{"content":"PONG"}}]}\n\ndata: [DONE]\n\n';
  const refusal = JSON.stringify({ error: { code: 'RateLimit.FreeUsageLimitError', message: 'Free usage limit reached.' } });
  for (const [name, url, payload, reply] of [
    ['chat-stream', chatURL, body, { status: 200, body: success, headers: { 'content-type': 'text/event-stream', 'x-request-id': 'fixture-request' } }],
    ['responses-refusal', responseURL, responsesBody, { status: 429, body: refusal, headers: { 'content-type': 'application/json', 'x-should-retry': 'false' } }],
    ['certificate-failure', chatURL, body, { error: Object.assign(Error('self-signed certificate'), { code: 'DEPTH_ZERO_SELF_SIGNED_CERT' }) }],
  ]) await t.test(name, { concurrency: false }, async st => {
    const fixture = transportFixture([reply]), nativeChecks = [];
    st.mock.method(https, 'request', fixture.request);
    const relay = createInference({ opencode: {
      capability: () => ({ available: true }),
      accepts: (target, sentBody) => { nativeChecks.push([target, sentBody]); return false; },
      request: () => assert.fail('an unsupported model entered the native CLI'),
    } });
    st.after(() => relay.close());
    const input = Object.freeze({ id: 'opencode-transport-' + name, instance: relay.instance,
      sessionId: 'transport-session', url, body: payload, headers: inputHeaders });
    assert.equal(relay.start(input).state, 'running');
    assert.equal(fixture.calls.length, 1);
    const sent = fixture.calls[0];
    assert.equal(sent.url, url);
    assert.deepEqual(sent.options, { method: 'POST', headers: { ...expectedHeaders, 'content-length': Buffer.byteLength(payload) }, ...optionsFor(new URL(url)) });
    assert.equal(typeof sent.options.ciphers, 'string');
    assert.equal(sent.options.rejectUnauthorized, undefined);
    assert.equal(sent.options.checkServerIdentity, undefined);
    assert.equal(sent.options.agent, undefined);
    assert.deepEqual(sent.timeouts, [0]);
    assert.equal(sent.body, payload);
    assert.deepEqual(nativeChecks, [[url, payload]]);
    assert.equal(input.headers, inputHeaders);
    assert.equal(input.headers.Authorization, 'Bearer fixture-opencode-key');
    assert.equal(input.headers['x-api-key'], 'fixture-second-key');
    assert.equal(input.body, payload);
    await tick();
    const settled = relay.get(input.id);
    assert.equal(settled.state, reply.error ? 'failed' : 'completed');
    if (!reply.error) { assert.equal(settled.status, reply.status); assert.equal(settled.body, reply.body); }
    assert.equal(relay.start(input).state, settled.state);
    await tick();
    assert.equal(fixture.calls.length, 1, 'completion, refusal and TLS failure never replay the request');
  });
});

test('Go and unrelated providers retain ordinary HTTPS options', { concurrency: false }, async t => {
  const fixture = transportFixture([{ status: 200, body: '{}' }, { status: 200, body: '{}' }]);
  t.mock.method(https, 'request', fixture.request);
  const relay = createInference(); t.after(() => relay.close());
  for (const [index, url] of ['https://opencode.ai/inference/go/v1/chat/completions', 'https://example.test/v1/chat/completions'].entries()) {
    const id = 'ordinary-transport-' + index;
    relay.start({ id, instance: relay.instance, url, headers: inputHeaders, body });
    assert.deepEqual(fixture.calls[index].options, { method: 'POST', headers: { ...expectedHeaders, 'content-length': Buffer.byteLength(body) } });
    await tick();
    assert.equal(relay.get(id).state, 'completed');
  }
});

test('the installed OpenCode CLI keeps priority and a native failure cannot switch to direct HTTP', { concurrency: false }, async t => {
  for (const failure of [false, true]) await t.test(failure ? 'native-failure' : 'native-success', { concurrency: false }, async st => {
    st.mock.method(https, 'request', () => assert.fail('native OpenCode request escaped to direct HTTPS'));
    const calls = [];
    const relay = createInference({ opencode: {
      capability: () => ({ available: true }), accepts: () => true,
      request: async input => { calls.push(input); if (failure) throw Error('Fixture native refusal'); return { status: 200, headers: {}, body: '{"native":true}' }; },
    }, kilo: { accepts: () => assert.fail('native OpenCode routing reached Kilo') } });
    st.after(() => relay.close());
    const input = { id: 'opencode-native-priority-' + failure, instance: relay.instance, url: chatURL, body, headers: inputHeaders };
    relay.start(input);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].url, chatURL);
    assert.equal(calls[0].body, body);
    assert.equal(calls[0].signal.aborted, false);
    await tick();
    const settled = relay.get(input.id);
    assert.equal(settled.state, failure ? 'failed' : 'completed');
    if (failure) assert.match(settled.error, /Fixture native refusal/);
    else assert.equal(settled.body, '{"native":true}');
    assert.equal(relay.start(input).state, settled.state);
    await tick();
    assert.equal(calls.length, 1);
  });
});

test('a delegated Kilo transport retains ownership of its TLS options', { concurrency: false }, async t => {
  t.mock.method(https, 'request', () => assert.fail('delegated transport escaped to HTTPS'));
  const fixture = transportFixture([{ status: 200, body: '{}' }]);
  // A synthetic acceptance on a qualifying OpenCode URL checks that the profile
  // follows the selected HTTPS transport rather than leaking to an adapter.
  const relay = createInference({ kilo: { accepts: () => true, request: fixture.request } });
  t.after(() => relay.close());
  const input = { id: 'opencode-delegated-transport', instance: relay.instance, url: chatURL, body, headers: inputHeaders };
  relay.start(input);
  assert.deepEqual(fixture.calls[0].options, { method: 'POST', headers: { ...expectedHeaders, 'content-length': Buffer.byteLength(body) } });
  await tick();
  assert.equal(relay.get(input.id).state, 'completed');
  assert.equal(fixture.calls.length, 1);
});
