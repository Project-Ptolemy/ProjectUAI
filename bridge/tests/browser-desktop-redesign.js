// Focused desktop redesign checks: settings preserve the conversation and edits,
// free metadata remains accurate, and harness setup produces usable private config.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const { startBridge } = require('./helpers/bridge');
const { navigation } = require('./helpers/browser-ui');

(async () => {
  const bridge = await startBridge();
  let browser, heartbeat, sequence = 0;
  const auth = { Authorization: 'Bearer ' + bridge.token, 'content-type': 'application/json' };
  const state = {
    protocol: 2, runtime: 'web', sessionId: 'redesign', player: 'David', place: { name: 'Studio garden' },
    agent: { busy: false, status: 'Ready', model: 'deepseek-v4.1-flash-free', provider: 'OpenCode' },
    threads: [{ id: 'redesign', title: 'A little room to create', active: true }],
    providers: [{ id: 'opencode', label: 'OpenCode', model: 'deepseek-v4.1-flash-free', enabled: true,
      models: ['deepseek-v4.1-flash-free', 'big-pickle', 'paid-model'], freeModels: ['deepseek-v4.1-flash-free', 'big-pickle'],
      modelInfo: { 'deepseek-v4.1-flash-free': { contextWindow: 131072, maxOutputTokens: 16384, reasoning: true, efforts: ['off', 'low', 'high'], effectiveEffort: 'high', effortSource: 'documented', temperatureAllowed: false, temperatureSource: 'learned', temperatureOverride: 'auto' },
        'big-pickle': { contextWindow: 40960, maxOutputTokens: 4096, reasoning: false } } }],
    context: { sessionId: 'redesign', providerId: 'opencode', model: 'deepseek-v4.1-flash-free', usedTokens: 32768, windowTokens: 131072,
      systemTokens: 8192, messageTokens: 22528, summaryTokens: 2048, compactionTokens: 100000, estimated: true, partial: false, calibrated: true },
    activeProvider: 'opencode', permissions: { mode: 'ask' }, tools: [], todos: [], loops: [], logs: [], requests: [],
    subagents: [], questions: [], pendingPermissions: [], settings: { ui: { density: 'comfortable', fontScale: 1, transcriptWidth: 'medium' },
      agent: { effort: 'high', temperature: .4, autoFreeRouting: true, customInstructions: '', maxTurns: 24 }, logs: { enabled: true } },
  };
  const push = async extra => {
    const response = await fetch(bridge.base + '/api/agent/events', { method: 'POST', headers: auth,
      body: JSON.stringify({ batchId: 'redesign-' + (++sequence), state, ...extra }) });
    assert.ok(response.ok);
  };
  try {
    await push({ sessionId: 'redesign', snapshot: [] });
    heartbeat = setInterval(() => push().catch(() => {}), 5000);
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({ viewport: { width: 1440, height: 960 }, permissions: ['clipboard-read', 'clipboard-write'], reducedMotion: 'reduce' });
    const page = await context.newPage(); page.setDefaultTimeout(12000);
    const { navigate } = navigation(page);
    const errors = [], commands = []; let followupReceipt; page.on('pageerror', error => errors.push(error.message));
    await page.route('**/api/command', route => { const command = route.request().postDataJSON(); commands.push(command); return route.fulfill({ json: { id: command.commandId } }); });
    await page.route('**/api/commands/*', async route => { const id = route.request().url().split('/').at(-1), sent = commands.find(command => command.commandId === id); if (sent?.type === 'subagent:followup' && followupReceipt) await followupReceipt; return route.fulfill({ json: { state: 'completed', result: { ok: true, ...(sent?.type === 'send' ? { data: { messageId: id, queued: true } } : {}) } } }); });
    const screenshot = async name => {
      if (!process.env.UAI_SCREENSHOTS) return;
      fs.mkdirSync(process.env.UAI_SCREENSHOTS, { recursive: true });
      await page.screenshot({ path: path.join(process.env.UAI_SCREENSHOTS, name + '.png'), animations: 'disabled' });
    };
    const close = async () => {
      // dialog.close() hides immediately; focus restoration runs from its later close event.
      const settled = page.evaluate(() => new Promise(resolve => document.querySelector('#modal').addEventListener('close', () => queueMicrotask(resolve), { once: true })));
      await page.locator('#modalClose').click(); await settled;
      await page.locator('#modal').waitFor({ state: 'hidden' });
    };
    await page.goto(bridge.base + '/#t=' + bridge.token); await page.locator('#app').waitFor({ state: 'visible' });
    await page.locator('#modelButton.is-free').waitFor();
    await page.locator('#input').fill('Keep this draft exactly as it is.');
    await page.locator('#settingsButton').click();
    assert.equal(await page.locator('#chatPage').isVisible(), true, 'settings overlay keeps the active conversation mounted');
    assert.equal(await page.locator('body').getAttribute('data-page'), 'chat');
    await page.locator('#settings-tab-agent').click();
    const routing = page.locator('[data-setting="agent.autoFreeRouting"]');
    assert.equal(await routing.isChecked(), true);
    assert.match(await routing.locator('..').textContent(), /^Automatic free routing.*Project UAI Free.*Providers library.*HCNSEC uses its own connection and key.*provider Auto/s);
    assert.doesNotMatch(await routing.locator('..').textContent(), /included HCNSEC/);
    for (const enabled of [false, true]) {
      const routeSettingRequest = page.waitForRequest(request => request.url().endsWith('/api/command') && request.postDataJSON().path === 'agent.autoFreeRouting');
      await routing.setChecked(enabled); assert.equal((await routeSettingRequest).postDataJSON().value, enabled);
      state.settings.agent.autoFreeRouting = enabled; await push();
      await page.waitForFunction(() => document.querySelector('[data-setting="agent.autoFreeRouting"]').closest('.setting').dataset.state === 'saved');
    }
    const instructions = page.locator('[data-setting="agent.customInstructions"]');
    await instructions.fill('Unfinished instructions'); await instructions.evaluate(node => node.setSelectionRange(2, 12));
    state.settings.agent.customInstructions = 'Remote value'; await push();
    await page.waitForTimeout(250);
    assert.equal(await instructions.inputValue(), 'Unfinished instructions');
    assert.deepEqual(await instructions.evaluate(node => [node.selectionStart, node.selectionEnd]), [2, 12]);
    await page.locator('#settings-tab-general').click();
    for (const theme of ['light', 'dark']) {
      await page.locator('#settings-tab-general').click();
      await page.locator('.theme-choice[data-theme-choice="' + theme + '"]').click();
      for (const size of [{ width: 1440, height: 960 }, { width: 390, height: 844 }, { width: 320, height: 480 }, { width: 844, height: 390 }]) {
        await page.setViewportSize(size);
        for (const section of ['general', 'appearance', 'agent', 'mcp', 'advanced', 'data']) {
          await page.locator('#settings-tab-' + section).click();
          if (section === 'mcp') await page.locator('.mcp-config').waitFor();
          const bounds = await page.locator('#modal').evaluate(node => {
            const r = node.getBoundingClientRect(), content = node.querySelector('.settings-content');
            const close = document.querySelector('#modalClose').getBoundingClientRect(), footer = document.querySelector('#modalFooter').getBoundingClientRect();
            return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, overflow: node.scrollWidth > node.clientWidth + 1,
              contentWidth: content.clientWidth, contentScroll: content.scrollWidth, contentHeight: content.clientHeight, closeTop: close.top, footerBottom: footer.bottom };
          });
          assert.ok(bounds.left >= 0 && bounds.right <= size.width && bounds.top >= 0 && bounds.bottom <= size.height, JSON.stringify(bounds));
          assert.ok(!bounds.overflow && bounds.contentScroll <= bounds.contentWidth + 1 && bounds.contentHeight >= 80, section + ': ' + JSON.stringify(bounds));
          assert.ok(bounds.closeTop >= 0 && bounds.footerBottom <= size.height, section + ' fixed actions');
          if (section === 'general' || section === 'mcp') await screenshot('redesign-settings-' + section + '-' + theme + '-' + size.width);
        }
      }
    }
    await page.setViewportSize({ width: 1440, height: 960 }); await page.locator('#settings-tab-mcp').click();
    const config = await (await fetch(bridge.base + '/api/mcp/config', { headers: auth })).json();
    assert.equal((await page.locator('.mcp-config').textContent()).includes(bridge.token), false, 'preview hides credentials');
    for (const harness of ['claude', 'cursor', 'vscode', 'opencode', 'codex', 'http']) {
      await page.getByLabel('Harness', { exact: true }).selectOption(harness);
      await page.getByRole('button', { name: 'Copy configuration', exact: true }).click();
      const copied = await page.evaluate(() => navigator.clipboard.readText());
      assert.ok(copied.includes(bridge.token), harness + ' copy includes explicitly requested credentials');
      if (harness === 'codex') { assert.match(copied, /\[mcp_servers.projectuai\]/); assert.match(copied, /tool_timeout_sec = 300/); continue; }
      const parsed = JSON.parse(copied);
      if (harness === 'opencode') { assert.deepEqual(parsed.mcp.projectuai.command, [config.stdio.command, ...config.stdio.args]); assert.equal(parsed.mcp.projectuai.environment.UAI_BRIDGE_TOKEN, bridge.token); }
      else if (harness === 'vscode') { assert.equal(parsed.servers.projectuai.type, 'stdio'); assert.deepEqual(parsed.servers.projectuai.args, config.stdio.args); }
      else if (harness === 'http') { assert.equal(parsed.mcpServers.projectuai.url, config.endpoint); assert.equal(parsed.mcpServers.projectuai.headers.Authorization, 'Bearer ' + bridge.token); }
      else { assert.equal(parsed.mcpServers.projectuai.command, config.stdio.command); assert.deepEqual(parsed.mcpServers.projectuai.args, config.stdio.args); }
    }
    await page.getByRole('button', { name: 'Copy setup prompt', exact: true }).click();
    const manualPrompt = await page.evaluate(() => navigator.clipboard.readText());
    assert.ok(manualPrompt.includes('Exact stdio command: ' + JSON.stringify(config.stdio.command)));
    assert.ok(manualPrompt.includes('Exact stdio arguments: ' + JSON.stringify(config.stdio.args)));
    assert.ok(manualPrompt.includes(bridge.token)); assert.match(manualPrompt, /Preserve all unrelated settings/);
    assert.match(manualPrompt, /read-only/); assert.match(manualPrompt, /instead of claiming success/);
    assert.equal((await page.locator('#modal').textContent()).includes(bridge.token), false, 'explicit copies never expose credentials in the UI');
    const desktop = { ...config, stdio: { command: 'C:\\Program Files\\Project UAI\\UAI Bridge.exe', args: ['--mcp-stdio'], discovery: true } };
    await page.route('**/api/mcp/config', route => route.fulfill({ json: desktop }));
    await page.locator('.mcp-status-line button').click();
    await page.waitForFunction(() => document.querySelector('.mcp-config').textContent.includes('UAI Bridge.exe'));
    for (const harness of ['claude', 'http']) {
      await page.getByLabel('Harness', { exact: true }).selectOption(harness);
      await page.getByRole('button', { name: 'Copy setup prompt', exact: true }).click();
      const prompt = await page.evaluate(() => navigator.clipboard.readText());
      assert.ok(prompt.includes(JSON.stringify(desktop.stdio.command)) && prompt.includes(JSON.stringify(desktop.stdio.args)));
      assert.ok(!prompt.includes(bridge.token) && !prompt.includes('YOUR_BRIDGE_TOKEN'), 'desktop setup uses discovery without credentials or placeholders');
    }
    await close(); assert.equal(await page.locator('#settingsButton').evaluate(node => node === document.activeElement), true);
    assert.equal(await page.locator('#input').inputValue(), 'Keep this draft exactly as it is.');
    await page.locator('#modelButton').click();
    state.providers[0].freeRoute = { supported: true, enabled: false, running: true, ready: true, model: 'old-candidate', ms: 2500 };
    state.settings.agent.autoFreeRouting = false; await push();
    await page.waitForFunction(() => document.querySelector('.free-route').textContent.includes('Automatic free routing is off'));
    assert.match(await page.locator('.free-route').textContent(), /Settings → Agent → Automatic free routing/);
    state.providers[0].freeRoute = null; state.settings.agent.autoFreeRouting = true; await push();
    assert.equal(await page.locator('.model-list .is-free').count(), 2);
    assert.deepEqual(await page.locator('.effort-choice').allTextContents(), ['Provider default', 'Low', 'High']);
    assert.equal(await page.locator('[data-effort="high"]').getAttribute('aria-pressed'), 'true');
    await page.locator('[data-effort="low"]').click();
    await page.waitForFunction(() => !document.querySelector('#modal').hasAttribute('aria-busy'));
    assert.ok(commands.some(command => command.type === 'setting' && command.path === 'agent.effort' && command.value === 'low'));
    state.settings.agent.effort = 'low'; state.providers[0].modelInfo['deepseek-v4.1-flash-free'].effectiveEffort = 'low'; await push();
    await page.waitForFunction(() => document.querySelector('[data-effort="low"]').getAttribute('aria-pressed') === 'true');
    const temperature = page.getByLabel('Temperature', { exact: true }), handling = page.getByLabel('Temperature handling', { exact: true });
    assert.equal(await temperature.isDisabled(), true); assert.match(await page.locator('.model-sampling .field-help').textContent(), /provider has rejected temperature/);
    const overrideRequest = page.waitForRequest(request => request.url().endsWith('/api/command') && request.postDataJSON().type === 'model:temperature');
    await handling.selectOption('send'); const overrideCommand = (await overrideRequest).postDataJSON();
    assert.equal(overrideCommand.model, 'deepseek-v4.1-flash-free'); assert.equal(overrideCommand.value, 'send');
    Object.assign(state.providers[0].modelInfo['deepseek-v4.1-flash-free'], { temperatureAllowed: true, temperatureSource: 'manual', temperatureOverride: 'send' }); await push();
    await page.waitForFunction(() => !document.querySelector('.model-sampling input').disabled);
    await temperature.fill('0.7'); await temperature.press('Tab');
    await page.waitForFunction(() => !document.querySelector('#modal').hasAttribute('aria-busy'));
    assert.ok(commands.some(command => command.type === 'setting' && command.path === 'agent.temperature' && command.value === .7));
    await page.getByLabel('Free only', { exact: true }).check(); assert.equal(await page.locator('.model-list button').count(), 2);
    await screenshot('redesign-free-models-dark');
    const style = await page.locator('.model-list .is-free').first().evaluate(node => ({ border: getComputedStyle(node).borderColor, width: parseFloat(getComputedStyle(node).borderWidth), radius: parseFloat(getComputedStyle(node).borderRadius) }));
    assert.ok(style.width >= 1 && style.radius >= 8); assert.notEqual(style.border, 'rgba(0, 0, 0, 0)');
    await page.locator('.model-list [data-model="big-pickle"]').click();
    state.providers[0].model = 'big-pickle'; state.agent.model = 'big-pickle'; await push();
    await page.waitForFunction(() => document.querySelector('.model-detail>h3').textContent === 'big-pickle');
    assert.equal(await page.locator('.effort-choice').count(), 0, 'models without documented effort do not expose fabricated choices');
    assert.match(await page.locator('.model-reasoning').textContent(), /does not advertise reasoning/);
    for (const size of [{ width: 390, height: 844 }, { width: 320, height: 480 }, { width: 844, height: 390 }]) {
      await page.setViewportSize(size);
      const fit = await page.locator('#modal').evaluate(node => ({ width: node.clientWidth, scroll: node.scrollWidth, body: document.querySelector('#modalBody').clientHeight }));
      assert.ok(fit.scroll <= fit.width + 1 && fit.body >= 48, JSON.stringify(fit));
      await screenshot('redesign-models-' + size.width);
    }
    // Provider metadata wins over names, including personal paid HCNSEC models.
    state.providers[0].freeModels = []; state.providers[0].preset = 'hcnsec'; await push();
    await page.waitForFunction(() => document.querySelectorAll('.model-list .is-free').length === 0);
    assert.equal(await page.locator('#modelButton').evaluate(node => node.classList.contains('is-free')), false);
    await close();
    await page.setViewportSize({ width: 1440, height: 960 });
    assert.equal(await page.locator('#contextPercent').textContent(), '25%');
    await page.locator('#contextButton').click();
    assert.match(await page.locator('.context-note').textContent(), /calibrated/);
    assert.equal(await page.locator('.context-meter>span').evaluate(node => node.style.width), '25%');
    assert.match(await page.locator('.context-breakdown').textContent(), /Instructions & tools.*Conversation.*Compacted history.*Remaining capacity/s);
    await screenshot('redesign-context-dark');
    state.context.usedTokens = 125000; state.context.partial = true; await push();
    await page.waitForFunction(() => document.querySelector('.context-note').textContent.includes('Partial estimate'));
    assert.equal(await page.locator('.context-meter').getAttribute('data-level'), 'high');
    state.context.windowTokens = null; await push();
    await page.waitForFunction(() => document.querySelector('.context-overview').textContent.includes('Unknown'));
    assert.equal(await page.locator('#contextPercent').textContent(), '?', 'unknown limits never imply zero usage');
    await close();
    // Follow-ups are admitted while a response runs; Stop is an independent action.
    state.agent.busy = true; state.queue = { items: [], count: 0, limit: 16, held: false }; await push();
    await page.waitForFunction(() => !document.querySelector('#stop').hidden && !document.querySelector('#send').hidden);
    await page.locator('#input').fill('Check the lighting after this response.');
    const queuedRequest = page.waitForRequest(request => request.url().endsWith('/api/command') && request.postDataJSON().type === 'send');
    await page.locator('#send').click(); const queued = (await queuedRequest).postDataJSON();
    await page.waitForFunction(() => document.querySelector('#input').value === '');
    state.queue = { items: [{ id: queued.commandId, text: queued.text, images: [], at: Date.now(), state: 'queued' }], count: 1, limit: 16, held: false }; await push();
    await page.locator('.queued-item').waitFor();
    assert.equal(await page.locator('.message.user').count(), 0, 'queued input is separate from consumed transcript messages');
    await page.locator('#input').fill('Keep this next thought in the draft.');
    const stoppingRequest = page.waitForRequest(request => request.url().endsWith('/api/command') && request.postDataJSON().type === 'abort');
    await page.locator('#stop').click(); await stoppingRequest;
    state.agent.busy = false; state.queue.held = true; state.queue.reason = 'Stopped by user'; await push();
    await page.waitForFunction(() => document.querySelector('.queued-heading').textContent.includes('paused'));
    assert.equal(await page.locator('#input').inputValue(), 'Keep this next thought in the draft.');
    assert.ok(commands.some(command => command.type === 'abort'));
    const resumeRequest = page.waitForRequest(request => request.url().endsWith('/api/command') && request.postDataJSON().type === 'queue:resume');
    await page.getByRole('button', { name: 'Resume queue', exact: true }).click(); await resumeRequest;
    assert.ok(commands.some(command => command.type === 'queue:resume'));
    state.agent.busy = true; state.queue.held = false; state.queue.reason = null; await push();
    for (const size of [{ width: 1440, height: 960 }, { width: 320, height: 480 }, { width: 844, height: 390 }]) {
      await page.setViewportSize(size);
      for (const selector of ['#send', '#stop']) {
        const box = await page.locator(selector).boundingBox();
        assert.ok(box.x >= 0 && box.y >= 0 && box.x + box.width <= size.width && box.y + box.height <= size.height, 'queued composer actions fit: ' + JSON.stringify(box));
      }
      await screenshot('redesign-queued-' + size.width);
    }
    const removeRequest = page.waitForRequest(request => request.url().endsWith('/api/command') && request.postDataJSON().type === 'queue:remove');
    await page.locator('.queue-remove').click(); await removeRequest;
    assert.ok(commands.some(command => command.type === 'queue:remove' && command.messageId === queued.commandId));
    state.queue.items = []; state.queue.count = 0; await push();
    await page.locator('#queuedMessages').waitFor({ state: 'hidden' });
    assert.equal(await page.locator('#input').inputValue(), 'Keep this next thought in the draft.');
    assert.equal(await page.locator('#input').evaluate(node => node === document.activeElement), true, 'removing the last queued message restores composer focus');
    state.agent.busy = false; await push();
    // Every secondary destination uses a bounded workspace above the mounted chat.
    for (const size of [{ width: 1440, height: 960 }, { width: 390, height: 844 }, { width: 320, height: 480 }, { width: 844, height: 390 }]) {
      await page.setViewportSize(size); await navigate('cowork');
      for (const destination of ['cowork', 'providers', 'tools', 'agents', 'loops', 'memory', 'logs']) {
        await page.locator('#workspaceTabs [data-page="' + destination + '"]').click();
        const geometry = await page.locator('#workspaceModal').evaluate(node => {
          const box = node.getBoundingClientRect(), panel = document.querySelector('#panel'), close = document.querySelector('#workspaceClose').getBoundingClientRect();
          return { left: box.left, right: box.right, top: box.top, bottom: box.bottom, width: panel.clientWidth, scroll: panel.scrollWidth, height: panel.clientHeight, closeTop: close.top, closeRight: close.right };
        });
        assert.ok(geometry.left >= 0 && geometry.top >= 0 && geometry.right <= size.width && geometry.bottom <= size.height, destination + ': ' + JSON.stringify(geometry));
        assert.ok(geometry.height >= 80 && geometry.scroll <= geometry.width + 1 && geometry.closeTop >= 0 && geometry.closeRight <= size.width, destination + ': ' + JSON.stringify(geometry));
        assert.equal(await page.locator('#chatPage').evaluate(node => node.hidden), false, 'workspace keeps the chat mounted');
        if (['cowork', 'providers'].includes(destination)) await screenshot('redesign-workspace-' + destination + '-' + size.width);
      }
      await page.locator('#workspaceTabs [data-page="providers"]').click();
      const add = page.getByRole('button', { name: 'Add provider', exact: true }); await add.click();
      assert.equal(await page.locator('#workspaceModal').evaluate(node => node.open), true, 'nested actions preserve the parent workspace');
      await page.getByLabel('API', { exact: true }).selectOption('gemini');
      assert.equal(await page.getByLabel('Authentication', { exact: true }).inputValue(), 'x-goog-api-key', 'choosing native Gemini uses the Google API key header');
      await close(); assert.equal(await add.evaluate(node => node === document.activeElement), true, 'nested dialog restores its workspace action');
      await page.locator('#workspaceTabs').getByRole('button', { name: 'Settings', exact: true }).click();
      await page.locator('#settings-tab-general').waitFor(); await close();
      assert.equal(await page.locator('#workspaceTabs').getByRole('button', { name: 'Settings', exact: true }).evaluate(node => node === document.activeElement), true);
      await page.keyboard.press('Escape'); await page.locator('#workspaceModal').waitFor({ state: 'hidden' });
      assert.equal(await page.locator('#input').inputValue(), 'Keep this next thought in the draft.');
    }
    // A nested subagent preview keeps drafts, selections and expanded calls stable.
    await page.setViewportSize({ width: 1440, height: 960 });
    const agent = { id: 'preview-agent', label: 'Inspect the garden', task: 'Inspect lighting and tree placement, then report the best improvements.',
      currentTask: 'Inspect lighting and tree placement, then report the best improvements.', preset: 'read', toolAccess: 'Instances, Files, Web',
      status: 'running', provider: 'OpenCode', model: 'deepseek-v4.1-flash-free', parentTitle: 'A little room to create', elapsedMs: 34000,
      runs: 1, canFollowup: false, calls: 2, finishedCalls: 1, currentTool: 'instance_search',
      preview: { text: 'I found the **main garden** and am checking its lighting.', reasoning: 'Compare the light sources before recommending changes.' },
      activity: [{ index: 1, name: 'file_read', done: true, ok: true, summary: 'Read the existing garden plan.', ms: 300 },
        { index: 2, name: 'instance_search', done: false, progress: 'Checking tree positions and light sources.' }] };
    state.subagents = [agent]; await push(); await navigate('agents');
    await page.locator('.agent-card').getByRole('button', { name: 'Preview', exact: true }).click();
    assert.equal(await page.locator('#workspaceModal').evaluate(node => node.open), true);
    assert.match(await page.locator('.agent-preview-summary').textContent(), /Working.*instance_search.*1 of 2/s);
    assert.equal(await page.locator('.agent-preview-page .body strong').first().textContent(), 'main garden', 'agent output renders Markdown');
    await page.locator('.agent-thoughts summary').click();
    assert.match(await page.locator('.agent-thoughts').textContent(), /Compare the light sources/);
    const agentDraft = page.getByLabel('Subagent follow-up', { exact: true }); await agentDraft.fill('Check the fountain next.');
    await agentDraft.evaluate(node => { node.setSelectionRange(2, 9); window.previewDraft = node; });
    agent.preview.text += '\n\nThe outer path is too dark.'; await push();
    await page.waitForFunction(() => document.querySelector('.agent-preview-page').textContent.includes('outer path'));
    assert.deepEqual(await agentDraft.evaluate(node => [node === window.previewDraft, node === document.activeElement, node.selectionStart, node.selectionEnd]), [true, true, 2, 9]);
    assert.equal(await page.getByRole('button', { name: 'Send follow-up', exact: true }).isDisabled(), true);
    await page.locator('.agent-preview-tabs [data-section="tools"]').click();
    const activeTool = page.locator('.agent-tool[data-call="2"]'); await activeTool.locator('summary').click();
    await activeTool.locator('p').evaluate(node => { const range = document.createRange(); range.selectNodeContents(node); const selection = getSelection(); selection.removeAllRanges(); selection.addRange(range); window.previewTool = node.parentElement; });
    const selectedToolText = await page.evaluate(() => getSelection().toString());
    agent.activity[1].progress = 'Checked 18 trees; reviewing shadows.'; await push(); await page.waitForTimeout(300);
    assert.equal(await page.evaluate(() => getSelection().toString()), selectedToolText, 'selected tool text is not replaced mid-read');
    assert.equal(await activeTool.evaluate(node => node === window.previewTool && node.open), true, 'live activity retains expanded tool identity');
    const retainedActivity = agent.activity; agent.activity = []; await push(); await page.waitForTimeout(300);
    assert.equal(await page.evaluate(() => getSelection().toString()), selectedToolText, 'bounded retention does not remove a selected call mid-read');
    agent.activity = retainedActivity; await push();
    await page.evaluate(() => getSelection().removeAllRanges());
    await page.waitForFunction(() => document.querySelector('.agent-tool[data-call="2"] p').textContent.includes('18 trees'));
    await page.locator('.agent-preview-tabs [data-section="task"]').click();
    assert.match(await page.locator('.agent-access').textContent(), /Instances, Files, Web/);
    await page.locator('.agent-preview-tabs [data-section="overview"]').click();
    assert.equal(await agentDraft.inputValue(), 'Check the fountain next.');
    for (const size of [{ width: 1440, height: 960 }, { width: 390, height: 844 }, { width: 320, height: 480 }, { width: 844, height: 390 }]) {
      await page.setViewportSize(size);
      const geometry = await page.locator('#modal').evaluate(node => { const box = node.getBoundingClientRect(), body = document.querySelector('#modalBody'), footer = document.querySelector('#modalFooter').getBoundingClientRect(); return { left: box.left, top: box.top, right: box.right, bottom: box.bottom, width: body.clientWidth, scroll: body.scrollWidth, height: body.clientHeight, footer: footer.bottom }; });
      assert.ok(geometry.left >= 0 && geometry.top >= 0 && geometry.right <= size.width && geometry.bottom <= size.height && geometry.footer <= size.height, 'agent preview fits: ' + JSON.stringify(geometry));
      assert.ok(geometry.scroll <= geometry.width + 1 && geometry.height >= 80, 'agent preview body fits: ' + JSON.stringify(geometry));
      await screenshot('redesign-agent-live-' + size.width);
      await agentDraft.scrollIntoViewIfNeeded();
      const draftGeometry = await agentDraft.evaluate(node => { const box = node.getBoundingClientRect(), form = node.parentElement.getBoundingClientRect(), body = document.querySelector('#modalBody').getBoundingClientRect(); return { width: box.width, formWidth: form.width, top: box.top, bottom: box.bottom, bodyTop: body.top, bodyBottom: body.bottom }; });
      assert.ok(draftGeometry.width >= draftGeometry.formWidth - 2 && draftGeometry.top >= draftGeometry.bodyTop && draftGeometry.bottom <= draftGeometry.bodyBottom + 1, 'follow-up input fills its row and remains reachable: ' + JSON.stringify(draftGeometry));
      if (size.height <= 500) await screenshot('redesign-agent-draft-' + size.width);
      await page.locator('#modalBody').evaluate(node => { node.scrollTop = 0; });
    }
    await page.setViewportSize({ width: 1440, height: 960 });
    const stopAgentRequest = page.waitForRequest(request => request.url().endsWith('/api/command') && request.postDataJSON().type === 'subagent:stop');
    await page.getByRole('button', { name: 'Stop subagent', exact: true }).click(); assert.equal((await stopAgentRequest).postDataJSON().id, agent.id);
    Object.assign(agent, { status: 'done', canFollowup: true, preview: null, latestText: 'The garden review is complete.', report: '## Garden review\n\nAdd warmer path lights and space the eastern trees.', finishedCalls: 2, currentTool: null });
    Object.assign(agent.activity[1], { done: true, ok: true, summary: 'Found 18 trees and four lights.', ms: 700 }); await push();
    await page.waitForFunction(() => !document.querySelector('.agent-followup button').disabled);
    assert.equal(await page.getByRole('button', { name: 'Stop subagent', exact: true }).isVisible(), false);
    await page.getByRole('button', { name: 'Copy report', exact: true }).click();
    const copiedReport = await page.evaluate(() => navigator.clipboard.readText());
    assert.equal(copiedReport.replace(/\r\n/g, '\n'), agent.report, 'clipboard preserves the report with platform line endings');
    await screenshot('redesign-agent-complete');
    let releaseFollowup; followupReceipt = new Promise(resolve => { releaseFollowup = resolve; });
    const followupRequest = page.waitForRequest(request => request.url().endsWith('/api/command') && request.postDataJSON().type === 'subagent:followup');
    await page.getByRole('button', { name: 'Send follow-up', exact: true }).click(); const followed = (await followupRequest).postDataJSON();
    assert.equal(followed.id, agent.id); assert.equal(followed.text, 'Check the fountain next.');
    await agentDraft.fill('Keep this later thought.'); releaseFollowup(); followupReceipt = null;
    await page.waitForFunction(() => !document.querySelector('.agent-followup .field-help').textContent.includes('Sending'));
    assert.equal(await agentDraft.inputValue(), 'Keep this later thought.', 'an admitted follow-up cannot erase a newer draft');
    await page.getByRole('button', { name: 'Send follow-up', exact: true }).click();
    await page.waitForFunction(() => document.querySelector('.agent-followup textarea').value === '');
    await close(); assert.equal(await page.locator('#workspaceModal').evaluate(node => node.open), true);
    assert.equal(await page.locator('.agent-card').getByRole('button', { name: 'Preview', exact: true }).evaluate(node => node === document.activeElement), true);
    await navigate('chat');
    const routeNotice = { kind: 'model:route', sessionId: 'redesign', model: 'verified-free-model', provider: 'HCNSEC', text: 'Automatic free routing selected verified-free-model. Turn it off in Settings → Agent → Automatic free routing.' };
    await push({ events: [routeNotice] });
    await page.waitForFunction(() => [...document.querySelectorAll('#transcript .note')].some(node => node.textContent.includes('Automatic free routing selected verified-free-model')));
    await push({ sessionId: 'redesign', snapshot: [routeNotice] });
    await page.reload(); await page.locator('#app').waitFor({ state: 'visible' });
    await page.locator('#transcript .note').filter({ hasText: routeNotice.text }).waitFor();
    assert.equal(await page.locator('#transcript .note').filter({ hasText: routeNotice.text }).count(), 1, 'route choice and disable path survive transcript replay');
    assert.deepEqual(errors, []);
    console.log('Desktop redesign passed: modal workspaces, settings/focus, MCP setup/token privacy, reasoning/temperature/context metadata, free filtering, queued messages, and live subagent previews/follow-ups.');
  } finally { clearInterval(heartbeat); await browser?.close(); await bridge.stop(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
