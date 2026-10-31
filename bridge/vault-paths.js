'use strict';
const fs = require('node:fs');
const path = require('node:path');

function fail(message, status = 400) { throw Object.assign(Error(message), { status }); }
function relativePath(value, allowEmpty = false) {
  if (allowEmpty && (value === undefined || value === '')) return '';
  if (typeof value !== 'string' || !value || Buffer.byteLength(value) > 1024 || value.includes('\\') || path.isAbsolute(value)) fail('Use a vault-relative path with forward slashes.');
  if (Buffer.from(value, 'utf8').toString('utf8') !== value) fail('Vault paths must contain valid Unicode.');
  const parts = value.split('/');
  for (const part of parts) {
    if (!part || part === '.' || part === '..' || /[<>:"|?*\x00-\x1f\x7f]/.test(part) || /[. ]$/.test(part) ||
        /^(con|prn|aux|nul|conin\$|conout\$|com[1-9¹²³]|lpt[1-9¹²³])(?:\.|$)/i.test(part) || part.startsWith('.')) fail('This vault path contains an unsupported or hidden component.');
  }
  return parts.join('/');
}
function notePath(value) {
  const relative = relativePath(value);
  if (!/\.md$/i.test(relative)) fail('Obsidian note paths must end in .md.');
  return relative;
}
function openRoot(value) {
  if (typeof value !== 'string' || !path.isAbsolute(value) || value.length > 2048) fail('Choose an existing absolute vault folder.');
  const supplied = path.resolve(value), stat = fs.lstatSync(supplied);
  if (!stat.isDirectory() || stat.isSymbolicLink()) fail('Choose a regular vault folder, not a symbolic link.');
  const root = fs.realpathSync(supplied);
  return { root, dev: stat.dev, ino: stat.ino };
}
function guard(vault, relative, allowMissing = false) {
  const identity = fs.lstatSync(vault.root);
  if (!identity.isDirectory() || identity.isSymbolicLink() || identity.dev !== vault.dev || identity.ino !== vault.ino) fail('The vault folder changed. Reconnect it in Settings.', 409);
  const clean = relativePath(relative, true);
  let current = vault.root;
  const parts = clean ? clean.split('/') : [];
  for (let index = 0; index < parts.length; index++) {
    current = path.join(current, parts[index]);
    let stat;
    try { stat = fs.lstatSync(current); }
    catch (error) { if (allowMissing && error.code === 'ENOENT') continue; throw error; }
    if (stat.isSymbolicLink() || (!stat.isDirectory() && (!stat.isFile() || stat.nlink > 1))) fail('Vault links and special files are unavailable.', 403);
    if (index < parts.length - 1 && !stat.isDirectory()) fail('A parent path is not a folder.');
  }
  const target = path.resolve(vault.root, clean);
  const within = path.relative(vault.root, target);
  if (within === '..' || within.startsWith('..' + path.sep) || path.isAbsolute(within)) fail('Path leaves this vault.', 403);
  return target;
}
module.exports = { fail, relativePath, notePath, openRoot, guard };
