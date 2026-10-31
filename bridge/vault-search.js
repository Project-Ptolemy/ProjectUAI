'use strict';
const fs = require('node:fs');
const { guard, relativePath } = require('./vault-paths');
const { read } = require('./vault-storage');
const { metadata, resolveLink, linkIndex } = require('./vault-notes');
const MAX_ENTRIES = 5000, MAX_SCAN_BYTES = 16 * 1024 * 1024;

function scan(vault, folder = '') {
  const prefix = relativePath(folder, true), notes = [], skipped = [];
  let visited = 0, incomplete = false;
  function walk(relative, depth) {
    if (depth > 20 || visited >= MAX_ENTRIES) { incomplete = true; return; }
    let entries = [];
    try {
      const directory = fs.opendirSync(guard(vault, relative));
      try {
        let entry;
        while ((entry = directory.readSync())) {
          if (++visited > MAX_ENTRIES) { incomplete = true; break; }
          entries.push(entry);
        }
      } finally { directory.closeSync(); }
      entries.sort((a, b) => a.name.localeCompare(b.name));
    }
    catch { incomplete = true; if (skipped.length < 20) skipped.push(relative || '(vault root)'); return; }
    for (const entry of entries) {
      if (entry.name.startsWith('.')) continue;
      const name = relative ? relative + '/' + entry.name : entry.name;
      if (entry.isSymbolicLink()) { incomplete = true; if (skipped.length < 20) skipped.push(name); continue; }
      try {
        guard(vault, name);
        if (entry.isDirectory()) walk(name, depth + 1);
        else if (entry.isFile() && /\.md$/i.test(entry.name)) {
          const stat = fs.statSync(guard(vault, name));
          notes.push({ path: name, bytes: stat.size, modifiedAt: stat.mtimeMs });
        }
      } catch { incomplete = true; if (skipped.length < 20) skipped.push(name); }
    }
  }
  walk(prefix, 0);
  notes.sort((a, b) => a.path.localeCompare(b.path));
  return { notes, incomplete, skipped, visited };
}
function paginate(values, offset = 1, limit = 50) {
  if (!Number.isInteger(offset) || offset < 1 || !Number.isInteger(limit) || limit < 1 || limit > 100) throw Object.assign(Error('Use a positive offset and a limit between 1 and 100.'), { status: 400 });
  const end = Math.min(values.length, offset - 1 + limit);
  return { data: values.slice(offset - 1, end), offset, nextOffset: end < values.length ? end + 1 : null, total: values.length };
}
function query(vault, input) {
  if (typeof input.query !== 'string' || !input.query.trim() || input.query.length > 300) throw Object.assign(Error('Search query must contain 1 to 300 characters.'), { status: 400 });
  const catalogue = scan(vault, input.folder), results = [], needle = input.query.toLowerCase();
  let scannedBytes = 0, unreadable = 0;
  for (const note of catalogue.notes) {
    if (note.bytes > 1024 * 1024) { unreadable++; catalogue.incomplete = true; continue; }
    if (scannedBytes + note.bytes > MAX_SCAN_BYTES) { catalogue.incomplete = true; break; }
    scannedBytes += note.bytes;
    let document;
    try { document = read(vault, note.path); } catch { unreadable++; catalogue.incomplete = true; continue; }
    const lines = document.content.split(/\r?\n/), matches = [];
    for (let index = 0; index < lines.length && matches.length < 3; index++) {
      const at = lines[index].toLowerCase().indexOf(needle);
      if (at >= 0) matches.push({ line: index + 1, excerpt: lines[index].slice(Math.max(0, at - 80), at + needle.length + 160) });
    }
    if (note.path.toLowerCase().includes(needle) || matches.length) results.push({ path: note.path, revision: document.revision, matches });
  }
  return { ...paginate(results, input.offset, input.limit), incomplete: catalogue.incomplete, skipped: catalogue.skipped, unreadable, scannedBytes };
}
function backlinks(vault, input) {
  const catalogue = scan(vault), paths = linkIndex(catalogue.notes.map(note => note.path)), results = [];
  let scannedBytes = 0;
  for (const note of catalogue.notes) {
    if (note.bytes > 1024 * 1024) { catalogue.incomplete = true; continue; }
    if (scannedBytes + note.bytes > MAX_SCAN_BYTES) { catalogue.incomplete = true; break; }
    scannedBytes += note.bytes;
    try {
      const document = read(vault, note.path), info = metadata(document.content, note.path);
      if (info.limited.links) catalogue.incomplete = true;
      const links = info.links.filter(link => resolveLink(link.target, note.path, paths).path === input.path);
      if (links.length) results.push({ path: note.path, title: info.title, links });
    } catch { catalogue.incomplete = true; }
  }
  return { ...paginate(results, input.offset, input.limit), incomplete: catalogue.incomplete, skipped: catalogue.skipped, scannedBytes };
}
module.exports = { MAX_ENTRIES, MAX_SCAN_BYTES, scan, paginate, query, backlinks };
