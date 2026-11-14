/* Browser previews are incremental; only the game's assistant:text is final. */
(function (root) {
  'use strict';
  const PAINT_MS = 60, MAX_LIVE = 32, MAX_TEXT = 8 * 1024 * 1024;

  function rateText(outputTokens, requestMs) {
    if (!Number.isFinite(outputTokens) || !Number.isInteger(outputTokens) || outputTokens < 0 || outputTokens > 1e12 ||
        !Number.isFinite(requestMs) || requestMs <= 0) return null;
    const rate = outputTokens / (requestMs / 1000);
    if (!Number.isFinite(rate)) return null;
    const measured = rate >= 1e6 ? rate.toExponential(2).replace(/\.?0+e/, 'e') : rate.toFixed(1);
    return (rate > 0 && rate < 0.1 ? '<0.1' : measured) + ' tk/s request avg';
  }

  function create(deps) {
    const live = new Map(), committed = new Map(), anchors = new Map(), pendingReasoning = new Map();
    let anonymous = 0;
    const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
    const identity = e => e.requestId || e.streamId || e.id;
    const session = e => e.sessionId || deps.getSession() || '';
    const key = e => session(e) + ':' + identity(e);
    const find = e => identity(e) ? live.get(key(e)) || committed.get(key(e)) : pendingReasoning.get(session(e));
    const matches = e => !e.sessionId || e.sessionId === deps.getSession();
    const signal = () => deps.onActivity?.([...live.values()].some(entry => entry.streaming));
    const node = (tag, cls, text) => {
      const n = document.createElement(tag); n.className = cls;
      if (text !== undefined) n.textContent = text;
      return n;
    };

    function selectedWithin(body) {
      const selection = document.getSelection();
      return selection && !selection.isCollapsed && (body.contains(selection.anchorNode) || body.contains(selection.focusNode) || selection.containsNode(body, true));
    }

    // Animated runs are temporary presentation wrappers, never Markdown input.
    // Treat them and adjacent text nodes as one leaf when a new delta arrives.
    const isText = n => n && (n.nodeType === 3 || n.nodeType === 1 && n.hasAttribute('data-stream-text'));
    function arrivingText(text, animate) {
      if (!animate) return document.createTextNode(text);
      const span = node('span', 'stream-token', text); span.setAttribute('data-stream-text', ''); return span;
    }
    function settleToken(span) {
      span.classList.remove('stream-token');
      if (selectedWithin(span)) return;
      const previous = span.previousSibling;
      if (previous?.nodeType === 3) { previous.appendData(span.textContent); span.remove(); }
      else span.replaceWith(document.createTextNode(span.textContent));
    }
    function morph(target, source, animate = false, topLevel = true) {
      let cursor = target.firstChild;
      for (const desired of [...source.childNodes]) {
        if (desired.nodeType === 3) {
          const group = []; let text = '';
          while (isText(cursor)) { group.push(cursor); text += cursor.textContent; cursor = cursor.nextSibling; }
          if (desired.textContent === text) continue;
          if (desired.textContent.startsWith(text)) {
            target.insertBefore(arrivingText(desired.textContent.slice(text.length), animate), cursor);
          } else {
            let common = 0;
            while (common < text.length && text[common] === desired.textContent[common]) common++;
            for (const old of group) old.remove();
            if (common) target.insertBefore(document.createTextNode(desired.textContent.slice(0, common)), cursor);
            if (common < desired.textContent.length) target.insertBefore(arrivingText(desired.textContent.slice(common), animate), cursor);
          }
          continue;
        }
        if (desired.nodeType !== 1) continue;
        if (cursor?.nodeType !== 1 || cursor.tagName !== desired.tagName || cursor.hasAttribute('data-stream-text')) {
          const added = desired.cloneNode(true);
          if (animate && (topLevel || ['LI', 'TR'].includes(added.tagName))) added.classList.add('stream-block-enter');
          target.insertBefore(added, cursor);
          continue;
        }
        const current = cursor; cursor = current.nextSibling;
        for (const attr of [...current.attributes]) if (!desired.hasAttribute(attr.name) && attr.name !== 'class') current.removeAttribute(attr.name);
        for (const attr of [...desired.attributes]) {
          const value = attr.name === 'class' && current.classList.contains('stream-block-enter') ? attr.value + ' stream-block-enter' : attr.value;
          if (current.getAttribute(attr.name) !== value) current.setAttribute(attr.name, value);
        }
        morph(current, desired, animate, false);
      }
      while (cursor) { const next = cursor.nextSibling; cursor.remove(); cursor = next; }
    }

    function state(entry, value, text) {
      if (entry.node.dataset.responseState !== value) entry.node.dataset.responseState = value;
      if (entry.statusCopy && text !== undefined && entry.statusCopy.textContent !== text) entry.statusCopy.textContent = text;
      deps.onState?.(entry);
    }
    function identify(entry, e) {
      entry.sessionId = session(e); entry.requestId = identity(e);
      entry.key = entry.requestId ? key(e) : entry.sessionId + ':anonymous-' + (++anonymous);
      entry.startedAt = Number.isFinite(e.startedAt) ? e.startedAt : Date.now();
      const anchor = anchors.get(entry.sessionId); entry.turnUser = anchor?.open ? anchor.node : null;
      if (entry.requestId) entry.node.dataset.requestId = entry.requestId;
      entry.node.dataset.content = 'waiting';
      return entry;
    }
    function contentState(entry, text) {
      entry.node.dataset.content = String(text || '').trim() ? 'answer' : entry.reasonBody ? 'reasoning' : 'waiting';
    }
    function reasoningState(entry, active) {
      const details = entry.reasonBody?.parentElement; if (!details) return;
      details.dataset.state = active ? 'thinking' : 'complete';
      const status = details.querySelector('.thinking-state');
      const label = active ? 'In progress' : entry.reasonCommitted ? 'Complete' : entry.reasoningStopped ? 'Stopped' : entry.failed ? 'Interrupted' : 'Complete';
      if (status && status.textContent !== label) status.textContent = label;
      entry.reasonBody.setAttribute('aria-busy', String(active));
    }
    function ensureReasoning(entry) {
      if (entry.reasonBody) return;
      const details = node('details', 'thinking'), summary = node('summary', 'thinking-summary');
      const heading = node('span', 'thinking-heading');
      heading.append(node('span', 'thinking-title', 'Reasoning'), node('span', 'thinking-caption', 'How this response was approached'));
      summary.append(heading, node('span', 'thinking-state', 'In progress'));
      entry.reasonBody = node('div', 'body reasoning-body rendered'); details.append(summary, entry.reasonBody);
      if (deps.onCopyReasoning) {
        const footer = node('div', 'thinking-footer'), copy = node('button', 'thinking-copy', 'Copy reasoning');
        copy.type = 'button'; copy.onclick = () => deps.onCopyReasoning(entry.reasoningText || ''); footer.append(copy); details.append(footer);
      }
      if (deps.attachReasoning) deps.attachReasoning(entry, details);
      else entry.node.insertBefore(details, entry.body);
      contentState(entry, entry.finalText ?? entry.text);
      reasoningState(entry, entry.streaming && !entry.text && !entry.reasonCommitted);
    }

    function cancelReasoning(entry) {
      if (!entry.reasonDeferred) return;
      document.removeEventListener('selectionchange', entry.reasonDeferred);
      entry.reasonBody.removeEventListener('focusout', entry.reasonDeferred);
      entry.reasonDeferred = null;
    }
    function cancel(entry, dispose = false) {
      clearTimeout(entry.timer); cancelAnimationFrame(entry.raf);
      entry.timer = entry.raf = null; entry.scheduled = false;
      entry.needsPaint = false;
      if (entry.deferred) {
        document.removeEventListener('selectionchange', entry.deferred);
        entry.body.removeEventListener('focusout', entry.deferred);
        entry.deferred = null;
      }
      if (entry.resumeSelection) {
        document.removeEventListener('selectionchange', entry.resumeSelection);
        entry.body.removeEventListener('focusout', entry.resumeSelection);
        entry.resumeSelection = null;
      }
      if (dispose) { cancelReasoning(entry); entry.reasonFinalText = null; }
    }
    function trimCommitted() {
      while (committed.size > 80) {
        const [oldId, old] = committed.entries().next().value; cancel(old, true); committed.delete(oldId);
        if (pendingReasoning.get(old.sessionId) === old) pendingReasoning.delete(old.sessionId);
      }
    }

    function ensure(e) {
      if (!matches(e) || committed.has(key(e))) return null;
      let entry = live.get(key(e));
      if (entry) return entry;
      while (live.size >= MAX_LIVE) {
        const [oldKey, old] = live.entries().next().value;
        cancel(old, true); old.streaming = false; old.node.classList.remove('streaming');
        old.body.removeAttribute('aria-busy');
        state(old, 'paused', 'Preview paused. Waiting for the saved reply.'); reasoningState(old, false);
        live.delete(oldKey);
      }
      const created = deps.createAgentMessage(e.model || deps.defaultModel());
      const stable = node('div', 'stream-stable'), tail = node('div', 'stream-tail');
      const status = node('div', 'stream-status'), statusCopy = node('span', 'stream-status-copy', 'Preparing a response');
      const indicator = node('span', 'stream-indicator'); indicator.setAttribute('aria-hidden', 'true');
      for (let i = 0; i < 3; i++) indicator.append(node('i', ''));
      status.append(indicator, statusCopy); status.setAttribute('role', 'status'); status.setAttribute('aria-live', 'polite');
      created.body.replaceChildren(stable, tail);
      created.node.append(status); created.node.classList.add('streaming');
      created.body.setAttribute('aria-busy', 'true');
      entry = identify({ ...created, stable, tail, status, statusCopy,
        text: '', reasoning: '', stableLength: 0, paintedTail: '', lastSeq: 0, lastPaint: 0,
        streaming: true, timer: null, raf: null, scheduled: false }, e);
      created.body.addEventListener('animationend', event => {
        if (event.target.matches('.stream-token')) settleToken(event.target);
        else if (event.target.matches('.stream-block-enter')) event.target.classList.remove('stream-block-enter');
      });
      state(entry, 'waiting');
      live.set(key(e), entry); signal();
      return entry;
    }

    // A block becomes stable only at a blank line outside a matching fence.
    function stableCut(text) {
      const lines = text.split('\n'); let fence = null, offset = 0, cut = 0;
      for (const line of lines) {
        const opening = line.match(/^\s*(`{3,}|~{3,})/);
        if (opening && !fence) fence = opening[1];
        else if (fence && new RegExp('^\\s*' + fence[0] + '{' + fence.length + ',}\\s*$').test(line)) fence = null;
        offset += line.length + 1;
        if (!fence && !line.trim() && offset <= text.length) cut = offset;
      }
      return cut;
    }

    function paint(entry) {
      entry.scheduled = false; entry.lastPaint = performance.now();
      if (!entry.node.isConnected) return;
      if (document.hidden) { entry.needsPaint = true; return; }
      entry.needsPaint = false;
      const pinned = deps.isPinned();
      // Keep a selected passage in the changing tail intact. Selecting an older
      // stable block never pauses the next part of the response.
      if (selectedWithin(entry.tail)) {
        if (!entry.resumeSelection) {
          entry.resumeSelection = () => {
            if (selectedWithin(entry.tail)) return;
            document.removeEventListener('selectionchange', entry.resumeSelection);
            entry.body.removeEventListener('focusout', entry.resumeSelection);
            entry.resumeSelection = null; schedule(entry);
          };
          document.addEventListener('selectionchange', entry.resumeSelection);
          entry.body.addEventListener('focusout', entry.resumeSelection);
        }
        return;
      }
      for (const token of entry.body.querySelectorAll('[data-stream-text]:not(.stream-token)')) settleToken(token);
      const remainder = entry.text.slice(entry.stableLength), cut = stableCut(remainder);
      if (remainder !== entry.paintedTail) {
        const fragment = document.createElement('template'); fragment.innerHTML = deps.md(remainder);
        morph(entry.tail, fragment.content, !reducedMotion.matches);
      }
      if (cut && !entry.tail.contains(document.activeElement)) {
        const fragment = document.createElement('template');
        fragment.innerHTML = deps.md(remainder.slice(0, cut));
        // Promote the existing rendered nodes. Code focus and old entrance
        // animations survive the tail-to-stable boundary unchanged.
        for (let i = 0; i < fragment.content.childNodes.length; i++) {
          if (entry.tail.firstChild) entry.stable.append(entry.tail.firstChild);
        }
        entry.stableLength += cut;
      }
      entry.paintedTail = entry.text.slice(entry.stableLength);
      if (entry.reasonBody && !entry.reasonCommitted) {
        const renderReasoning = () => {
          if (!entry.reasonBody?.isConnected || isInteracting(entry.reasonBody)) return;
          const fragment = document.createElement('template'); fragment.innerHTML = deps.md(entry.reasoningText || '');
          morph(entry.reasonBody, fragment.content); cancelReasoning(entry);
        };
        if (!isInteracting(entry.reasonBody)) renderReasoning();
        else if (!entry.reasonDeferred) {
          entry.reasonDeferred = () => queueMicrotask(renderReasoning);
          document.addEventListener('selectionchange', entry.reasonDeferred);
          entry.reasonBody.addEventListener('focusout', entry.reasonDeferred);
        }
      }
      if (entry.streaming && (entry.text || entry.reasoning)) state(entry, entry.text ? 'writing' : 'thinking', entry.text ? 'Writing' : 'Thinking through it');
      reasoningState(entry, entry.streaming && !entry.text && !entry.reasonCommitted);
      if (pinned) deps.scrollToEnd();
    }

    function schedule(entry) {
      if (document.hidden) { entry.needsPaint = true; return; }
      if (entry.scheduled) return;
      entry.scheduled = true;
      entry.timer = setTimeout(() => {
        entry.timer = null;
        entry.raf = requestAnimationFrame(() => { entry.raf = null; paint(entry); });
      }, Math.max(0, PAINT_MS - (performance.now() - entry.lastPaint)));
    }

    function flush(entry) {
      clearTimeout(entry.timer); cancelAnimationFrame(entry.raf);
      entry.timer = entry.raf = null; paint(entry);
    }

    function isInteracting(body) {
      if (body.contains(document.activeElement)) return true;
      return selectedWithin(body);
    }

    function reconcile(entry, text) {
      const render = () => {
        if (isInteracting(entry.body)) return;
        const pinned = deps.isPinned(), fragment = document.createElement('template'); fragment.innerHTML = deps.md(text);
        if (entry.stable) {
          if (entry.tail?.parentElement) { entry.stable.append(...entry.tail.childNodes); entry.tail.remove(); }
          morph(entry.stable, fragment.content);
        } else morph(entry.body, fragment.content);
        cancel(entry);
        if (pinned) deps.scrollToEnd();
      };
      if (isInteracting(entry.body)) {
        entry.deferred = () => queueMicrotask(render);
        entry.body.addEventListener('focusout', entry.deferred);
        document.addEventListener('selectionchange', entry.deferred);
      } else render();
    }

    function start(e) { ensure(e); }

    function resync(e) {
      const entry = ensure(e); if (!entry) return;
      flush(entry);
      entry.text = ''; entry.stableLength = 0; entry.paintedTail = ''; entry.stable.replaceChildren(); entry.tail.replaceChildren();
      if (!entry.reasonCommitted) { entry.reasoning = ''; entry.reasoningText = ''; if (entry.reasonBody) entry.reasonBody.textContent = ''; }
      entry.lastSeq = Math.max(0, (e.from || entry.lastSeq + 1) - 1);
      if (!entry.gap) { entry.gap = node('p', 'stream-gap', 'Earlier live text is unavailable. The saved reply will replace this preview.'); entry.node.append(entry.gap); }
    }

    function delta(e) {
      const entry = ensure(e); if (!entry) return;
      if (Number.isFinite(e.seq)) {
        if (e.seq <= entry.lastSeq) return;
        if (e.seq > entry.lastSeq + 1) resync({ ...e, from: e.seq });
        entry.lastSeq = e.seq;
      }
      const d = e.frame?.choices?.[0]?.delta || {}, anthropic = e.frame?.delta || {};
      const text = e.channel ? (e.channel === 'text' && typeof e.text === 'string' ? e.text : '') : d.content || anthropic.text || '';
      const reasoning = e.channel ? (e.channel === 'reasoning' && typeof e.text === 'string' ? e.text : '') : d.reasoning_content || d.reasoning || anthropic.thinking || '';
      if (entry.text.length + entry.reasoning.length + text.length + reasoning.length > MAX_TEXT) {
        done({ ...e, state: 'failed', error: 'Live preview reached its size limit. Waiting for the saved reply.' }); return;
      }
      entry.text += text; entry.reasoning += reasoning;
      if (reasoning) entry.reasoningText = entry.reasoning;
      if (reasoning && !entry.reasonBody) ensureReasoning(entry);
      contentState(entry, entry.text);
      if (text || reasoning) schedule(entry);
    }

    function done(e) {
      if (!matches(e) || committed.has(key(e))) return;
      const entry = ensure(e); if (!entry) return;
      const selection = document.getSelection(), pinned = deps.isPinned() && (!selection || selection.isCollapsed);
      flush(entry); entry.streaming = false; entry.node.classList.remove('streaming');
      entry.body.removeAttribute('aria-busy'); reasoningState(entry, false);
      const failure = (e.state && e.state !== 'completed') || e.status >= 400;
      if (failure) {
        entry.failed = true; entry.reasoningStopped = e.state === 'cancelled'; reasoningState(entry, false);
        state(entry, e.state === 'cancelled' ? 'stopped' : 'error');
        entry.status.className = 'stream-error'; entry.status.setAttribute('role', e.state === 'cancelled' ? 'status' : 'alert');
        entry.status.replaceChildren(node('span', '', e.error || e.providerError || (e.state === 'cancelled' ? 'Request stopped.' : 'Request failed.')));
        const actions = deps.onError?.(entry.status, { ...e, hasPreview: !!entry.text }) || entry.status;
        if (deps.onRetry && e.state !== 'cancelled') {
          const retry = node('button', 'retry', 'Review message'); retry.type = 'button';
          retry.onclick = () => deps.onRetry(entry.sessionId); actions.prepend(retry);
        }
      } else state(entry, 'saving', e.streamed === false ? 'Response received. Waiting for Roblox…' : 'Finishing up');
      signal();
      if (pinned) deps.scrollToEnd();
    }

    function commitText(e) {
      if (!matches(e)) return;
      let entry = find(e);
      if (entry && !entry.node.isConnected) { cancel(entry, true); live.delete(entry.key); committed.delete(entry.key); entry = null; }
      if (entry) {
        if (live.has(entry.key)) flush(entry);
        cancel(entry); reconcile(entry, e.text || '');
        entry.streaming = false; entry.authoritative = true; entry.finalText = e.text || ''; entry.node.classList.remove('streaming');
        contentState(entry, e.text);
        state(entry, 'complete'); entry.body.removeAttribute('aria-busy'); reasoningState(entry, false);
        entry.status?.remove(); entry.gap?.remove();
        deps.onFinal?.(entry, e.text || '', e.model, e);
        entry.text = entry.reasoning = ''; live.delete(entry.key); committed.set(entry.key, entry);
        if (pendingReasoning.get(entry.sessionId) === entry) pendingReasoning.delete(entry.sessionId);
      } else {
        const created = identify(deps.createAgentMessage(e.model || deps.defaultModel()), e);
        created.authoritative = true; created.finalText = e.text || ''; created.node.dataset.responseState = 'complete'; contentState(created, e.text);
        created.body.innerHTML = deps.md(e.text || ''); deps.onFinal?.(created, e.text || '', e.model, e);
        if (identity(e)) committed.set(created.key, created);
      }
      trimCommitted(); signal();
    }

    function commitReasoning(e) {
      if (!matches(e)) return;
      let entry = find(e);
      if (entry && !entry.node.isConnected) { cancel(entry, true); live.delete(entry.key); committed.delete(entry.key); entry = null; }
      if (!entry && e.text) {
        entry = identify(deps.createAgentMessage(e.model || deps.defaultModel()), e);
        entry.text = ''; entry.streaming = false;
        if (!identity(e)) pendingReasoning.set(entry.sessionId, entry);
      }
      if (entry) {
        if (live.has(entry.key)) { flush(entry); cancel(entry); }
        entry.authoritative = true; entry.streaming = false; entry.node.classList.remove('streaming');
        entry.body.removeAttribute('aria-busy'); entry.status?.remove();
        state(entry, 'complete'); live.delete(entry.key); committed.set(entry.key, entry);
        if (!entry.reasonBody && e.text) ensureReasoning(entry);
        if (entry.reasonBody) {
          cancelReasoning(entry); entry.reasonFinalText = e.text || ''; entry.reasoningText = e.text || '';
          const render = () => {
            if (entry.reasonFinalText === null || isInteracting(entry.reasonBody)) return;
            const fragment = document.createElement('template'); fragment.innerHTML = deps.md(entry.reasonFinalText);
            morph(entry.reasonBody, fragment.content); entry.reasonBody.classList.add('rendered');
            cancelReasoning(entry); entry.reasonFinalText = null;
          };
          if (isInteracting(entry.reasonBody)) {
            entry.reasonDeferred = () => queueMicrotask(render);
            document.addEventListener('selectionchange', entry.reasonDeferred);
            entry.reasonBody.addEventListener('focusout', entry.reasonDeferred);
          } else render();
        }
        entry.reasonCommitted = true; reasoningState(entry, false);
      }
      trimCommitted(); signal();
    }

    function anchorUser(e, userNode) {
      const sessionId = session(e), at = Number.isFinite(e.at) ? e.at : null;
      anchors.set(sessionId, { node: userNode, at, open: true }); pendingReasoning.delete(sessionId);
      let first = null;
      for (const entry of live.values()) {
        if (entry.sessionId !== sessionId || entry.authoritative || entry.failed || entry.turnEnded) continue;
        const belongs = at !== null ? entry.startedAt >= at : !entry.turnUser;
        if (!belongs) continue;
        entry.turnUser = userNode;
        const response = deps.responseRoot?.(entry.node) || entry.node;
        if (response.parentNode === userNode.parentNode && response.compareDocumentPosition(userNode) & 4) {
          if (!first || response.compareDocumentPosition(first) & 4) first = response;
        }
      }
      // Move the newly confirmed user row, preserving live response selection,
      // tool focus and every older completed or failed message in place.
      if (first) userNode.parentNode.insertBefore(userNode, first);
      return first;
    }

    function endTurn(sessionId, stopped = false, at) {
      const anchor = anchors.get(sessionId);
      if (anchor && (!Number.isFinite(at) || !anchor.at || at >= anchor.at)) anchor.open = false;
      for (const entry of live.values()) if (entry.sessionId === sessionId) {
        if (Number.isFinite(at) && entry.startedAt > at) continue;
        entry.turnEnded = true; entry.reasoningStopped = stopped;
        flush(entry); entry.streaming = false; entry.node.classList.remove('streaming');
        entry.body.removeAttribute('aria-busy'); reasoningState(entry, false);
        if (!entry.text && !entry.failed && !entry.reasonBody) entry.node.remove();
        else if (!entry.text && entry.reasonBody && !entry.failed) { entry.status?.remove(); state(entry, 'complete'); }
        else if (!entry.failed) state(entry, stopped ? 'stopped' : 'saving', stopped ? 'Stopped. This is a partial response.' : 'Preview only. Waiting for the saved reply.');
      }
      signal();
    }

    function dropSession(sessionId) {
      for (const map of [live, committed]) for (const [id, entry] of map) if (entry.sessionId === sessionId) { cancel(entry, true); map.delete(id); }
      anchors.delete(sessionId); pendingReasoning.delete(sessionId);
      signal();
    }

    function dropNode(removed) {
      for (const map of [live, committed]) for (const [id, entry] of map) {
        if (removed === entry.node || removed.contains(entry.node)) {
          cancel(entry, true); entry.reasonBody?.parentElement?.remove(); map.delete(id);
          if (pendingReasoning.get(entry.sessionId) === entry) pendingReasoning.delete(entry.sessionId);
        } else if (entry.reasonBody && removed.contains(entry.reasonBody)) {
          cancelReasoning(entry); entry.reasonBody = null; entry.reasonFinalText = null;
        }
      }
      for (const [id, anchor] of anchors) if (removed === anchor.node || removed.contains(anchor.node)) anchors.delete(id);
      signal();
    }

    function reset() {
      for (const map of [live, committed]) { for (const entry of map.values()) cancel(entry, true); map.clear(); }
      anchors.clear(); pendingReasoning.clear();
      signal();
    }
    const resume = () => { if (!document.hidden) for (const entry of live.values()) if (entry.needsPaint) schedule(entry); };
    const reduce = () => {
      if (!reducedMotion.matches) return;
      for (const map of [live, committed]) for (const entry of map.values()) {
        for (const token of entry.body.querySelectorAll('[data-stream-text]')) settleToken(token);
        for (const block of entry.body.querySelectorAll('.stream-block-enter')) block.classList.remove('stream-block-enter');
      }
    };
    document.addEventListener('visibilitychange', resume);
    reducedMotion.addEventListener('change', reduce);
    return { start, delta, done, resync, commitText, commitReasoning, anchorUser, endTurn, dropSession, dropNode, reset,
      destroy() { reset(); document.removeEventListener('visibilitychange', resume); reducedMotion.removeEventListener('change', reduce); },
      has: id => [...live.keys(), ...committed.keys()].some(value => value.endsWith(':' + id)) };
  }

  root.UAIStreamRenderer = { create, rateText };
  if (typeof module !== 'undefined') module.exports = root.UAIStreamRenderer;
})(typeof window !== 'undefined' ? window : globalThis);
