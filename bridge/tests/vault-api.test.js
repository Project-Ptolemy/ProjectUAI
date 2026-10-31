'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { fixture } = require('./helpers/vault');
const { startBridge } = require('./helpers/bridge');

test('authenticated vault API configures folders and enforces note revisions', async t => {
  const f = fixture(t); f.write('Start.md', '# Start');
  const bridge = await startBridge(t, [], 'bridge/server.js', { UAI_VAULT_CONFIG: f.configFile });
  const request = async (route, body, extra = {}) => {
    const response = await fetch(bridge.base + route, { method: body ? 'POST' : 'GET', headers: { Authorization: 'Bearer ' + bridge.token, 'Content-Type': 'application/json', ...extra }, body: body ? JSON.stringify(body) : undefined });
    return { status: response.status, data: await response.json() };
  };
  const hello = await request('/api/hello'); assert.equal(hello.data.capabilities.obsidian.schema, 1);
  const listed = await request('/api/vaults'); assert.equal(listed.data.vaults[0].root, undefined);
  const configured = await request('/api/vaults/config'); assert.equal(configured.data.vaults[0].root, f.root);
  const read = await request('/api/vaults', { action: 'read', vault: f.id, path: 'Start.md' }); assert.equal(read.data.content, '# Start');
  const saved = await request('/api/vaults', { action: 'update', vault: f.id, path: 'Start.md', content: '# Saved', revision: read.data.revision }); assert.equal(saved.status, 200);
  const stale = await request('/api/vaults', { action: 'update', vault: f.id, path: 'Start.md', content: '# Stale', revision: read.data.revision }); assert.equal(stale.status, 409);
  const missing = await request('/api/vaults', { action: 'read', vault: f.id, path: 'Private.md' }); assert.equal(missing.status, 404); assert.ok(!JSON.stringify(missing.data).includes(f.root));
});

test('vault routes retain bearer and same-origin protections', async t => {
  const bridge = await startBridge(t);
  for (const endpoint of ['/api/vaults', '/api/vaults/config']) {
    assert.equal((await fetch(bridge.base + endpoint)).status, 401);
    assert.equal((await fetch(bridge.base + endpoint, { headers: { Authorization: 'Bearer ' + bridge.token, Origin: 'https://example.invalid' } })).status, 403);
    assert.equal((await fetch(bridge.base + endpoint, { method: 'DELETE', headers: { Authorization: 'Bearer ' + bridge.token } })).status, 405);
  }
});
