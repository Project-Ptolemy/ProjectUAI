'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { metadata, resolveLink } = require('../vault-notes');

test('note metadata reads simple frontmatter, headings, tags and prose links without evaluating YAML', () => {
  const text = '---\ntitle: "Title"\nactive: true\ncount: 4\n__proto__: harmless\nunsafe: !execute anything\n---\n# Heading\n[[Other#Section|Label]] ![[Image.png]] [relative](../Note.md#Anchor) #研究/tag\n```md\n[[Ignored]] #ignored\n```\n`[[Inline ignored]]`';
  const value = metadata(text, 'Folder/Name.md');
  assert.equal(value.title, 'Title'); assert.equal(value.properties.active, true); assert.equal(value.properties.count, 4);
  assert.equal(value.properties.__proto__, 'harmless'); assert.equal(value.properties.unsafe, undefined);
  assert.equal(value.links.length, 3); assert.equal(value.links[0].anchor, 'Section'); assert.equal(value.links[1].embed, true); assert.equal(value.links[2].style, 'markdown');
  assert.deepEqual(value.tags, ['研究/tag']); assert.equal(value.headings[0].line, 8);
});

test('link resolution favors exact local paths and reports ambiguous basenames', () => {
  const paths = ['Folder/Note.md', 'Note.md', 'A/Topic.md', 'B/Topic.md', 'Case.md', 'case.md'];
  assert.equal(resolveLink('Note', 'Folder/Source.md', paths).path, 'Folder/Note.md');
  assert.equal(resolveLink('../Note', 'Folder/Source.md', paths).path, 'Note.md');
  assert.equal(resolveLink('', 'Folder/Source.md', paths).path, 'Folder/Source.md');
  assert.equal(resolveLink('Topic', 'Source.md', paths).path, null);
  assert.equal(resolveLink('CASE', 'Source.md', paths).candidates.length, 2);
  assert.equal(resolveLink('Case', 'Source.md', paths).path, 'Case.md');
  assert.deepEqual(resolveLink('../../private', 'Source.md', paths).candidates, []);
});

test('bounded metadata exposes omissions instead of reporting a complete graph', () => {
  const value = metadata(Array.from({ length: 205 }, (_, index) => '# H' + index + '\n[[Note' + index + ']] #tag' + index).join('\n'), 'Large.md');
  assert.equal(value.links.length, 200); assert.equal(value.headings.length, 100); assert.equal(value.tags.length, 100);
  assert.deepEqual(value.limited, { links: true, headings: true, tags: true, frontmatter: false });
});

test('ambiguous link results bound candidate payloads while retaining the full count', () => {
  const paths = Array.from({ length: 100 }, (_, index) => 'Folder' + index + '/Topic.md');
  const value = resolveLink('Topic', 'Source.md', paths);
  assert.equal(value.path, null); assert.equal(value.candidateCount, 100); assert.equal(value.candidates.length, 25); assert.equal(value.candidatesLimited, true);
});

test('long frontmatter is explicitly limited and does not manufacture body links', () => {
  const value = metadata('---\n' + 'property: [[not a body link]]\n'.repeat(210) + '---\n# Body', 'Note.md');
  assert.equal(value.limited.frontmatter, true); assert.equal(value.links.length, 0); assert.equal(value.title, 'Body');
});
