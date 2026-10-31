'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createVaults } = require('../../vaults');

function fixture(t, options = {}) {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'uai-vault-test-'));
  const root = path.join(temporary, 'notes'), configFile = path.join(temporary, 'config', 'vaults.json');
  fs.mkdirSync(root);
  t.after(() => {
    if (path.dirname(temporary) !== path.resolve(os.tmpdir()) || !path.basename(temporary).startsWith('uai-vault-test-')) throw Error('Unsafe fixture cleanup path');
    fs.rmSync(temporary, { recursive: true, force: true });
  });
  const vaults = createVaults({ configFile });
  const id = vaults.configure({ action: 'connect', name: 'Fixture', root, readOnly: options.readOnly ?? false }).connectedId;
  const write = (name, content) => { const target = path.join(root, name); fs.mkdirSync(path.dirname(target), { recursive: true }); fs.writeFileSync(target, content); return target; };
  return { temporary, root, configFile, vaults, id, write, run: input => vaults.run({ vault: id, ...input }) };
}

module.exports = { fixture };
