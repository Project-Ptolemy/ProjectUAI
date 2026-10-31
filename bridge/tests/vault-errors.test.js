'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { publicError } = require('../vault-errors');

test('filesystem errors never return absolute paths or raw exception text', () => {
  for (const code of ['ENOENT', 'EPERM', 'ENOSPC', 'UNKNOWN']) {
    const result = publicError(Object.assign(Error('secret C:/Users/private/Vault/note.md'), { code }));
    assert.doesNotMatch(result.error, /private|secret|C:\//); assert.ok(result.status >= 400);
  }
  assert.deepEqual(publicError(Object.assign(Error('This note changed.'), { status: 409 })), { status: 409, error: 'This note changed.' });
});
