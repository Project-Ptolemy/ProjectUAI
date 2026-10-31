'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { readNote, saveNote, editorText, savedText } = require('../web/vault-client');
const { fixture } = require('./helpers/vault');

test('browser editor assembles a full revision-bound UTF-8 document', async t => {
  const f = fixture(t), content = '# Large\n' + '界🙂\n'.repeat(5000); f.write('Large.md', content); let calls = 0;
  const result = await readNote(async (_, input) => { calls++; return f.run(input); }, f.id, 'Large.md');
  assert.equal(result.content, content); assert.ok(calls > 1); assert.equal(result.metadata.title, 'Large');
});

test('browser rejects non-advancing and prematurely completed pages', async () => {
  const revision = 'a'.repeat(64);
  await assert.rejects(readNote(async () => ({ content: 'abc', bytes: 6, offset: 1, revision, nextOffset: 1, eof: false }), 'id', 'note.md'), /advance/);
  await assert.rejects(readNote(async () => ({ content: 'abc', bytes: 6, offset: 1, revision, nextOffset: null, eof: true }), 'id', 'note.md'), /full contents/);
});

test('editor never retries uncertain saves or stale revisions', async () => {
  let calls = 0;
  await assert.rejects(saveNote(async () => { calls++; throw Error('connection reset'); }, { vault: 'id', path: 'note.md' }, 'draft'), error => error.uncertain === true);
  assert.equal(calls, 1);
  await assert.rejects(saveNote(async () => { calls++; throw Object.assign(Error('Changed'), { status: 409 }); }, { vault: 'id', path: 'note.md', revision: 'a'.repeat(64) }, 'draft'), error => error.status === 409 && !error.uncertain);
  assert.equal(calls, 2);
});

test('browser editing preserves CRLF notes without marking loaded text dirty', () => {
  const document = { content: '\ufeff# Title\r\nBody\r\n' };
  assert.equal(editorText(document.content), '\ufeff# Title\nBody\n');
  assert.equal(savedText(document, editorText(document.content) + 'Added\n'), '\ufeff# Title\r\nBody\r\nAdded\r\n');
  assert.equal(savedText({ content: 'LF\n' }, 'Next\n'), 'Next\n');
});
