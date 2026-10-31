'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { relativePath, notePath, guard, openRoot } = require('../vault-paths');
const { fixture } = require('./helpers/vault');

test('vault paths reject traversal, hidden files, device names and ambiguous Windows paths', () => {
  for (const value of ['../secret.md', '/root.md', 'C:/secret.md', 'x\\a.md', '.obsidian/config.md', 'a//b.md', 'a/./b.md', 'a/../b.md', 'aux.md', 'COM1/a.md', 'name./a.md', 'a:b.md', 'a\0.md', '']) {
    assert.throws(() => notePath(value), undefined, value);
  }
  assert.equal(notePath('Research/世界.md'), 'Research/世界.md');
  assert.equal(relativePath('', true), '');
  assert.throws(() => notePath('image.png'));
  assert.throws(() => notePath('\ud800.md'), /Unicode/);
  assert.throws(() => notePath('COM¹.md'));
});

test('vault access refuses hard links and replaced root identities', t => {
  const f = fixture(t), source = f.write('source.md', 'private');
  fs.linkSync(source, path.join(f.root, 'linked.md'));
  assert.throws(() => f.run({ action: 'read', path: 'linked.md' }), /links/);
  const opened = openRoot(f.root);
  fs.renameSync(f.root, path.join(f.temporary, 'old-notes')); fs.mkdirSync(f.root);
  assert.throws(() => guard(opened, ''), /changed/);
});

test('linked folders never expose files outside the connected root', t => {
  const f = fixture(t), outside = path.join(f.temporary, 'outside'); fs.mkdirSync(outside); fs.writeFileSync(path.join(outside, 'secret.md'), 'outside');
  try { fs.symlinkSync(outside, path.join(f.root, 'linked'), process.platform === 'win32' ? 'junction' : 'dir'); }
  catch (error) { if (error.code === 'EPERM') { t.skip('Symlink permission unavailable'); return; } throw error; }
  assert.throws(() => f.run({ action: 'read', path: 'linked/secret.md' }), /links/);
  const listing = f.run({ action: 'list' }); assert.equal(listing.data.length, 0); assert.equal(listing.incomplete, true);
});
