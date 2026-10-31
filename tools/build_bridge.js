#!/usr/bin/env node
'use strict';

// Deterministic, dependency-free assets for an official GitHub bridge release.
// Run only after manually auditing all bridge and web inputs. --check is read-only.
const fs = require('node:fs');
const path = require('node:path');
const RELEASE = require('../bridge/release');
const { ROOT_FILES, MANIFEST_NAME, PACKAGE_NAME, validPath, checkPackage, hash, json } = require('../bridge/updater');
const root = path.resolve(__dirname, '..'), bridge = path.join(root, 'bridge');
// Older installed updaters allow only the original root filenames. Inline
// these private CommonJS helpers, using ordinary source (no eval or extraction),
// while checkout/executor/desktop installations keep their separate modules.
function runtimeSource(name, directory = bridge) {
  const inline = new Set(['opencode', 'support', 'mcp', 'mcp-stdio', 'environment', 'kilo', 'kilo-tor', 'kilo-proxy', 'cline', 'vaults', 'vault-paths', 'vault-notes', 'vault-storage', 'vault-search', 'vault-errors']);
  function read(filename, parents = new Set()) {
    if (parents.has(filename)) throw Error('Circular embedded bridge helper');
    const active = new Set(parents); active.add(filename);
    const input = path.join(directory, filename);
    if (!fs.lstatSync(input).isFile()) throw Error('Unexpected bridge helper input: ' + filename);
    return fs.readFileSync(input, 'utf8').replace(/\r\n/g, '\n').replace(/require\('\.\/(opencode|support|mcp|mcp-stdio|environment|kilo|kilo-tor|kilo-proxy|cline|vaults|vault-paths|vault-notes|vault-storage|vault-search|vault-errors)'\)/g, (call, helper) => {
      if (!inline.has(helper)) return call;
      const source = read(helper + '.js', active).replace(/^#![^\n]*\n/, '');
      return '(() => {\nconst embedded = { exports: {} };\n(function(module, exports, require) {\n' + source +
        '\n})(embedded, embedded.exports, require);\nreturn embedded.exports;\n})()';
    });
  }
  return Buffer.from(read(name));
}

function main() {
  const names = [...ROOT_FILES];
  function walk(folder, prefix) {
    for (const entry of fs.readdirSync(folder, { withFileTypes: true })) {
      if (entry.isSymbolicLink()) throw Error('Do not bundle symbolic links');
      if (entry.isDirectory()) walk(path.join(folder, entry.name), prefix + entry.name + '/');
      else if (entry.isFile()) names.push(prefix + entry.name);
      else throw Error('Unexpected bridge build input');
    }
  }
  walk(path.join(bridge, 'web'), 'web/');
  const files = names.sort().map(name => {
    validPath(name);
    const source = path.join(bridge, name);
    if (!fs.lstatSync(source).isFile()) throw Error('Unexpected bridge build input: ' + name);
    let bytes = ROOT_FILES.includes(name) && name.endsWith('.js') ? runtimeSource(name) : fs.readFileSync(source);
    if (/\.(?:js|html|css|svg|txt|json)$/.test(name)) bytes = Buffer.from(bytes.toString('utf8').replace(/\r\n/g, '\n'));
    return { path: name, bytes: bytes.length, sha256: hash(bytes), data: bytes.toString('base64') };
  });
  const archive = json({ format: 'project-uai-bridge-package', schema: 1, version: RELEASE.version, files });
  const manifest = { format: 'project-uai-bridge-release', schema: 1, ...RELEASE,
    package: { name: PACKAGE_NAME, bytes: archive.length, sha256: hash(archive) } };
  checkPackage(archive, manifest);
  const outputs = [[MANIFEST_NAME, json(manifest)], [PACKAGE_NAME, archive]];
  if (process.argv.includes('--check')) {
    for (const [name, bytes] of outputs) {
      const target = path.join(root, 'dist', name);
      if (!fs.existsSync(target) || !fs.readFileSync(target).equals(bytes)) throw Error('Stale bridge release asset: dist/' + name);
    }
    process.stdout.write(`Bridge ${RELEASE.version} release assets are current (${files.length} files).\n`);
  } else {
    fs.mkdirSync(path.join(root, 'dist'), { recursive: true });
    for (const [name, bytes] of outputs) fs.writeFileSync(path.join(root, 'dist', name), bytes);
    process.stdout.write(`Built bridge ${RELEASE.version}: ${files.length} files, ${archive.length} package bytes.\nInspect both dist assets before verification.\n`);
  }
}
module.exports = { runtimeSource };
if (require.main === module) main();
