// Response composition, activity disclosure and approvals in a real browser.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const { startBridge } = require('./helpers/bridge');

(async () => {
  const bridge = await startBridge();
  let browser, heartbeat, sequence = 0;
  const state = {
    protocol: 2, runtime: 'web', sessionId: 'response-layout', player: 'David', place: { name: 'Studio garden' },
    agent: { busy: false, status: 'Ready', model: 'Claude Sonnet 4.5', provider: 'Anthropic' },
    threads: [{ id: 'response-layout', title: 'A little room to create', active: true }],
    providers: [{ id: 'fixture', label: 'Anthropic', model: 'Claude Sonnet 4.5', enabled: true, models: ['Claude Sonnet 4.5'] }],
    activeProvider: 'fixture', permissions: { mode: 'ask' }, tools: [], todos: [], loops: [], logs: [], requests: [],
    subagents: [], questions: [], pendingPermissions: [], settings: { ui: { fontScale: 1, transcriptWidth: 'medium' }, agent: {} },
  };
  const push = async extra => {
    const response = await fetch(bridge.base + '/api/agent/events', { method: 'POST',
      headers: { Authorization: 'Bearer ' + bridge.token, 'content-type': 'application/json' },
      body: JSON.stringify({ batchId: 'response-' + (++sequence), state, ...extra }) });
    assert.ok(response.ok, 'response fixture is accepted');
  };
  const event = (kind, fields = {}) => ({ kind, sessionId: state.sessionId, ...fields });
  try {
    await push({ sessionId: state.sessionId, snapshot: [] });
    heartbeat = setInterval(() => push().catch(() => {}), 5000);
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, reducedMotion: 'reduce', permissions: ['clipboard-read', 'clipboard-write'] });
    const page = await context.newPage(); page.setDefaultTimeout(12000);
    const errors = []; page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
    const screenshot = async name => {
      if (!process.env.UAI_SCREENSHOTS) return;
      fs.mkdirSync(process.env.UAI_SCREENSHOTS, { recursive: true });
      await page.screenshot({ path: path.join(process.env.UAI_SCREENSHOTS, 'response-' + name + '.png'), animations: 'disabled' });
    };
    await page.goto(bridge.base + '/#t=' + bridge.token); await page.locator('#app').waitFor({ state: 'visible' });
    await page.evaluate(() => document.fonts.ready);
    const introduction = 'I’ll look at the garden’s layout and lighting, then put together a small, practical plan.';
    const reasoning = '### Understand the space\n\nStart with the existing **paths, scale, and lighting**. Keep the walking route accessible and use the planting bed as the boundary for seating.\n\n### Keep the changes practical\n\n- Check the space beside the path before placing a bench.\n- Use one warm light instead of several competing lights.\n- Preserve the fountain and the main walking route.\n\nThe recommendation should be small enough to try without rebuilding the garden.';
    const answer = '## A quieter corner\n\nThe garden already has a lovely foundation. Keep the **stone path open** and use the planting bed to frame a small place to sit.\n\n### Three changes that work together\n\n1. **Add a low bench** beside the path, facing the garden.\n2. **Soften the edges** with a little planting around the seating.\n3. **Use one warm light** near the bench to make the space inviting.\n\nThe fountain and the main walking route can stay where they are.';
    state.agent.busy = true;
    await push({ events: [event('user', { text: 'Help me make a quieter corner in this garden.' }), event('turn:start'),
      event('assistant:text', { requestId: 'intro', text: introduction }),
      event('assistant:reasoning', { requestId: 'plan', text: reasoning }),
      event('tool:call', { id: 'inspect', name: 'inspect_workspace', arguments: '{"path":"workspace.Garden"}' }),
    ] });
    const response = page.locator('.response-turn').first(), drawer = response.locator('.response-activity');
    await response.locator('.activity-title').waitFor();
    assert.equal(await page.locator('.response-turn').count(), 1);
    assert.equal(await response.locator('.response-heading').count(), 1, 'one identity covers every step in the turn');
    assert.equal(await drawer.getAttribute('open'), null);
    assert.equal(await response.locator('.tool-call').isVisible(), false);
    assert.equal(await response.locator('.thinking').isVisible(), false);
    await push({ events: [event('tool:progress', { id: 'inspect', name: 'inspect_workspace', text: 'Checking paths and seating areas' })] });
    await page.waitForFunction(() => document.querySelector('.activity-current').textContent === 'Checking paths and seating areas');
    assert.equal(await drawer.getAttribute('open'), null, 'progress updates never force activity open');
    // An approval is deliberately outside the disclosure, even while activity is closed.
    state.pendingPermissions = [{ id: 'permit', name: 'file_write', sessionId: state.sessionId, args: { path: 'garden-plan.lua' } }];
    await push();
    await page.getByRole('button', { name: 'Allow', exact: true }).waitFor({ state: 'visible' });
    assert.equal(await page.locator('#questions').evaluate(node => !node.closest('.response-activity')), true);
    state.pendingPermissions = [];
    await push({ events: [event('tool:result', { id: 'inspect', name: 'inspect_workspace', ok: true, text: 'Found a clear stone path and a planting bed.', ms: 420 })] });
    const steps = [];
    for (let i = 0; i < 11; i++) steps.push(event('tool:call', { id: 'light-' + i, name: 'get_properties', arguments: JSON.stringify({ path: 'workspace.Garden.Light' + i }) }),
      event('tool:result', { id: 'light-' + i, name: 'get_properties', ok: true, text: 'Light inspected.', ms: 80 + i }));
    await push({ events: [...steps, event('assistant:text', { requestId: 'plan', text: answer }), event('turn:end')] });
    state.agent.busy = false; await push();
    await page.waitForFunction(() => document.querySelector('.activity-meta').textContent.includes('12 steps'));
    assert.equal(await page.locator('.response-turn').count(), 1, 'twelve tool steps still belong to one response');
    assert.equal(await response.locator('.response-content>.message.agent').count(), 2);
    assert.equal(await drawer.getAttribute('open'), null, 'completion keeps work details collapsed');
    assert.equal(await response.locator('.tool-call:visible').count(), 0);
    const bounds = await response.evaluate(node => ({ answer: node.querySelector('.response-content').getBoundingClientRect().bottom, activity: node.querySelector('.response-activity').getBoundingClientRect().top }));
    assert.ok(bounds.answer <= bounds.activity, 'the complete answer precedes activity');
    await response.getByRole('button', { name: 'Copy response', exact: true }).click();
    assert.equal((await page.evaluate(() => navigator.clipboard.readText())).replace(/\r\n/g, '\n'), introduction + '\n\n' + answer, 'Copy response includes all answer prose and excludes internal work');
    for (const theme of ['light', 'dark']) {
      await page.evaluate(value => UAI.theme.set(value), theme);
      await page.locator('#transcript').evaluate(node => { node.scrollTop = 0; });
      await screenshot('answer-' + theme);
    }
    await drawer.locator(':scope > summary').focus(); await page.keyboard.press('Enter');
    assert.equal(await drawer.getAttribute('open'), '', 'the activity drawer is keyboard operable');
    const thoughts = drawer.locator('.thinking');
    await thoughts.locator(':scope > summary').click();
    assert.equal(await thoughts.locator('.reasoning-body h3').count(), 2, 'reasoning retains its document hierarchy');
    assert.equal(await thoughts.locator('.reasoning-body li').count(), 3);
    assert.equal(await thoughts.locator('.thinking-state').textContent(), 'Complete');
    await thoughts.getByRole('button', { name: 'Copy reasoning', exact: true }).click();
    assert.equal((await page.evaluate(() => navigator.clipboard.readText())).replace(/\r\n/g, '\n'), reasoning, 'reasoning Copy retains exact Markdown after answer commitment');
    await screenshot('reasoning-expanded-dark');
    for (const width of [390, 320]) {
      await page.setViewportSize({ width, height: 844 });
      await thoughts.locator(':scope > summary').scrollIntoViewIfNeeded();
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
      await screenshot('reasoning-expanded-' + width + '-dark');
    }
    await page.setViewportSize({ width: 1440, height: 1000 });
    await thoughts.locator(':scope > summary').click();
    const firstCall = drawer.locator('.tool-call>.tool').first();
    await firstCall.locator(':scope > summary').click();
    await firstCall.locator('summary').filter({ hasText: /^Input$/ }).click();
    const field = firstCall.locator('.tool-fields dd');
    assert.equal(await field.textContent(), 'workspace.Garden');
    await push();
    assert.equal(await drawer.getAttribute('open'), '');
    assert.equal(await firstCall.getAttribute('open'), '', 'live state updates preserve nested disclosure choices');
    await screenshot('activity-expanded-dark');
    await drawer.locator(':scope > summary').click();
    for (const width of [390, 320]) {
      await page.setViewportSize({ width, height: 844 });
      for (const theme of ['light', 'dark']) {
        await page.evaluate(value => UAI.theme.set(value), theme);
        await page.locator('#transcript').evaluate(node => { node.scrollTop = 0; });
        const geometry = await response.evaluate(node => ({ width: node.getBoundingClientRect().width, scroll: node.scrollWidth, page: document.documentElement.scrollWidth, viewport: innerWidth }));
        assert.ok(geometry.scroll <= geometry.width + 1 && geometry.page <= geometry.viewport, 'response fits at ' + width + ': ' + JSON.stringify(geometry));
        await screenshot('answer-' + width + '-' + theme);
      }
    }
    // A separate failed turn remains readable without exposing its raw payload.
    await page.setViewportSize({ width: 1440, height: 1000 });
    await push({ events: [event('user', { text: 'Check the fountain too.' }), event('turn:start'),
      event('tool:call', { id: 'fountain', name: 'inspect_workspace', arguments: '{"path":"workspace.Garden.Fountain"}' }),
      event('tool:error', { id: 'fountain', name: 'inspect_workspace', text: 'The fountain was removed before inspection.' }),
      event('assistant:text', { requestId: 'fountain-answer', text: 'The fountain is no longer available in the workspace. Restore it and I can check it again.' }), event('turn:end')] });
    const failed = page.locator('.response-turn').nth(1);
    await failed.locator('.activity-current').waitFor();
    assert.match(await failed.locator('.activity-meta').textContent(), /1 failed/);
    assert.equal(await failed.locator('.activity-current').textContent(), 'The fountain was removed before inspection.');
    assert.equal(await failed.locator('.tool-call').isVisible(), false, 'failures are signposted without dumping tool cards');
    assert.equal(await response.locator('.tool-call').count(), 12, 'later turns cannot absorb earlier tool activity');
    await screenshot('failure-summary-dark');
    await page.emulateMedia({ forcedColors: 'active' });
    assert.equal(await failed.locator('.response-activity').evaluate(node => getComputedStyle(node).borderStyle), 'solid');
    await page.emulateMedia({ forcedColors: 'none' });

    const diagnostic = 'HTTP 429: ' + JSON.stringify({ error: { message: 'Too many requests', code: 'rate_limit', detail: 'Diagnostic context. '.repeat(80) } });
    let mutations = 0;
    page.on('request', request => { if (request.method() === 'POST' && /\/api\/(?:command|inference)(?:$|\/)/.test(request.url())) mutations++; });
    await push({ events: [event('error', { message: diagnostic, status: 429 })] });
    const rateError = page.locator('#transcript > .response-error').last();
    await rateError.locator('.error-title').waitFor();
    assert.equal(await rateError.locator('.error-title').textContent(), 'Request limit reached');
    assert.equal(await rateError.locator('.error-details').getAttribute('open'), null);
    assert.equal(await rateError.locator('pre').isVisible(), false, 'raw error data does not fill the conversation');
    await page.locator('#input').fill('Keep this unsent draft.');
    await rateError.getByRole('button', { name: 'Review message', exact: true }).click();
    assert.equal(await page.locator('#input').inputValue(), 'Keep this unsent draft.');
    assert.equal(mutations, 0, 'reviewing an error never resubmits inference or commands');
    await screenshot('error-summary-dark');
    await rateError.locator('.error-details > summary').click();
    await rateError.getByRole('button', { name: 'Copy Error details', exact: true }).click();
    assert.equal((await page.evaluate(() => navigator.clipboard.readText())).replace(/\r\n/g, '\n'), diagnostic, 'original diagnostics copy exactly');
    await screenshot('error-details-dark');
    for (const width of [390, 320]) {
      await page.setViewportSize({ width, height: 844 });
      await rateError.scrollIntoViewIfNeeded();
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false, 'technical errors wrap at ' + width);
      await screenshot('error-details-' + width + '-dark');
    }
    await page.setViewportSize({ width: 1440, height: 1000 });
    await push({ events: [event('error', { message: 'Relay rejected the request (400): invalid executorrequest. Inference was not resubmitted. (599)' })] });
    const relayError = page.locator('#transcript > .response-error').last();
    await relayError.getByRole('button', { name: 'Check connection', exact: true }).waitFor();
    assert.equal(await relayError.locator('.error-title').textContent(), 'Update UAI Relay to continue');
    assert.equal(await relayError.locator('.error-message').textContent(), 'Update the UAI Relay app and reload the UAI script. Keep your current pairing.');
    await relayError.getByRole('button', { name: 'Check connection', exact: true }).click();
    await page.locator('#workspaceModal').waitFor({ state: 'visible' });
    assert.equal(await page.locator('#workspaceTitle').textContent(), 'Connection');
    assert.equal(mutations, 0);
    await page.locator('#workspaceClose').click(); await page.locator('#workspaceModal').waitFor({ state: 'hidden' });
    await screenshot('relay-error-guidance-dark');
    const errorCases = [
      ['invalid executor request', 400, 'Update UAI Relay to continue', 'Check connection'],
      ['The companion could not read the executor request.', 400, 'Update UAI Relay to continue', 'Check connection'],
      ['Request encoding failed.', 401, 'Update UAI Relay to continue', 'Check connection'],
      ['invalid gzip request', 403, 'Update UAI Relay to continue', 'Check connection'],
      ['Relay token unauthorized.', 401, 'Check your bridge connection', 'Check connection'],
      ['Invalid token for relay.', 403, 'Check your bridge connection', 'Check connection'],
      ['HTTP 401: invalid API key', 401, 'Check your provider access', 'Open providers'],
      ['HTTP 429: RateLimit.FreeUsageLimitError: Free usage limit reached. Free models work in OpenCode (https://opencode.ai); subscribe to OpenCode Go to keep going: https://opencode.ai/go', 429, 'OpenCode free API access refused', 'Open providers'],
      ['HTTP 429: Free usage limit reached. Free models work in OpenCode (https://opencode.ai).', 429, 'OpenCode free API access refused', 'Open providers'],
    ];
    for (const [message, status, title, action] of errorCases) {
      const count = await page.locator('#transcript > .response-error').count();
      await push({ events: [event('error', { message, status })] });
      await page.waitForFunction(expected => document.querySelectorAll('#transcript > .response-error').length === expected, count + 1);
      const card = page.locator('#transcript > .response-error').last();
      assert.equal(await card.locator('.error-title').textContent(), title, message);
      assert.equal(await card.getByRole('button', { name: action, exact: true }).count(), 1);
      assert.equal(await card.locator('.error-details pre').textContent(), message, 'classification preserves the diagnostic');
      assert.equal(await card.locator('.error-details').getAttribute('open'), null);
      if (title === 'OpenCode free API access refused') {
        assert.match(await card.locator('.error-message').textContent(), /Desktop Bridge for API-key access/);
        assert.match(await card.locator('.error-message').textContent(), /installed OpenCode tunnel/);
        assert.match(await card.locator('.error-message').textContent(), /Changing keys may not restore access/);
        assert.doesNotMatch(await card.locator('.error-message').textContent(), /wait a moment/i);
      }
    }

    // Live history can outgrow a snapshot. Eviction must release moved reasoning
    // and active tool records while keeping a focused disclosure intact.
    await page.emulateMedia({ forcedColors: 'none' });
    await push({ events: [event('cleared'), event('user', { text: 'Inspect a large workspace.' }), event('turn:start'),
      event('assistant:reasoning', { requestId: 'evicted-answer', text: 'An old thought to evict with its answer.' }),
      event('assistant:text', { requestId: 'evicted-answer', text: 'Starting a large inspection.' }),
      event('tool:call', { id: 'evicted-tool', name: 'inspect_workspace', arguments: '{}' }),
      event('tool:call', { id: 'focused-tool', name: 'get_properties', arguments: '{}' })] });
    await page.getByText('Inspect a large workspace.', { exact: true }).waitFor({ state: 'visible' });
    await page.locator('.activity-summary').click();
    await page.locator('.tool-head').nth(1).focus();
    await page.evaluate(() => { window.retainedToolFocus = document.activeElement; });
    for (let batch = 0; batch < 5; batch++) {
      const history = [];
      for (let i = 0; i < 95; i++) {
        const id = batch * 95 + i;
        if (id < 90) history.push(event('assistant:text', { requestId: 'retained-' + id, text: 'Inspection update ' + id }));
        else history.push(event('tool:call', { id: 'retained-tool-' + id, name: 'get_properties', arguments: '{}' }),
          event('tool:result', { id: 'retained-tool-' + id, name: 'get_properties', ok: true, text: 'Inspected ' + id + '.' }));
      }
      await push({ events: history });
      await page.locator('.tool-outcome').filter({ hasText: new RegExp('^Inspected ' + (batch * 95 + 94) + '\\.$') }).waitFor({ state: 'attached', timeout: 30000 });
    }
    await page.waitForFunction(() => document.querySelectorAll('.message,.tool-call,.thinking,.activity-note,.subagent-report').length <= 450 && document.querySelectorAll('.tool-call').length > 350).catch(async error => {
      error.message += '\nRetention: ' + JSON.stringify(await page.evaluate(() => ({ total: document.querySelectorAll('.message,.tool-call,.thinking,.activity-note,.subagent-report').length,
        calls: document.querySelectorAll('.tool-call').length, focus: window.retainedToolFocus?.isConnected }))) + '\nPage errors: ' + JSON.stringify(errors);
      throw error;
    });
    assert.equal(await page.evaluate(() => window.retainedToolFocus.isConnected && document.activeElement === window.retainedToolFocus), true, 'retention preserves the focused old tool while evicting other entries');
    assert.equal(await page.locator('[data-request-id="evicted-answer"]').count(), 0);
    assert.equal(await page.locator('[data-reasoning-request-id="evicted-answer"]').count(), 0, 'reasoning is removed with an answer even after its renderer cache entry expired');
    await push({ events: [event('tool:progress', { id: 'evicted-tool', name: 'inspect_workspace', text: 'This evicted progress must not reappear.' }),
      event('tool:result', { id: 'evicted-tool', name: 'inspect_workspace', ok: false, text: 'Evicted result.' }),
      event('tool:result', { id: 'focused-tool', name: 'get_properties', ok: true, text: 'Focused call completed.' })] });
    await page.waitForFunction(() => window.retainedToolFocus.parentElement.dataset.status === 'done');
    assert.equal(await page.getByText('This evicted progress must not reappear.', { exact: true }).count(), 0);
    assert.deepEqual(errors, []);
    console.log('Response layout checks passed: grouped turns, quiet activity, approvals, exact Copy, keyboard disclosure, bounded focused retention, failures, forced colors and 320–1440px layouts.');
  } finally { clearInterval(heartbeat); await browser?.close(); await bridge.stop(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
