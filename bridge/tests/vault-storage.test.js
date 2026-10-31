'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { fixture } = require('./helpers/vault');

test('create, update and append verify bytes and reject stale revisions without overwriting', t => {
  const f = fixture(t), created = f.run({ action: 'create', path: 'Folder/Note.md', content: '# First\n世界🙂' });
  assert.equal(created.created, true); assert.match(created.revision, /^[a-f0-9]{64}$/);
  assert.throws(() => f.run({ action: 'create', path: 'Folder/Note.md', content: 'overwrite' }), /already exists/);
  const updated = f.run({ action: 'update', path: created.path, content: '# Second', revision: created.revision });
  assert.notEqual(updated.revision, created.revision);
  assert.throws(() => f.run({ action: 'append', path: created.path, content: 'stale', revision: created.revision }), /changed/);
  const appended = f.run({ action: 'append', path: created.path, content: '\nDone', revision: updated.revision });
  assert.equal(f.run({ action: 'read', path: created.path }).content, '# Second\nDone');
  assert.notEqual(appended.revision, updated.revision);
});

test('read-only policy stops every note mutation and can be changed independently of roots', t => {
  const f = fixture(t, { readOnly: true }); f.write('Read.md', 'safe'); const note = f.run({ action: 'read', path: 'Read.md' });
  for (const action of ['create', 'update', 'append']) assert.throws(() => f.run({ action, path: 'Read.md', content: 'write', revision: note.revision }), /read-only/);
  f.vaults.configure({ action: 'policy', id: f.id, readOnly: false });
  f.run({ action: 'update', path: 'Read.md', content: 'allowed', revision: note.revision });
  assert.equal(f.run({ action: 'read', path: 'Read.md' }).content, 'allowed');
});

test('UTF-8 pages preserve every byte and reject mixed revisions and split codepoints', t => {
  const f = fixture(t); const source = 'a🙂界\n'.repeat(100); f.write('Utf8.md', source);
  let offset = 1, revision, output = '';
  do { const page = f.run({ action: 'read', path: 'Utf8.md', offset, limit: 7, revision }); revision = page.revision; output += page.content; offset = page.nextOffset; } while (offset);
  assert.equal(output, source);
  assert.throws(() => f.run({ action: 'read', path: 'Utf8.md', offset: 3 }), /UTF-8/);
  f.write('Utf8.md', 'changed');
  assert.throws(() => f.run({ action: 'read', path: 'Utf8.md', revision }), /between pages/);
});

test('invalid encoding, unpaired surrogates and oversized files fail explicitly', t => {
  const f = fixture(t); f.write('Invalid.md', Buffer.from([0xff]));
  assert.throws(() => f.run({ action: 'read', path: 'Invalid.md' }), /UTF-8/);
  assert.throws(() => f.run({ action: 'create', path: 'Surrogate.md', content: '\ud800' }), /Unicode/);
  f.write('Large.md', Buffer.alloc(1048577));
  assert.throws(() => f.run({ action: 'read', path: 'Large.md' }), /1 MiB/);
  assert.throws(() => f.run({ action: 'create', path: 'Large2.md', content: 'a'.repeat(1048577) }), /1 MiB/);
  assert.equal(fs.readdirSync(f.root).some(value => value.startsWith('.uai-note-')), false);
});

test('append preserves a UTF-8 byte-order mark and existing CRLF bytes', t => {
  const f = fixture(t); f.write('Bom.md', '\ufeff# Note\r\n');
  const note = f.run({ action: 'read', path: 'Bom.md' });
  f.run({ action: 'append', path: 'Bom.md', content: 'Next\r\n', revision: note.revision });
  assert.equal(f.run({ action: 'read', path: 'Bom.md' }).content, '\ufeff# Note\r\nNext\r\n');
});
