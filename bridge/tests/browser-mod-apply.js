// Mod tools use ordinary permission receipts; ask_user remains an explicit question.
'use strict';
const assert = require('node:assert/strict');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const { startBridge } = require('./helpers/bridge');
const { navigation } = require('./helpers/browser-ui');

(async () => {
  const bridge = await startBridge(); let browser, heartbeat, sequence = 0, publication = Promise.resolve();
  const headers = { Authorization: 'Bearer ' + bridge.token, 'content-type': 'application/json' };
  const sessionId = 'mod-browser-fixture';
  const state = { protocol: 2, runtime: 'web', sessionId, player: 'Fixture',
    agent: { status: 'Ready', busy: false, model: 'fixture-model', provider: 'Fixture' },
    providers: [], threads: [], usage: { total: 0 }, settings: { agent: {}, ui: {} },
    permissions: { mode: 'full' }, pendingPermissions: [], questions: [], logs: [], requests: [],
    tools: [{ name: 'ui_mod_apply', description: 'Apply an exact saved UI mod using current tool permissions.',
      available: true, enabled: true, risk: 'danger', group: 'ui_mods', parameters: { type: 'object', properties: {
        id: { type: 'string', minLength: 1, maxLength: 64 },
        expected_revision: { type: 'string', minLength: 1, maxLength: 512 },
      }, required: ['id', 'expected_revision'] } }] };
  const publish = () => {
    const body = JSON.stringify({ batchId: 'mod-apply-' + (++sequence), sessionId, state, events: [] });
    publication = publication.then(async () => {
      const response = await fetch(bridge.base + '/api/agent/events', { method: 'POST', headers, body });
      assert.ok(response.ok);
    });
    return publication;
  };
  try {
    await publish(); heartbeat = setInterval(() => publish().catch(() => {}), 10000);
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage({ viewport: { width: 1280, height: 900 }, reducedMotion: 'reduce' });
    page.setDefaultTimeout(15000);
    const errors = [], commands = [], receipts = new Map(); let waitingMod;
    page.on('pageerror', error => errors.push(error.message));
    await page.route('**/api/command', route => {
      const command = route.request().postDataJSON(); commands.push(command);
      let result = { state: 'completed', result: { ok: true, data: true } };
      if (command.type === 'tool:run' && command.name === 'ui_mod_apply') {
        if (state.permissions.mode === 'ask') { waitingMod = command.commandId; result = { state: 'queued' }; }
        else if (state.permissions.mode === 'readonly') result.result.data = { ok: false, text: 'Fixture: read-only rejected mod activation' };
        else result.result.data = { ok: true, text: 'Applied saved mod.', data: { applied: true } };
      } else if (command.type === 'permission' && command.allow && waitingMod) {
        receipts.set(waitingMod, { state: 'completed', result: { ok: true,
          data: { ok: true, text: 'Applied saved mod.', data: { applied: true } } } });
        waitingMod = null;
      }
      receipts.set(command.commandId, result);
      return route.fulfill({ status: 200, json: { id: command.commandId } });
    });
    await page.route('**/api/commands/*', route => route.fulfill({ status: 200,
      json: receipts.get(route.request().url().split('/').pop()) || { state: 'queued' } }));
    await page.goto(bridge.base + '/#t=' + bridge.token);
    await page.locator('#app').waitFor({ state: 'visible' });
    const { navigate } = navigation(page);
    const sent = async action => {
      const before = commands.length;
      const response = page.waitForResponse(value => value.url().endsWith('/api/command') && value.request().method() === 'POST');
      await action(); await response;
      assert.equal(commands.length, before + 1);
      return commands[before];
    };
    const apply = async (id, revision) => {
      await navigate('tools');
      await page.locator('.tool-grid .card').filter({ has: page.getByRole('heading', { name: 'ui_mod_apply', exact: true }) })
        .getByRole('button', { name: 'Run…', exact: true }).click();
      await page.locator('#modal [data-parameter="id"]').fill(id);
      await page.locator('#modal [data-parameter="expected_revision"]').fill(revision);
      const formState = await page.locator('#modalForm').evaluate(form => {
        const run = document.querySelector('#modalFooter button[type=submit]');
        return { valid: form.checkValidity(), target: run.getAttribute('form'), formId: run.form?.getAttribute('id') || null };
      });
      assert.deepEqual(formState, { valid: true, target: 'modalForm', formId: 'modalForm' },
        'A tool parameter named id must keep its footer submit button associated with the form');
      return sent(() => page.getByRole('button', { name: 'Run tool', exact: true }).click());
    };
    const closeResult = async () => {
      await page.waitForFunction(() => document.querySelector('#modal').open
        && document.querySelector('#modalTitle').textContent === 'ui_mod_apply result');
      await page.locator('#modalFooter').getByRole('button', { name: 'Done', exact: true }).click();
      await page.locator('#modal').waitFor({ state: 'hidden' });
    };
    assert.equal(commands.length, 0, 'Opening the browser does not apply a mod');
    for (const id of ['script-workspace', 'visual-workspace']) {
      const revision = 'mod:browser-fixture:' + id + ':1', command = await apply(id, revision);
      assert.equal(command.type, 'tool:run'); assert.equal(command.name, 'ui_mod_apply');
      assert.equal(command.sessionId, sessionId);
      assert.deepEqual(command.arguments, { id, expected_revision: revision });
      assert.equal(Object.hasOwn(command, 'uiModReviewRevision'), false);
      await closeResult();
      assert.equal(await page.locator('#questions .question').count(), 0, 'Allow all applies through the normal tool receipt without a separate question');
    }

    state.permissions.mode = 'ask'; await publish();
    const guarded = await apply('guarded-workspace', 'mod:browser-fixture:guarded:1');
    state.pendingPermissions = [{ id: 'normal-mod-policy', name: 'ui_mod_apply', sessionId, args: guarded.arguments }];
    await publish();
    const permission = page.locator('#questions .question[data-request-key="permission:normal-mod-policy"]');
    await permission.getByText('Allow ui_mod_apply?', { exact: true }).waitFor({ state: 'visible' });
    assert.deepEqual(JSON.parse(await permission.locator('pre').textContent()), guarded.arguments);
    const allowed = await sent(() => permission.getByRole('button', { name: 'Allow', exact: true }).click());
    assert.equal(allowed.type, 'permission'); assert.equal(allowed.id, 'normal-mod-policy'); assert.equal(allowed.allow, true);
    state.pendingPermissions = []; await publish(); await closeResult();

    state.permissions.mode = 'readonly'; await publish();
    await apply('read-only-workspace', 'mod:browser-fixture:readonly:1');
    const failure = page.locator('#modal [aria-label="Execution details"]');
    await failure.waitFor({ state: 'visible' });
    assert.equal(await failure.textContent(), 'Fixture: read-only rejected mod activation',
      'A completed command with a failed tool result exposes the real policy refusal');
    await closeResult();
    assert.equal(await page.locator('#questions .question').count(), 0, 'A policy refusal does not create a dedicated mod question');

    state.permissions.mode = 'full';
    const question = { id: 'ordinary-question', question: 'Pick a color <img id="question-injected">', options: ['Blue', 'Keep'],
      sessionTitle: 'Ordinary fixture', uiModReviewRequired: true,
      uiModReview: { spec: { source: 'window.modReviewExecuted = true', description: '<script id="review-injected">' } } };
    state.questions = [question]; await publish();
    const card = page.locator('#questions .question[data-request-key="question:ordinary-question"]');
    await card.getByRole('button', { name: 'Blue', exact: true }).waitFor({ state: 'visible' });
    assert.equal(await page.locator('.ui-mod-review,#question-injected,#review-injected').count(), 0, 'Retired metadata creates no review controls or markup');
    assert.equal(await page.evaluate(() => window.modReviewExecuted), undefined);
    assert.equal(commands.filter(command => command.type === 'ask:answer').length, 0, 'Allow all never answers an ordinary question automatically');
    const input = card.locator('input[type=text]'); await input.fill('Preserve this answer draft');
    await input.evaluate(node => { node.focus(); node.setSelectionRange(2, 7); window.retainedAnswerInput = node; });
    question.sessionTitle = 'Updated ordinary fixture'; await publish();
    await card.getByText('Conversation: Updated ordinary fixture', { exact: true }).waitFor({ state: 'visible' });
    assert.equal(await input.inputValue(), 'Preserve this answer draft');
    assert.equal(await input.evaluate(node => node === window.retainedAnswerInput && document.activeElement === node
      && node.selectionStart === 2 && node.selectionEnd === 7), true, 'Question refresh retains the active answer draft and selection');
    const answer = await sent(() => card.getByRole('button', { name: 'Blue', exact: true }).click());
    assert.equal(answer.type, 'ask:answer'); assert.equal(answer.id, question.id); assert.equal(answer.text, 'Blue');
    assert.equal(Object.hasOwn(answer, 'uiModReviewRevision'), false, 'Ordinary answers carry no privileged mod metadata');
    state.questions = [{ id: 'ordinary-dismiss', question: 'Dismiss this question', options: [] }]; await publish();
    const dismissed = await sent(() => page.locator('#questions').getByRole('button', { name: 'Dismiss', exact: true }).click());
    assert.equal(dismissed.id, 'ordinary-dismiss'); assert.equal(dismissed.text, '');
    for (const width of [320, 390]) {
      await page.setViewportSize({ width, height: 844 });
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), true);
    }
    assert.deepEqual(errors, []);
    process.stdout.write('Browser mod apply: normal tool/permission receipts, read-only refusal, explicit questions and retained drafts passed\n');
  } finally { clearInterval(heartbeat); await browser?.close(); await bridge.stop(); }
})().catch(error => { process.stderr.write(error.stack + '\n'); process.exitCode = 1; });
