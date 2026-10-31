// Real local bridge and Chromium; never uses a personal vault or provider.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const { fixture } = require('./helpers/vault');
const { startBridge } = require('./helpers/bridge');

(async () => {
  const cleanup = [], t = { after: fn => cleanup.push(fn) }, f = fixture(t, { readOnly: true });
  f.write('Folder/Note.md', '# My note\nOriginal'); f.write('Other.md', 'Searchable needle');
  fs.unlinkSync(f.configFile);
  let browser;
  try {
    const bridge = await startBridge(t, [], 'bridge/server.js', { UAI_VAULT_CONFIG: f.configFile });
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({ viewport: { width: 390, height: 844 }, reducedMotion: 'reduce', permissions: ['clipboard-read', 'clipboard-write'] });
    const page = await context.newPage(); page.setDefaultTimeout(12000);
    const errors = []; page.on('pageerror', error => errors.push(error.message));
    await page.goto(bridge.base + '/?settings=obsidian#t=' + bridge.token);
    const panel = page.locator('#settings-obsidian'); await panel.waitFor({ state: 'visible' });
    await page.waitForFunction(() => document.querySelector('#settings-obsidian').getAttribute('aria-busy') === 'false');
    await panel.locator('.vault-setup summary').click();
    await panel.getByRole('textbox', { name: 'Vault name', exact: true }).fill('Fixture');
    await panel.getByRole('textbox', { name: 'Folder on bridge computer', exact: true }).fill(f.root);
    await panel.getByRole('button', { name: 'Connect vault', exact: true }).click();
    await panel.locator('.vault-note').first().waitFor();
    assert.equal(await panel.getByRole('button', { name: 'New note', exact: true }).isDisabled(), true);
    await panel.getByRole('button', { name: 'Enable editing', exact: true }).click();
    await page.waitForFunction(() => document.querySelector('#settings-obsidian').getAttribute('aria-busy') === 'false');
    await panel.locator('.vault-note').filter({ hasText: 'Folder/Note.md' }).click();
    const editor = panel.getByRole('textbox', { name: 'Note Markdown', exact: true }); await editor.waitFor({ state: 'visible' });
    await editor.fill('# Updated\nUnicode 界🙂'); await panel.getByRole('button', { name: 'Save note', exact: true }).click();
    await page.waitForFunction(() => document.querySelector('.vault-status').textContent.includes('saved and verified'));
    assert.equal(fs.readFileSync(path.join(f.root, 'Folder/Note.md'), 'utf8'), '# Updated\nUnicode 界🙂');
    f.write('Folder/Note.md', '# External edit');
    await editor.fill('# Kept draft'); await panel.getByRole('button', { name: 'Save note', exact: true }).click();
    await page.waitForFunction(() => document.querySelector('.vault-status').textContent.includes('changed'));
    assert.equal(await editor.inputValue(), '# Kept draft'); assert.equal(await panel.getByRole('button', { name: 'Save note', exact: true }).isDisabled(), true);
    assert.equal(fs.readFileSync(path.join(f.root, 'Folder/Note.md'), 'utf8'), '# External edit');
    await panel.getByRole('button', { name: 'Copy note', exact: true }).click(); assert.equal(await page.evaluate(() => navigator.clipboard.readText()), '# Kept draft');
    page.once('dialog', dialog => dialog.dismiss()); await page.locator('#modalClose').click(); assert.equal(await page.locator('#modal').evaluate(node => node.open), true);
    page.once('dialog', dialog => dialog.accept()); await panel.getByRole('button', { name: 'Reload note', exact: true }).click();
    await page.waitForFunction(() => document.querySelector('.vault-note-text').value === '# External edit');
    const search = panel.getByRole('searchbox', { name: 'Search notes', exact: true }); await search.fill('needle'); await panel.getByRole('button', { name: 'Search', exact: true }).click();
    await page.waitForFunction(() => document.querySelectorAll('.vault-note').length === 1); assert.match(await panel.locator('.vault-note').textContent(), /Other.md/);
    for (const size of [{ width: 320, height: 480 }, { width: 1440, height: 960 }]) {
      await page.setViewportSize(size); const bounds = await panel.evaluate(node => ({ width: node.clientWidth, scroll: node.scrollWidth }));
      assert.ok(bounds.scroll <= bounds.width + 1, 'Obsidian fits viewport: ' + JSON.stringify(bounds));
      assert.ok(await editor.evaluate(node => node.getBoundingClientRect().height >= 220), 'Editor retains a useful minimum height within shared modal styles');
      const tab = await page.locator('#settings-tab-obsidian').evaluate(node => {
        const box = node.getBoundingClientRect(), parent = node.parentElement.getBoundingClientRect(); return { left: box.left, right: box.right, parentLeft: parent.left, parentRight: parent.right };
      });
      assert.ok(tab.left >= tab.parentLeft && tab.right <= tab.parentRight, 'Active Settings tab is fully visible');
      if (process.env.UAI_SCREENSHOTS) {
        fs.mkdirSync(process.env.UAI_SCREENSHOTS, { recursive: true });
        await panel.locator('.vault-connection').first().scrollIntoViewIfNeeded();
        await page.screenshot({ path: path.join(process.env.UAI_SCREENSHOTS, 'obsidian-connections-' + size.width + '.png'), animations: 'disabled' });
        await editor.scrollIntoViewIfNeeded();
        await page.screenshot({ path: path.join(process.env.UAI_SCREENSHOTS, 'obsidian-editor-' + size.width + '.png'), animations: 'disabled' });
      }
    }
    assert.deepEqual(errors, []); process.stdout.write('Obsidian browser: configuration, notes, conflicts, draft protection and responsive layout passed.\n');
  } finally { await browser?.close(); for (const close of cleanup.reverse()) await close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
