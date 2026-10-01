'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { once } = require('node:events');
const { createPictureStore } = require('../picture-store');
const { startBridge } = require('./helpers/bridge');
const { makePng, makeJpeg, makeWebp } = require('./helpers/images');

test('provider image blocks contain the uploaded bytes and enforce ownership', () => {
  const store = createPictureStore(), owner = { browserId: 'browser', sessionId: 's1' };
  const bytes = makePng(5, 7), id = 'pic_vision_fixture';
  store.stage({ id, ...owner, name: 'colors.png', mediaType: 'image/png', bytes });
  const image = store.reference(id, owner);
  const body = source => JSON.stringify({ messages: [{ role: 'user', content: [{ type: 'text', text: 'Look' }, source] }] });
  const openai = { type: 'image_url', image_url: { url: image.url } };
  assert.throws(() => store.providerBody(body(openai), 's1'), /not attached/i);
  store.markQueued([id], 'image-command');
  const actual = JSON.parse(store.providerBody(body(openai), 's1')).messages[0].content[1];
  assert.equal(actual.type, 'image_url');
  assert.equal(actual.image_url.url, 'data:image/png;base64,' + bytes.toString('base64'));
  const anthropic = JSON.parse(store.providerBody(body({ type: 'image', source: { type: 'url', url: image.url } }), 's1')).messages[0].content[1];
  assert.deepEqual(anthropic, { type: 'image', source: { type: 'base64', media_type: 'image/png', data: bytes.toString('base64') } });
  assert.throws(() => store.providerBody(body(openai), 's2'), /belong/i);
  assert.throws(() => store.providerBody(body({ type: 'image_url', image_url: { url: image.url.slice(0, -1) + (image.url.endsWith('a') ? 'b' : 'a') } }), 's1'), /belong/i);
  const textOnly = body({ type: 'text', text: image.url });
  assert.deepEqual(JSON.parse(store.providerBody(textOnly, 's1')), JSON.parse(textOnly), 'references in ordinary text are never expanded');
  store.markStatus(id, 'expired');
  assert.throws(() => store.providerBody(body(openai), 's1'), /expired/i);
  const history = JSON.parse(body(openai)); history.messages.push({ role: 'user', content: 'Continue without it' });
  assert.match(JSON.parse(store.providerBody(JSON.stringify(history), 's1')).messages[0].content[1].text, /earlier image.*no longer available/i);
  store.close();
});

test('browser upload and Lua-shaped relay requests deliver actual PNG, JPEG and WebP content', async t => {
  const bridge = await startBridge(t), requests = [];
  const provider = http.createServer((req, res) => {
    let body = ''; req.on('data', data => body += data); req.on('end', () => {
      requests.push(JSON.parse(body));
      res.writeHead(200, { 'content-type': 'application/json' }); res.end('{"choices":[{"message":{"content":"Received"}}]}');
    });
  });
  provider.listen(0, '127.0.0.1'); await once(provider, 'listening');
  t.after(() => new Promise(resolve => provider.close(resolve)));
  const auth = { Authorization: 'Bearer ' + bridge.token, 'content-type': 'application/json', 'X-UAI-Browser-Id': 'vision-browser' };
  const post = (route, body) => fetch(bridge.base + route, { method: 'POST', headers: auth, body: JSON.stringify(body) });
  await post('/api/agent/events', { sessionId: 's1', state: { sessionId: 's1', imageInput: true } });
  const hello = await (await fetch(bridge.base + '/api/hello', { headers: auth })).json();
  assert.equal(hello.capabilities.pictures.mode, 'provider-image-content');
  const samples = [['png', 'image/png', makePng(3, 4)], ['jpg', 'image/jpeg', makeJpeg(12, 9)], ['webp', 'image/webp', makeWebp(20, 16)]];
  for (const [extension, mediaType, bytes] of samples) {
    const id = 'pic_actual_' + extension;
    const staged = await fetch(bridge.base + '/api/pictures', { method: 'POST', headers: { ...auth, 'content-type': mediaType,
      'X-UAI-Picture-Id': id, 'X-UAI-Session-Id': 's1', 'X-UAI-Picture-Name': 'sample.' + extension }, body: bytes });
    assert.equal(staged.status, 201);
    const send = await post('/api/send', { sessionId: 's1', commandId: 'vision-command-' + extension, text: 'Describe this', pictureIds: [id] });
    assert.equal(send.status, 202);
    const inbox = await (await fetch(bridge.base + '/api/agent/inbox', { headers: auth })).json();
    const command = inbox.commands.find(entry => entry.commandId === 'vision-command-' + extension);
    assert.equal(command.text, 'Describe this');
    assert.equal(command.images.length, 1); assert.ok(!JSON.stringify(command).includes('base64'));
    const source = extension === 'jpg' ? { type: 'image', source: { type: 'url', url: command.images[0].url } }
      : { type: 'image_url', image_url: { url: command.images[0].url, detail: 'auto' } };
    const input = { id: 'vision-request-' + extension, instance: hello.instance, sessionId: 's1',
      url: 'http://127.0.0.1:' + provider.address().port + '/v1/' + (extension === 'jpg' ? 'messages' : 'chat/completions'), headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ model: 'vision-fixture', messages: [{ role: 'user', content: [{ type: 'text', text: command.text }, source] }] }) };
    assert.equal((await post('/api/inference', input)).status, 202);
    let job;
    for (let attempt = 0; attempt < 60; attempt++) {
      job = await (await fetch(bridge.base + '/api/inference/' + input.id, { headers: auth })).json();
      if (job.state !== 'running') break;
      await new Promise(resolve => setTimeout(resolve, 20));
    }
    assert.equal(job.state, 'completed');
    const block = requests.at(-1).messages[0].content[1];
    const encoded = extension === 'jpg' ? block.source.data : block.image_url.url.split(',')[1];
    assert.deepEqual(Buffer.from(encoded, 'base64'), bytes, 'fixture provider receives the original image bytes');
    await post('/api/agent/ack', { results: [{ id: command.commandId, ok: true }] });
    await fetch(bridge.base + '/api/pictures/' + id, { method: 'DELETE', headers: { ...auth, 'X-UAI-Session-Id': 's1' } });
    assert.equal((await post('/api/inference', input)).status, 202, 'lost receipt uses existing job even after picture removal');
    assert.equal(requests.length, samples.findIndex(sample => sample[0] === extension) + 1);
  }
});

test('old game clients reject image sends with a useful upgrade error', async t => {
  const bridge = await startBridge(t);
  const headers = { Authorization: 'Bearer ' + bridge.token, 'X-UAI-Browser-Id': 'browser', 'X-UAI-Session-Id': 's1' };
  await fetch(bridge.base + '/api/pictures', { method: 'POST', headers: { ...headers, 'content-type': 'image/png', 'X-UAI-Picture-Id': 'pic_old_client', 'X-UAI-Picture-Name': 'x.png' }, body: makePng(1, 1) });
  const response = await fetch(bridge.base + '/api/send', { method: 'POST', headers: { ...headers, 'content-type': 'application/json' }, body: JSON.stringify({ sessionId: 's1', pictureIds: ['pic_old_client'] }) });
  assert.equal(response.status, 400); assert.match((await response.json()).error, /reload.*client/i);
});
