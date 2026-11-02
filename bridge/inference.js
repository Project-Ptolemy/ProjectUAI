'use strict';

const http = require('node:http');
const https = require('node:https');
const crypto = require('node:crypto');
const { StringDecoder } = require('node:string_decoder');
const { help } = require('./support');
const { optionsFor: openCodeTransportOptions } = require('./opencode-transport');

// Per-job normalized frame ring bounds. The ring is a browser projection only;
// the raw body accumulator (job.body) is kept separately for the Roblox poll and
// is never trimmed by these.
const RING_FRAMES = 4096;
const RING_BYTES = 4 * 1024 * 1024;
// The game's HTTP layer rejects any provider body over 8 MiB, so a job that can
// only produce an undeliverable body is failed fast rather than stalled.
const DELIVERABLE_MAX = 8 * 1024 * 1024;
const PREVIEW_PAGE_BYTES = 64 * 1024;
const PREVIEW_FRAME_BYTES = 8 * 1024;

// Requests live independently of the short executor polls. IDs are never reused
// during a server lifetime, even after response bodies expire.
function createInference({ publish = () => {}, maxBytes = 16 * 1024 * 1024,
  deliverableMax = DELIVERABLE_MAX, retentionMs = 300000, maxJobs = 10000,
  maxActive = 16, maxTotalBytes = 64 * 1024 * 1024, legacy = false,
  prepareBody = body => body, maxRequestBytes = 32 * 1024 * 1024, maxActiveRequestBytes = 64 * 1024 * 1024, opencode, kilo, cline } = {}) {
  const jobs = new Map();
  // A previously seen ID must never become resubmittable, even after its job is
  // evicted for capacity. The horizon remembers evicted IDs so a late resubmit
  // is answered with an expired tombstone instead of running a second time.
  const horizon = new Set();
  const instance = crypto.randomUUID();
  const effectiveMax = Math.min(deliverableMax, maxBytes);
  let retainedBytes = 0;
  let activeRequestBytes = 0;

  function releaseRequest(job) {
    activeRequestBytes -= job.requestBytes || 0;
    job.requestBytes = 0;
  }

  function rememberEvicted(id) {
    horizon.add(id);
  }

  function finish(job, state, error) {
    if (job.state !== 'running') return;
    job.state = state;
    job.error = error && state !== 'cancelled' ? help(error) : error;
    job.finishedAt = Date.now();
    releaseRequest(job);
    if (state !== 'completed') {
      retainedBytes -= job.bodyBytes || 0;
      job.body = ''; job.bodyBytes = 0;
    }
    const providerError = job.status >= 400 ? help('Provider returned HTTP ' + job.status) : undefined;
    publish({ kind: 'inference:done', id: job.id, sessionId: job.sessionId, state, error: job.error,
      status: job.status, providerError, streamed: !!job.streaming, sawText: !!job.sawText, overflow: !!job.ringDropped });
    job.request = undefined;
  }
  function previewPage(job, after) {
    const preview = { schema: 1, after, cursor: after, frames: [],
      model: typeof job.model === 'string' ? job.model.slice(0, 300) : undefined };
    if (after > job.seq || (job.ring[0]?.seq || job.seq + 1) > after + 1) {
      preview.gap = true; preview.cursor = job.seq; return preview;
    }
    let bytes = Buffer.byteLength(JSON.stringify(preview)) + 32;
    for (const rec of job.ring) {
      if (rec.seq <= after) continue;
      if (rec.channel !== 'text' && rec.channel !== 'reasoning') { preview.cursor = rec.seq; continue; }
      if (preview.frames.length >= 128) break;
      const raw = Buffer.from(rec.text);
      // A single oversized provider chunk cannot make a poll unbounded. Keep
      // its real UTF-8 prefix and mark the preview incomplete until the final.
      const text = raw.length > PREVIEW_FRAME_BYTES
        ? new StringDecoder('utf8').write(raw.subarray(0, PREVIEW_FRAME_BYTES)) : rec.text;
      const frame = { seq: rec.seq, channel: rec.channel, text };
      const size = Buffer.byteLength(JSON.stringify(frame)) + 1;
      if (bytes + size > PREVIEW_PAGE_BYTES) break;
      preview.frames.push(frame); preview.cursor = rec.seq; bytes += size;
      if (text !== rec.text) { preview.limited = true; break; }
    }
    return preview;
  }
  function view(job, after) {
    const result = { id: job.id, state: job.state, error: job.error, status: job.status,
      headers: job.headers, body: job.state === 'completed' ? job.body : undefined };
    // The final raw response stays byte-for-byte unchanged, without duplicate
    // preview payload that could push a valid receipt over its delivery limit.
    if (job.state === 'running' && Number.isSafeInteger(after) && after >= 0) result.preview = previewPage(job, after);
    return result;
  }

  // Push one normalized delta into the bounded ring, assigning its gapless seq.
  function pushFrame(job, rec) {
    job.seq += 1;
    rec.seq = job.seq;
    rec.size = Buffer.byteLength(JSON.stringify(rec));
    job.ring.push(rec);
    job.ringBytes += rec.size;
    retainedBytes += rec.size;
    job.frameCount += 1;
    if (job.firstFrameAt == null) job.firstFrameAt = Date.now();
    while (job.ring.length && (job.ring.length > RING_FRAMES || job.ringBytes > RING_BYTES || retainedBytes > maxTotalBytes)) {
      const dropped = job.ring.shift();
      job.ringBytes -= dropped.size;
      retainedBytes -= dropped.size;
      job.ringDropped = true;
    }
    return rec;
  }

  function publishDelta(job, rec) {
    if (!job.sessionId) return;
    if (legacy) { publish({ kind: 'inference:delta', id: job.id, sessionId: job.sessionId, frame: rec.frame }); return; }
    publish({ kind: 'inference:delta', id: job.id, sessionId: job.sessionId, seq: rec.seq,
      channel: rec.channel, text: rec.text, model: job.model, frame: rec.frame });
  }

  // Turn a parsed provider frame into zero or more {channel, text} deltas. text
  // is a string for text/reasoning; tool carries a small bounded object.
  function normalize(frame, job) {
    const out = [];
    if (!frame || typeof frame !== 'object') return out;
    // Gemini parts can mix visible text, thought summaries and complete calls.
    // Signatures and all other raw fields stay solely in the native response.
    if (Array.isArray(frame.candidates)) {
      const parts = frame.candidates[0]?.content?.parts;
      for (const part of Array.isArray(parts) ? parts : []) {
        if (typeof part?.text === 'string' && part.text) out.push({ channel: part.thought === true ? 'reasoning' : 'text', text: part.text });
        if (part?.functionCall && typeof part.functionCall === 'object') {
          const call = part.functionCall, summary = {};
          if (typeof call.name === 'string') summary.name = call.name.slice(0, 200);
          if (call.args && typeof call.args === 'object') summary.argsDelta = JSON.stringify(call.args).slice(0, 4096);
          if (Object.keys(summary).length) out.push({ channel: 'tool', text: summary });
        }
      }
      return out;
    }
    // OpenCode's Responses lane uses typed events and its own completion
    // marker. These previews never replace the raw body consumed by Roblox.
    if (frame.type === 'response.output_text.delta' && typeof frame.delta === 'string') {
      if (frame.delta) out.push({ channel: 'text', text: frame.delta });
      return out;
    }
    if (['response.reasoning_summary_text.delta', 'response.reasoning_text.delta'].includes(frame.type) && typeof frame.delta === 'string') {
      if (frame.delta) out.push({ channel: 'reasoning', text: frame.delta });
      return out;
    }
    if (frame.type === 'response.output_item.added' && frame.item?.type === 'function_call') {
      out.push({ channel: 'tool', text: { name: String(frame.item.name || '').slice(0, 200) } });
      return out;
    }
    if (frame.type === 'response.function_call_arguments.delta' && typeof frame.delta === 'string') {
      if (frame.delta) out.push({ channel: 'tool', text: { argsDelta: frame.delta.slice(0, 4096) } });
      return out;
    }
    if (frame.type === 'response.completed' && frame.response && typeof frame.response === 'object') {
      // Some gateways emit only the final output. Fill missing channels, but
      // never append the final copy to text already delivered as deltas.
      for (const item of Array.isArray(frame.response.output) ? frame.response.output : []) {
        if (item?.type === 'message' && !job.sawText) {
          for (const part of Array.isArray(item.content) ? item.content : []) {
            if (part?.type === 'output_text' && typeof part.text === 'string' && part.text) out.push({ channel: 'text', text: part.text });
          }
        } else if (item?.type === 'reasoning' && !job.sawReasoning) {
          for (const part of Array.isArray(item.summary) ? item.summary : []) {
            if (typeof part?.text === 'string' && part.text) out.push({ channel: 'reasoning', text: part.text });
          }
        }
      }
      return out;
    }
    // Anthropic streaming: typed events over a single content block.
    if (frame.type === 'content_block_delta' && frame.delta && typeof frame.delta === 'object') {
      const d = frame.delta;
      if (typeof d.text === 'string' && d.text) out.push({ channel: 'text', text: d.text });
      else if (typeof d.thinking === 'string' && d.thinking) out.push({ channel: 'reasoning', text: d.thinking });
      else if (typeof d.partial_json === 'string' && d.partial_json) out.push({ channel: 'tool', text: { argsDelta: d.partial_json.slice(0, 4096) } });
      return out;
    }
    if (frame.type === 'content_block_start' && frame.content_block && frame.content_block.type === 'tool_use') {
      out.push({ channel: 'tool', text: { name: String(frame.content_block.name || '').slice(0, 200) } });
      return out;
    }
    // OpenAI-compatible chat.completion chunks.
    for (const choice of Array.isArray(frame.choices) ? frame.choices : []) {
      const d = choice && choice.delta;
      if (!d || typeof d !== 'object') continue;
      if (typeof d.content === 'string' && d.content) out.push({ channel: 'text', text: d.content });
      const reasoning = d.reasoning_content != null ? d.reasoning_content : d.reasoning;
      if (typeof reasoning === 'string' && reasoning) out.push({ channel: 'reasoning', text: reasoning });
      for (const call of Array.isArray(d.tool_calls) ? d.tool_calls : []) {
        const fn = call && call.function;
        if (!fn) continue;
        const summary = {};
        if (fn.name) summary.name = String(fn.name).slice(0, 200);
        if (typeof fn.arguments === 'string') summary.argsDelta = fn.arguments.slice(0, 4096);
        if (Object.keys(summary).length) out.push({ channel: 'tool', text: summary });
      }
    }
    return out;
  }

  function onFrame(job, parsed) {
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return;
    if (job.model == null && typeof parsed.model === 'string') job.model = parsed.model;
    if (typeof parsed.modelVersion === 'string') job.model = parsed.modelVersion.slice(0, 300);
    if (parsed.type === 'message_start' && parsed.message && typeof parsed.message.model === 'string') job.model = parsed.message.model;
    if (parsed.response && typeof parsed.response.model === 'string') job.model = parsed.response.model;
    if (parsed.type === 'message_stop') job.sseDone = true;
    if (parsed.type === 'response.completed' && parsed.response && typeof parsed.response === 'object') job.sseDone = true;
    // Match the native adapters for compatible gateways that close after the
    // final reason without sending a separate sentinel. Completion still waits
    // for EOF, and a later streamed provider error remains terminal.
    if (Array.isArray(parsed.choices) && typeof parsed.choices[0]?.finish_reason === 'string' && parsed.choices[0].finish_reason) job.sseDone = true;
    if (parsed.type === 'message_delta' && typeof parsed.delta?.stop_reason === 'string' && parsed.delta.stop_reason) job.sseDone = true;
    // Google ends with finishReason rather than a [DONE] event. The adapter
    // interprets refusal/length semantics from the retained original body.
    if (typeof parsed.candidates?.[0]?.finishReason === 'string' && parsed.candidates[0].finishReason) job.sseDone = true;
    if (typeof parsed.promptFeedback?.blockReason === 'string' && parsed.promptFeedback.blockReason) job.sseDone = true;
    for (const delta of normalize(parsed, job)) {
      if (delta.channel === 'text') job.sawText = true;
      if (delta.channel === 'reasoning') job.sawReasoning = true;
      // The compatibility frame contains only this delta. Re-emitting a whole
      // provider frame for each channel would duplicate mixed text/reasoning in
      // older browsers and retain arbitrary provider payloads in replay memory.
      const part = delta.channel === 'text' ? { content: delta.text } : delta.channel === 'reasoning' ? { reasoning_content: delta.text } : {};
      const frame = typeof parsed.type === 'string' && parsed.type.startsWith('content_block_') ? {
        type: 'content_block_delta', delta: delta.channel === 'text' ? { text: delta.text } : delta.channel === 'reasoning' ? { thinking: delta.text } : {},
      } : { choices: [{ delta: part }] };
      publishDelta(job, pushFrame(job, { channel: delta.channel, text: delta.text, frame }));
    }
  }

  function start(input) {
    if (!input || typeof input.id !== 'string' || !/^[\w-]{8,100}$/.test(input.id)) throw new Error('Invalid request ID');
    if (input.instance !== instance) throw new Error('Bridge restarted; request was not resubmitted');
    if (typeof input.body !== 'string' || Buffer.byteLength(input.body) > maxBytes) throw new Error('Invalid inference body');
    const url = new URL(input.url);
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) throw new Error('Use an HTTP(S) provider URL');
    // This reserved address is an internal route, never an outbound HTTP host.
    const clineRoute = url.hostname.replace(/\.$/, '') === 'uai-tunnel.invalid';
    if (clineRoute && (url.hostname !== 'uai-tunnel.invalid' || url.protocol !== 'https:' || url.port || url.search || url.hash ||
        url.pathname !== '/cline/v1/chat/completions' || !cline)) {
      throw new Error('This bridge does not support the requested Cline tunnel route. Update UAI Bridge.');
    }
    const headers = {};
    for (const [name, value] of Object.entries(input.headers || {})) {
      // Older clients attached the executor's deadline as SDK metadata. It
      // must not impose a provider-side deadline on unlimited Cowork work.
      if (/^(host|connection|content-length|transfer-encoding|accept-encoding|x-stainless-timeout)$/i.test(name)) continue;
      http.validateHeaderName(name);
      http.validateHeaderValue(name, String(value));
      headers[name] = String(value);
    }
    if (clineRoute && Object.keys(headers).some(name => /authorization|api[-_]?key|token|cookie|organization/i.test(name))) {
      throw new Error('Cline uses its signed-in local profile. Set this provider authentication to None.');
    }
    headers['accept-encoding'] = 'identity';
    headers['content-length'] = Buffer.byteLength(input.body);
    const fingerprint = crypto.createHash('sha256').update(JSON.stringify([url.href,
      Object.entries(headers).sort(([a], [b]) => a.localeCompare(b)), input.body, input.sessionId])).digest('hex');
    const existing = jobs.get(input.id);
    if (existing) {
      if (existing.state === 'cancelled' && !existing.fingerprint) return view(existing);
      if (existing.fingerprint !== fingerprint) throw new Error('Request ID already belongs to a different payload');
      return view(existing);
    }
    // An ID that was evicted after being seen must never run again.
    if (horizon.has(input.id)) return { id: input.id, state: 'expired', error: 'Request expired and was evicted; do not resubmit' };
    if (horizon.size >= 50000) { const e = new Error('Bridge request history is full; restart the bridge while idle'); e.status = 503; throw e; }
    if (jobs.size >= maxJobs || [...jobs.values()].filter(j => j.state === 'running').length >= maxActive) { const e = new Error('Inference capacity reached'); e.status = 503; throw e; }
    // Check idempotency before reading image bytes: retries still return the
    // original job after its attachments expire, without another provider call.
    const providerBody = prepareBody(input.body, input.sessionId);
    const requestBytes = Buffer.byteLength(providerBody);
    if (requestBytes > maxRequestBytes || activeRequestBytes + requestBytes > maxActiveRequestBytes) {
      const e = new Error('Image request memory limit reached; wait for other requests or send fewer images'); e.status = 413; throw e;
    }
    headers['content-length'] = requestBytes;
    // Cowork inference has no elapsed-time limit. Legacy timeout fields are
    // deliberately ignored; only Stop, shutdown or a real failure ends a job.
    let model;
    try { const b = JSON.parse(input.body); if (b && typeof b.model === 'string') model = b.model; } catch { /* body need not be JSON */ }
    const job = { id: input.id, fingerprint, sessionId: input.sessionId, state: 'running', body: '', bytes: 0, bodyBytes: 0, wireBytes: 0,
      startedAt: Date.now(), seq: 0, frameCount: 0, ring: [], ringBytes: 0, ringDropped: false,
      firstFrameAt: null, sawText: false, model, requestBytes };
    jobs.set(job.id, job);
    const native = clineRoute ? cline : opencode?.capability().available && opencode.accepts(url.href, providerBody) ? opencode : null;
    if (native) {
      const controller = new AbortController();
      job.request = { destroy: () => controller.abort() };
      activeRequestBytes += requestBytes;
      if (job.sessionId) publish({ kind: 'inference:start', id: job.id, sessionId: job.sessionId, model: job.model, startedAt: job.startedAt });
      native.request({ body: providerBody, url: url.href, signal: controller.signal,
        onFrame: frame => { if (job.state === 'running') { job.streaming = true; onFrame(job, frame); } } }).then(result => {
        if (job.state !== 'running') return;
        job.status = result.status; job.headers = result.headers;
        const bytes = Buffer.byteLength(result.body);
        if (bytes > effectiveMax || retainedBytes + bytes > maxTotalBytes ||
          Buffer.byteLength(JSON.stringify({ ...view(job), state: 'completed', body: result.body })) > deliverableMax) {
          finish(job, 'failed', 'CLI response exceeds the deliverable limit; it will not be resubmitted'); return;
        }
        job.body = result.body; job.bodyBytes = bytes; retainedBytes += bytes;
        finish(job, 'completed');
      }, error => { if (job.state === 'running') finish(job, 'failed', String(error?.message || 'CLI request failed')); });
      return view(job);
    }
    const decoder = new StringDecoder('utf8');
    let buffer = '', eventName = '', dataLines = [], firstText = true;
    const secrets = Object.entries(headers).filter(([name]) => /authorization|api[-_]?key|token|secret/i.test(name))
      .flatMap(([, value]) => [value, value.replace(/^Bearer\s+/i, '')]);
    for (const [name, value] of url.searchParams) if (/key|token|secret|auth/i.test(name)) secrets.push(value);
    const streamFailure = (parsed, name) => {
      const type = typeof parsed?.type === 'string' ? parsed.type : name;
      const failed = ['error', 'response.failed', 'response.incomplete', 'response.cancelled'].includes(type)
        || ['error', 'response.failed', 'response.incomplete', 'response.cancelled'].includes(name)
        || !!parsed?.error || ['failed', 'incomplete', 'cancelled'].includes(parsed?.response?.status);
      if (!failed) return null;
      const detail = parsed?.error || parsed?.response?.error || parsed?.response?.incomplete_details || parsed;
      let message = typeof detail === 'string' ? detail : String(detail?.message || detail?.reason || detail?.code || type || 'provider error');
      for (const secret of secrets) if (secret.length >= 4) message = message.split(secret).join('[redacted]');
      message = message.replace(/Bearer\s+[^\s,;"'<>]+/gi, 'Bearer [redacted]').replace(/[\r\n\t]+/g, ' ').slice(0, 400);
      return 'Provider stream failed: ' + message;
    };
    const dispatchEvent = () => {
      if (!dataLines.length) { eventName = ''; return; }
      const payload = dataLines.join('\n'), name = eventName; dataLines = []; eventName = '';
      if (payload === '[DONE]') { job.sseDone = true; return; }
      let parsed;
      try { parsed = JSON.parse(payload); }
      catch {
        const failure = streamFailure(payload, name);
        request.destroy(); finish(job, 'failed', failure || 'Provider returned malformed streaming data'); return;
      }
      const failure = streamFailure(parsed, name);
      if (failure) { request.destroy(); finish(job, 'failed', failure); return; }
      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
        request.destroy(); finish(job, 'failed', 'Provider returned malformed streaming data'); return;
      }
      if (!parsed.type && name) parsed.type = name;
      onFrame(job, parsed);
    };
    const handleLine = raw => {
      const line = raw.endsWith('\r') ? raw.slice(0, -1) : raw;
      if (line === '') { dispatchEvent(); return; }
      if (line.startsWith(':')) return; // keepalive comment
      const colon = line.indexOf(':');
      const field = colon < 0 ? line : line.slice(0, colon);
      let value = colon < 0 ? '' : line.slice(colon + 1);
      if (value.startsWith(' ')) value = value.slice(1);
      if (field === 'data') dataLines.push(value);
      else if (field === 'event') eventName = value;
    };
    const drainLines = (final = false) => {
      for (;;) {
        const idx = buffer.search(/[\r\n]/);
        if (idx < 0 || (!final && buffer[idx] === '\r' && idx === buffer.length - 1)) return;
        const width = buffer[idx] === '\r' && buffer[idx + 1] === '\n' ? 2 : 1;
        const line = buffer.slice(0, idx); buffer = buffer.slice(idx + width);
        handleLine(line);
        if (job.state !== 'running') return;
      }
    };
    const consume = text => {
      if (job.state !== 'running') return;
      const bytes = Buffer.byteLength(text);
      if (retainedBytes + bytes > maxTotalBytes) {
        request.destroy(); finish(job, 'failed', 'Bridge response memory is full; wait for retained requests to expire'); return;
      }
      job.wireBytes += Buffer.byteLength(JSON.stringify(text)) - 2;
      if (job.wireBytes > deliverableMax) {
        request.destroy(); finish(job, 'failed', 'Provider response exceeds the deliverable limit after JSON encoding; it will not be resubmitted'); return;
      }
      job.body += text;
      job.bodyBytes += bytes; retainedBytes += bytes;
      if (job.state !== 'running' || !job.streaming) return;
      if (firstText && text) { firstText = false; text = text.replace(/^\uFEFF/, ''); }
      buffer += text;
      drainLines();
    };
    const transport = kilo?.accepts(url, headers, providerBody) ? kilo : url.protocol === 'https:' ? https : http;
    const request = transport.request(url, { method: 'POST', headers, ...(transport === https ? openCodeTransportOptions(url) : {}) }, response => {
      job.status = response.statusCode;
      job.headers = {};
      for (const name of ['content-type', 'retry-after', 'x-should-retry', 'x-request-id', 'server']) {
        if (response.headers[name]) job.headers[name] = response.headers[name];
      }
      // HTTP error bodies go back to Roblox unchanged, even when a provider
      // mistakenly labels its error page as an event stream.
      job.streaming = job.status >= 200 && job.status < 300 && String(response.headers['content-type'] || '').toLowerCase().includes('text/event-stream');
      response.on('data', chunk => {
        if (job.state !== 'running') return;
        job.bytes += chunk.length;
        if (job.bytes > effectiveMax) {
          finish(job, 'failed', job.bytes > maxBytes ? 'Provider response exceeds relay limit'
            : 'Provider response exceeds the deliverable limit; the game rejects a body this large and it will not be resubmitted');
          request.destroy(); return;
        }
        consume(decoder.write(chunk));
      });
      response.on('end', () => {
        if (job.state !== 'running') return;
        consume(decoder.end());
        if (job.state !== 'running') return;
        if (job.streaming) {
          drainLines(true);
          if (job.state !== 'running') return;
          if (buffer.length) { handleLine(buffer); buffer = ''; }
          if (job.state !== 'running') return;
          if (dataLines.length) dispatchEvent();
          if (job.state !== 'running') return;
        }
        if (job.streaming && job.status >= 200 && job.status < 300 && !job.sseDone) finish(job, 'failed', 'Provider stream ended before completion');
        else if (Buffer.byteLength(JSON.stringify({ ...view(job), state: 'completed', body: job.body })) > deliverableMax) {
          finish(job, 'failed', 'Provider response exceeds the deliverable limit after JSON encoding; it will not be resubmitted');
        } else finish(job, 'completed');
      });
      response.on('error', () => finish(job, 'failed', 'Provider response connection closed'));
    });
    job.request = request;
    // Node's shared agent may configure an idle socket timeout. Active provider
    // work belongs to this job until it answers or the user stops it.
    request.setTimeout(0);
    activeRequestBytes += requestBytes;
    request.on('finish', () => releaseRequest(job));
    request.on('error', () => finish(job, 'failed', 'Could not complete provider connection'));
    if (job.sessionId) publish({ kind: 'inference:start', id: job.id, sessionId: job.sessionId, model: job.model, startedAt: job.startedAt });
    request.end(providerBody);
    return view(job);
  }
  function cancel(id) {
    const job = jobs.get(id);
    if (!job) {
      if (typeof id !== 'string' || !/^[\w-]{8,100}$/.test(id) || horizon.has(id) || horizon.size >= 50000 || jobs.size >= maxJobs) return horizon.has(id);
      jobs.set(id, { id, state: 'cancelled', error: 'Stopped before submission', finishedAt: Date.now(), seq: 0, frameCount: 0, ring: [], ringBytes: 0, body: '' });
      return true;
    }
    const request = job.request;
    finish(job, 'cancelled', 'Stopped');
    request?.destroy();
    return true;
  }
  const cleanup = setInterval(() => {
    const now = Date.now();
    for (const [id, job] of jobs) {
      if (job.finishedAt && now - job.finishedAt > retentionMs && job.state !== 'expired') {
        retainedBytes -= (job.bodyBytes || 0) + (job.ringBytes || 0); job.bodyBytes = 0;
        job.body = ''; job.ring = []; job.ringBytes = 0; job.headers = undefined; job.request = undefined; job.state = 'expired'; job.expiredAt = now;
      }
      // Second stage: drop the expired tombstone but keep its ID on the horizon.
      if (job.state === 'expired' && job.expiredAt && now - job.expiredAt > Math.max(retentionMs, 60000)) {
        jobs.delete(id); rememberEvicted(id);
      }
    }
  }, Math.min(retentionMs, 10000));
  cleanup.unref();
  return { instance, start, get: (id, after) => jobs.has(id) ? view(jobs.get(id), after) : (horizon.has(id) ? { id, state: 'expired', error: 'Request expired and was evicted; do not resubmit' } : null), cancel,
    pending: () => [...jobs.values()].some(job => job.state === 'running' ||
      (!job.committed && job.finishedAt && Date.now() - job.finishedAt < retentionMs)),
    limits: { maxBytes, deliverableMax: effectiveMax },
    commit(id, sessionId) { const job = jobs.get(id); if (!job) return false; if (sessionId !== undefined && job.sessionId !== sessionId) return false; job.committed = true; return true; },
    previews(sessionId) {
      const out = [];
      for (const j of jobs.values()) {
        if (j.sessionId !== sessionId || j.committed) continue;
        if (!['running', 'completed', 'failed', 'cancelled'].includes(j.state)) continue;
        out.push({ kind: 'inference:start', id: j.id, sessionId, model: j.model, startedAt: j.startedAt });
        if (j.ringDropped) out.push({ kind: 'inference:resync', id: j.id, sessionId, from: j.ring[0]?.seq || j.seq + 1 });
        for (const rec of j.ring) out.push(legacy ? { kind: 'inference:delta', id: j.id, sessionId, frame: rec.frame } : { kind: 'inference:delta', id: j.id, sessionId, seq: rec.seq, channel: rec.channel, text: rec.text, model: j.model, frame: rec.frame });
        // Replay a terminal failure/partial-cancel so a fresh reconnect re-renders the
        // truthful error state instead of a silently missing turn. A pre-submission
        // cancel (no frames) is not surfaced as an error.
        if (j.state !== 'running') {
          out.push({ kind: 'inference:done', id: j.id, sessionId, state: j.state, error: j.error,
            providerError: j.status >= 400 ? help('Provider returned HTTP ' + j.status) : undefined,
            status: j.status, streamed: !!j.streaming, sawText: !!j.sawText, overflow: !!j.ringDropped });
        }
      }
      return out;
    },
    close() { clearInterval(cleanup); for (const id of jobs.keys()) cancel(id); } };
}
module.exports = { createInference };
