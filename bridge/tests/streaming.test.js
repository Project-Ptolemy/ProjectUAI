'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { once } = require('node:events');
const { createInference } = require('../inference');
const sleep = ms => new Promise(r => setTimeout(r, ms));

// One-shot loopback upstream. Error handlers keep the process alive when the
// relay destroys the connection mid-response (oversize/malformed cases).
async function upstream(t, handler) {
  const server = http.createServer((req, res) => { req.on('error', () => {}); res.on('error', () => {}); handler(req, res); });
  server.on('clientError', () => {});
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => { server.closeAllConnections?.(); server.close(); });
  return `http://127.0.0.1:${server.address().port}`;
}

// Run one job to a terminal state and return the collected events + final view.
async function run(t, handler, opts = {}) {
  const url = await upstream(t, handler);
  const events = [];
  const relay = createInference({ publish: e => events.push(e), ...opts });
  t.after(() => relay.close());
  const id = 'job-' + Math.random().toString(36).slice(2);
  relay.start({ id, instance: relay.instance, url, sessionId: 's1', body: '{}' });
  for (let i = 0; i < 500 && relay.get(id).state === 'running'; i++) await sleep(5);
  return { events, relay, id, url, view: relay.get(id) };
}
const done = events => events.find(e => e.kind === 'inference:done');
const deltas = events => events.filter(e => e.kind === 'inference:delta');

test('Gemini projects text, thoughts and bounded calls while retaining exact signed parts', async t => {
  const frames = [
    { modelVersion: 'gemini-3.1-pro-preview', candidates: [{ content: { role: 'model', parts: [
      { text: 'Checking the scene', thought: true, thoughtSignature: 'private-signature' }, { text: 'Ready' },
      { functionCall: { name: 'inspect', args: { query: 'Workspace' } }, thoughtSignature: 'tool-signature' },
      { inlineData: { mimeType: 'image/png', data: 'not-a-browser-preview' } },
    ] } }] },
    { candidates: [{ finishReason: 'STOP', content: { role: 'model', parts: [] } }], usageMetadata: { totalTokenCount: 100 } },
  ];
  const raw = frames.map(frame => 'data: ' + JSON.stringify(frame) + '\n\n').join('');
  const { events, view, relay } = await run(t, (req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' }); res.end(raw);
  });
  assert.equal(view.state, 'completed'); assert.equal(view.body, raw);
  assert.deepEqual(deltas(events).map(e => [e.channel, e.text]), [
    ['reasoning', 'Checking the scene'], ['text', 'Ready'], ['tool', { name: 'inspect', argsDelta: '{"query":"Workspace"}' }],
  ]);
  assert.equal(deltas(events)[0].model, 'gemini-3.1-pro-preview');
  assert.deepEqual(deltas(relay.previews('s1')), deltas(events));
  assert.doesNotMatch(JSON.stringify(events), /signature|not-a-browser-preview/i);
});

test('Gemini blocked prompts reach the native adapter and truncated streams fail', async t => {
  const blocked = 'data: {"promptFeedback":{"blockReason":"SAFETY"},"modelVersion":"gemini-fixture"}\n\n';
  const result = await run(t, (req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' }); res.end(blocked);
  });
  assert.equal(result.view.state, 'completed'); assert.equal(result.view.body, blocked);
  assert.deepEqual(deltas(result.events), []);
  const truncated = await run(t, (req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.end('data: {"candidates":[{"content":{"parts":[{"text":"partial"}]}}]}\n\n');
  });
  assert.equal(truncated.view.state, 'failed'); assert.match(truncated.view.error, /before completion/);
});

test('frame 1 is delivered to the browser before inference:done', async t => {
  const { events, view } = await run(t, (req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.write('data: {"choices":[{"delta":{"content":"first"}}]}\n\n');
    setTimeout(() => res.end('data: [DONE]\n\n'), 40);
  });
  const firstDelta = events.findIndex(e => e.kind === 'inference:delta');
  const end = events.findIndex(e => e.kind === 'inference:done');
  assert.ok(firstDelta >= 0 && end >= 0 && firstDelta < end, 'delta precedes done');
  assert.equal(events[firstDelta].text, 'first');
  assert.equal(view.state, 'completed');
});

test('per-job seq is 1-based, gapless, and monotonic', async t => {
  const { events } = await run(t, (req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    for (let i = 1; i <= 5; i++) res.write(`data: {"choices":[{"delta":{"content":"t${i}"}}]}\n\n`);
    res.end('data: [DONE]\n\n');
  });
  assert.deepEqual(deltas(events).map(e => e.seq), [1, 2, 3, 4, 5]);
});

test('Unicode split across writes and across data: lines is reassembled into one delta each', async t => {
  const s = 'data: {"choices":[{"delta":{"content":"世界"}}]}\n\n';
  const frame = Buffer.from(s);
  const cut = Buffer.byteLength(s.slice(0, s.indexOf('世'))) + 1; // mid-byte of 世
  const { events, view } = await run(t, (req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.write(frame.subarray(0, cut));
    setTimeout(() => {
      res.write(frame.subarray(cut));
      // A single logical frame spread over two data: lines (joined with \n).
      res.write('data: {"choices":[{"delta":\ndata: {"content":"X"}}]}\n\n');
      res.end('data: [DONE]\n\n');
    }, 30);
  });
  const d = deltas(events);
  assert.equal(d[0].text, '世界');
  assert.equal(d[1].text, 'X');
  assert.equal(view.state, 'completed');
});

test('malformed streaming JSON fails with a stable reason and never completes', async t => {
  const { view } = await run(t, (req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.write('data: {"choices":[{"delta":{"content":"ok"}}]}\n\n');
    res.end('data: {not valid json\n\n');
  });
  assert.equal(view.state, 'failed');
  assert.match(view.error, /malformed streaming data/i);
});

test('a truncated stream (no [DONE]) fails instead of completing', async t => {
  const { view } = await run(t, (req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.end('data: {"choices":[{"delta":{"content":"partial"}}]}\n\n');
  });
  assert.equal(view.state, 'failed');
  assert.match(view.error, /ended before completion/i);
});

test('Chat and Messages final reasons complete at EOF without a separate sentinel', async t => {
  for (const frames of [
    [{ choices: [{ delta: { content: 'Ready' } }] }, { choices: [{ delta: {}, finish_reason: 'stop' }] }],
    [{ type: 'content_block_delta', delta: { type: 'text_delta', text: 'Ready' } }, { type: 'message_delta', delta: { stop_reason: 'end_turn' } }],
  ]) {
    const raw = frames.map(frame => 'data: ' + JSON.stringify(frame)).join('\n\n');
    let calls = 0;
    const { events, view, relay, id, url } = await run(t, (req, res) => {
      calls++; res.writeHead(200, { 'content-type': 'text/event-stream' }); res.end(raw);
    });
    assert.equal(view.state, 'completed'); assert.equal(view.body, raw);
    assert.equal(deltas(events).map(event => event.text).join(''), 'Ready');
    assert.equal(done(events).state, 'completed');
    assert.equal(relay.start({ id, instance: relay.instance, url, sessionId: 's1', body: '{}' }).state, 'completed');
    assert.equal(calls, 1);
  }
});

test('null, empty, invalid and unrelated finish reasons cannot complete truncated streams', async t => {
  for (const final of [
    ...[null, '', false, 1, {}].map(finish_reason => ({ choices: [{ delta: {}, finish_reason }] })),
    ...[null, '', false, 1, {}].map(stop_reason => ({ type: 'message_delta', delta: { stop_reason } })),
    { type: 'content_block_delta', delta: { text: 'Partial', stop_reason: 'end_turn' } },
    { finish_reason: 'stop', stop_reason: 'end_turn' },
    { type: 'response.output_text.delta', delta: 'Partial', stop_reason: 'end_turn' },
  ]) {
    const { view } = await run(t, (req, res) => {
      res.writeHead(200, { 'content-type': 'text/event-stream' });
      res.end('data: ' + JSON.stringify(final) + '\n\n');
    });
    assert.equal(view.state, 'failed', JSON.stringify(final));
    assert.match(view.error, /ended before completion/i);
  }
});

test('a final reason does not hide a later streamed failure', async t => {
  for (const final of [
    { choices: [{ delta: { content: 'Partial' }, finish_reason: 'stop' }] },
    { type: 'message_delta', delta: { stop_reason: 'end_turn' } },
  ]) {
    const { events, view } = await run(t, (req, res) => {
      res.writeHead(200, { 'content-type': 'text/event-stream' });
      res.end('data: ' + JSON.stringify(final) + '\n\ndata: {"error":{"message":"late upstream failure"}}\n\n');
    });
    assert.equal(view.state, 'failed'); assert.equal(view.body, undefined);
    assert.match(view.error, /late upstream failure/);
    assert.equal(done(events).state, 'failed');
  }
});

test('OpenCode Responses streams text, reasoning and tools and completes on response.completed', async t => {
  const frames = [
    { type: 'response.created', response: { model: 'muse-spark-fixture' } },
    { type: 'response.reasoning_summary_text.delta', delta: 'Thinking' },
    { type: 'response.output_text.delta', delta: 'Ready' },
    { type: 'response.output_item.added', output_index: 1, item: { type: 'function_call', name: 'read_file' } },
    { type: 'response.function_call_arguments.delta', delta: '{"path":"a.lua"}' },
    { type: 'response.completed', response: { status: 'completed', output: [
      { type: 'message', content: [{ type: 'output_text', text: 'Ready' }] },
      { type: 'reasoning', summary: [{ text: 'Thinking' }] },
    ] } },
  ];
  const raw = frames.map(frame => 'event: ' + frame.type + '\ndata: ' + JSON.stringify(frame) + '\n\n').join('');
  const { events, view, relay } = await run(t, (req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' }); res.end(raw);
  });
  assert.equal(view.state, 'completed'); assert.equal(view.body, raw);
  assert.deepEqual(deltas(events).map(e => e.channel), ['reasoning', 'text', 'tool', 'tool']);
  assert.equal(deltas(events).filter(e => e.channel === 'text').map(e => e.text).join(''), 'Ready');
  assert.equal(deltas(events)[0].model, 'muse-spark-fixture');
  assert.deepEqual(deltas(relay.previews('s1')), deltas(events));
});

test('Responses final-only output is projected when a gateway sends no text deltas', async t => {
  const { events, view } = await run(t, (req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.end('event: response.completed\ndata: {"response":{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"Final answer"}]}]}}\n\n');
  });
  assert.equal(view.state, 'completed'); assert.equal(deltas(events)[0].text, 'Final answer');
});

test('provider stream errors remain terminal after partial output and later completion markers', async t => {
  for (const frame of [
    'event: error\ndata: overloaded',
    'data: {"error":{"message":"overloaded"}}',
    'data: {"type":"response.failed","response":{"status":"failed","error":{"message":"overloaded"}}}',
    'data: {"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"}}}',
    'data: {"type":"response.completed","response":{"status":"failed","error":{"message":"overloaded"}}}',
  ]) {
    const { events, view } = await run(t, (req, res) => {
      res.writeHead(200, { 'content-type': 'text/event-stream' });
      res.end('data: {"choices":[{"delta":{"content":"partial"}}]}\n\n' + frame + '\n\ndata: [DONE]\n\n');
    });
    assert.equal(view.state, 'failed', frame);
    assert.match(view.error, /Provider stream failed/); assert.equal(view.body, undefined);
    assert.equal(done(events).state, 'failed'); assert.equal(done(events).sawText, true);
  }
});

test('provider errors redact echoed credentials from live and retained previews', async t => {
  const url = await upstream(t, (req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.end('data: ' + JSON.stringify({ error: { message: req.headers.authorization + ' rejected' } }) + '\n\n');
  });
  const events = [], relay = createInference({ publish: event => events.push(event) });
  t.after(() => relay.close());
  relay.start({ id: 'redacted-response', instance: relay.instance, url, sessionId: 's1', body: '{}', headers: { Authorization: 'Bearer credential-fixture-1234' } });
  for (let i = 0; i < 500 && relay.get('redacted-response').state === 'running'; i++) await sleep(5);
  assert.equal(relay.get('redacted-response').state, 'failed');
  assert.doesNotMatch(JSON.stringify([events, relay.get('redacted-response'), relay.previews('s1')]), /credential-fixture-1234/);
  assert.match(done(events).error, /redacted/);
});

test('Cowork ignores caller timeouts and completes the original provider request', async t => {
  let calls = 0;
  const url = await upstream(t, (req, res) => {
    calls++; res.writeHead(200, { 'content-type': 'text/event-stream' }); res.flushHeaders();
    setTimeout(() => res.end('data: {"choices":[{"delta":{"content":"Finished thinking"}}]}\n\ndata: [DONE]\n\n'), 120);
  });
  const relay = createInference(); t.after(() => relay.close());
  const input = { id: 'unlimited-completion', instance: relay.instance, url, body: '{}', timeout: 0.01 };
  relay.start(input);
  await sleep(60);
  assert.equal(relay.get(input.id).state, 'running');
  assert.equal(relay.start({ ...input, timeout: 0.001 }).state, 'running', 'changing a retired setting cannot restart or shorten the job');
  for (let i = 0; i < 200 && relay.get(input.id).state === 'running'; i++) await sleep(5);
  assert.equal(relay.get(input.id).state, 'completed');
  assert.match(relay.get(input.id).body, /Finished thinking/);
  assert.equal(calls, 1);
});

test('an unlimited quiet provider job remains stoppable and cannot be resubmitted', async t => {
  let calls = 0, responseClosed;
  const closed = new Promise(resolve => { responseClosed = resolve; });
  const url = await upstream(t, (req, res) => {
    calls++; res.on('close', responseClosed);
    res.writeHead(200, { 'content-type': 'text/event-stream' }); res.flushHeaders();
  });
  const relay = createInference(); t.after(() => relay.close());
  const input = { id: 'unlimited-stop', instance: relay.instance, url, body: '{}', timeout: 0.01 };
  relay.start(input); await sleep(80);
  assert.equal(relay.get(input.id).state, 'running');
  assert.equal(relay.cancel(input.id), true);
  await closed;
  assert.equal(relay.get(input.id).state, 'cancelled');
  assert.equal(relay.start(input).state, 'cancelled'); assert.equal(calls, 1);
});

test('advancing past the former three-minute and one-day limits does not end Cowork inference', async t => {
  let answer, accept;
  const accepted = new Promise(resolve => { accept = resolve; });
  const url = await upstream(t, (req, res) => { answer = res; accept(); });
  const relay = createInference(); t.after(() => relay.close());
  t.mock.timers.enable({ apis: ['setTimeout'] });
  relay.start({ id: 'unlimited-clock', instance: relay.instance, url, body: '{}' });
  await accepted;
  t.mock.timers.tick(2 * 86400 * 1000);
  assert.equal(relay.get('unlimited-clock').state, 'running');
  answer.end('{"choices":[{"message":{"content":"After a long think"}}]}');
  for (let i = 0; i < 100 && relay.get('unlimited-clock').state === 'running'; i++) await new Promise(setImmediate);
  assert.equal(relay.get('unlimited-clock').state, 'completed');
  t.mock.timers.reset();
});

test('stream framing accepts a split UTF-8 BOM, CRLF and bare CR without altering the receipt', async t => {
  const raw = '\uFEFFdata: {"choices":[{"delta":{"content":"one"}}]}\r\rdata: {"choices":[{"delta":{"content":"two"}}]}\r\n\r\ndata: [DONE]\r\n\r\n';
  const { events, view } = await run(t, (req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    const bytes = Buffer.from(raw); res.write(bytes.subarray(0, 1));
    setTimeout(() => res.end(bytes.subarray(1)), 5);
  });
  assert.equal(view.state, 'completed'); assert.equal(view.body, raw);
  assert.equal(deltas(events).map(e => e.text).join(''), 'onetwo');
});

test('a non-SSE 200 response completes with streamed:false and keeps its body', async t => {
  const { events, view } = await run(t, (req, res) => {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end('{"choices":[{"message":{"content":"buffered"}}]}');
  });
  assert.equal(view.state, 'completed');
  assert.equal(done(events).streamed, false);
  assert.equal(done(events).sawText, false); // non-SSE path emits no normalized deltas
  assert.match(view.body, /buffered/);
});

test('a zero-token stream failure is state failed with sawText:false', async t => {
  const { events, view } = await run(t, (req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.end(); // opened as a stream, produced no frames or [DONE]
  });
  assert.equal(view.state, 'failed');
  assert.equal(done(events).sawText, false);
  assert.equal(done(events).streamed, true);
});

test('keepalive comment lines are ignored and [DONE] cleanly completes', async t => {
  const { events, view } = await run(t, (req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.write(': keepalive ping\n\n');
    res.write('data: {"choices":[{"delta":{"content":"hello"}}]}\n\n');
    res.end('data: [DONE]\n\n');
  });
  assert.equal(deltas(events).length, 1);
  assert.equal(deltas(events)[0].text, 'hello');
  assert.equal(view.state, 'completed');
  assert.equal(done(events).sawText, true);
});

test('frame ring overflow is flagged on done without trimming the raw body', async t => {
  const N = 4200; // exceeds the 4096-frame ring bound
  let payload = '';
  for (let i = 0; i < N; i++) payload += 'data: {"choices":[{"delta":{"content":"x"}}]}\n\n';
  payload += 'data: [DONE]\n\n';
  const { events, view } = await run(t, (req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.end(payload);
  });
  assert.equal(view.state, 'completed');
  assert.equal(done(events).overflow, true);
  assert.equal(deltas(events).length, N); // every frame was still published live
  assert.equal((view.body.match(/"content":"x"/g) || []).length, N); // Roblox poll body intact
});

test('a body over the 8 MiB deliverable limit fails fast and is never resubmitted', async t => {
  let calls = 0;
  const url = await upstream(t, (req, res) => {
    calls++;
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(Buffer.alloc(9 * 1024 * 1024, 0x61));
  });
  const relay = createInference({ publish: () => {} });
  t.after(() => relay.close());
  const input = { id: 'too-big-body', instance: relay.instance, url, sessionId: 's1', body: '{}' };
  relay.start(input);
  for (let i = 0; i < 500 && relay.get('too-big-body').state === 'running'; i++) await sleep(5);
  assert.equal(relay.get('too-big-body').state, 'failed');
  assert.match(relay.get('too-big-body').error, /deliverable limit/i);
  assert.equal(relay.start(input).state, 'failed'); // retry returns the terminal view
  assert.equal(calls, 1); // upstream was hit exactly once
});

test('the JSON receipt limit includes escaped response text and envelope bytes', async t => {
  const { view } = await run(t, (req, res) => { res.writeHead(200, { 'content-type': 'text/plain' }); res.end('"'.repeat(700)); }, { deliverableMax: 1000 });
  assert.equal(view.state, 'failed'); assert.match(view.error, /JSON encoding/); assert.equal(view.body, undefined);
});

test('HTTP provider errors retain the original body for Roblox and show an error in browser replay', async t => {
  const raw = '<html>Upstream overloaded. Retry later.</html>';
  const { view, events, relay } = await run(t, (req, res) => { res.writeHead(503, { 'content-type': 'text/event-stream', 'retry-after': '20' }); res.end(raw); });
  assert.equal(view.state, 'completed'); assert.equal(view.body, raw); assert.equal(view.status, 503);
  assert.equal(view.headers['retry-after'], '20'); assert.match(done(events).providerError, /HTTP 503/);
  assert.match(relay.previews('s1').at(-1).providerError, /HTTP 503/);
});

test('legacy mixed-channel frames do not duplicate text and replay their terminal state', async t => {
  const { events, relay } = await run(t, (req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.end('data: {"type":4,"choices":[{"delta":{"content":"answer","reasoning_content":"thought"}}],"private":"do not project"}\n\ndata: [DONE]\n\n');
  }, { legacy: true });
  const frames = deltas(events).map(e => e.frame.choices[0].delta);
  assert.equal(frames.map(d => d.content || '').join(''), 'answer');
  assert.equal(frames.map(d => d.reasoning_content || '').join(''), 'thought');
  assert.ok(!JSON.stringify(events).includes('do not project'));
  assert.equal(relay.previews('s1').at(-1).kind, 'inference:done');
});

test('replay reports dropped frame ranges while the authoritative raw body stays intact', async t => {
  const payload = Array.from({ length: 4300 }, (_, i) => 'data: ' + JSON.stringify({ choices: [{ delta: { content: String(i) } }] }) + '\n\n').join('') + 'data: [DONE]\n\n';
  const { relay, view } = await run(t, (req, res) => { res.writeHead(200, { 'content-type': 'text/event-stream' }); res.end(payload); });
  const replay = relay.previews('s1'), gap = replay.find(e => e.kind === 'inference:resync'), frames = deltas(replay);
  assert.ok(gap.from > 1); assert.equal(frames.length, 4096); assert.equal(frames[0].seq, gap.from);
  assert.equal(view.body, payload);
});

test('fresh replay shares its frame budget across full jobs and retains terminal outcomes', async t => {
  const raw = 'data: {"choices":[{"delta":{"reasoning_content":"x"}}]}\n\n'.repeat(4096) + 'data: [DONE]\n\n';
  const calls = new Map(), events = [];
  const url = await upstream(t, (req, res) => {
    calls.set(req.url, (calls.get(req.url) || 0) + 1);
    if (req.url === '/failed') { res.writeHead(503, { 'content-type': 'text/plain' }); res.end('Retained refusal'); return; }
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    if (req.url === '/cancelled') res.write('data: {"choices":[{"delta":{"content":"Partial before Stop"}}]}\n\n');
    else res.end(raw);
  });
  const relay = createInference({ publish: event => events.push(event) });
  t.after(() => relay.close());
  const ids = ['full-first', 'full-second', 'failed-job', 'cancelled-job'];
  for (const [index, path] of ['/first', '/second', '/failed', '/cancelled'].entries()) {
    relay.start({ id: ids[index], instance: relay.instance, url: url + path, sessionId: 's1', body: '{}' });
  }
  for (let attempt = 0; attempt < 500 && (ids.slice(0, 3).some(id => relay.get(id).state === 'running') ||
      !events.some(event => event.id === 'cancelled-job' && event.kind === 'inference:delta')); attempt++) await sleep(5);
  assert.ok(relay.cancel('cancelled-job'));
  const replay = relay.previews('s1');
  assert.ok(replay.length <= 4500);
  assert.ok(replay.reduce((sum, event) => sum + Buffer.byteLength(JSON.stringify(event)), 0) <= 7 * 1024 * 1024);
  for (const id of ids.slice(0, 2)) {
    const retained = replay.filter(event => event.id === id), frames = deltas(retained);
    const gap = retained.find(event => event.kind === 'inference:resync');
    assert.ok(frames.length > 0 && frames.length < 4096);
    assert.equal(frames[0].seq, gap.from); assert.equal(frames.at(-1).seq, 4096);
    assert.equal(retained.at(-1).state, 'completed'); assert.equal(retained.at(-1).overflow, true);
    assert.equal(relay.get(id).body, raw, 'projection leaves the complete provider receipt unchanged');
  }
  assert.match(replay.find(event => event.id === 'failed-job' && event.kind === 'inference:done').providerError, /HTTP 503/);
  assert.equal(replay.find(event => event.id === 'cancelled-job' && event.kind === 'inference:done').state, 'cancelled');
  assert.deepEqual([...calls.values()], [1, 1, 1, 1], 'projecting previews never resubmits a provider request');
});

test('fresh replay clips aggregate bytes to contiguous tails without changing receipts', async t => {
  const frames = [
    { choices: [{ delta: { reasoning_content: 'x'.repeat(2 * 1024 * 1024 - 1024) } }] },
    ...Array.from({ length: 3 }, () => ({ choices: [{ delta: { reasoning_content: 'tail' } }] })),
  ];
  const raw = frames.map(frame => 'data: ' + JSON.stringify(frame) + '\n\n').join('') + 'data: [DONE]\n\n';
  let calls = 0;
  const url = await upstream(t, (req, res) => { calls++; res.writeHead(200, { 'content-type': 'text/event-stream' }); res.end(raw); });
  const relay = createInference(); t.after(() => relay.close());
  for (const id of ['large-first', 'large-second']) relay.start({ id, instance: relay.instance, url, sessionId: 's1', body: '{}' });
  for (let attempt = 0; attempt < 500 && ['large-first', 'large-second'].some(id => relay.get(id).state === 'running'); attempt++) await sleep(5);
  const replay = relay.previews('s1');
  assert.ok(replay.reduce((sum, event) => sum + Buffer.byteLength(JSON.stringify(event)), 0) <= 7 * 1024 * 1024);
  for (const id of ['large-first', 'large-second']) {
    const retained = replay.filter(event => event.id === id);
    assert.equal(retained.find(event => event.kind === 'inference:resync').from, 2);
    assert.deepEqual(deltas(retained).map(event => event.seq), [2, 3, 4]);
    assert.equal(retained.at(-1).overflow, true); assert.equal(relay.get(id).body, raw);
  }
  assert.equal(calls, 2);
});

test('fresh replay retains an older running job ahead of excessive terminal previews', async t => {
  let calls = 0;
  const response = { status: 200, headers: {}, body: '{"choices":[{"message":{"content":"Complete"}}]}' };
  const relay = createInference({ opencode: {
    capability: () => ({ available: true }), accepts: () => true,
    request: async ({ body, onFrame, signal }) => {
      calls++;
      if (JSON.parse(body).model !== 'old-running') return response;
      onFrame({ choices: [{ delta: { content: 'Still running' } }] });
      return new Promise(resolve => signal.addEventListener('abort', () => resolve(response), { once: true }));
    },
  } });
  t.after(() => relay.close());
  relay.start({ id: 'old-running', instance: relay.instance, sessionId: 's1', url: 'https://fixture.invalid', body: '{"model":"old-running"}' });
  for (let index = 1; index <= 34; index++) {
    relay.start({ id: 'terminal-' + index, instance: relay.instance, sessionId: 's1', url: 'https://fixture.invalid', body: '{"model":"complete"}' });
    await Promise.resolve();
  }
  const replay = relay.previews('s1');
  assert.equal(replay.filter(event => event.kind === 'inference:start').length, 32);
  assert.ok(replay.some(event => event.kind === 'inference:start' && event.id === 'old-running'));
  assert.ok(replay.some(event => event.kind === 'inference:delta' && event.id === 'old-running'));
  assert.equal(replay.filter(event => event.kind === 'inference:done').length, 31);
  assert.ok(replay.some(event => event.kind === 'inference:done' && event.id === 'terminal-34'));
  assert.ok(replay.some(event => event.kind === 'status' && /older live previews/.test(event.text)));
  assert.equal(relay.get('old-running').state, 'running', 'recovery never cancels an admitted job');
  assert.equal(calls, 35, 'projection starts no additional native inference');
});
