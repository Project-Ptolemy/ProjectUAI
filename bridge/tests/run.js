#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { root } = require('./helpers/bridge');
const args = process.argv.slice(2);
// General regression fixtures never start a user's authenticated Cline profile.
// Cline's focused fixtures inject their own isolated process and account state.
process.env.UAI_CLINE_DISABLED = '1';
const skipImages = args.includes('--skip-images');
const imageSuites = new Set(['picture-store.test.js', 'pictures.test.js', 'vision.test.js', 'browser-revamp.js', 'browser-ui-audit.js']);
if (skipImages) delete process.env.UAI_SCREENSHOTS;
const included = name => {
  if (skipImages && imageSuites.has(name)) { process.stdout.write('SKIP ' + name + ' (--skip-images)\n'); return false; }
  return true;
};
if (process.env.UAI_SCREENSHOTS) fs.mkdirSync(process.env.UAI_SCREENSHOTS, { recursive: true });
function run(files, test = false) {
  const result = spawnSync(process.execPath, [...(test ? ['--test'] : []), ...files], { cwd: root, stdio: 'inherit', env: process.env });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status || 1);
}
if (!args.includes('--browser-only')) run(fs.readdirSync(__dirname).filter(name => name.endsWith('.test.js') && included(name)).sort().map(name => path.join(__dirname, name)), true);
if (args.includes('--browser') || args.includes('--browser-only')) {
  for (const name of ['browser.js', 'browser-workflows.js', 'browser-revamp.js', 'browser-ui-audit.js', 'browser-visual-rework.js', 'browser-desktop-redesign.js', 'browser-tool-cards.js', 'browser-response-layout.js', 'browser-queue.js', 'browser-tunnels.js', 'browser-model-lifecycle.js', 'browser-vaults.js'].filter(included)) run([path.join(__dirname, name)]);
}
