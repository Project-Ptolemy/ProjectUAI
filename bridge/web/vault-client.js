/* Revision-bound note reads shared by the Obsidian browser and its tests. */
(function(root) {
  'use strict';
  const MAX_BYTES = 1024 * 1024;
  const bytes = text => new TextEncoder().encode(text).length;
  const editorText = text => text.replace(/\r\n?/g, '\n');
  const savedText = (document, text) => document.content.includes('\r\n') && !/(^|[^\r])\n/.test(document.content) ? text.replace(/\r\n?/g, '\n').replace(/\n/g, '\r\n') : text;
  async function readNote(request, vault, path) {
    let offset = 1, revision, size, modifiedAt, content = '', metadata;
    for (let page = 0; page < 90; page++) {
      const value = await request('/vaults', { action: 'read', vault, path, offset, limit: 12000, revision, metadata: offset === 1 });
      if (!value || typeof value.content !== 'string' || !/^[a-f0-9]{64}$/.test(value.revision) || value.offset !== offset ||
          !Number.isInteger(value.bytes) || value.bytes < 0 || value.bytes > MAX_BYTES ||
          (revision && (revision !== value.revision || size !== value.bytes))) throw Error('The bridge returned an inconsistent note page. Reload the note.');
      revision = value.revision; size = value.bytes; modifiedAt = value.modifiedAt;
      if (offset === 1) metadata = value.metadata;
      const length = bytes(value.content);
      if (bytes(content) + length > MAX_BYTES) throw Error('This note exceeds the 1 MiB editor limit.');
      content += value.content;
      if (value.nextOffset == null) {
        if (bytes(content) !== size || value.eof !== true) throw Error('The note read ended before its full contents arrived. Reload the note.');
        return { path, vault, content, revision, bytes: size, modifiedAt, metadata };
      }
      if (!length || value.nextOffset !== offset + length || value.eof !== false) throw Error('The note read did not advance safely. Reload the note.');
      offset = value.nextOffset;
    }
    throw Error('This note could not be read within the page limit.');
  }
  async function saveNote(request, document, content) {
    if (typeof content !== 'string' || bytes(content) > MAX_BYTES) throw Error('Notes must fit within 1 MiB.');
    try {
      return await request('/vaults', { action: document.revision ? 'update' : 'create', vault: document.vault,
        path: document.path, revision: document.revision, content });
    } catch (error) {
      if (!error.status) {
        error.message = 'The save could not be confirmed. Your draft is kept here. Reload the note to check the file before saving again.';
        error.uncertain = true;
      }
      throw error;
    }
  }
  const api = { MAX_BYTES, bytes, editorText, savedText, readNote, saveNote };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else { root.UAI = root.UAI || {}; root.UAI.vaultClient = api; }
})(typeof window !== 'undefined' ? window : globalThis);
