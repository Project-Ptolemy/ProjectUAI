// Synthetic event rates, live adoption and saved replay; no model requests.
'use strict';
const assert = require('node:assert/strict');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const { startBridge } = require('./helpers/bridge');
const { rateText } = require('../web/stream-renderer');

(async () => {
  assert.equal(rateText(60, 2000), '30.0 tk/s request avg');
  assert.equal(rateText(1, 100000), '<0.1 tk/s request avg');
  assert.equal(rateText(1e12, 1), '1e+15 tk/s request avg');
  assert.equal(rateText(1e6, 1000), '1e+6 tk/s request avg');
  assert.equal(rateText(1234567, 1000), '1.23e+6 tk/s request avg');
  assert.equal(rateText(1200000, 1000), '1.2e+6 tk/s request avg');
  for (const value of [undefined, null, -1, 0.5, '60', Infinity, NaN]) assert.equal(rateText(value, 2000), null);
  for (const value of [undefined, null, 0, -1, '2000', Infinity, NaN]) assert.equal(rateText(60, value), null);
  const bridge = await startBridge(); let browser, sequence = 0;
  const headers = { Authorization: 'Bearer ' + bridge.token, 'content-type': 'application/json' };
  const sessionId = 'rate-browser-fixture';
  const state = { protocol: 2, runtime: 'web', sessionId, player: 'Fixture',
    agent: { status: 'Ready', busy: false, model: 'fixture-model', provider: 'Fixture' },
    providers: [], threads: [], usage: { total: 0 }, settings: { agent: {}, ui: {} },
    permissions: { mode: 'ask' }, pendingPermissions: [], questions: [], tools: [], logs: [], requests: [] };
  const publish = async (events, snapshot) => {
    const response = await fetch(bridge.base + '/api/agent/events', { method: 'POST', headers,
      body: JSON.stringify({ batchId: 'rate-' + (++sequence), sessionId, state, events: events || [], ...(snapshot ? { snapshot } : {}) }) });
    assert.ok(response.ok);
  };
  try {
    await publish();
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage({ viewport: { width: 1280, height: 900 }, reducedMotion: 'reduce' });
    const errors = []; page.on('pageerror', error => errors.push(error.message));
    await page.goto(bridge.base + '/#t=' + bridge.token);
    await page.locator('#app').waitFor({ state: 'visible' });
    const completed = { kind: 'assistant:text', text: 'Measured final reply', model: 'fixture-model', streamId: 'measured', outputTokens: 120, requestMs: 4000 };
    await publish([{ kind: 'user', text: 'Measure the reply' }]);
    await page.locator('#input').fill('Keep my draft');
    await publish([{ kind: 'assistant:reasoning', text: 'Reasoning before the final answer', model: 'fixture-model', streamId: 'measured' }]);
    await page.locator('.thinking .reasoning-body').waitFor({ state: 'attached' });
    assert.equal(await page.locator('.message-token-rate').count(), 0, 'Reasoning preview does not invent a speed');
    await page.evaluate(() => { window.retainedRateMessage = document.querySelector('.message.agent'); });
    await publish([completed]);
    await page.locator('.message-token-rate').waitFor({ state: 'visible' });
    assert.equal(await page.locator('.message-token-rate').textContent(), '30.0 tk/s request avg');
    assert.match(await page.locator('.message-token-rate').getAttribute('title'), /including waiting and transport/);
    assert.equal(await page.evaluate(() => document.querySelector('.message.agent') === window.retainedRateMessage), true, 'The completed reply adopts the existing message');
    assert.equal(await page.locator('#input').inputValue(), 'Keep my draft', 'Painting the rate preserves the composer');
    await publish([{ kind: 'assistant:text', text: 'Legacy reply without measured usage', streamId: 'legacy' }]);
    await page.waitForFunction(() => document.querySelectorAll('.message.agent').length === 2);
    assert.equal(await page.locator('.message-token-rate').count(), 1, 'A legacy reply has no fabricated rate');
    await page.evaluate(() => { window.beforeRateSnapshot = document.querySelector('.message.agent'); });
    await publish([], [{ kind: 'user', text: 'Measure the reply' }, completed, { kind: 'assistant:text', text: 'Legacy reply without measured usage', streamId: 'legacy' }]);
    await page.waitForFunction(() => !window.beforeRateSnapshot.isConnected && document.querySelectorAll('.message.agent').length === 2 && document.querySelectorAll('.message-token-rate').length === 1);
    assert.equal(await page.locator('.message-token-rate').textContent(), '30.0 tk/s request avg', 'Snapshot replay preserves measured metadata');
    await publish([{ kind: 'assistant:text', text: 'Extreme measured reply', streamId: 'extreme', outputTokens: 1e12, requestMs: 1 }]);
    await page.waitForFunction(() => document.querySelectorAll('.message-token-rate').length === 2);
    assert.equal(await page.locator('.message-token-rate').last().textContent(), '1e+15 tk/s request avg');
    for (const width of [320, 390]) {
      await page.setViewportSize({ width, height: 844 });
      await page.locator('.message-token-rate').last().scrollIntoViewIfNeeded();
      assert.equal(await page.locator('.message-token-rate').last().isVisible(), true, 'The counter remains readable at ' + width + 'px');
      const counters = await page.locator('.message-token-rate').evaluateAll(nodes => nodes.map(node => {
        const box = node.getBoundingClientRect(), range = document.createRange(); range.selectNodeContents(node);
        const text = range.getBoundingClientRect();
        return { label: node.textContent, fits: node.scrollWidth <= node.clientWidth + 1 && node.scrollHeight <= node.clientHeight + 1
          && text.left >= box.left - 1 && text.right <= box.right + 1 && text.top >= box.top - 1 && text.bottom <= box.bottom + 1 };
      }));
      assert.deepEqual(counters.map(counter => counter.label), ['30.0 tk/s request avg', '1e+15 tk/s request avg']);
      assert.equal(counters.every(counter => counter.fits), true, 'Every counter includes its units without clipping at ' + width + 'px');
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), true, 'The counter does not widen the viewport');
    }
    assert.deepEqual(errors, []);
    process.stdout.write('Browser response token rate: measured averages, adoption and replay checks passed\n');
  } finally { await browser?.close(); await bridge.stop(); }
})().catch(error => { process.stderr.write(error.stack + '\n'); process.exitCode = 1; });
