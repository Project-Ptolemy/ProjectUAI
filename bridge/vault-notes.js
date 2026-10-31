'use strict';
const crypto = require('node:crypto');
const path = require('node:path');

const revision = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
function metadata(text, notePath) {
  const lines = text.replace(/^\uFEFF/, '').split(/\r?\n/);
  let frontmatter = '', start = 0, frontmatterLimited = false;
  if (lines[0] === '---') {
    const end = lines.findIndex((line, index) => index > 0 && (line === '---' || line === '...'));
    if (end > 0) { frontmatter = lines.slice(1, Math.min(end, 201)).join('\n'); start = end + 1; frontmatterLimited = end > 200; }
  }
  const properties = Object.create(null);
  for (const line of frontmatter.split('\n')) {
    const match = line.match(/^([\w-]+):\s*(.*)$/);
    if (!match || Object.keys(properties).length >= 40) continue;
    const value = match[2].trim();
    if (/^(true|false)$/i.test(value)) properties[match[1]] = value.toLowerCase() === 'true';
    else if (/^-?\d+(?:\.\d+)?$/.test(value) && Number.isFinite(Number(value))) properties[match[1]] = Number(value);
    else if (!/^[>|&*!{]/.test(value)) properties[match[1]] = value.replace(/^(["'])(.*)\1$/, '$2').slice(0, 500);
  }
  const links = [], tags = new Set(), headings = [], limited = { links: false, headings: false, tags: false, frontmatter: frontmatterLimited || frontmatter.length > 12000 };
  let fence = null, title = '';
  for (let index = start; index < lines.length; index++) {
    const line = lines[index], fenced = line.match(/^\s{0,3}(`{3,}|~{3,})/);
    if (fenced) { if (!fence) fence = fenced[1]; else if (fenced[1][0] === fence[0] && fenced[1].length >= fence.length) fence = null; continue; }
    if (fence) continue;
    const heading = line.match(/^\s{0,3}(#{1,6})\s+(.+?)\s*#*$/);
    if (heading) {
      if (headings.length < 100) headings.push({ level: heading[1].length, text: heading[2].slice(0, 300), line: index + 1 });
      else limited.headings = true;
      if (!title && heading[1].length === 1) title = heading[2];
    }
    const prose = line.replace(/`+[^`]*`+/g, '');
    for (const match of prose.matchAll(/(!?)\[\[([^\]\n]{1,500})\]\]/g)) {
      if (links.length >= 200) { limited.links = true; break; }
      const [target, alias] = match[2].split('|'), [file, anchor] = target.split('#');
      links.push({ target: file.trim(), anchor: anchor || '', alias: alias || '', embed: match[1] === '!', line: index + 1, style: 'wiki' });
    }
    for (const match of prose.matchAll(/(!?)\[([^\]\n]*)\]\(([^\s)]+)(?:\s+"[^"]*")?\)/g)) {
      if (/^[a-z][a-z0-9+.-]*:|^\/\//i.test(match[3])) continue;
      if (links.length >= 200) { limited.links = true; break; }
      let target; try { target = decodeURIComponent(match[3]); } catch { target = match[3]; }
      const [file, anchor] = target.split('#');
      links.push({ target: file, anchor: anchor || '', alias: match[2], embed: match[1] === '!', line: index + 1, style: 'markdown' });
    }
    for (const match of prose.matchAll(/(?:^|\s)#([\p{L}\p{N}_/-]+)/gu)) {
      if (tags.size < 100 || tags.has(match[1])) tags.add(match[1]); else limited.tags = true;
    }
  }
  return { title: (typeof properties.title === 'string' && properties.title || title || notePath.split('/').pop().replace(/\.md$/i, '')).slice(0, 300),
    frontmatter: frontmatter.slice(0, 12000), properties, headings, links, tags: [...tags].sort(), limited };
}
function slice(bytes, offset = 1, limit = 6000) {
  if (!Number.isInteger(offset) || offset < 1 || offset > bytes.length + 1) throw Object.assign(Error('Read offset is outside this note.'), { status: 400 });
  if (!Number.isInteger(limit) || limit < 4 || limit > 12000) throw Object.assign(Error('Read limit must be between 4 and 12000 bytes.'), { status: 400 });
  let start = offset - 1;
  if (start < bytes.length && (bytes[start] & 0xc0) === 0x80) throw Object.assign(Error('Read offset splits a UTF-8 character; use nextOffset.'), { status: 400 });
  let end = Math.min(bytes.length, start + limit);
  while (end < bytes.length && end > start && (bytes[end] & 0xc0) === 0x80) end--;
  return { content: bytes.subarray(start, end).toString('utf8'), offset, nextOffset: end < bytes.length ? end + 1 : null, eof: end === bytes.length };
}
function linkIndex(paths) {
  const exact = new Set(paths), folded = new Map(), basenames = new Map();
  for (const value of paths) {
    const lower = value.toLowerCase(), basename = value.split('/').pop().replace(/\.md$/i, '').toLowerCase();
    for (const [map, key] of [[folded, lower], [basenames, basename]]) { if (!map.has(key)) map.set(key, []); map.get(key).push(value); }
  }
  return { exact, folded, basenames };
}
function resolved(candidates) {
  const shown = []; let bytes = 0;
  for (const candidate of candidates) {
    const size = Buffer.byteLength(candidate);
    if (shown.length >= 25 || bytes + size > 8000) break;
    shown.push(candidate); bytes += size;
  }
  return { path: candidates.length === 1 ? candidates[0] : null, candidates: shown, candidateCount: candidates.length, candidatesLimited: shown.length < candidates.length };
}
function resolveLink(target, source, paths) {
  if (!target) return resolved([source]);
  const index = Array.isArray(paths) ? linkIndex(paths) : paths;
  const clean = target.replace(/\.md$/i, '').replace(/^\/+/, '');
  const sourceFolder = source.includes('/') ? source.slice(0, source.lastIndexOf('/') + 1) : '';
  for (const candidate of [path.posix.normalize(sourceFolder + clean + '.md'), path.posix.normalize(clean + '.md')]) {
    if (index.exact.has(candidate)) return resolved([candidate]);
    const candidates = index.folded.get(candidate.toLowerCase());
    if (candidates) return resolved(candidates);
  }
  return resolved(clean.includes('/') ? [] : index.basenames.get(clean.toLowerCase()) || []);
}
module.exports = { revision, metadata, slice, linkIndex, resolveLink };
