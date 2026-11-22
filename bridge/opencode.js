'use strict';

const RELEASE = require('./release');
const { INSTRUCTIONS, DESCRIPTION_PREFIX } = require('./environment');
const { isZenInference } = require('./opencode-transport');

// OpenCode owns the upstream connection. This adapter owns an isolated CLI
// server and returns UAI tool calls to Roblox without executing host tools.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const crypto = require('node:crypto');
const { spawn, execFile } = require('node:child_process');
const { once } = require('node:events');
const { isDeepStrictEqual } = require('node:util');
const { help } = require('./support');

const MAX_REPLY = 8 << 20;
const WAIT_MS = 150;
const HOST_ACTION = 'opencode_host_action';
const HOST_GUARD = 'project-uai.desktop-guard';
const HANDOFF_WAIT_MS = 5000;
const REQUIRED_ROUTES = ['/api/model', '/api/session', '/api/session/{sessionID}', '/api/session/{sessionID}/prompt',
  '/api/session/{sessionID}/message', '/api/session/{sessionID}/interrupt', '/api/session/{sessionID}/permission', '/api/experimental/mcp/{server}', '/api/plugin'];
const missing = 'OpenCode CLI not found. Install OpenCode Desktop or run npm install -g @opencode/cli, then restart Cowork.';
const pause = (ms, signal) => new Promise((resolve, reject) => {
  if (signal?.aborted) { reject(Error('Stopped')); return; }
  const abort = () => { clearTimeout(timer); reject(Error('Stopped')); };
  const timer = setTimeout(() => { signal?.removeEventListener('abort', abort); resolve(); }, ms);
  signal?.addEventListener('abort', abort, { once: true });
});

function official(url) {
  return isZenInference(url);
}

function nativeHeadersAllowed(headers) {
  if (headers === undefined) return true;
  if (!headers || typeof headers !== 'object' || Array.isArray(headers)) return false;
  for (const [name, value] of Object.entries(headers)) {
    if (/auth|api[-_]?key|token|secret|cookie|credential|organization|(?:^|[-_])org(?:[-_]?id)?$/i.test(name) &&
        !(name.toLowerCase() === 'authorization' && value === 'Bearer public')) return false;
  }
  return true;
}

function findBinaries(env = process.env, platform = process.platform, arch = process.arch) {
  const value = name => env[name] ?? (platform === 'win32' ? env[Object.keys(env).find(key => key.toLowerCase() === name.toLowerCase())] : undefined);
  if (value('UAI_OPENCODE_DISABLED') === '1') return [];
  const clean = entry => typeof entry === 'string' ? entry.trim().replace(/^"(.*)"$/, '$1') : '';
  const windows = platform === 'win32', extension = windows ? '.exe' : '';
  const cli = 'opencode-cli' + extension, command = 'opencode' + extension;
  const candidates = new Set(), modules = new Set();
  const add = file => { if (file && path.isAbsolute(file)) candidates.add(file); };
  const addModules = folder => { if (folder && path.isAbsolute(folder)) modules.add(folder); };
  const addBin = folder => {
    folder = clean(folder);
    if (!path.isAbsolute(folder)) return;
    add(path.join(folder, cli));
    add(path.join(folder, 'resources', cli));
    // A Desktop launcher on PATH has the same name as the CLI on Windows.
    if (!windows || !fs.existsSync(path.join(folder, 'resources', 'app.asar'))) add(path.join(folder, command));
    addModules(path.join(folder, 'node_modules'));
    if (path.basename(folder) === '.bin') addModules(path.dirname(folder));
    if (!windows) addModules(path.join(path.dirname(folder), 'lib', 'node_modules'));
  };
  const override = value('UAI_OPENCODE_BINARY');
  if (override) add(clean(override));
  else {
    const home = clean(value(windows ? 'USERPROFILE' : 'HOME') || value('HOME'));
    const local = clean(value('LOCALAPPDATA')), roaming = clean(value('APPDATA'));
    if (windows) {
      for (const root of [local && path.join(local, 'Programs'), value('ProgramFiles'), value('ProgramFiles(x86)'), local]) {
        if (!root || !path.isAbsolute(root)) continue;
        for (const name of ['@opencodedesktop', 'OpenCode']) {
          add(path.join(root, name, 'resources', cli));
          add(path.join(root, name, cli));
        }
      }
    } else if (platform === 'darwin') {
      for (const root of [home && path.join(home, 'Applications'), '/Applications'].filter(Boolean)) {
        add(path.join(root, 'OpenCode.app', 'Contents', 'Resources', cli));
        add(path.join(root, 'OpenCode.app', 'Contents', 'MacOS', cli));
      }
    }
    for (const folder of (value('PATH') || '').split(windows ? ';' : ':')) addBin(folder);
    for (const folder of [value('NPM_CONFIG_PREFIX'), value('NVM_SYMLINK'), value('NVM_BIN'),
      windows && roaming && path.join(roaming, 'npm'), windows && value('ProgramFiles') && path.join(value('ProgramFiles'), 'nodejs'),
      home && path.join(home, '.opencode', 'bin'), home && path.join(home, '.local', 'bin')]) if (folder) addBin(folder);
    const bun = clean(value('BUN_INSTALL') || (home && path.join(home, '.bun')));
    if (bun && path.isAbsolute(bun)) {
      addBin(path.join(bun, 'bin'));
      addModules(path.join(bun, 'install', 'global', 'node_modules'));
    }
    const pnpm = clean(value('PNPM_HOME'));
    if (pnpm && path.isAbsolute(pnpm)) { addBin(pnpm); addModules(path.join(pnpm, 'global', '5', 'node_modules')); }
    // npm and Bun expose shell shims on Windows. Resolve their installed native
    // payloads directly instead of asking a shell to interpret the shim.
    const nativePlatform = windows ? 'windows' : platform;
    const variant = arch === 'x64' ? ['-baseline', ''] : [''];
    for (const folder of modules) {
      for (const name of ['@opencode/cli', 'opencode-ai']) {
        const packageRoot = path.join(folder, name);
        add(path.join(packageRoot, 'bin', command));
        add(path.join(packageRoot, 'bin', '.opencode'));
        for (const suffix of variant) {
          const dependency = (name === '@opencode/cli' ? '@opencode/cli-' : 'opencode-') + nativePlatform + '-' + arch + suffix;
          add(path.join(packageRoot, 'node_modules', dependency, 'bin', command));
          add(path.join(folder, dependency, 'bin', command));
        }
      }
    }
  }
  const installed = new Set();
  for (const candidate of candidates) {
    let descriptor;
    try {
      if (!fs.statSync(candidate).isFile()) continue;
      fs.accessSync(candidate, windows ? fs.constants.F_OK : fs.constants.X_OK);
      descriptor = fs.openSync(candidate, 'r');
      const header = Buffer.alloc(4);
      if (fs.readSync(descriptor, header, 0, 4, 0) !== 4) continue;
      const native = windows ? header[0] === 0x4d && header[1] === 0x5a
        : platform === 'darwin' ? ['feedface', 'feedfacf', 'cefaedfe', 'cffaedfe', 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca'].includes(header.toString('hex'))
          : header.equals(Buffer.from([0x7f, 0x45, 0x4c, 0x46]));
      if (native) installed.add(fs.realpathSync(candidate));
    } catch { /* Missing, inaccessible or shell-only installation; try the next native payload. */ }
    finally { if (descriptor !== undefined) fs.closeSync(descriptor); }
  }
  return [...installed];
}

function findBinary(env = process.env, platform = process.platform, arch = process.arch) {
  return findBinaries(env, platform, arch)[0] || null;
}

function jsonRequest(base, password, route, method = 'GET', body, signal, timeout = 5000) {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) { reject(Error('Stopped')); return; }
    const bytes = body === undefined ? null : Buffer.from(JSON.stringify(body));
    const req = http.request(base + route, { method, signal, headers: {
      authorization: 'Basic ' + Buffer.from('opencode:' + password).toString('base64'),
      accept: 'application/json', ...(bytes ? { 'content-type': 'application/json', 'content-length': bytes.length } : {})
    } }, res => {
      const chunks = []; let size = 0;
      res.on('data', chunk => { size += chunk.length; if (size > MAX_REPLY) req.destroy(Error('OpenCode response exceeds the relay limit')); else chunks.push(chunk); });
      res.on('error', () => reject(Error('OpenCode local response was interrupted')));
      res.on('end', () => {
        if (res.statusCode < 200 || res.statusCode >= 300) { reject(Error('OpenCode local API returned HTTP ' + res.statusCode)); return; }
        if (res.statusCode === 204) { resolve(null); return; }
        try { resolve(JSON.parse(Buffer.concat(chunks).toString('utf8'))); }
        catch { reject(Error('OpenCode returned an incompatible API response; update OpenCode Desktop')); }
      });
    });
    if (timeout) req.setTimeout(timeout, () => req.destroy(Error('OpenCode local API did not respond')));
    req.on('error', reject); req.end(bytes);
  });
}

function toolDefinitions(body) {
  if (!Array.isArray(body.tools)) return [];
  const seen = new Set();
  // Filter the actual direct-wire placeholders, not every UAI tool that shares
  // a native name. The native CLI supplies its own guarded host schemas.
  const legacy = { bash: ['Execute bash command', 'command', 'The command to run'], read: ['Read file', 'path', 'The path to the file'],
    edit: ['Edit file', 'path', 'The path to the file'], glob: ['Find files', 'pattern', 'Glob pattern'],
    grep: ['Search pattern', 'pattern', 'Regex pattern'], list: ['List files', 'path', 'Directory path'],
    shell: ['Execute shell command', 'command', 'The command to run'] };
  const placeholder = tool => {
    const f = tool?.function || tool, expected = Object.hasOwn(legacy, f?.name) ? legacy[f.name] : null;
    if (!expected || tool?.type !== 'function') return false;
    const [description, field, fieldDescription] = expected;
    const parameters = { type: 'object', properties: { [field]: { type: 'string', description: fieldDescription } },
      ...(f.name === 'list' ? {} : { required: [field] }) };
    return (f.description === description || f.description === 'OpenCode compatibility declaration only. This tool does not execute in Roblox; use the supplied Project UAI tools.')
      && isDeepStrictEqual(f.parameters, parameters);
  };
  return body.tools.filter(tool => !placeholder(tool)).map(tool => {
    const f = tool?.type === 'function' ? tool.function || tool : null;
    if (!f || typeof f.name !== 'string' || !/^[a-zA-Z0-9_-]{1,100}$/.test(f.name) || seen.has(f.name) || f.name === HOST_ACTION) throw Error('OpenCode requires unique UAI function tools; opencode_host_action is reserved for blocked desktop actions');
    seen.add(f.name);
    return { name: f.name, description: String(f.description || ''), inputSchema: f.parameters || { type: 'object', properties: {} } };
  });
}

function promptFor(body) {
  const source = body.messages || body.input;
  if (!Array.isArray(source) && typeof source !== 'string') throw Error('OpenCode requires a conversation');
  // No history is carried between native sessions: the caller's compacted
  // messages and tool results remain the sole conversation of record.
  const instructions = [
    'You are Project UAI, operating in Roblox through its supplied remote tools.',
    'The JSON below is the conversation to continue. Respect its system/developer instructions and message roles.',
    'Only the uai MCP tools act in Roblox. They are exposed directly as uai_<original tool name>. Call these top-level tools directly; never use execute, search, filesystem, terminal, web, task, permission or other host tools.',
    'Tool names in the conversation and tool feedback use their original Roblox names. For example, file_read means uai_file_read and run_luau means uai_run_luau here. Use each supplied tool\'s declared arguments.',
    'An opencode_host_action result records a desktop tool that was blocked before execution. Continue the user\'s work with the suggested uai tools; do not repeat that desktop action or call the receipt tool.',
    'Return the assistant answer or call the requested uai tools. Tool results will arrive in the next conversation. Do not invent results.',
  ];
  if (typeof body.instructions === 'string') instructions.push(body.instructions);
  return instructions.join('\n') + '\n\nConversation:\n' + JSON.stringify(source);
}

function promptInput(body) {
  const files = [], source = body.messages || body.input;
  const conversation = Array.isArray(source) ? source.map(message => {
    if (!Array.isArray(message?.content)) return message;
    return { ...message, content: message.content.map(part => {
      if (!['image_url', 'input_image'].includes(part?.type)) return part;
      const uri = typeof part.image_url === 'string' ? part.image_url : part.image_url?.url;
      if (typeof uri !== 'string' || !/^data:image\/(?:png|jpeg|webp);base64,[A-Za-z0-9+/=]+$/.test(uri))
        throw Error('OpenCode needs images attached through Cowork; reattach the picture or use another image-capable provider.');
      if (files.length >= 8 || Buffer.byteLength(uri) > 8 << 20) throw Error('OpenCode image attachment limit reached');
      const number = files.length + 1;
      files.push({ uri, name: 'image-' + number + '.' + (/^data:image\/jpeg/.test(uri) ? 'jpg' : /^data:image\/webp/.test(uri) ? 'webp' : 'png') });
      return { type: 'text', text: '[Attached image ' + number + ' for this message]' };
    }) };
  }) : source;
  const normalized = { ...body, ...(body.messages ? { messages: conversation } : { input: conversation }) };
  return { text: promptFor(normalized), ...(files.length ? { files } : {}) };
}

function responseBody(model, message, calls, responses) {
  const parts = Array.isArray(message?.content) ? message.content : [];
  const text = parts.filter(p => p.type === 'text').map(p => p.text || '').join('');
  const reasoning = parts.filter(p => p.type === 'reasoning').map(p => p.text || '').join('');
  const id = 'uai_' + crypto.randomBytes(12).toString('hex');
  const tokens = message?.tokens;
  // Native input/output contain only uncached input and visible output.
  // OpenAI-compatible totals include cache reads/writes and reasoning.
  const promptTokens = (tokens?.input || 0) + (tokens?.cache?.read || 0) + (tokens?.cache?.write || 0);
  const completionTokens = (tokens?.output || 0) + (tokens?.reasoning || 0);
  const usage = tokens ? { prompt_tokens: promptTokens, completion_tokens: completionTokens,
    total_tokens: promptTokens + completionTokens, cache_creation_input_tokens: tokens.cache?.write || 0,
    prompt_tokens_details: { cached_tokens: tokens.cache?.read || 0 }, completion_tokens_details: { reasoning_tokens: tokens.reasoning || 0 } } : undefined;
  if (responses) {
    const output = [];
    if (reasoning) output.push({ type: 'reasoning', summary: [{ type: 'summary_text', text: reasoning }] });
    if (text) output.push({ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] });
    for (const call of calls) output.push({ type: 'function_call', id: call.id, call_id: call.id, name: call.name, arguments: JSON.stringify(call.arguments) });
    return { id, object: 'response', model, status: message?.finish === 'length' ? 'incomplete' : 'completed', output,
      ...(tokens ? { usage: { input_tokens: usage.prompt_tokens, output_tokens: usage.completion_tokens, total_tokens: usage.total_tokens,
        cache_creation_input_tokens: usage.cache_creation_input_tokens,
        input_tokens_details: usage.prompt_tokens_details, output_tokens_details: usage.completion_tokens_details } } : {}) };
  }
  const result = { role: 'assistant', content: text || null };
  if (reasoning) result.reasoning_content = reasoning;
  if (calls.length) result.tool_calls = calls.map(call => ({ id: call.id, type: 'function', function: { name: call.name, arguments: JSON.stringify(call.arguments) } }));
  return { id, object: 'chat.completion', model, ...(usage ? { usage } : {}), choices: [{ index: 0, message: result,
    finish_reason: message?.finish === 'length' ? 'length' : calls.length ? 'tool_calls' : 'stop' }] };
}

// A native tool choice is recoverable only while its permission is still held.
// The receipt never carries executable host arguments or an original tool name
// that could collide with a Roblox/custom handler. Correction belongs to UAI's
// next ordinary agent step, with the caller's history as the source of truth.
function toolHandoff(parts, tools, job, permissions, messageID, sessionID) {
  const ids = new Set(), used = new Set(), calls = [];
  let remoteCount = 0, waiting = false;
  if (parts.length > 64) throw Error('OpenCode returned too many tool calls');
  for (const part of parts) {
    if (typeof part.id !== 'string' || !/^[\w-]{1,160}$/.test(part.id) || ids.has(part.id) ||
        typeof part.name !== 'string' || !/^[\w-]{1,100}$/.test(part.name))
      throw Error('OpenCode returned an invalid tool handoff');
    ids.add(part.id);
    if (part.executed !== true && part.state?.status === 'streaming') { waiting = true; continue; }
    if (part.executed === true || part.state?.status !== 'running' || !part.state.input || typeof part.state.input !== 'object' || Array.isArray(part.state.input))
      throw Error('OpenCode could not hand off the requested tool call. No desktop action was approved; the request was not repeated.');
    if (tools.some(tool => 'uai_' + tool.name === part.name)) {
      remoteCount++;
      const index = job.calls.findIndex((call, i) => !used.has(i) && 'uai_' + call.name === part.name && isDeepStrictEqual(call.arguments, part.state.input));
      if (index < 0) waiting = true;
      else { used.add(index); calls.push(job.calls[index]); }
    } else {
      if (!permissions.some(permission => permission?.sessionID === sessionID && permission?.action === HOST_ACTION &&
          permission?.source?.type === 'tool' && permission.source.id === part.id && permission.source.messageID === messageID)) waiting = true;
      else calls.push({ id: 'call_' + crypto.randomBytes(12).toString('hex'), name: HOST_ACTION, arguments: { name: part.name } });
    }
  }
  if (permissions.some(permission => permission?.action !== HOST_ACTION || permission?.sessionID !== sessionID || permission?.source?.messageID !== messageID ||
      !parts.some(part => part.id === permission?.source?.id && permission.source.type === 'tool' &&
        !tools.some(tool => 'uai_' + tool.name === part.name))))
    throw Error('OpenCode returned a permission that could not be matched to a blocked desktop tool.');
  if (!parts.some(part => part.state?.status === 'streaming') &&
      (job.calls.length > remoteCount || (used.size !== job.calls.length && job.calls.length === remoteCount)))
    throw Error('OpenCode returned an unmatched tool call');
  return waiting ? null : calls;
}

function createOpenCode({ env = process.env, binary, binaryArgs = [], startupMs = 30000, pollMs = WAIT_MS } = {}) {
  let child, directory, base, password, rpcServer, rpcSecret, starting, closed = false;
  const enabled = env.UAI_OPENCODE_DISABLED !== '1';
  const binaries = !enabled ? [] : binary === undefined ? findBinaries(env) : binary ? [binary] : [];
  binary = binaries[0] || null;
  const unavailable = env.UAI_OPENCODE_BINARY ? 'The configured OpenCode CLI was not found. Check UAI_OPENCODE_BINARY, then restart Cowork.' : missing;
  let state = !enabled ? 'disabled' : binary ? 'starting' : 'missing', modelsCache = [], version;
  let failure = 'OpenCode could not start. Update OpenCode Desktop and restart Cowork.';
  const jobs = new Map();
  const killOwnedChild = () => { if (child && child.exitCode === null && child.signalCode === null) child.kill(); };
  process.once('exit', killOwnedChild);
  const api = (route, method, body, signal, timeout) => jsonRequest(base, password, route, method, body, signal, timeout);
  const capability = () => ({ schema: 1, enabled, available: !!binary && !closed && state !== 'failed', state, models: '/api/opencode/models',
    ...(binary ? { binary: path.basename(binary) } : {}), ...(version ? { version } : {}),
    ...(state === 'disabled' ? { message: 'OpenCode tunnel is turned off. Enable it in the desktop app, then start Cowork again.' }
      : state === 'missing' ? { message: help(unavailable) } : state === 'failed' ? { message: help(failure) } : {}) });

  async function start() {
    if (closed) throw Error('OpenCode bridge stopped');
    if (!enabled) throw Error('OpenCode tunnel is turned off');
    if (!binary) throw Error(unavailable);
    if (starting) return starting;
    starting = (async () => {
      directory = fs.mkdtempSync(path.join(os.tmpdir(), 'project-uai-opencode-'));
      rpcSecret = crypto.randomBytes(32).toString('hex');
      password = crypto.randomBytes(32).toString('hex');
      rpcServer = http.createServer((req, res) => {
        if (req.url === '/guard' && req.method === 'POST' && req.headers.origin === undefined &&
            req.headers.authorization === 'Bearer ' + rpcSecret) {
          let size = 0; const chunks = [];
          req.on('error', () => {});
          req.on('data', chunk => { size += chunk.length; if (size > 4096) req.destroy(); else chunks.push(chunk); });
          req.on('end', () => {
            let input;
            try { input = JSON.parse(Buffer.concat(chunks).toString()); } catch { res.writeHead(400); res.end(); return; }
            if (!input || typeof input.sessionID !== 'string' || typeof input.tool !== 'string') { res.writeHead(400); res.end(); return; }
            const job = [...jobs.values()].find(value => value.session === input.sessionID);
            const allowed = !!job && job.tools.some(tool => 'uai_' + tool.name === input.tool);
            res.writeHead(200, { 'content-type': 'application/json' }); res.end(JSON.stringify({ allowed }));
          });
          return;
        }
        const job = jobs.get(req.url?.slice('/mcp/'.length));
        if (req.method !== 'POST' || !req.url?.startsWith('/mcp/') || !job || req.headers.origin !== undefined ||
            req.headers.authorization !== 'Bearer ' + rpcSecret) { res.writeHead(403); res.end(); return; }
        let size = 0; const chunks = [];
        const hold = () => { if (!job.pending.has(res)) { job.pending.add(res); res.on('close', () => job.pending.delete(res)); } };
        req.on('error', () => {});
        req.on('data', chunk => {
          size += chunk.length;
          if (size > 1 << 20) { job.failure = 'OpenCode returned oversized tool arguments'; hold(); }
          else chunks.push(chunk);
        });
        req.on('end', () => {
          if (job.failure) return;
          let input;
          try { input = JSON.parse(Buffer.concat(chunks).toString()); } catch { res.writeHead(400); res.end(); return; }
          const reply = result => { res.writeHead(200, { 'content-type': 'application/json' }); res.end(JSON.stringify({ jsonrpc: '2.0', id: input.id, result })); };
          if (input.method === 'initialize') reply({ protocolVersion: '2024-11-05', capabilities: { tools: {} }, serverInfo: { name: 'Project UAI', version: RELEASE.version }, instructions: INSTRUCTIONS });
          else if (input.method === 'tools/list') reply({ tools: job.tools.map(tool => ({ ...tool, description: DESCRIPTION_PREFIX + (tool.description || '') })) });
          else if (input.method === 'tools/call') {
            const name = input.params?.name, args = input.params?.arguments;
            const argumentBytes = Buffer.byteLength(JSON.stringify(args || {}));
            if (!job.tools.some(tool => tool.name === name) || !args || typeof args !== 'object' || Array.isArray(args) || job.calls.length >= 64 ||
                job.argumentBytes + argumentBytes > 256000) {
              job.failure = 'OpenCode returned invalid or oversized tool arguments'; hold(); return;
            }
            job.argumentBytes += argumentBytes;
            job.calls.push({ id: 'call_' + crypto.randomBytes(12).toString('hex'), name, arguments: args });
            // Hold the result. Roblox must execute the call; returning a fake
            // result here would let the native agent take a second model turn.
            hold();
          } else if (input.id === undefined) { res.writeHead(202); res.end(); }
          else reply({});
        });
      });
      rpcServer.listen(0, '127.0.0.1'); await once(rpcServer, 'listening');
      const reserve = http.createServer(); reserve.listen(0, '127.0.0.1'); await once(reserve, 'listening');
      const port = reserve.address().port; await new Promise(resolve => reserve.close(resolve));
      if (closed) throw Error('OpenCode bridge stopped');
      base = 'http://127.0.0.1:' + port;
      // The CLI's execute wrapper and several internal helpers have no native
      // permission check. Install an awaited gate before every host tool, while
      // retaining the schemas required by OpenCode's free-model endpoint.
      const guard = path.join(directory, 'guard'); fs.mkdirSync(guard);
      fs.writeFileSync(path.join(guard, 'package.json'), JSON.stringify({ type: 'module' }));
      fs.writeFileSync(path.join(guard, 'server.js'), `export default {
  id: ${JSON.stringify(HOST_GUARD)},
  async setup(ctx) {
    const hook = await ctx.tool.hook('execute.before', async event => {
      const response = await fetch(${JSON.stringify('http://127.0.0.1:' + rpcServer.address().port + '/guard')}, {
        method: 'POST', signal: AbortSignal.timeout(5000),
        headers: { authorization: ${JSON.stringify('Bearer ' + rpcSecret)}, 'content-type': 'application/json' },
        body: JSON.stringify({ sessionID: event.sessionID, tool: event.tool })
      });
      if (!response.ok) throw Error('Project UAI desktop guard unavailable');
      if ((await response.json()).allowed === true) return;
      await ctx.permission.assert({ sessionID: event.sessionID, agent: event.agent,
        action: ${JSON.stringify(HOST_ACTION)}, resources: ['*'],
        source: { type: 'tool', messageID: event.messageID, id: event.id } });
      throw Error('Project UAI desktop tools cannot execute');
    });
    return () => hook.dispose();
  }
};\n`);
      const config = { update: 'disable', share: 'disabled', snapshots: false, lsp: false, formatter: false,
        plugins: [guard],
        permissions: [{ action: '*', resource: '*', effect: 'ask' }], agents: { uai: { mode: 'primary',
          system: 'Continue the supplied Project UAI Roblox conversation. Only call its uai MCP tools. Never execute host tools.' } } };
      const isolated = { ...env, OPENCODE_SERVER_PASSWORD: password, OPENCODE_SERVER_USERNAME: 'opencode',
        OPENCODE_CONFIG_CONTENT: JSON.stringify(config), OPENCODE_CONFIG: '', OPENCODE_CONFIG_DIR: '',
        XDG_DATA_HOME: path.join(directory, 'data'), XDG_CONFIG_HOME: path.join(directory, 'config'),
        XDG_CACHE_HOME: path.join(directory, 'cache'), XDG_STATE_HOME: path.join(directory, 'state') };
      for (const name of Object.keys(isolated)) {
        if (/(?:^|_)(?:API_KEY|API_TOKEN|ACCESS_TOKEN|AUTH_TOKEN|SECRET_KEY)$/.test(name) || name === 'OPENCODE_AUTH_JSON') delete isolated[name];
      }
      for (const candidate of binaries) {
        if (closed) throw Error('OpenCode bridge stopped');
        binary = candidate; state = 'starting'; modelsCache = [];
        failure = 'OpenCode could not start. Update OpenCode Desktop and restart Cowork.';
        // Probe each installed native candidate before admitting inference. An
        // old PATH installation must not hide a compatible npm/Desktop copy.
        version = await new Promise(resolve => execFile(binary, [...binaryArgs, '--version'],
          { cwd: directory, env: isolated, windowsHide: true, timeout: 4000, maxBuffer: 4096 }, (error, stdout) => {
            const match = !error && /^(?:opencode\s+)?v?(\d+\.\d+\.\d+(?:[-+][\w.-]+)?)\s*$/i.exec(stdout.trim());
            resolve(match ? match[1] : undefined);
          }));
        if (closed) throw Error('OpenCode bridge stopped');
        const owned = spawn(binary, [...binaryArgs, 'serve', '--port', String(port), '--hostname', '127.0.0.1'],
          { cwd: directory, env: isolated, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
        child = owned;
        let exited = false;
        owned.stdout.resume(); owned.stderr.resume(); // Never expose credentials or provider output in launcher logs.
        const ended = () => { exited = true; if (!closed && child === owned && state === 'ready') state = 'failed'; };
        owned.on('error', ended); owned.on('exit', ended);
        const expires = Date.now() + startupMs;
        while (!closed && !exited && Date.now() < expires) {
          try {
            const spec = await api('/openapi.json');
            if (!REQUIRED_ROUTES.every(route => spec.paths?.[route])) {
              failure = 'OpenCode CLI' + (version ? ' ' + version : '') + ' has an incompatible server API. Install OpenCode Desktop v2 or npm install -g @opencode/cli, then restart Cowork.';
              break;
            }
            const list = await api('/api/model');
            modelsCache = modelRows(list);
            await verifyGuard();
            if (modelsCache.length && !exited) { state = 'ready'; return; }
            failure = 'OpenCode is installed but returned no supported free models. Update OpenCode and restart Cowork.';
          } catch { /* The native server and its built-in provider plugin start independently. */ }
          await pause(pollMs);
        }
        if (closed) throw Error('OpenCode bridge stopped');
        // Never overlap two owned servers or change binaries after admission.
        if (owned.pid && owned.exitCode === null && owned.signalCode === null) {
          const stopped = once(owned, 'exit').catch(() => {});
          owned.kill(); await Promise.race([stopped, pause(2500)]);
          if (owned.exitCode === null && owned.signalCode === null) {
            failure = 'OpenCode did not stop during setup. Stop and start Cowork to try again.';
            break;
          }
        }
      }
      state = 'failed';
      throw Error(failure);
    })().catch(error => { if (!closed) state = 'failed'; throw error; });
    return starting;
  }

  function modelRows(value) {
    if (!Array.isArray(value?.data)) throw Error('OpenCode returned an invalid model catalog');
    return value.data.filter(item => item?.providerID === 'opencode' && typeof item.id === 'string' &&
      Array.isArray(item.cost) && item.cost.length > 0 && item.cost.every(tier =>
        tier.input === 0 && tier.output === 0 && tier.cache?.read === 0 && tier.cache?.write === 0)).map(item => ({
      id: item.id, object: 'model', owned_by: 'opencode', name: item.name,
      ...(item.limit ? { context_length: item.limit.context, max_output_tokens: item.limit.output } : {}),
      ...(item.capabilities ? { capabilities: item.capabilities } : {})
    }));
  }

  async function models() {
    await start();
    modelsCache = modelRows(await api('/api/model'));
    return { object: 'list', data: modelsCache };
  }

  async function verifyGuard(query = '', signal) {
    const expires = Date.now() + HANDOFF_WAIT_MS;
    do {
      const plugins = await api('/api/plugin' + query, 'GET', undefined, signal);
      const guard = plugins?.data?.find(plugin => plugin.id === HOST_GUARD);
      if (guard?.state?.status === 'active') return;
      if (guard?.state?.status === 'failed') break;
      await pause(pollMs, signal);
    } while (!closed && Date.now() < expires);
    throw Error('OpenCode desktop tool guard did not load. Update OpenCode Desktop and restart Cowork.');
  }

  async function request({ body, url, signal, onFrame = () => {} }) {
    await start();
    if (signal?.aborted || closed) throw Error('Stopped');
    if (!official(url)) throw Error('Unsupported OpenCode endpoint');
    const input = JSON.parse(body), tools = toolDefinitions(input);
    if (typeof input.model !== 'string' || !input.model) throw Error('Choose an OpenCode model');
    const prompt = promptInput(input);
    const key = crypto.randomBytes(16).toString('hex'), location = path.join(directory, key);
    fs.mkdirSync(location);
    const job = { tools, calls: [], argumentBytes: 0, pending: new Set() }; jobs.set(key, job);
    const locationQuery = '?location[directory]=' + encodeURIComponent(location);
    let session, registered = false;
    const abort = () => { if (session) api('/api/session/' + session + '/interrupt', 'POST', {}).catch(() => {}); };
    signal?.addEventListener('abort', abort, { once: true });
    try {
      if (tools.length) {
        registered = true;
        await api('/api/experimental/mcp/uai' + locationQuery, 'PUT', { config: { type: 'remote',
          url: 'http://127.0.0.1:' + rpcServer.address().port + '/mcp/' + key,
          headers: { Authorization: 'Bearer ' + rpcSecret }, oauth: false, codemode: false, protocol: 'legacy' } }, signal);
      }
      const created = await api('/api/session', 'POST', { title: 'Project UAI temporary request', agent: 'uai',
        location: { directory: location }, model: { id: input.model.replace(/^opencode\//, ''), providerID: 'opencode' },
        permissions: [{ action: '*', resource: '*', effect: 'ask' },
          ...tools.map(tool => ({ action: 'uai_' + tool.name, resource: '*', effect: 'allow' }))] }, signal);
      session = created?.data?.id;
      if (typeof session !== 'string' || !/^[\w-]+$/.test(session)) throw Error('OpenCode returned an invalid session');
      job.session = session;
      await verifyGuard(locationQuery, signal);
      await api('/api/session/' + session + '/prompt', 'POST', prompt, signal);
      let message, calls, handoffWaitingAt, textSize = 0, reasoningSize = 0;
      for (;;) {
        if (closed || signal?.aborted || state !== 'ready') throw Error(signal?.aborted ? 'Stopped' : 'OpenCode stopped during the request');
        if (job.failure) throw Error(job.failure);
        const page = await api('/api/session/' + session + '/message?limit=20&order=desc', 'GET', undefined, signal);
        message = page?.data?.find(value => value.type === 'assistant');
        if (message?.error) throw Error('OpenCode provider rejected the request (' + String(message.error.type || message.error.name || 'provider_error').replace(/[^\w.-]/g, '').slice(0, 80) + '). Check the model availability in OpenCode Desktop.');
        const parts = Array.isArray(message?.content) ? message.content : [];
        const text = parts.filter(part => part.type === 'text').map(part => part.text || '').join('');
        const reasoning = parts.filter(part => part.type === 'reasoning').map(part => part.text || '').join('');
        if (text.length > textSize) onFrame({ choices: [{ delta: { content: text.slice(textSize) } }] });
        if (reasoning.length > reasoningSize) onFrame({ choices: [{ delta: { reasoning_content: reasoning.slice(reasoningSize) } }] });
        textSize = text.length; reasoningSize = reasoning.length;
        const nativeTools = parts.filter(part => part.type === 'tool');
        // OpenCode v2 records time.streamed when the provider stream ends,
        // before waiting for MCP results. time.completed waits for those
        // results, which intentionally remain held for the Roblox handoff.
        const permissions = await api('/api/session/' + session + '/permission', 'GET', undefined, signal);
        if (!Array.isArray(permissions?.data)) throw Error('OpenCode returned an invalid permission list');
        if (message?.time?.completed) {
          if (nativeTools.length || job.calls.length || permissions.data.length)
            throw Error('OpenCode could not hand off the requested tool call. No desktop action was approved; the request was not repeated.');
          calls = []; break;
        }
        if (message?.time?.streamed && nativeTools.length) {
          calls = toolHandoff(nativeTools, tools, job, permissions.data, message.id, session);
          if (calls) break;
          if (handoffWaitingAt === undefined) handoffWaitingAt = Date.now();
          if (Date.now() - handoffWaitingAt >= HANDOFF_WAIT_MS)
            throw Error('OpenCode tool handoff did not become ready. The desktop guard prevented execution; the request was not repeated.');
        }
        if (nativeTools.some(part => ['error', 'completed'].includes(part.state?.status)))
          throw Error('OpenCode could not hand off the requested tool call. No desktop action was approved; the request was not repeated.');
        await pause(pollMs, signal);
      }
      if (!message) throw Error('OpenCode returned no assistant response');
      if (calls.length) {
        const stopped = await api('/api/session/' + session + '/interrupt', 'POST', {}, signal);
        if (stopped?.interrupted !== true) throw Error('OpenCode did not confirm interruption; the tool handoff was not delivered.');
      }
      if (closed || signal?.aborted || state !== 'ready') throw Error(signal?.aborted ? 'Stopped' : 'OpenCode stopped during the request');
      for (const [index, call] of calls.entries()) onFrame({ choices: [{ delta: { tool_calls: [{ index, id: call.id, type: 'function', function: { name: call.name, arguments: JSON.stringify(call.arguments) } }] } }] });
      const payload = responseBody(input.model, message, calls, new URL(url).pathname.endsWith('/responses'));
      return { status: 200, headers: { 'content-type': 'application/json' }, body: JSON.stringify(payload) };
    } finally {
      signal?.removeEventListener('abort', abort);
      if (session) {
        await api('/api/session/' + session + '/interrupt', 'POST', {}).catch(() => {});
        await api('/api/session/' + session, 'DELETE').catch(() => {});
      }
      for (const res of job.pending) res.destroy();
      if (registered) await api('/api/experimental/mcp/uai' + locationQuery, 'DELETE').catch(() => {});
      jobs.delete(key);
      if (path.dirname(location) === directory && path.basename(location) === key)
        try { fs.rmSync(location, { recursive: true, force: true, maxRetries: 2, retryDelay: 100 }); } catch { /* Native watcher may still hold the isolated directory; close retries the root. */ }
    }
  }

  async function close() {
    if (closed) return; closed = true;
    if (state !== 'disabled' && state !== 'missing') state = 'stopped';
    process.removeListener('exit', killOwnedChild);
    for (const job of jobs.values()) for (const res of job.pending) res.destroy();
    rpcServer?.closeAllConnections(); rpcServer?.close();
    if (child && child.exitCode === null && child.signalCode === null) {
      const exited = once(child, 'exit').catch(() => {}); child.kill();
      await Promise.race([exited, pause(2500)]);
    }
    // This root was created by mkdtemp, never derived from a caller's path.
    if (directory && path.dirname(directory) === os.tmpdir() && path.basename(directory).startsWith('project-uai-opencode-'))
      try { fs.rmSync(directory, { recursive: true, force: true, maxRetries: 2, retryDelay: 100 }); } catch { /* Locked native cache is safe to leave private. */ }
  }
  function accepts(url, body, headers) {
    // The isolated free CLI cannot preserve a personal key or workspace auth.
    // Those requests keep their original credential-bearing HTTPS dispatch.
    if (!official(url) || state !== 'ready' || !nativeHeadersAllowed(headers)) return false;
    try {
      const model = JSON.parse(body).model?.replace(/^opencode\//, '');
      return modelsCache.some(item => item.id === model);
    } catch { return false; }
  }
  return { start, request, models, capability, close, accepts };
}

module.exports = { createOpenCode, findBinary, official, nativeHeadersAllowed, promptFor, promptInput, responseBody, toolDefinitions };
