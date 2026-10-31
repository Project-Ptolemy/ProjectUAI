/* Local Obsidian connections and a plain-text Markdown editor. */
(function(root) {
  'use strict';
  root.UAI = root.UAI || {};
  root.UAI.vaults = { mount };
  function mount(host, options) {
    const client = root.UAI.vaultClient, controller = new AbortController();
    let alive = true, loaded = false, pending = false, vaults = [], document = null, offset = 1, nextOffset = null, needsReload = false;
    const node = (tag, cls, text) => { const value = root.document.createElement(tag); if (cls) value.className = cls; if (text !== undefined) value.textContent = text; return value; };
    const button = (text, run, cls = 'outline') => { const value = node('button', cls, text); value.type = 'button'; value.onclick = run; return value; };
    const field = (parent, title, value = '', type = 'text') => {
      const label = node('label', 'vault-field', title), input = node(type === 'textarea' ? 'textarea' : 'input');
      if (type !== 'textarea') input.type = type; input.value = value; label.append(input); parent.append(label); return input;
    };
    const request = async (path, body) => {
      const exchange = new AbortController(), abort = () => exchange.abort();
      if (controller.signal.aborted) exchange.abort(); else controller.signal.addEventListener('abort', abort, { once: true });
      const timer = setTimeout(abort, 20000);
      try { return await options.request(path, body, undefined, exchange.signal); }
      finally { clearTimeout(timer); controller.signal.removeEventListener('abort', abort); }
    };
    const status = node('p', 'vault-status'); status.setAttribute('role', 'status'); status.setAttribute('aria-live', 'polite');
    host.append(node('h3', null, 'Obsidian vaults'), node('p', 'settings-intro', 'Read, search and edit Markdown notes on the bridge computer. Connect a folder below; Obsidian does not need to be running.'), status);
    const connections = node('div', 'vault-connections'); host.append(connections, button('Refresh vault connections', () => perform(async () => {
      await configure(); if (!alive) return; await listNotes(1); report('Vault connections refreshed.');
    })));
    const setup = node('details', 'vault-setup'); setup.append(node('summary', null, 'Connect a vault'));
    const form = node('form', 'dialog-form'); setup.append(form); host.append(setup);
    const name = field(form, 'Vault name'); name.required = true; name.maxLength = 80; name.placeholder = 'Personal notes';
    const folder = field(form, 'Folder on bridge computer'); folder.required = true; folder.maxLength = 2048; folder.placeholder = 'C:/Users/you/Documents/Notes';
    const readonlyLabel = node('label', 'vault-check'), readonly = node('input'); readonly.type = 'checkbox'; readonly.checked = true;
    readonlyLabel.append(readonly, root.document.createTextNode('Read-only')); form.append(readonlyLabel, node('p', 'field-help', 'Hidden folders, plugins, links and non-Markdown files stay outside vault access.'));
    const connect = node('button', 'primary', 'Connect vault'); connect.type = 'submit'; form.append(connect);
    const explorer = node('section', 'vault-explorer'); explorer.append(node('h4', null, 'Notes'));
    const chooseLabel = node('label', 'vault-field', 'Vault'), choose = node('select'); choose.setAttribute('aria-label', 'Vault'); chooseLabel.append(choose);
    const filters = node('form', 'vault-search'), query = field(filters, 'Search notes'); query.type = 'search'; query.maxLength = 300; query.placeholder = 'Search paths and note text';
    const search = node('button', 'outline', 'Search'); search.type = 'submit'; filters.append(search);
    const toolbar = node('div', 'row'), refresh = button('Refresh notes', () => perform(() => listNotes(1))), create = button('New note', newNote); toolbar.append(refresh, create);
    const resultInfo = node('p', 'field-help'), results = node('div', 'vault-results');
    const pages = node('div', 'row'), previous = button('Previous notes', () => perform(() => listNotes(Math.max(1, offset - 50)))), next = button('More notes', () => perform(() => listNotes(nextOffset)));
    pages.append(previous, next); explorer.append(chooseLabel, filters, toolbar, resultInfo, results, pages); host.append(explorer);
    const editor = node('section', 'vault-editor'); editor.hidden = true;
    const path = field(editor, 'Note path'); path.placeholder = 'Folder/New note.md'; path.maxLength = 1024;
    const text = field(editor, 'Markdown', '', 'textarea'); text.className = 'vault-note-text'; text.spellcheck = false; text.setAttribute('aria-label', 'Note Markdown');
    const details = node('p', 'field-help'), actions = node('div', 'row');
    const save = button('Save note', () => perform(saveCurrent), 'primary'), reload = button('Reload note', () => openNote(path.value, document?.vault));
    actions.append(save, reload, button('Copy note', () => options.copyText(text.value)), button('Download note', () => options.download((path.value.split('/').pop() || 'note.md'), text.value, 'text/markdown;charset=utf-8')), button('Close note', () => { if (discard()) { document = null; editor.hidden = true; update(); } }));
    editor.append(details, actions); host.append(editor);
    function selected() { return vaults.find(value => value.id === choose.value); }
    function dirty() { return !!document && (text.value !== client.editorText(document.content) || path.value !== document.path); }
    function discard() { return !dirty() || root.confirm('Discard the unsaved note changes? Download or copy the draft first if you want to keep it.'); }
    function report(message, error = false) { status.textContent = message; status.classList.toggle('form-error', error); }
    function update() {
      host.setAttribute('aria-busy', String(pending));
      for (const control of host.querySelectorAll('button,input,select,textarea')) control.disabled = pending;
      const vault = selected(); explorer.hidden = vaults.length === 0;
      create.disabled = pending || !vault || vault.readOnly || !vault.available;
      previous.disabled = pending || offset <= 1; next.disabled = pending || nextOffset == null;
      if (document) {
        const editable = vaults.find(value => value.id === document.vault);
        text.readOnly = !!editable?.readOnly; path.readOnly = !!document.revision;
        save.disabled = pending || !editable || editable.readOnly || needsReload || (!dirty() && !!document.revision);
        reload.disabled = pending || !path.value;
        const count = client.bytes(text.value);
        details.textContent = (dirty() ? 'Unsaved changes. ' : '') + count.toLocaleString() + ' bytes' + (count > client.MAX_BYTES ? ' — exceeds the 1 MiB limit.' : '') + (editable?.readOnly ? ' · Read-only vault' : '');
      }
    }
    async function perform(work) {
      if (!alive || pending) return; pending = true; update();
      try { await work(); }
      catch (error) { if (alive) report(error.message || 'The vault request failed.', true); }
      finally { if (alive) { pending = false; update(); } }
    }
    function renderConnections() {
      connections.replaceChildren();
      for (const vault of vaults) {
        const row = node('section', 'vault-connection'); row.dataset.vault = vault.id;
        row.append(node('strong', null, vault.name), node('code', 'vault-folder', vault.root), node('small', 'field-help', !vault.available ? 'Folder unavailable' : vault.readOnly ? 'Read-only' : 'Editing enabled'));
        const controls = node('div', 'row');
        controls.append(button(vault.readOnly ? 'Enable editing' : 'Make read-only', () => perform(async () => {
          await configure({ action: 'policy', id: vault.id, readOnly: !vault.readOnly }); report('Vault permissions saved.');
        })), button('Disconnect vault', () => {
          if (document?.vault === vault.id && !discard()) return;
          if (!root.confirm('Disconnect ' + vault.name + '? Its files stay on this computer.')) return;
          perform(async () => { await configure({ action: 'remove', id: vault.id }); if (document?.vault === vault.id) { document = null; editor.hidden = true; } await listNotes(1); report('Vault disconnected. Its files were kept.'); });
        })); row.append(controls); connections.append(row);
      }
      const chosen = choose.value; choose.replaceChildren();
      for (const vault of vaults) { const option = node('option', null, vault.name); option.value = vault.id; choose.append(option); }
      if (vaults.some(value => value.id === chosen)) choose.value = chosen;
    }
    async function configure(input) {
      const value = await request('/vaults/config', input); if (!alive) return;
      if (!Array.isArray(value?.vaults) || value.error) throw Error(value?.error || 'Invalid vault configuration response.');
      vaults = value.vaults; renderConnections();
      if (value.connectedId) choose.value = value.connectedId;
      update();
    }
    async function listNotes(start = 1) {
      if (!choose.value) { results.replaceChildren(); nextOffset = null; resultInfo.textContent = 'Connect your first vault to browse notes.'; return; }
      const value = await request('/vaults', { action: query.value.trim() ? 'search' : 'list', vault: choose.value, query: query.value.trim(), offset: start, limit: 50 });
      if (!alive) return;
      if (!Array.isArray(value?.data)) throw Error('The bridge returned an invalid note listing.');
      offset = start; nextOffset = value.nextOffset; results.replaceChildren();
      for (const note of value.data) {
        const row = button('', () => openNote(note.path), 'vault-note'); row.append(node('strong', null, note.path));
        if (note.matches?.length) row.append(node('small', null, note.matches[0].excerpt));
        else if (Number.isFinite(note.bytes)) row.append(node('small', null, note.bytes.toLocaleString() + ' bytes'));
        results.append(row);
      }
      resultInfo.textContent = (value.total ? 'Showing ' + start + '–' + (start + value.data.length - 1) + ' of ' + value.total + ' notes.' : 'No notes match this search.') + (value.incomplete ? ' Coverage is incomplete. Narrow the search or check unavailable files.' : '');
    }
    function openNote(notePath, vaultId = choose.value) {
      if (pending || !notePath || !discard()) return;
      perform(async () => {
        report('Reading note…'); const value = await client.readNote(request, vaultId, notePath); if (!alive) return;
        document = value; needsReload = false; path.value = value.path; text.value = value.content; editor.hidden = false; report('Note loaded.');
        editor.scrollIntoView({ block: 'nearest' });
      });
    }
    function newNote() {
      if (pending || !selected() || selected().readOnly || !discard()) return;
      document = { vault: choose.value, path: '', content: '' }; needsReload = false; path.value = ''; text.value = ''; editor.hidden = false; update(); path.focus();
    }
    async function saveCurrent() {
      if (!document) return;
      const snapshot = { ...document, path: path.value }, content = client.savedText(document, text.value);
      if (!snapshot.path.trim()) throw Error('Enter a note path ending in .md.');
      try {
        const result = await client.saveNote(request, snapshot, content); if (!alive) return;
        if (!/^[a-f0-9]{64}$/.test(result?.revision)) { needsReload = true; throw Error('The save response was incomplete. Reload to check the note; your draft is kept here.'); }
        document = { ...snapshot, content, revision: result.revision }; needsReload = false; report('Note saved and verified.'); await listNotes(offset);
      } catch (error) { if (error.status === 409 || error.uncertain) needsReload = true; throw error; }
    }
    form.onsubmit = event => { event.preventDefault(); perform(async () => {
      await configure({ action: 'connect', name: name.value.trim(), root: folder.value.trim(), readOnly: readonly.checked });
      if (!alive) return; name.value = ''; folder.value = ''; readonly.checked = true; setup.open = false; await listNotes(1); report('Vault connected.');
    }); };
    filters.onsubmit = event => { event.preventDefault(); perform(() => listNotes(1)); };
    choose.onchange = () => { if (document && !discard()) { choose.value = document.vault; return; } document = null; editor.hidden = true; perform(() => listNotes(1)); };
    text.oninput = update; path.oninput = update;
    const unload = event => { if (dirty()) { event.preventDefault(); event.returnValue = ''; } }; root.addEventListener('beforeunload', unload);
    update();
    return {
      dirty,
      load() { if (loaded || pending) return; perform(async () => { await configure(); if (!alive) return; await listNotes(1); loaded = true; report(vaults.length ? 'Vault connections loaded.' : 'Connect a folder to get started.'); }); },
      dispose() { alive = false; controller.abort(); root.removeEventListener('beforeunload', unload); },
    };
  }
})(window);
