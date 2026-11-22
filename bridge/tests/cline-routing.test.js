'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const https = require('node:https');
const { createInference } = require('../inference');
const url = 'https://uai-tunnel.invalid/cline/v1/chat/completions';
const body = JSON.stringify({ model: 'fixture-free', messages: [{ role: 'user', content: 'fixture' }] });

test('reserved Cline addresses never use outbound HTTP when unsupported or misconfigured', t => {
  t.mock.method(https, 'request', () => assert.fail('reserved Cline URL escaped to HTTP'));
  const absent = createInference(); t.after(() => absent.close());
  assert.throws(() => absent.start({ id: 'cline-missing', instance: absent.instance, url, body }), /Update UAI Bridge/);
  const inference = createInference({ cline: { request: () => assert.fail('invalid route entered Cline') } }); t.after(() => inference.close());
  for (const [index, candidate] of [url + '?key=secret', url.replace('/chat/completions', '/responses'), url.replace('https:', 'http:'),
    url.replace('uai-tunnel.invalid', 'uai-tunnel.invalid.')].entries()) {
    assert.throws(() => inference.start({ id: 'cline-invalid-' + index, instance: inference.instance, url: candidate, body }), /does not support/);
  }
  for (const name of ['Authorization', 'Authentication', 'Secret', 'X-Secret', 'Credential', 'X-Credential', 'Org', 'X-Org-Id', 'OpenAI-Organization'])
    assert.throws(() => inference.start({ id: 'cline-credential-' + name, instance: inference.instance, url, body, headers: { [name]: 'fixture' } }), /authentication to None/);
});

test('Cline refusal stays terminal without direct fallback or duplicate dispatch', async t => {
  t.mock.method(https, 'request', () => assert.fail('Cline error escaped to HTTP'));
  let calls = 0;
  const inference = createInference({ cline: { request: async () => { calls++; throw Error('Sign in to Cline'); } } }); t.after(() => inference.close());
  const input = { id: 'cline-auth-required', instance: inference.instance, url, body };
  inference.start(input); await new Promise(resolve => setImmediate(resolve));
  assert.equal(inference.get(input.id).state, 'failed');
  assert.match(inference.get(input.id).error, /Sign in/);
  assert.equal(inference.start(input).state, 'failed'); assert.equal(calls, 1);
});

test('Cline retains the relay job, forwards frames, and Stop prevents late completion', async t => {
  let resolve, signal, forwarded;
  const events = [];
  const inference = createInference({ publish: frame => events.push(frame), cline: { request: input => {
    signal = input.signal; forwarded = input.body;
    input.onFrame({ choices: [{ delta: { content: 'partial' } }] });
    return new Promise(done => { resolve = done; });
  } } }); t.after(() => inference.close());
  const input = { id: 'cline-stop-fixture', instance: inference.instance, sessionId: 'fixture', url, body };
  inference.start(input); assert.equal(forwarded, body);
  assert.equal(events.some(frame => frame.kind === 'inference:delta'), true);
  inference.cancel(input.id); assert.equal(signal.aborted, true);
  resolve({ status: 200, headers: {}, body: '{"late":true}' });
  await new Promise(done => setImmediate(done));
  assert.equal(inference.get(input.id).state, 'cancelled');
  assert.equal(inference.start(input).state, 'cancelled');
});
