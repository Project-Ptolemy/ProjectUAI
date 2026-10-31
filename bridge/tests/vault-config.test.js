'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { createVaults } = require('../vaults');
const { fixture } = require('./helpers/vault');

test('vault connections persist stable ids and omit absolute roots from agent listings', t => {
  const f = fixture(t); f.write('Keep.md', 'keep');
  const fresh = createVaults({ configFile: f.configFile });
  assert.equal(fresh.list().vaults[0].id, f.id); assert.equal(fresh.list().vaults[0].root, undefined);
  assert.equal(fresh.list(true).vaults[0].root, f.root);
  fresh.configure({ action: 'connect', id: f.id, name: 'Renamed', root: f.root });
  assert.equal(fresh.list().vaults[0].readOnly, true); assert.equal(fresh.list().vaults[0].id, f.id);
  fresh.configure({ action: 'remove', id: f.id }); assert.equal(fresh.list().vaults.length, 0);
  assert.equal(fs.readFileSync(f.root + '/Keep.md', 'utf8'), 'keep');
});

test('damaged or unsupported configuration blocks edits without overwriting evidence', t => {
  const f = fixture(t); const damaged = '{broken'; fs.writeFileSync(f.configFile, damaged);
  const fresh = createVaults({ configFile: f.configFile }); assert.match(fresh.list().error, /configuration/);
  assert.throws(() => fresh.configure({ action: 'connect', name: 'New', root: f.root }), /configuration/);
  assert.equal(fs.readFileSync(f.configFile, 'utf8'), damaged); assert.equal(fresh.capability().configError, true);
});

test('connection validation rejects duplicates and invalid policy values', t => {
  const f = fixture(t);
  assert.throws(() => f.vaults.configure({ action: 'connect', name: 'Different', root: f.root }), /already connected/);
  assert.throws(() => f.vaults.configure({ action: 'connect', name: 'Fixture', root: f.root }), /unique/);
  assert.throws(() => f.vaults.configure({ action: 'policy', id: f.id, readOnly: 'false' }), /true or false/);
  assert.throws(() => f.vaults.configure({ action: 'policy', id: 'missing', readOnly: false }), /Unknown/);
});

test('two bridge instances cannot silently overwrite each other’s connection changes', t => {
  const f = fixture(t), second = createVaults({ configFile: f.configFile }); second.list();
  f.vaults.configure({ action: 'policy', id: f.id, readOnly: true });
  assert.throws(() => second.configure({ action: 'remove', id: f.id }), /another bridge/);
  assert.equal(createVaults({ configFile: f.configFile }).list().vaults[0].readOnly, true);
});
