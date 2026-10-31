'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { fixture } = require('./helpers/vault');

test('literal search returns resumable exact paths and ignores hidden settings', t => {
  const f = fixture(t); f.write('One.md', 'literal [term]\nsecond'); f.write('Two.md', 'LITERAL [TERM]'); f.write('.obsidian/Hidden.md', '[term]'); f.write('skip.txt', '[term]');
  const first = f.run({ action: 'search', query: '[term]', limit: 1 });
  const second = f.run({ action: 'search', query: '[term]', limit: 1, offset: first.nextOffset });
  assert.equal(first.total, 2); assert.equal(first.data[0].path, 'One.md'); assert.equal(second.data[0].path, 'Two.md'); assert.equal(second.nextOffset, null);
  assert.equal(first.data[0].matches[0].line, 1); assert.match(first.data[0].revision, /^[a-f0-9]{64}$/);
  assert.throws(() => f.run({ action: 'search', query: ' ' }), /query/);
  assert.throws(() => f.run({ action: 'list', offset: -1 }), /offset/);
});

test('oversized and unreadable notes do not hide later searchable notes', t => {
  const f = fixture(t); f.write('A-huge.md', Buffer.alloc(17000000)); f.write('B-invalid.md', Buffer.from([0xff])); f.write('C-readable.md', 'needle');
  const result = f.run({ action: 'search', query: 'needle' });
  assert.equal(result.incomplete, true); assert.equal(result.unreadable, 2); assert.equal(result.data[0].path, 'C-readable.md');
});

test('backlinks resolve Markdown relative paths without claiming ambiguous wiki links', t => {
  const f = fixture(t); f.write('A/Target.md', '# Target'); f.write('B/Target.md', '# Other'); f.write('Source.md', '[[Target]]'); f.write('A/Source.md', '[[Target]]'); f.write('C/Source.md', '[known](../A/Target.md)');
  const result = f.run({ action: 'backlinks', path: 'A/Target.md' });
  assert.deepEqual(result.data.map(value => value.path), ['A/Source.md', 'C/Source.md']);
  const outgoing = f.run({ action: 'links', path: 'Source.md' }); assert.equal(outgoing.data[0].path, null); assert.equal(outgoing.data[0].candidates.length, 2);
});

test('large directories stay bounded and explicitly report incomplete coverage', t => {
  const f = fixture(t); for (let index = 0; index < 5010; index++) f.write('note-' + index + '.md', '');
  const result = f.run({ action: 'list', limit: 100 });
  assert.equal(result.incomplete, true); assert.ok(result.total <= 5000); assert.equal(result.data.length, 100);
});
