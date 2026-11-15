// Observable scheduling, bounded hidden recovery, folded reasoning and personas.
'use strict';
const assert = require('node:assert/strict');
const http = require('node:http');
const { once } = require('node:events');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const { startBridge } = require('./helpers/bridge');

(async () => {
  const bridge = await startBridge();
  let browser, heartbeat, fixtureUpstream, sequence = 0;
  const auth = { Authorization: 'Bearer ' + bridge.token, 'content-type': 'application/json' };
  const state = {
    protocol: 2, runtime: 'web', sessionId: 'conversation-performance', player: 'David', place: { name: 'Fixture' },
    agent: { busy: false, status: 'Ready', provider: 'Fixture', model: 'fixture-model' },
    threads: [{ id: 'conversation-performance', title: 'Long conversation', active: true }],
    providers: [{ id: 'fixture', label: 'Fixture', model: 'fixture-model', models: ['fixture-model'], enabled: true }],
    activeProvider: 'fixture', permissions: { mode: 'full' }, tools: [], todos: [], loops: [], logs: [], requests: [],
    subagents: [], questions: [], pendingPermissions: [], settings: { ui: {}, agent: { persona: 'uai' } },
    personaOptions: [
      { value: 'uai', label: 'UAI', description: 'Direct answers and practical action.', sample: 'Fixed it. The check passed.' },
      { value: 'femboy', label: 'Femboy', description: 'Playful, cute, and direct.', sample: 'Cute UI, serious fixes.' },
    ],
  };
  const push = async extra => {
    const result = await fetch(bridge.base + '/api/agent/events', { method: 'POST', headers: auth,
      body: JSON.stringify({ batchId: 'performance-' + (++sequence), state, ...extra }) });
    assert.ok(result.ok, 'bridge fixture accepted');
  };
  try {
    await push({ sessionId: state.sessionId, snapshot: [] });
    heartbeat = setInterval(() => push().catch(() => {}), 10000);
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({ viewport: { width: 1280, height: 800 }, reducedMotion: 'reduce' });
    const page = await context.newPage(); page.setDefaultTimeout(15000);
    const errors = [], requests = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => requests.push({ path: new URL(request.url()).pathname, method: request.method() }));
    await page.addInitScript(() => {
      window.reasoningMarkdownCalls = 0;
      let markdown;
      Object.defineProperty(window, 'UAIMarkdown', {
        configurable: true, get: () => markdown,
        set(value) {
          const render = value.render;
          value.render = text => {
            if (String(text).includes('Reasoning performance fixture')) window.reasoningMarkdownCalls++;
            return render(text);
          };
          markdown = value;
        },
      });
    });
    await page.goto(bridge.base + '/#t=' + bridge.token);
    await page.locator('#app').waitFor({ state: 'visible' });
    await page.waitForFunction(() => document.querySelector('#modelLabel').textContent === 'fixture-model' && document.querySelector('#transcript').getAttribute('aria-busy') !== 'true');
    await page.locator('#input').fill('Keep this draft while history loads.');

    const history = [];
    for (let index = 1; index <= 110; index++) {
      history.push({ kind: 'user', sessionId: state.sessionId, text: 'Retained question ' + index });
      history.push({ kind: 'assistant:text', sessionId: state.sessionId, requestId: 'history-' + index,
        text: 'Retained answer ' + index + '\n\n' + ('A readable paragraph with **details**, paths, and exact results. '.repeat(120)) });
    }
    const started = await page.evaluate(({ history, owner }) => {
      window.replayEvents = 0; window.maxReplayEventsPerTask = 0;
      const originalRender = renderEvent;
      renderEvent = (event, ...args) => { window.replayEvents++; return originalRender(event, ...args); };
      const timeout = window.setTimeout;
      window.setTimeout = (callback, delay, ...args) => {
        if (typeof callback !== 'function') return timeout(callback, delay, ...args);
        return timeout(() => {
          const before = window.replayEvents;
          try { callback(...args); }
          finally { window.maxReplayEventsPerTask = Math.max(window.maxReplayEventsPerTask, window.replayEvents - before); }
        }, delay);
      };
      apply({ kind: 'bridge:snapshot', sessionId: owner, events: history });
      const synchronousEvents = window.replayEvents;
      apply({ kind: 'assistant:text', sessionId: owner, requestId: 'after-snapshot', text: 'Live reply after all retained history.' });
      return { synchronousEvents, busy: document.querySelector('#transcript').getAttribute('aria-busy') };
    }, { history, owner: state.sessionId });
    assert.deepEqual(started, { synchronousEvents: 0, busy: 'true' }, 'large history starts without a synchronous render burst');
    await page.waitForFunction(() => document.querySelector('#transcript').getAttribute('aria-busy') !== 'true');
    assert.equal(await page.locator('.message.user').count(), 110);
    assert.equal(await page.locator('.message.agent').count(), 111);
    assert.equal(await page.locator('.message.agent').last().locator('.body').textContent(), 'Live reply after all retained history.');
    assert.equal(await page.locator('#input').inputValue(), 'Keep this draft while history loads.');
    assert.ok(await page.evaluate(() => window.maxReplayEventsPerTask <= 12), 'each browser task renders at most twelve events');
    assert.equal(await page.evaluate(() => window.replayEvents), 221, 'queued live output follows the entire snapshot once');

    // A newer snapshot revokes scheduled old work rather than interleaving two histories.
    await page.evaluate(owner => {
      apply({ kind: 'bridge:snapshot', sessionId: owner, events: Array.from({ length: 100 }, (_, index) => ({ kind: 'user', text: 'Superseded history ' + index, sessionId: owner })) });
      apply({ kind: 'bridge:snapshot', sessionId: owner, events: [
        { kind: 'user', text: 'Current history', sessionId: owner },
        { kind: 'assistant:text', text: 'Current answer', requestId: 'current', sessionId: owner },
      ] });
    }, state.sessionId);
    await page.waitForFunction(() => document.querySelector('#transcript').getAttribute('aria-busy') !== 'true');
    assert.equal(await page.locator('.message.user').count(), 1);
    assert.equal(await page.locator('.message.agent').count(), 1);
    assert.equal(await page.locator('#transcript').textContent().then(text => text.includes('Superseded history')), false);

    state.agent.busy = true;
    const controls = await page.evaluate(owner => {
      window.stopUnavailableDuringReplay = false;
      const originalRender = renderEvent;
      renderEvent = (event, ...args) => {
        const result = originalRender(event, ...args);
        if (snapshotReplay && state.agent?.busy && (document.querySelector('#stop').hidden || document.querySelector('#stop').disabled)) window.stopUnavailableDuringReplay = true;
        return result;
      };
      const saved = [];
      for (let index = 0; index < 40; index++) saved.push(
        { kind: 'turn:start', sessionId: owner },
        { kind: 'user', text: 'Completed request ' + index, sessionId: owner },
        { kind: 'assistant:text', text: 'Completed reply ' + index, requestId: 'completed-' + index, sessionId: owner },
        { kind: 'turn:end', sessionId: owner });
      apply({ kind: 'bridge:snapshot', sessionId: owner, events: saved });
      apply({ kind: 'bridge:state', state: { ...state, agent: { ...state.agent, busy: true } } });
      // A newer state supersedes this queued turn marker for live controls.
      apply({ kind: 'turn:end', sessionId: owner });
      apply({ kind: 'bridge:state', state: { ...state, agent: { ...state.agent, busy: true } } });
      return { stopVisible: !document.querySelector('#stop').hidden, stopEnabled: !document.querySelector('#stop').disabled,
        restoring: !!snapshotReplay, busy: document.querySelector('#transcript').getAttribute('aria-busy') };
    }, state.sessionId);
    assert.deepEqual(controls, { stopVisible: true, stopEnabled: true, restoring: true, busy: 'true' }, 'current busy state enables Stop before the first saved entry is painted');
    await page.waitForFunction(() => !snapshotReplay);
    assert.equal(await page.evaluate(() => window.stopUnavailableDuringReplay), false, 'historical and superseded turn endings cannot hide Stop for the current request');
    assert.equal(await page.locator('#stop').isVisible(), true);
    assert.equal(await page.locator('#stop').isEnabled(), true);
    assert.equal(await page.locator('#transcript').getAttribute('aria-busy'), 'true', 'finishing history does not clear the live generation indicator');
    state.agent.busy = false;
    await page.evaluate(() => apply({ kind: 'bridge:state', state: { ...state, agent: { ...state.agent, busy: false } } }));

    // Visibility is simulated to make scheduling deterministic; recovery uses
    // actual POSTs, a closed EventSource and the server's retained snapshot.
    await page.evaluate(() => {
      window.fixtureHidden = true;
      Object.defineProperty(document, 'hidden', { configurable: true, get: () => window.fixtureHidden });
      document.dispatchEvent(new Event('visibilitychange'));
      window.originalQueueSnapshotEvent = queueSnapshotEvent;
      queueSnapshotEvent = event => {
        window.originalQueueSnapshotEvent(event);
        if (snapshotReplay) {
          window.maxHiddenPendingCount = Math.max(window.maxHiddenPendingCount, snapshotReplay.pending.length - snapshotReplay.pendingCursor);
          window.maxHiddenPendingBytes = Math.max(window.maxHiddenPendingBytes, snapshotReplay.pendingBytes);
        }
      };
      window.originalSnapshotStart = startSnapshotReplay;
      startSnapshotReplay = event => {
        window.originalSnapshotStart(event);
        if (window.recoveryRingFixture && snapshotReplay?.recovery) window.fixtureHidden = true;
      };
      window.originalReplayApply = apply;
      apply = (event, ...args) => {
        if (!args[0] && event.kind === 'bridge:cursor' && window.recoveryRingFixture && snapshotReplay?.recovery) {
          const label = window.recoveryRingFixture, owner = state.sessionId, requestId = 'recovery-preview-' + label;
          // Network backlog precedes the cursor. Hold rendering long enough to
          // combine it with one full normalized preview ring, then resume.
          window.originalReplayApply({ kind: 'inference:start', sessionId: owner, requestId });
          const frames = label === 'count' ? 4096 : 1;
          for (let seq = 1; seq <= frames; seq++) window.originalReplayApply({ kind: 'inference:delta', sessionId: owner,
            requestId, seq, channel: 'reasoning', text: label === 'count' ? 'Retained preview thought ' + seq + '\n' : 'x'.repeat(4.5 * 1024 * 1024) });
          window.originalReplayApply({ kind: 'inference:done', sessionId: owner, requestId, state: 'completed', streamed: true });
          window.recoveryAllowance = { count: snapshotReplay?.pending.length, bytes: snapshotReplay?.pendingBytes,
            recovering: snapshotReplay?.recovery, cursor: snapshotReplay?.cursor };
          window.recoveryRingFixture = null; window.fixtureHidden = false;
          document.dispatchEvent(new Event('visibilitychange'));
        }
        return window.originalReplayApply(event, ...args);
      };
    });
    for (const label of ['count', 'bytes']) {
      const question = { kind: 'user', sessionId: state.sessionId, text: 'Retained recovery question: ' + label };
      const reply = { kind: 'assistant:text', sessionId: state.sessionId, requestId: 'recovered-' + label,
        text: 'Durable saved reply after ' + label + ' overflow.' };
      await page.evaluate(() => { window.fixtureHidden = true; window.maxHiddenPendingCount = 0; window.maxHiddenPendingBytes = 0; });
      await push({ sessionId: state.sessionId, snapshot: [question] });
      await page.waitForFunction(text => snapshotReplay?.events[0]?.text === text, question.text);
      await page.evaluate(() => { window.overflowTask = snapshotReplay; window.overflowStream = stream; });
      const streamsBefore = requests.filter(request => request.path === '/api/stream').length;
      if (label === 'count') {
        await push({ events: [...Array.from({ length: 400 }, () => ({ kind: 'compact', sessionId: state.sessionId })), reply] });
      } else {
        // Each accepted event fits the server's 8 MiB event limit; together they
        // must trip the browser byte bound long before the 400-event bound.
        for (let index = 0; index < 2; index++) {
          await push({ events: [{ kind: 'tool:result', sessionId: state.sessionId, id: 'hidden-large-' + index,
            text: 'Retained large output ' + index + ': ' + 'x'.repeat(4.5 * 1024 * 1024) }] });
          if (index === 0) await page.waitForFunction(() => snapshotReplay?.pendingBytes > 4 * 1024 * 1024);
        }
      }
      await page.waitForFunction(() => transcriptResyncNeeded && !snapshotReplay && stream === null);
      const bounded = await page.evaluate(() => ({ maxCount: window.maxHiddenPendingCount, maxBytes: window.maxHiddenPendingBytes,
        hiddenCursor: window.overflowTask.cursor, remainingEvents: window.overflowTask.events.length,
        remainingPending: window.overflowTask.pending.length, remainingBytes: window.overflowTask.pendingBytes,
        remainingResponses: window.overflowTask.responses.length, retainedTrim: window.overflowTask.trim.retained,
        closed: window.overflowStream.readyState === EventSource.CLOSED }));
      const { maxCount, maxBytes, ...cleared } = bounded;
      assert.equal(maxCount, label === 'count' ? 400 : 1, label + ' overflow reaches only its applicable queue bound');
      assert.ok(maxBytes <= 8 * 1024 * 1024, 'queued browser bytes remain bounded');
      assert.deepEqual(cleared, {
        hiddenCursor: 0, remainingEvents: 0, remainingPending: 0, remainingBytes: 0, remainingResponses: 0, retainedTrim: null, closed: true },
      'hidden replay paints nothing and cancellation releases its retained inputs');
      const receipt = 'Durable receipt after ' + label + ' overflow.';
      await push({ events: [
        { kind: 'tool:call', id: 'recovery-' + label, name: 'inspect', arguments: { path: 'Fixture' } },
        { kind: 'tool:result', id: 'recovery-' + label, name: 'inspect', text: receipt },
        ...(label === 'bytes' ? [reply] : []), { kind: 'turn:end' }] });
      await page.evaluate(() => {
        window.overflowStream.onmessage({ data: JSON.stringify({ kind: 'assistant:text', text: 'Stale closed-stream reply' }) });
        apply({ kind: 'assistant:text', text: 'Discarded while waiting for retained recovery' });
      });
      assert.equal(await page.evaluate(() => window.overflowTask.pending.length), 0, 'closed hidden view stops collecting updates');
      assert.equal(requests.filter(request => request.path === '/api/stream').length, streamsBefore, 'hidden overflow waits for visibility before opening another stream');
      await page.evaluate(label => { window.recoveryRingFixture = label; window.fixtureHidden = false; document.dispatchEvent(new Event('visibilitychange')); }, label);
      await page.waitForFunction(text => !snapshotReplay && !transcriptResyncNeeded && [...document.querySelectorAll('.message.agent .body')].some(node => node.textContent === text), reply.text);
      assert.equal(requests.filter(request => request.path === '/api/stream').length, streamsBefore + 1, 'visible recovery opens one fresh SSE stream');
      const allowance = await page.evaluate(() => window.recoveryAllowance);
      assert.equal(allowance.recovering, true); assert.equal(allowance.cursor, 0, 'the complete recovery burst is buffered before rendering');
      assert.ok(allowance.count <= 5000 && allowance.bytes <= 16 * 1024 * 1024, 'fresh recovery keeps both server-ring bounds');
      if (label === 'count') assert.equal(allowance.count, 400 + 4096 + 2, 'a full durable backlog and preview ring fit without another resync');
      else assert.ok(allowance.bytes > 8 * 1024 * 1024, 'fresh recovery has bounded byte headroom for retained previews');
      assert.equal(await page.locator('.message.user').count(), 1);
      assert.equal(await page.locator('.message.user .body').textContent(), question.text, 'fresh SSE restores the actual retained server snapshot');
      assert.equal((await page.locator('.message.agent .body').allTextContents()).filter(text => text === reply.text).length, 1, 'retained durable output appears once');
      assert.equal(await page.locator('.thinking[data-reasoning-request-id="recovery-preview-' + label + '"] .reasoning-body').textContent(), '', 'recovery retains folded preview reasoning without parsing it');
      assert.equal(await page.locator('.tool[data-status="done"]').count(), 1, 'retained tool receipt finishes its call once');
      assert.equal(await page.locator('.tool-result-content').textContent(), receipt);
      assert.equal(await page.locator('#input').inputValue(), 'Keep this draft while history loads.', 'overflow recovery preserves the full draft');
      const stale = await page.evaluate(() => {
        const active = stream, before = document.querySelector('#transcript').textContent;
        window.overflowStream.onmessage({ data: JSON.stringify({ kind: 'bridge:reset' }) });
        window.overflowStream.onerror(); window.overflowStream.onopen();
        return { unchanged: before === document.querySelector('#transcript').textContent, sameStream: active === stream,
          link: document.body.dataset.link, game: document.body.dataset.game };
      });
      assert.deepEqual(stale, { unchanged: true, sameStream: true, link: 'online', game: 'connected' }, 'callbacks from the old SSE connection cannot reset the recovered transcript or controls');
    }
    assert.equal(requests.filter(request => request.path.startsWith('/api/inference') || request.path === '/api/command').length, 0, 'transcript recovery never resubmits agent work');
    await page.evaluate(() => {
      delete document.hidden; delete window.fixtureHidden;
      queueSnapshotEvent = window.originalQueueSnapshotEvent;
      startSnapshotReplay = window.originalSnapshotStart; apply = window.originalReplayApply;
      delete window.originalQueueSnapshotEvent; delete window.overflowTask; delete window.overflowStream;
      delete window.originalSnapshotStart; delete window.originalReplayApply; delete window.recoveryRingFixture;
      document.dispatchEvent(new Event('visibilitychange'));
    });

    // Two genuine loopback jobs retain full per-job rings. Recovery must fit the
    // aggregate server projection, rather than repeatedly reopening the same burst.
    const rawPreview = 'data: {"choices":[{"delta":{"reasoning_content":"x"}}]}\n\n'.repeat(4096) + 'data: [DONE]\n\n';
    let providerCalls = 0;
    fixtureUpstream = http.createServer((request, response) => {
      providerCalls++; request.on('error', () => {}); response.on('error', () => {});
      request.resume(); response.writeHead(200, { 'content-type': 'text/event-stream' }); response.end(rawPreview);
    });
    fixtureUpstream.listen(0, '127.0.0.1'); await once(fixtureUpstream, 'listening');
    const hello = await fetch(bridge.base + '/api/hello', { headers: auth }).then(response => response.json());
    await page.evaluate(() => {
      window.fixtureHidden = true;
      Object.defineProperty(document, 'hidden', { configurable: true, get: () => window.fixtureHidden });
      window.originalMultiStart = startSnapshotReplay; window.originalMultiApply = apply;
      startSnapshotReplay = event => {
        window.originalMultiStart(event);
        if (snapshotReplay?.recovery) window.fixtureHidden = true;
      };
      apply = (event, ...args) => {
        if (!args[0] && event.kind === 'bridge:cursor' && snapshotReplay?.recovery) {
          window.multiRecoveryAllowance = { count: snapshotReplay.pending.length, bytes: snapshotReplay.pendingBytes };
          window.fixtureHidden = false; document.dispatchEvent(new Event('visibilitychange'));
        }
        return window.originalMultiApply(event, ...args);
      };
    });
    const question = 'Question retained through multiple preview rings.';
    await push({ sessionId: state.sessionId, snapshot: [{ kind: 'user', sessionId: state.sessionId, text: question }] });
    await page.waitForFunction(text => snapshotReplay?.events[0]?.text === text, question);
    for (const id of ['ring-first', 'ring-second']) {
      const result = await fetch(bridge.base + '/api/inference', { method: 'POST', headers: auth, body: JSON.stringify({
        id, instance: hello.instance, url: 'http://127.0.0.1:' + fixtureUpstream.address().port,
        sessionId: state.sessionId, body: '{"model":"fixture-model"}',
      }) });
      assert.ok(result.ok, 'loopback inference fixture accepted');
    }
    for (const id of ['ring-first', 'ring-second']) {
      let receipt;
      for (let attempt = 0; attempt < 200; attempt++) {
        receipt = await fetch(bridge.base + '/api/inference/' + id, { headers: auth }).then(response => response.json());
        if (receipt.state !== 'running') break;
        await new Promise(resolve => setTimeout(resolve, 10));
      }
      assert.equal(receipt.state, 'completed'); assert.equal(receipt.body, rawPreview);
    }
    await page.waitForFunction(() => transcriptResyncNeeded && !snapshotReplay && stream === null);
    const receiptText = 'Durable tool receipt retained across multiple rings.';
    const replyText = 'Durable reply retained across multiple rings.';
    await push({ events: [...Array.from({ length: 396 }, () => ({ kind: 'compact', sessionId: state.sessionId })),
      { kind: 'tool:call', sessionId: state.sessionId, id: 'multiple-ring-tool', name: 'inspect', arguments: {} },
      { kind: 'tool:result', sessionId: state.sessionId, id: 'multiple-ring-tool', name: 'inspect', text: receiptText },
      { kind: 'assistant:text', sessionId: state.sessionId, requestId: 'multiple-ring-reply', text: replyText },
      { kind: 'turn:end', sessionId: state.sessionId }] });
    const streamsBeforeMultiple = requests.filter(request => request.path === '/api/stream').length;
    await page.evaluate(() => { window.fixtureHidden = false; document.dispatchEvent(new Event('visibilitychange')); });
    await page.waitForFunction(() => !snapshotReplay && !transcriptResyncNeeded && document.querySelectorAll('.thinking').length === 2);
    const multiple = await page.evaluate(() => window.multiRecoveryAllowance);
    assert.ok(multiple.count > 4096 && multiple.count <= 5000, 'durable backlog and both projected rings fit one bounded recovery');
    assert.ok(multiple.bytes <= 16 * 1024 * 1024);
    assert.equal(requests.filter(request => request.path === '/api/stream').length, streamsBeforeMultiple + 1, 'multiple rings need one fresh stream');
    assert.equal(await page.locator('.message.user .body').textContent(), question);
    assert.equal(await page.locator('.tool-result-content').textContent(), receiptText);
    assert.equal((await page.locator('.message.agent .body').allTextContents()).filter(text => text === replyText).length, 1);
    for (const id of ['ring-first', 'ring-second']) {
      assert.equal(await page.locator('.message.agent[data-request-id="' + id + '"] .stream-gap').count(), 1, 'each clipped tail discloses its omitted prefix');
      assert.equal(await page.locator('.thinking[data-reasoning-request-id="' + id + '"] .reasoning-body').textContent(), '');
    }
    assert.equal(providerCalls, 2, 'fresh transcript recovery never resubmits either fixture request');
    assert.equal(await page.locator('#input').inputValue(), 'Keep this draft while history loads.');
    await page.evaluate(() => {
      startSnapshotReplay = window.originalMultiStart; apply = window.originalMultiApply;
      delete document.hidden; delete window.fixtureHidden; delete window.originalMultiStart; delete window.originalMultiApply;
      document.dispatchEvent(new Event('visibilitychange'));
    });

    const reasoning = '## Reasoning performance fixture\n\n' + 'Keep the exact **paths and results** for the next step. '.repeat(400);
    await page.evaluate(({ owner, reasoning }) => {
      apply({ kind: 'user', text: 'Show a live response.', sessionId: owner });
      apply({ kind: 'inference:start', requestId: 'reasoning-performance', sessionId: owner });
      apply({ kind: 'inference:delta', requestId: 'reasoning-performance', sessionId: owner, seq: 1, channel: 'reasoning', text: reasoning });
    }, { owner: state.sessionId, reasoning });
    await page.waitForTimeout(180);
    const thoughts = page.locator('.thinking[data-reasoning-request-id="reasoning-performance"]');
    await thoughts.waitFor({ state: 'attached' });
    assert.equal(await thoughts.locator('.reasoning-body').textContent(), '', 'folded reasoning creates no formatted text');
    assert.equal(await page.evaluate(() => window.reasoningMarkdownCalls), 0, 'folded live reasoning performs no Markdown parse');
    await thoughts.evaluate(node => { node.closest('.response-activity').open = true; node.open = true; });
    await thoughts.locator('.reasoning-body h2').waitFor({ state: 'visible' });
    assert.equal(await page.evaluate(() => window.reasoningMarkdownCalls), 1);
    await page.evaluate(owner => {
      for (let seq = 2; seq <= 12; seq++) apply({ kind: 'inference:delta', requestId: 'reasoning-performance', sessionId: owner, seq, channel: 'text', text: 'Answer text ' });
    }, state.sessionId);
    await page.waitForTimeout(180);
    assert.equal(await page.evaluate(() => window.reasoningMarkdownCalls), 1, 'text-channel paints reuse unchanged expanded reasoning');
    await thoughts.evaluate(node => { node.open = false; });
    const finalReasoning = reasoning + '\n\nFinal exact finding.';
    await page.evaluate(({ owner, text }) => {
      apply({ kind: 'assistant:reasoning', requestId: 'reasoning-performance', sessionId: owner, text });
      apply({ kind: 'assistant:text', requestId: 'reasoning-performance', sessionId: owner, text: 'The final answer is ready.' });
      apply({ kind: 'turn:end', sessionId: owner });
    }, { owner: state.sessionId, text: finalReasoning });
    assert.equal(await page.evaluate(() => window.reasoningMarkdownCalls), 1, 'folded commitment retains source without parsing it');
    await thoughts.evaluate(node => { node.open = true; });
    await page.waitForFunction(() => document.querySelector('.thinking[data-reasoning-request-id="reasoning-performance"] .reasoning-body').textContent.includes('Final exact finding.'));
    assert.equal(await page.evaluate(() => window.reasoningMarkdownCalls), 2, 'opening paints the newer authoritative reasoning');
    await thoughts.evaluate(node => { node.open = false; });
    await page.waitForTimeout(30);
    await thoughts.evaluate(node => { node.open = true; });
    await page.waitForTimeout(30);
    assert.equal(await page.evaluate(() => window.reasoningMarkdownCalls), 2, 'reopening unchanged reasoning reuses its content');

    await page.evaluate(() => openSettings('agent'));
    const persona = page.locator('[data-setting="agent.persona"]');
    assert.deepEqual(await persona.locator('option').allTextContents(), ['UAI', 'Femboy'], 'browser uses the supplied shared catalogue');
    assert.equal(await page.locator('.persona-sample').textContent(), 'Example: Fixed it. The check passed.');
    const request = page.waitForRequest(request => request.url().endsWith('/api/command') && request.method() === 'POST');
    await persona.selectOption('femboy');
    const command = (await request).postDataJSON();
    assert.equal(command.type, 'setting'); assert.equal(command.path, 'agent.persona'); assert.equal(command.value, 'femboy');
    assert.equal(await page.locator('.persona-description').textContent(), 'Playful, cute, and direct.');
    assert.equal(await page.locator('.persona-sample').textContent(), 'Example: Cute UI, serious fixes.');
    await fetch(bridge.base + '/api/agent/ack', { method: 'POST', headers: auth, body: JSON.stringify({ results: [{ id: command.commandId, ok: true }] }) });
    state.settings.agent.persona = 'femboy'; await push();
    await page.waitForFunction(() => document.querySelector('[data-setting="agent.persona"]').closest('.setting').dataset.state === 'saved');
    assert.deepEqual(errors, []);
    console.log('Conversation browser checks passed: sliced history, responsive Stop, hidden count/byte recovery, durable ordering, lazy reasoning, and shared personas.');
  } finally { clearInterval(heartbeat); fixtureUpstream?.closeAllConnections?.(); fixtureUpstream?.close(); await browser?.close(); await bridge.stop(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
