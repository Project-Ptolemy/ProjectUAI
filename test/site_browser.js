// Focused public-site behavior checks. Use an external Playwright installation:
// PLAYWRIGHT_MODULE=/path/to/playwright node test/site_browser.js
// UAI_SCREENSHOTS optionally saves responsive and fallback review images.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

const root = path.resolve(__dirname, '..');
const version = JSON.parse(fs.readFileSync(path.join(root, 'dist/uai.manifest.json'), 'utf8')).buildId.split('-')[0];
// Public download versions are independent of future source-tree candidates.
const publishedDesktopVersion = '3.8.0';
const relayVersion = fs.readFileSync(path.join(root, 'companion/app/build.gradle.kts'), 'utf8').match(/\bversionName\s*=\s*"(\d+\.\d+\.\d+)"/)?.[1];
assert.ok(relayVersion, 'relay release version is declared');
const downloadAssets = new Map([
  ['UAI-Bridge-' + publishedDesktopVersion + '-win-x64.exe', publishedDesktopVersion],
  ['UAI-Relay-' + relayVersion + '.apk', relayVersion],
]);
const loader = 'loadstring(game:HttpGet("https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/main/dist/uai.lua"))()';
const mime = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.svg': 'image/svg+xml',
  '.png': 'image/png', '.ico': 'image/x-icon', '.mp4': 'video/mp4', '.webm': 'video/webm' };

async function serve() {
  const server = http.createServer((request, response) => {
    try {
      const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
      const file = path.resolve(root, '.' + (pathname.endsWith('/') ? pathname + 'index.html' : pathname));
      if (!file.startsWith(root + path.sep) || !fs.statSync(file).isFile()) throw new Error('missing');
      response.writeHead(200, { 'content-type': mime[path.extname(file)] || 'application/octet-stream',
        'content-length': fs.statSync(file).size, 'cache-control': 'no-store' });
      if (request.method === 'HEAD') response.end();
      else fs.createReadStream(file).on('error', () => response.destroy()).pipe(response);
    } catch { response.writeHead(404); response.end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return { server, origin: 'http://127.0.0.1:' + server.address().port };
}

async function screenshot(page, name) {
  if (!process.env.UAI_SCREENSHOTS) return;
  fs.mkdirSync(process.env.UAI_SCREENSHOTS, { recursive: true });
  await page.screenshot({ path: path.join(process.env.UAI_SCREENSHOTS, 'site-' + name + '.png'), animations: 'disabled' });
}

async function geometry(page, label) {
  const overflow = await page.evaluate(() => {
    const width = document.documentElement.clientWidth;
    return { width, scroll: document.documentElement.scrollWidth,
      controls: [...document.querySelectorAll('main input, main select, main button, #mobileMenuToggle')]
        .filter(node => node.getClientRects().length && !node.closest('[hidden]'))
        .map(node => ({ id: node.id || node.textContent.trim(), rect: node.getBoundingClientRect().toJSON() }))
        .filter(({ rect }) => rect.width > 0 && (rect.left < -1 || rect.right > width + 1)) };
  });
  assert.ok(overflow.scroll <= overflow.width + 1, label + ': page overflows horizontally: ' + JSON.stringify(overflow));
  assert.deepEqual(overflow.controls, [], label + ': a control extends beyond the viewport');
}

async function menu(page) {
  const toggle = page.locator('#mobileMenuToggle');
  const nav = page.locator('#siteNav');
  await toggle.focus(); await page.keyboard.press('Enter');
  assert.equal(await toggle.getAttribute('aria-expanded'), 'true');
  assert.equal(await nav.isVisible(), true);
  if (!await nav.evaluate(node => node.contains(document.activeElement))) await page.keyboard.press('Tab');
  assert.equal(await nav.evaluate(node => node.contains(document.activeElement)), true, 'keyboard opening reaches a navigation link');
  await page.keyboard.press('Escape');
  assert.equal(await nav.isVisible(), false);
  assert.equal(await toggle.evaluate(node => node === document.activeElement), true, 'Escape returns focus to menu toggle');
  await toggle.click();
  await nav.locator('a[href="#tools"]').click();
  assert.equal(await toggle.getAttribute('aria-expanded'), 'false', 'choosing a destination closes mobile navigation');
  await page.setViewportSize({ width: 1440, height: 900 });
  assert.equal(await nav.isVisible(), true);
  await nav.locator('a').first().focus();
  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForFunction(() => document.activeElement === document.querySelector('#mobileMenuToggle'));
  assert.equal(await nav.isVisible(), false, 'resize never leaves keyboard focus inside hidden navigation');
}

async function catalog(page) {
  const search = page.locator('#toolSearch');
  const clear = page.locator('#clearFilters');
  const rows = page.locator('[data-tool-name]');
  const total = await rows.count();
  const initialOpen = await page.locator('.tool-group').evaluateAll(nodes => nodes.filter(node => node.open).map(node => node.dataset.group));
  await search.fill('raycast');
  await page.waitForFunction(() => document.querySelector('#catalogStatus').textContent.includes(' of '));
  assert.equal(await page.locator('[data-tool-name="raycast"]').isVisible(), true, 'search exposes its matching disclosure');
  assert.equal(await page.locator('[data-tool-name="ray_target"]').isVisible(), true, 'search also matches tool descriptions');
  const matches = await page.locator('[data-tool-name]:not([hidden])').count();
  assert.ok(matches > 0 && matches < total, 'search narrows the catalog');
  assert.match(await page.locator('#catalogStatus').textContent(), new RegExp(matches + ' of ' + total + ' tools'));
  await search.fill('no-such-uai-tool-7291');
  await page.locator('#catalogEmpty').waitFor({ state: 'visible' });
  await clear.click();
  assert.equal(await search.inputValue(), '');
  assert.equal(await search.evaluate(node => node === document.activeElement), true, 'clear returns focus to search');
  assert.equal(await page.locator('[data-tool-name]:not([hidden])').count(), total);
  assert.deepEqual(await page.locator('.tool-group').evaluateAll(nodes => nodes.filter(node => node.open).map(node => node.dataset.group)), initialOpen, 'clearing search restores browsing disclosure state');
  await page.locator('#toolCategory').selectOption('fs');
  assert.equal(await page.locator('.tool-group:not([hidden])').count(), 1);
  assert.equal(await page.locator('.tool-group:not([hidden])').getAttribute('data-group'), 'fs');
  assert.equal(await page.locator('[data-tool-name="file_read_many"]').isVisible(), true);
  await page.locator('#riskFilters [data-risk="read"]').click();
  assert.equal(await page.locator('[data-tool-name]:not([hidden]) .risk-write').count(), 0);
  assert.equal(await page.locator('[data-tool-name]:not([hidden]) .risk-danger').count(), 0);
  await clear.click();
  assert.equal(await page.locator('#toolCategory').inputValue(), '');
  assert.equal(await clear.isDisabled(), true);
  await page.locator('#catalogExpandAll').click();
  assert.equal(await page.locator('.tool-group:not([open])').count(), 0);
  await geometry(page, 'expanded catalog at 390px');
  await screenshot(page, 'catalog-390');
  await page.locator('#catalogCollapseAll').click();
  assert.equal(await page.locator('.tool-group[open]').count(), 0);
  await page.locator('#mainContent').focus(); await page.keyboard.press('/');
  assert.equal(await search.evaluate(node => node === document.activeElement), true);
  await search.fill('files'); await page.keyboard.press('Escape');
  assert.equal(await search.inputValue(), '', 'Escape clears search');
  await page.locator('#toolCategory').selectOption('fs');
  await page.locator('#riskFilters [data-risk="read"]').click();
  await search.fill('read');
  await page.waitForFunction(() => new URL(location.href).searchParams.get('toolQuery') === 'read');
  await page.locator('#catalogShare summary').click();
  await page.locator('#copyCatalogLink').click();
  const shared = new URL(await page.evaluate(() => navigator.clipboard.readText()));
  assert.equal(shared.searchParams.get('toolQuery'), 'read');
  assert.equal(shared.searchParams.get('toolGroup'), 'fs');
  assert.equal(shared.searchParams.get('toolRisk'), 'read');
  assert.equal(shared.hash, '#tools');
  await clear.click();
  await page.goto(shared.href);
  assert.equal(await search.inputValue(), 'read', 'shared links restore search');
  assert.equal(await page.locator('#toolCategory').inputValue(), 'fs', 'shared links restore category');
  assert.equal(await page.locator('#riskFilters [data-risk="read"]').getAttribute('aria-pressed'), 'true');
  assert.equal(await page.locator('[data-tool-name="file_read_many"]').isVisible(), true);
  await clear.click();
  assert.equal(new URL(page.url()).search, '', 'clearing filters removes only the catalog parameters');
  const invalid = new URL(page.url());
  invalid.search = '?toolGroup=unknown&toolRisk=invalid&ref=kept';
  await page.goto(invalid.href);
  assert.equal(await page.locator('#toolCategory').inputValue(), '');
  assert.equal(await page.locator('#riskAll').getAttribute('aria-pressed'), 'true');
  assert.equal(new URL(page.url()).search, '?ref=kept', 'invalid filters are ignored and unrelated URL state is preserved');
  assert.equal(new URL(await page.locator('#catalogLink').textContent()).search, '', 'shared links omit unrelated query parameters');
}

async function copyAndDownloads(page) {
  await page.locator('#copyLoadstringBtn').click();
  assert.equal((await page.evaluate(() => navigator.clipboard.readText())).trim(), loader, 'clipboard contains the exact production loader');
  assert.match(await page.locator('#copyStatus').textContent(), /Loader copied/);
  await page.evaluate(() => Object.defineProperty(navigator, 'clipboard', { configurable: true,
    value: { writeText: async () => { throw new Error('Fixture clipboard denial'); } } }));
  await page.locator('#copyLoadstringBtn').click();
  await page.waitForFunction(() => document.querySelector('#copyLoadstringBtn').dataset.state === 'manual');
  assert.equal(await page.evaluate(() => getSelection().toString()), loader, 'clipboard denial selects the exact text for manual copy');
  assert.match(await page.locator('#copyStatus').textContent(), /selected|manually/i);

  const links = await page.locator('a[href*="/releases/"]').evaluateAll(nodes => nodes.map(node => ({ href: node.href, name: node.textContent.trim(),
    card: node.closest('.download-card')?.textContent || '' })));
  assert.ok(links.length, 'official release links are present');
  for (const link of links) {
    const url = new URL(link.href);
    assert.equal(url.origin, 'https://github.com');
    assert.ok(url.pathname.startsWith('/Project-Ptolemy/ProjectUAI/releases/'), 'download stays in the official repository');
    if (/\/releases\/tag\//.test(url.pathname)) assert.equal(url.pathname.split('/')[5], 'v' + version, 'release link matches the published client version');
    if (/\/releases\/download\//.test(url.pathname)) {
      const asset = url.pathname.split('/').at(-1);
      assert.ok(downloadAssets.has(asset), 'download names a verified published desktop or relay asset');
      assert.equal(url.pathname.split('/')[5], 'v' + downloadAssets.get(asset), 'download tag matches its component release version');
      assert.ok(link.card.includes('v' + downloadAssets.get(asset)), 'download card labels the actual published asset version');
    }
    assert.ok(link.name, 'download links have accessible text');
  }
  for (const asset of downloadAssets.keys()) {
    assert.ok(links.some(link => new URL(link.href).pathname.endsWith('/' + asset)), 'current download is present: ' + asset);
  }
  await geometry(page, 'downloads at 390px');
  await screenshot(page, 'loader-390');
}

function instrumentCanvas() {
  window.__siteDraws = 0;
  const clear = CanvasRenderingContext2D.prototype.clearRect;
  CanvasRenderingContext2D.prototype.clearRect = function (...args) {
    if (this.canvas.id === 'heroCanvas') window.__siteDraws++;
    return clear.apply(this, args);
  };
}

async function stillCanvas(page, label) {
  await page.waitForTimeout(120);
  const before = await page.evaluate(() => window.__siteDraws);
  await page.waitForTimeout(250);
  assert.equal(await page.evaluate(() => window.__siteDraws), before, label);
}

(async () => {
  const { server, origin } = await serve();
  let browser;
  const errors = [];
  try {
    browser = await chromium.launch({ headless: true });
    async function context(options = {}) {
      const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, reducedMotion: 'reduce', ...options });
      // All interaction checks are offline; remote downloads are inspected, never fetched.
      await ctx.route('**/*', route => new URL(route.request().url()).origin === origin ? route.continue() : route.abort());
      ctx.on('page', page => page.on('pageerror', error => errors.push(error.message)));
      return ctx;
    }
    const interactive = await context({ permissions: ['clipboard-read', 'clipboard-write'] });
    await interactive.addInitScript(instrumentCanvas);
    const page = await interactive.newPage(); page.setDefaultTimeout(10000);
    await page.goto(origin); await page.evaluate(() => document.fonts.ready);
    assert.equal(await page.locator('#motionToggle').getAttribute('aria-pressed'), 'true', 'reduced motion starts paused');
    await stillCanvas(page, 'reduced motion avoids a continuous canvas loop');
    assert.equal(await page.evaluate(() => document.getAnimations().filter(animation => animation.playState === 'running' && animation.effect.getTiming().iterations === Infinity).length), 0, 'reduced motion stops continuous SVG/CSS animation');
    for (const width of [320, 390, 768, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      await page.evaluate(() => scrollTo(0, 0));
      await geometry(page, width + 'px');
      await screenshot(page, String(width));
    }
    await page.setViewportSize({ width: 390, height: 844 });
    await menu(page);
    await catalog(page);
    await copyAndDownloads(page);
    const tabs = page.locator('#demoTabs [role="tab"]');
    await tabs.first().focus(); await page.keyboard.press('End');
    assert.equal(await tabs.last().getAttribute('aria-selected'), 'true');
    const lastPanel = await tabs.last().getAttribute('aria-controls');
    assert.equal(await page.locator('#' + lastPanel).isVisible(), true);
    await page.keyboard.press('Home');
    assert.equal(await tabs.first().getAttribute('aria-selected'), 'true', 'example tabs remain keyboard operable');
    console.log('PASS responsive layout, menu/focus, catalog, loader copy/fallback, downloads and example tabs');

    const motionContext = await context({ reducedMotion: 'no-preference', viewport: { width: 1440, height: 900 } });
    await motionContext.addInitScript(instrumentCanvas);
    const motion = await motionContext.newPage();
    await motion.goto(origin);
    await motion.waitForFunction(() => window.__siteDraws > 2);
    await motion.locator('#motionToggle').click();
    assert.equal(await motion.locator('#motionToggle').getAttribute('aria-pressed'), 'true');
    await stillCanvas(motion, 'Pause motion stops canvas work');
    await motion.locator('#motionToggle').click();
    const stopped = await motion.evaluate(() => window.__siteDraws);
    await motion.waitForFunction(count => window.__siteDraws > count, stopped);
    await motion.locator('#quickstart').scrollIntoViewIfNeeded();
    // Smooth scrolling and observer delivery may continue after the scroll request.
    // Establish the actual offscreen state before measuring stopped animation.
    await motion.waitForFunction(() => document.getElementById('heroStage').getBoundingClientRect().bottom <= 0);
    await motion.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    await stillCanvas(motion, 'offscreen hero stops canvas work');
    console.log('PASS canvas animation, pause/resume, offscreen lifecycle and reduced motion');

    const fallbackContext = await context();
    await fallbackContext.addInitScript(() => {
      const getContext = HTMLCanvasElement.prototype.getContext;
      HTMLCanvasElement.prototype.getContext = function (...args) {
        return this.id === 'heroCanvas' ? null : getContext.apply(this, args);
      };
    });
    const fallback = await fallbackContext.newPage(); await fallback.goto(origin);
    assert.equal(await fallback.locator('#heroFallback').isVisible(), true, 'SVG remains available when Canvas2D is unavailable');
    assert.equal(await fallback.locator('#heroFallback').evaluate(node => getComputedStyle(node).opacity), '1');
    assert.equal(await fallback.locator('#loadstringCode').textContent(), loader);
    assert.equal(await fallback.locator('#copyLoadstringBtn').isVisible(), true, 'canvas failure does not interrupt page controls');
    await screenshot(fallback, 'canvas-fallback');

    const plainContext = await context({ javaScriptEnabled: false });
    const plain = await plainContext.newPage(); await plain.goto(origin);
    assert.equal(await plain.locator('h1').isVisible(), true);
    assert.equal(await plain.locator('#siteNav').isVisible(), true, 'navigation is available without JavaScript');
    assert.equal(await plain.locator('#loadstringCode').textContent(), loader);
    assert.equal(await plain.locator('#copyLoadstringBtn').isVisible(), false, 'inactive copy control is hidden without JavaScript');
    assert.equal(await plain.locator('#heroFallback').isVisible(), true);
    const closed = plain.locator('.tool-group:not([open])').first();
    const tool = await closed.locator('[data-tool-name]').first().getAttribute('data-tool-name');
    await closed.locator('summary').click();
    assert.equal(await plain.locator('[data-tool-name="' + tool + '"]').isVisible(), true, 'native catalog disclosures work without JavaScript');
    await geometry(plain, 'JavaScript disabled at 390px');
    await plain.evaluate(() => scrollTo(0, 0)); await screenshot(plain, 'no-js');
    console.log('PASS canvas fallback and JavaScript-disabled content/navigation/catalog');
    assert.deepEqual(errors, [], 'no uncaught browser errors');
    console.log('Public site browser checks passed (Chromium; local fixtures, no download network verification).');
  } finally {
    if (browser) await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
