'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const { spawn, fork } = require('node:child_process');
const { once } = require('node:events');
const { Updater, RELEASES_URL, MANIFEST_NAME, PACKAGE_NAME, ROOT_FILES, checkPackage,
  compare, validPath, trustedUrl, releaseCandidates, cacheDirectory, hash, json } = require('../updater');
const { Supervisor } = require('../supervisor');
const RELEASE = require('../release');
const CURRENT = RELEASE.version;
const [major, minor] = CURRENT.split('.').map(Number);
const NEXT = `${major}.${minor + 1}.0`;
const { runtimeSource } = require('../../tools/build_bridge');
process.env.UAI_OPENCODE_DISABLED = '1';
const { materialize } = require('../launcher');
const source = path.resolve(__dirname, '..');
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));

function temporary(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'uai-updater-test-'));
  t.after(() => {
    assert.ok(path.resolve(root).startsWith(path.resolve(os.tmpdir()) + path.sep));
    fs.rmSync(root, { recursive: true, force: true });
  });
  return root;
}
function fixture(next = NEXT, overrides = {}) {
  const names = [...ROOT_FILES, 'web/index.html'].sort();
  const files = names.map(name => {
    let data = name === 'web/index.html' ? Buffer.from('<html>synthetic bridge release</html>') : runtimeSource(name);
    if (name === 'release.js') data = Buffer.from("'use strict';\nmodule.exports = " + JSON.stringify({ ...RELEASE, version: next }) + ';\n');
    if (Object.hasOwn(overrides, name)) data = Buffer.from(overrides[name]);
    return { path: name, bytes: data.length, sha256: hash(data), data: data.toString('base64') };
  });
  return fromFiles(next, files);
}
function fromFiles(next, files) {
  const archive = json({ format: 'project-uai-bridge-package', schema: 1, version: next, files });
  const manifest = { format: 'project-uai-bridge-release', schema: 1, ...RELEASE, version: next,
    package: { name: PACKAGE_NAME, bytes: archive.length, sha256: hash(archive) } };
  const release = { tag_name: 'bridge-v' + next, draft: false, prerelease: false, assets: [MANIFEST_NAME, PACKAGE_NAME].map(name => ({
    name, browser_download_url: `https://github.com/Project-Ptolemy/ProjectUAI/releases/download/bridge-v${next}/${name}` })) };
  const responses = new Map([[RELEASES_URL, json([release])],
    [release.assets[0].browser_download_url, json(manifest)], [release.assets[1].browser_download_url, archive]]);
  const requests = [];
  return { archive, manifest, release, files, requests, fetchBytes: async (url, limit, signal) => {
    assert.ok(!signal?.aborted); assert.ok(responses.has(url), 'only expected official URLs are fetched');
    const value = responses.get(url); assert.ok(value.length <= limit); requests.push(url); return value;
  } };
}
async function port() {
  const server = http.createServer(); server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const number = server.address().port; await new Promise(resolve => server.close(resolve)); return number;
}
async function running(t, data, extras = {}) {
  let supervisor;
  t.after(() => supervisor?.stop());
  const cacheDir = path.join(temporary(t), 'cache'), number = await port();
  const updater = new Updater({ cacheDir, fetchBytes: data.fetchBytes });
  supervisor = new Supervisor({ updater, args: ['--port', String(number)], enabled: true,
    initialDelayMs: 2 ** 30, idleRetryMs: 2 ** 30, stdout: null, stderr: null, ...extras });
  await supervisor.start();
  const call = (route, body, method = body === undefined ? 'GET' : 'POST') => fetch(`http://127.0.0.1:${number}` + route,
    { method, headers: { Authorization: 'Bearer ' + supervisor.token, 'Content-Type': 'application/json' },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
  return { supervisor, updater, number, call, cacheDir };
}
async function until(predicate, message, timeout = 5000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) { if (await predicate()) return; await pause(25); }
  assert.fail(message);
}

test('only newer stable releases with exact official asset paths are eligible', () => {
  const good = fixture('3.3.0');
  assert.equal(compare('3.10.0', '3.9.9'), 1);
  assert.equal(compare('3.2.0', '3.2.0'), 0);
  for (const bad of ['03.2.0', '3.1', '3.2.0-beta', '9007199254740992.1.0']) assert.throws(() => compare(bad, '3.2.0'));
  const copy = value => JSON.parse(JSON.stringify(value));
  const remote = copy(good.release); remote.assets[0].browser_download_url = 'https://example.invalid/bridge-release.json';
  const duplicate = copy(good.release); duplicate.assets.push(duplicate.assets[0]);
  const candidates = releaseCandidates([{ ...good.release, draft: true }, { ...good.release, prerelease: true },
    { ...good.release, tag_name: 'bridge-v3.3.0-rc1' }, remote, duplicate, fixture('2.9.0').release, good.release], '3.2.0');
  assert.deepEqual(candidates.map(x => x.version), ['3.3.0']);
  assert.deepEqual(releaseCandidates([{ ...good.release, assets: [] }], '3.2.0'), [], 'old ZIP-only releases are skipped');
  for (const url of ['http://github.com/', 'https://github.com.evil.invalid/', 'https://user:pw@github.com/',
    'https://github.com:8443/', 'https://raw.githubusercontent.com/evil/code', 'file:///C:/code.js']) assert.throws(() => trustedUrl(url));
  assert.equal(trustedUrl('https://release-assets.githubusercontent.com/github-production-release-asset/x').hostname, 'release-assets.githubusercontent.com');
});

test('package validation rejects hash, size, path, missing file and case collisions before staging', t => {
  const data = fixture(), updater = new Updater({ cacheDir: path.join(temporary(t), 'cache') });
  assert.throws(() => checkPackage(Buffer.concat([data.archive, Buffer.from('x')]), data.manifest), /SHA-256|size/);
  const bad = Buffer.from(data.archive); bad[100] ^= 1;
  assert.throws(() => checkPackage(bad, data.manifest), /SHA-256/);
  for (const name of ['../outside.js', '/root.js', 'web/../file.js', 'web\\file.js', 'web/file.js:stream',
    'web/file. /bad.js', 'web/con.js', 'web/LPT1.txt', 'web/file\u0000.js', 'node_modules/a.js', 'package.json']) assert.throws(() => validPath(name));
  for (const files of [data.files.filter(f => f.path !== 'server.js'), [...data.files, { ...data.files.at(-1), path: data.files.at(-1).path.toUpperCase() }],
    data.files.map(f => f.path === 'server.js' ? { ...f, sha256: '0'.repeat(64) } : f),
    data.files.map(f => f.path === 'server.js' ? { ...f, bytes: f.bytes + 1 } : f)]) {
    const broken = fromFiles(NEXT, files);
    assert.throws(() => checkPackage(broken.archive, broken.manifest));
  }
  assert.equal(fs.existsSync(updater.cacheDir), false);
});

test('the shipped 3.1 updater accepts the new release without additional root filenames', async t => {
  const root = temporary(t), snapshot = Buffer.from(fs.readFileSync(path.join(__dirname, 'fixtures', 'updater-3.1.js.txt'), 'utf8').replace(/\r\n/g, '\n'));
  assert.equal(hash(snapshot), '13092676e9075cd21f7014ef0d7be215dfb54768840c547ef832d211d372a985', 'exact released validator fixture');
  fs.writeFileSync(path.join(root, 'updater.js'), snapshot);
  fs.writeFileSync(path.join(root, 'release.js'), "module.exports={version:'3.1.0',protocol:2,updateProtocol:1,minNode:18};\n");
  const previous = require(path.join(root, 'updater.js')), data = fixture(CURRENT);
  const files = previous.checkPackage(data.archive, data.manifest);
  assert.deepEqual(files.filter(file => !file.path.startsWith('web/')).map(file => file.path).sort(), previous.ROOT_FILES.slice().sort());
  assert.ok(files.find(file => file.path === 'server.js').data.includes(Buffer.from('function createOpenCode')));
  assert.ok(files.find(file => file.path === 'server.js').data.includes(Buffer.from('function createMcp')));
  assert.ok(!files.find(file => file.path === 'inference.js').data.includes(Buffer.from("require('./support')")));
  const updater = new previous.Updater({ cacheDir: path.join(root, 'cache'), fetchBytes: data.fetchBytes });
  const staged = await updater.check('3.1.0'); assert.equal(staged.version, CURRENT);
  updater.activate(staged); assert.equal(updater.active('3.1.0').key, staged.key);
});

test('verified cache activation is isolated, detects corruption and repairs from a valid download', async t => {
  const data = fixture(), root = temporary(t), sourceBefore = fs.readFileSync(path.join(source, 'server.js'));
  const updater = new Updater({ cacheDir: path.join(root, 'cache'), fetchBytes: data.fetchBytes });
  const release = await updater.check(CURRENT);
  assert.equal(release.version, NEXT); assert.equal(updater.active(CURRENT), null);
  assert.equal(data.requests.length, 3);
  updater.activate(release); assert.equal(updater.active(CURRENT).key, release.key);
  fs.appendFileSync(release.entry, '\n// corrupt');
  assert.equal(updater.active(CURRENT), null); assert.throws(() => updater.verify(release.key), /size|SHA-256/);
  assert.equal((await updater.check(CURRENT)).key, release.key, 'a corrupt saved version is repaired');
  assert.equal(updater.active(CURRENT).version, NEXT);
  fs.writeFileSync(path.join(path.dirname(release.entry), 'package.json'), '{}');
  assert.throws(() => updater.verify(release.key), /Unexpected/);
  assert.deepEqual(fs.readFileSync(path.join(source, 'server.js')), sourceBefore, 'even a dirty checkout is not an update destination');
  assert.ok(fs.readdirSync(updater.cacheDir).every(name => !name.startsWith('.stage-')));
});

test('cache junctions and cached metadata cannot redirect runnable files', async t => {
  const root = temporary(t), outside = path.join(root, 'outside'); fs.mkdirSync(outside);
  const link = path.join(root, 'cache'); fs.symlinkSync(outside, link, process.platform === 'win32' ? 'junction' : 'dir');
  const data = fixture(), updater = new Updater({ cacheDir: link, fetchBytes: data.fetchBytes });
  await assert.rejects(updater.check(CURRENT), /symbolic link/); assert.deepEqual(fs.readdirSync(outside), []);
  const clean = new Updater({ cacheDir: path.join(root, 'clean'), fetchBytes: data.fetchBytes });
  const release = await clean.check(CURRENT);
  const metadata = path.join(path.dirname(release.entry), '.release.json');
  const record = JSON.parse(fs.readFileSync(metadata, 'utf8'));
  record.files.find(f => f.path === 'web/index.html').sha256 = '0'.repeat(64);
  fs.writeFileSync(metadata, json(record));
  assert.throws(() => clean.verify(release.key), /SHA-256/);
});

test('offline release failure leaves the running bridge and token usable', async t => {
  const live = await running(t, { fetchBytes: async () => { throw Error('offline'); } });
  const original = live.supervisor.worker.child.pid, token = live.supervisor.token;
  await live.supervisor.checkUpdates();
  assert.equal(live.supervisor.status.state, 'error'); assert.equal(live.supervisor.worker.child.pid, original);
  let hello;
  await until(async () => { hello = await (await live.call('/api/hello')).json(); return hello.update.state === 'error'; },
    'worker did not receive the supervised offline failure status');
  assert.equal(hello.update.state, 'error'); assert.equal(live.supervisor.token, token);
  assert.equal(fs.existsSync(live.cacheDir), false);
});

test('busy agent, subagent, permission, and question state defer update; idle restart keeps token and flags', async t => {
  const data = fixture(), live = await running(t, data, { args: ['--port', String(await port()), '--legacy'] });
  // This test supplies its own port flag, so use the worker's reported port.
  const number = Number(live.supervisor.args[1]);
  const call = (route, body) => fetch(`http://127.0.0.1:${number}` + route, { method: body ? 'POST' : 'GET',
    headers: { Authorization: 'Bearer ' + live.supervisor.token, 'Content-Type': 'application/json' }, ...(body ? { body: JSON.stringify(body) } : {}) });
  const original = live.supervisor.worker.child.pid, token = live.supervisor.token;
  for (const state of [{ agent: { busy: true } }, { threads: [{ busy: true }] }, { subagents: [{ status: 'running' }] },
    { loops: [{ state: 'waiting' }] }, { pendingPermissions: [{}] }, { questions: [{}] }]) {
    assert.equal((await call('/api/agent/events', { state })).status, 204);
    if (!live.supervisor.staged) await live.supervisor.checkUpdates(); else await live.supervisor.applyStaged();
    assert.equal(live.supervisor.worker.child.pid, original); assert.equal(live.supervisor.status.state, 'staged');
  }
  assert.equal((await call('/api/agent/events', { state: { agent: { busy: false }, threads: [], subagents: [] } })).status, 204);
  assert.equal(await live.supervisor.applyStaged(), true);
  assert.notEqual(live.supervisor.worker.child.pid, original); assert.equal(live.supervisor.token, token);
  const hello = await (await call('/api/hello')).json();
  assert.equal(hello.update.currentVersion, NEXT); assert.equal(hello.capabilities.pictures, undefined, 'legacy flag survives worker update');
  assert.equal(live.updater.active(CURRENT).version, NEXT);
});

test('queued commands and an unfinished request body block restart without duplicate delivery', async t => {
  const data = fixture(), live = await running(t, data);
  const original = live.supervisor.worker.child.pid;
  const body = '{"type":"clear","commandId":"updater-queued-command"}';
  const request = http.request({ host: '127.0.0.1', port: live.number, path: '/api/command', method: 'POST',
    headers: { Authorization: 'Bearer ' + live.supervisor.token, 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) } });
  request.on('error', () => {}); request.write(body.slice(0, 8));
  await pause(50); await live.supervisor.checkUpdates();
  assert.equal(live.supervisor.worker.child.pid, original); assert.equal(live.supervisor.status.state, 'staged');
  const response = once(request, 'response'); request.end(body.slice(8)); const [res] = await response; res.resume(); await once(res, 'end');
  assert.equal(res.statusCode, 202); assert.equal(await live.supervisor.applyStaged(), false);
  const inbox = await fetch(`http://127.0.0.1:${live.number}/api/agent/inbox`, { headers: {
    Authorization: 'Bearer ' + live.supervisor.token, 'X-UAI-Poll-Wait-Ms': '0' } });
  assert.equal((await inbox.json()).commands.filter(x => x.commandId === 'updater-queued-command').length, 1);
});

test('worker health keeps its actual version while supervisor activation status catches up', async t => {
  const live = await running(t, fixture());
  live.supervisor.send({ type: 'update-state', update: { state: 'restarting', currentVersion: '0.0.0', availableVersion: NEXT } });
  let hello;
  await until(async () => {
    hello = await (await live.call('/api/hello')).json();
    return hello.update.state === 'restarting';
  }, 'worker receives activation metadata');
  assert.equal(hello.update.currentVersion, CURRENT);
  assert.equal(hello.update.availableVersion, NEXT);
});

test('active PC inference waits indefinitely; completion is retained until authoritative commit', async t => {
  const data = fixture(), live = await running(t, data); let providerResponse, received = 0;
  const provider = http.createServer((req, res) => { received++; providerResponse = res; req.resume(); });
  provider.listen(0, '127.0.0.1'); await once(provider, 'listening');
  t.after(() => { provider.closeAllConnections(); return new Promise(resolve => provider.close(resolve)); });
  const id = 'updater-inference-123';
  const { instance } = await (await live.call('/api/hello')).json();
  const result = await live.call('/api/inference', { id, instance, sessionId: 'update-session', url: `http://127.0.0.1:${provider.address().port}/v1/responses`,
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}', timeout: 1 });
  assert.equal(result.status, 202); await until(() => providerResponse, 'provider starts');
  const original = live.supervisor.worker.child.pid;
  await live.supervisor.checkUpdates(); assert.equal(live.supervisor.status.state, 'staged');
  assert.equal(live.supervisor.worker.child.pid, original); assert.equal(providerResponse.destroyed, false);
  providerResponse.end('{"output":[]}');
  await until(async () => (await (await live.call('/api/inference/' + id)).json()).state === 'completed', 'inference completes');
  assert.equal(await live.supervisor.applyStaged(), false, 'game may still need the completed body');
  await live.call('/api/agent/events', { sessionId: 'update-session', events: [{ kind: 'assistant:text', requestId: id, text: 'done' }] });
  assert.equal(await live.supervisor.applyStaged(), true); assert.equal(received, 1);
});

test('failed candidate startup rolls back to the original worker without moving active pointer', async t => {
  const live = await running(t, fixture(NEXT, { 'server.js': "'use strict'; process.exit(7);\n" }));
  const original = live.supervisor.worker.child.pid, token = live.supervisor.token;
  await live.supervisor.checkUpdates();
  assert.equal(live.supervisor.status.state, 'error'); assert.equal(live.supervisor.current.version, CURRENT);
  assert.notEqual(live.supervisor.worker.child.pid, original, 'previous files were launched after candidate failure');
  assert.equal(live.supervisor.token, token); assert.equal((await live.call('/api/hello')).status, 200);
  assert.equal(live.updater.active(CURRENT), null);
});

test('live picture drafts survive staging until explicitly removed', async t => {
  const live = await running(t, fixture()), id = 'pic_update-draft-123';
  const headers = { Authorization: 'Bearer ' + live.supervisor.token, 'X-UAI-Browser-Id': 'update-browser',
    'X-UAI-Session-Id': 'update-session', 'X-UAI-Picture-Id': id, 'Content-Type': 'image/png' };
  const base = `http://127.0.0.1:${live.number}`, bytes = require('./helpers/images').makePng(2, 2);
  const upload = await fetch(base + '/api/pictures', { method: 'POST', headers, body: bytes });
  assert.equal(upload.status, 201); await upload.json();
  const original = live.supervisor.worker.child.pid;
  await live.supervisor.checkUpdates(); assert.equal(live.supervisor.status.state, 'staged');
  assert.equal(live.supervisor.worker.child.pid, original);
  assert.deepEqual(Buffer.from(await (await fetch(base + '/api/pictures/' + id, { headers })).arrayBuffer()), bytes);
  await (await fetch(base + '/api/pictures/' + id, { method: 'DELETE', headers })).json();
  assert.equal(await live.supervisor.applyStaged(), true);
});

test('activation failure stops the candidate and restores the previous live version', async t => {
  const live = await running(t, fixture());
  live.updater.activate = () => { throw Error('simulated disk failure'); };
  await live.supervisor.checkUpdates();
  assert.equal(live.supervisor.status.state, 'error'); assert.equal(live.supervisor.current.version, CURRENT);
  assert.equal((await live.call('/api/hello')).status, 200); assert.equal(live.updater.active(CURRENT), null);
});

test('a cached startup error is withheld until the installed fallback can become ready', async t => {
  let sup; t.after(() => sup?.stop());
  const root = temporary(t), data = fixture(NEXT, { 'server.js':
    "process.stdout.write(JSON.stringify({type:'error',message:'synthetic startup failure'})+'\\n',()=>process.exit(7));\n" });
  const updater = new Updater({ cacheDir: path.join(root, 'cache'), fetchBytes: data.fetchBytes });
  updater.activate(await updater.check(CURRENT));
  let output = '';
  sup = new Supervisor({ updater, args: ['--port', String(await port())], initialDelayMs: 2 ** 30,
    stdout: { write: chunk => { output += chunk; } }, stderr: null });
  await sup.start();
  await until(() => /Token\s+[a-f0-9]{64}/.test(output), 'fallback prints its ready output');
  assert.equal(sup.current.version, CURRENT); assert.ok(!output.includes('synthetic startup failure'));
});

test('a worker crash during idle negotiation restores a live worker instead of retrying a dead one', async t => {
  let sup; t.after(() => sup?.stop());
  const root = temporary(t), entry = path.join(root, 'base.js'), data = fixture();
  fs.writeFileSync(entry, "process.send({type:'ready',version:'" + CURRENT + "',updateProtocol:1,token:process.env.UAI_BRIDGE_SESSION_TOKEN});\n" +
    "process.on('message',m=>{if(m.type==='prepare-update'||m.type==='stop')process.exit(9);});\n" +
    "process.on('disconnect',()=>process.exit(0));process.stdin.resume();process.stdin.on('end',()=>process.exit(0));\n");
  const updater = new Updater({ cacheDir: path.join(root, 'cache'), fetchBytes: data.fetchBytes });
  sup = new Supervisor({ entry, updater, args: [], initialDelayMs: 2 ** 30, stdout: null, stderr: null });
  await sup.start(); const original = sup.worker.child.pid;
  await sup.checkUpdates();
  assert.equal(sup.status.state, 'error'); assert.notEqual(sup.worker.child.pid, original);
  assert.equal(sup.worker.child.exitCode, null); assert.equal(sup.current.version, CURRENT);
});

test('pruning removes stale versions and quarantine folders while keeping fresh entries', async t => {
  const root = temporary(t), cacheDir = path.join(root, 'cache');
  const updater = new Updater({ cacheDir, fetchBytes: fixture().fetchBytes });
  const first = await updater.check(CURRENT);
  updater.activate(first);
  const stale = path.join(cacheDir, 'versions', '9.9.9-' + 'b'.repeat(64));
  const quarantine = path.join(cacheDir, '.invalid-stale');
  fs.mkdirSync(stale, { recursive: true }); fs.mkdirSync(quarantine, { recursive: true });
  const old = new Date(Date.now() - 7200000);
  fs.utimesSync(stale, old, old); fs.utimesSync(quarantine, old, old);
  const fresh = path.join(cacheDir, 'versions', '9.9.9-' + 'c'.repeat(64));
  fs.mkdirSync(fresh, { recursive: true });
  updater.prune([first.key]);
  assert.equal(fs.existsSync(stale), false, 'stale version removed');
  assert.equal(fs.existsSync(quarantine), false, 'stale quarantine removed');
  assert.equal(fs.existsSync(fresh), true, 'recent unreferenced entry survives for concurrent processes');
  assert.equal(fs.existsSync(path.dirname(first.entry)), true, 'active version kept');
});

test('a desktop update-check request performs one supervised check and answers before applying', async t => {
  const data = fixture();
  const { supervisor, call } = await running(t, data, { idleRetryMs: 50 });
  assert.equal(supervisor.status.state, 'current');
  const response = await call('/api/desktop/update-check', {});
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.ok, true);
  assert.equal(body.update.state, 'staged');
  assert.equal(body.update.currentVersion, CURRENT);
  assert.equal(body.update.availableVersion, NEXT);
  await until(async () => supervisor.status.state === 'updated', 'the staged release applies once the reply is delivered');
  await until(async () => { try { return (await call('/api/hello')).ok; } catch { return false; } }, 'the updated worker serves the API again');
  assert.equal(supervisor.current.version, NEXT);
  const settled = await call('/api/desktop/update-check', {});
  assert.equal(settled.status, 200);
  const settledBody = await settled.json();
  assert.equal(settledBody.ok, true);
  assert.equal(settledBody.update.state, 'current');
  assert.equal(settledBody.update.currentVersion, NEXT);
});

test('a downloaded start.txt keeps its cached update after the original runtime is rematerialized', async t => {
  let sup; t.after(() => sup?.stop());
  const root = temporary(t), packageDir = path.join(root, 'packages', 'original'); fs.mkdirSync(packageDir, { recursive: true });
  const original = fixture(CURRENT);
  const manifest = { revision: 'a'.repeat(40), files: original.files.map(file => {
    const bytes = Buffer.from(file.data, 'base64'), target = path.join(packageDir, file.path + '.txt');
    fs.mkdirSync(path.dirname(target), { recursive: true }); fs.writeFileSync(target, bytes);
    return { path: file.path, size: bytes.length, sha: require('node:crypto').createHash('sha1').update('blob ' + bytes.length + '\0').update(bytes).digest('hex') };
  }) };
  const entry = materialize(manifest, packageDir);
  const cacheDir = path.join(root, 'user-cache'), update = fixture();
  const updater = new Updater({ cacheDir, fetchBytes: update.fetchBytes }), release = await updater.check(CURRENT); updater.activate(release);
  materialize(manifest, packageDir);
  sup = new Supervisor({ entry, updater, args: ['--port', String(await port())], initialDelayMs: 2 ** 30, stdout: null, stderr: null });
  await sup.start();
  assert.equal(sup.current.version, NEXT); assert.equal(sup.worker.release.entry, release.entry);
  assert.ok(fs.readFileSync(path.join(path.dirname(entry), 'release.js'), 'utf8').includes(CURRENT));
  assert.equal(cacheDirectory(path.join(root, 'start.txt')), cacheDirectory(path.join(root, 'start.txt')));
  assert.ok(!cacheDirectory(path.join(root, 'start.txt')).startsWith(packageDir));
  const previous = process.env.UAI_BRIDGE_INSTALLATION_ID;
  try {
    process.env.UAI_BRIDGE_INSTALLATION_ID = path.join(root, 'original-desktop');
    assert.equal(cacheDirectory(), cacheDirectory(path.join(root, 'original-desktop')), 'desktop cache identity survives versioned app folders');
  } finally {
    if (previous === undefined) delete process.env.UAI_BRIDGE_INSTALLATION_ID; else process.env.UAI_BRIDGE_INSTALLATION_ID = previous;
  }
});

test('worker exits when its owning IPC parent disconnects', async t => {
  const number = await port();
  const child = fork(path.join(source, 'server.js'), ['--port', String(number)], { env: { ...process.env,
    UAI_BRIDGE_WORKER: '1', UAI_BRIDGE_SESSION_TOKEN: 'a'.repeat(64) }, stdio: ['pipe', 'pipe', 'pipe', 'ipc'], windowsHide: true });
  child.stdout.resume(); child.stderr.resume();
  t.after(() => { if (child.exitCode === null && child.signalCode === null) child.kill(); });
  await new Promise((resolve, reject) => { child.once('error', reject); child.on('message', message => { if (message.type === 'ready') resolve(); }); });
  const exit = once(child, 'exit'); child.disconnect();
  const timeout = setTimeout(() => child.kill(), 4000);
  const [code, signal] = await exit; clearTimeout(timeout);
  assert.equal(code, 0); assert.equal(signal, null);
  await assert.rejects(fetch(`http://127.0.0.1:${number}/api/hello`));
});

test('hard killing a CLI supervisor leaves no listening worker', async t => {
  const number = await port();
  const supervisor = spawn(process.execPath, [path.join(source, 'server.js'), '--port', String(number)], {
    env: { ...process.env, UAI_BRIDGE_TEST_NO_UPDATES: '1' }, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
  supervisor.stderr.resume();
  t.after(() => { if (supervisor.exitCode === null && supervisor.signalCode === null) supervisor.kill(); });
  await new Promise((resolve, reject) => {
    supervisor.once('error', reject); let text = '';
    supervisor.stdout.on('data', chunk => { text += chunk; if (/Token\s+[a-f0-9]{64}/.test(text)) resolve(); });
  });
  const exit = once(supervisor, 'exit'); supervisor.kill('SIGKILL'); await exit;
  await until(async () => { try { await fetch(`http://127.0.0.1:${number}/api/hello`); return false; } catch { return true; } }, 'orphan worker releases its port');
});
