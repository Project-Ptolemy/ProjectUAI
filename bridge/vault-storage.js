'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { TextDecoder } = require('node:util');
const { fail, guard, notePath } = require('./vault-paths');
const { revision } = require('./vault-notes');
const MAX_NOTE_BYTES = 1024 * 1024;
const decode = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });

function read(vault, relative) {
  const clean = notePath(relative), target = guard(vault, clean);
  const descriptor = fs.openSync(target, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0));
  try {
    const stat = fs.fstatSync(descriptor);
    if (!stat.isFile() || stat.nlink > 1) fail('Vault links and special files are unavailable.', 403);
    if (stat.size > MAX_NOTE_BYTES) fail('This note exceeds the 1 MiB limit.', 413);
    const bytes = Buffer.alloc(Math.min(MAX_NOTE_BYTES + 1, stat.size + 1));
    let count = 0, amount;
    do { amount = fs.readSync(descriptor, bytes, count, bytes.length - count, null); count += amount; } while (amount && count < bytes.length);
    if (count > MAX_NOTE_BYTES || count > stat.size) fail('This note changed while reading. Read it again.', 409);
    const current = fs.statSync(guard(vault, clean)), after = fs.fstatSync(descriptor);
    if (current.dev !== stat.dev || current.ino !== stat.ino || after.size !== stat.size || after.mtimeMs !== stat.mtimeMs || after.ctimeMs !== stat.ctimeMs) {
      fail('This note changed while reading. Read it again.', 409);
    }
    const result = bytes.subarray(0, count);
    let content;
    try { content = decode.decode(result); } catch { fail('This note is not valid UTF-8.', 422); }
    return { bytes: result, content, revision: revision(result), modifiedAt: stat.mtimeMs };
  } finally { fs.closeSync(descriptor); }
}
function write(vault, relative, content, expectedRevision, create) {
  if (vault.readOnly) fail('This vault is read-only. Enable editing in Obsidian Settings first.', 403);
  const clean = notePath(relative);
  if (typeof content !== 'string' || Buffer.byteLength(content) > MAX_NOTE_BYTES) fail('Note content must be at most 1 MiB.', 413);
  // JSON can carry unpaired UTF-16 surrogates; never silently replace user text.
  const bytes = Buffer.from(content, 'utf8');
  if (bytes.toString('utf8') !== content) fail('Note content contains an invalid Unicode character.');
  const target = guard(vault, clean, true);
  let before = null;
  try { before = read(vault, clean); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  if (create && before) fail('This note already exists. Read it before editing.', 409);
  if (!create && !before) fail('This note does not exist. Use create to add it.', 404);
  if (!create && (typeof expectedRevision !== 'string' || expectedRevision !== before.revision)) fail('This note changed. Read its current revision before editing.', 409);
  const parts = clean.split('/'); parts.pop();
  let folder = vault.root, relativeFolder = '';
  for (const part of parts) {
    relativeFolder = relativeFolder ? relativeFolder + '/' + part : part;
    folder = guard(vault, relativeFolder, true);
    try { fs.mkdirSync(folder); } catch (error) { if (error.code !== 'EEXIST') throw error; }
    guard(vault, relativeFolder);
  }
  const temporary = path.join(folder, '.uai-note-' + crypto.randomBytes(12).toString('hex') + '.tmp');
  let fd;
  try {
    fd = fs.openSync(temporary, 'wx', 0o600);
    fs.writeFileSync(fd, bytes); fs.fsyncSync(fd); fs.closeSync(fd); fd = undefined;
    guard(vault, clean, true);
    if (create) {
      // link is an atomic create-if-absent; the private temporary link is removed
      // before verification, leaving the note with a single link.
      try { fs.linkSync(temporary, target); } catch (error) { if (error.code === 'EEXIST') fail('This note was created elsewhere. Read it before editing.', 409); throw error; }
      fs.unlinkSync(temporary);
    } else {
      const latest = read(vault, clean);
      if (latest.revision !== before.revision) fail('This note changed while preparing the edit. Read it again.', 409);
      fs.chmodSync(temporary, fs.statSync(target).mode & 0o777);
      fs.renameSync(temporary, target);
    }
    const saved = read(vault, clean);
    if (!saved.bytes.equals(bytes)) fail('Note verification failed. Inspect this note before retrying.', 409);
    return { path: clean, bytes: bytes.length, revision: saved.revision, modifiedAt: saved.modifiedAt, created: !!create };
  } finally {
    if (fd !== undefined) fs.closeSync(fd);
    try { fs.unlinkSync(temporary); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
}
module.exports = { MAX_NOTE_BYTES, read, write };
