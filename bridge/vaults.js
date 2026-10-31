'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const { fail, openRoot, guard, notePath } = require('./vault-paths');
const storage = require('./vault-storage');
const notes = require('./vault-notes');
const search = require('./vault-search');

function createVaults(options = {}) {
  const configFile = options.configFile || process.env.UAI_VAULT_CONFIG || path.join(os.homedir(), '.project-uai', 'vaults.json');
  let entries = [], loaded = false, loadError = null, configRevision = null;
  function load() {
    if (loaded) return; loaded = true;
    try {
      const stat = fs.lstatSync(configFile);
      if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 65536) fail('Vault configuration is not a regular bounded file.');
      const bytes = fs.readFileSync(configFile);
      if (bytes.length > 65536) fail('Vault configuration exceeds its size limit.');
      const value = JSON.parse(bytes.toString('utf8'));
      if (!value || value.schema !== 1 || !Array.isArray(value.vaults) || value.vaults.length > 16) fail('Unsupported vault configuration.');
      const ids = new Set(), names = new Set();
      entries = value.vaults.map(entry => {
        if (!entry || !/^[a-z0-9_-]{1,80}$/i.test(entry.id || '') || typeof entry.name !== 'string' || !entry.name.trim() || entry.name.length > 80 ||
            typeof entry.root !== 'string' || !path.isAbsolute(entry.root) || typeof entry.readOnly !== 'boolean' || ids.has(entry.id) || names.has(entry.name.toLowerCase())) fail('Invalid vault configuration.');
        ids.add(entry.id); names.add(entry.name.toLowerCase());
        return { id: entry.id, name: entry.name, root: entry.root, readOnly: entry.readOnly };
      });
      configRevision = notes.revision(bytes);
    } catch (error) { if (error.code !== 'ENOENT') loadError = 'Could not read vault configuration. Repair or move vaults.json before changing vault connections.'; }
  }
  function persist(next) {
    if (loadError) fail(loadError, 409);
    const folder = path.dirname(configFile);
    fs.mkdirSync(folder, { recursive: true });
    const directory = fs.lstatSync(folder);
    if (!directory.isDirectory() || directory.isSymbolicLink()) fail('Vault configuration folder must be a regular folder.');
    let currentRevision = null;
    try {
      const existing = fs.lstatSync(configFile);
      if (!existing.isFile() || existing.isSymbolicLink() || existing.size > 65536) fail('Vault configuration must be a regular bounded file.');
      currentRevision = notes.revision(fs.readFileSync(configFile));
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
    if (currentRevision !== configRevision) fail('Vault connections changed in another bridge. Restart this bridge before changing them.', 409);
    const data = JSON.stringify({ schema: 1, vaults: next }, null, 2) + '\n';
    const temporary = path.join(folder, '.vaults-' + crypto.randomBytes(12).toString('hex') + '.tmp');
    try {
      fs.writeFileSync(temporary, data, { flag: 'wx', mode: 0o600 });
      fs.renameSync(temporary, configFile);
      if (fs.readFileSync(configFile, 'utf8') !== data) fail('Vault configuration verification failed. Reload Settings before retrying.', 409);
      entries = next; configRevision = notes.revision(Buffer.from(data));
    } finally { try { fs.unlinkSync(temporary); } catch (error) { if (error.code !== 'ENOENT') throw error; } }
  }
  function get(id) {
    load(); if (loadError) fail(loadError, 409);
    const entry = entries.find(candidate => candidate.id === id);
    if (!entry) fail('Unknown vault. Connect one in Settings > Obsidian.', 404);
    return { ...entry, ...openRoot(entry.root) };
  }
  function list(includeRoots = false) {
    load();
    return { vaults: entries.map(entry => {
      let available = true, obsidian = false;
      try { const root = openRoot(entry.root); obsidian = fs.existsSync(path.join(root.root, '.obsidian')); }
      catch { available = false; }
      return { id: entry.id, name: entry.name, readOnly: entry.readOnly, available, obsidian, ...(includeRoots ? { root: entry.root } : {}) };
    }), error: loadError };
  }
  function configure(input) {
    load(); if (loadError) fail(loadError, 409);
    if (!input || typeof input !== 'object' || Array.isArray(input)) fail('Expected a vault connection object.');
    if (input.action === 'remove') {
      if (!entries.some(entry => entry.id === input.id)) fail('Unknown vault.', 404);
      persist(entries.filter(entry => entry.id !== input.id));
      return list(true);
    }
    if (input.action === 'policy') {
      if (!entries.some(entry => entry.id === input.id)) fail('Unknown vault.', 404);
      if (typeof input.readOnly !== 'boolean') fail('readOnly must be true or false.');
      persist(entries.map(entry => entry.id === input.id ? { ...entry, readOnly: input.readOnly } : entry));
      return list(true);
    }
    if (input.action !== 'connect') fail('Choose connect, policy or remove.');
    if (typeof input.name !== 'string' || !input.name.trim() || input.name.trim().length > 80 || /[\x00-\x1f]/.test(input.name)) fail('Vault name must contain 1 to 80 readable characters.');
    if (input.readOnly !== undefined && typeof input.readOnly !== 'boolean') fail('readOnly must be true or false.');
    const name = input.name.trim();
    let prior;
    if (input.id !== undefined) { prior = entries.find(entry => entry.id === input.id); if (!prior) fail('Unknown vault connection.', 404); }
    if (!prior && entries.length >= 16) fail('Connect at most 16 vaults.');
    if (entries.some(entry => entry.id !== prior?.id && entry.name.toLowerCase() === name.toLowerCase())) fail('Choose a unique vault name.');
    const opened = openRoot(input.root);
    if (entries.some(entry => entry.id !== prior?.id && path.resolve(entry.root).toLowerCase() === opened.root.toLowerCase())) fail('This folder is already connected. Edit its existing connection.');
    const entry = { id: prior?.id || 'vault_' + crypto.randomBytes(8).toString('hex'), name, root: opened.root, readOnly: input.readOnly !== false };
    persist(prior ? entries.map(candidate => candidate.id === prior.id ? entry : candidate) : [...entries, entry]);
    return { ...list(true), connectedId: entry.id };
  }
  function run(input) {
    if (!input || typeof input !== 'object' || Array.isArray(input)) fail('Expected a vault operation object.');
    if (input.action === 'vaults') return list();
    const vault = get(input.vault);
    if (input.action === 'list') {
      const result = search.scan(vault, input.folder);
      return { ...search.paginate(result.notes, input.offset, input.limit), incomplete: result.incomplete, skipped: result.skipped };
    }
    if (input.action === 'search') return search.query(vault, input);
    if (input.action === 'read') {
      const clean = notePath(input.path), document = storage.read(vault, clean);
      if (input.revision !== undefined && input.revision !== document.revision) fail('This note changed between pages. Read it again from offset 1.', 409);
      return { path: clean, bytes: document.bytes.length, revision: document.revision, modifiedAt: document.modifiedAt,
        ...notes.slice(document.bytes, input.offset, input.limit), ...(input.metadata === false ? {} : { metadata: notes.metadata(document.content, clean) }) };
    }
    if (input.action === 'create' || input.action === 'update') return storage.write(vault, input.path, input.content, input.revision, input.action === 'create');
    if (input.action === 'append') {
      const clean = notePath(input.path), document = storage.read(vault, clean);
      if (typeof input.content !== 'string') fail('Append content must be text.');
      if (input.revision !== document.revision) fail('This note changed. Read its current revision before appending.', 409);
      return storage.write(vault, clean, document.content + input.content, input.revision, false);
    }
    if (input.action === 'links') {
      const clean = notePath(input.path), document = storage.read(vault, clean), info = notes.metadata(document.content, clean), catalogue = search.scan(vault);
      const paths = notes.linkIndex(catalogue.notes.map(note => note.path));
      return { ...search.paginate(info.links.map(link => ({ ...link, ...notes.resolveLink(link.target, clean, paths) })), input.offset, input.limit),
        revision: document.revision, incomplete: catalogue.incomplete || info.limited.links };
    }
    if (input.action === 'backlinks') { guard(vault, notePath(input.path)); return search.backlinks(vault, input); }
    fail('Unknown vault operation.');
  }
  return { list, configure, run, capability: () => ({ schema: 1, available: true, configured: list().vaults.length, readLimit: storage.MAX_NOTE_BYTES, configError: !!loadError }) };
}
module.exports = { createVaults };
