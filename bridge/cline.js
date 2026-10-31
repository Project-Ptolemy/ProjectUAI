'use strict';
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const http = require('node:http');
const crypto = require('node:crypto');
const { spawn, execFile } = require('node:child_process');
const { once } = require('node:events');
const { StringDecoder } = require('node:string_decoder');
const { version: bridgeVersion } = require('./release');

const ENDPOINT = 'https://uai-tunnel.invalid/cline/v1/chat/completions';
// This is the same explicit promotion list used by Cline CLI's free-model-cost
// module. An ordinary API model with missing/zero pricing is not sufficient.
const FREE_MODELS_URL = 'https://api.cline.bot/api/v1/ai/cline/recommended-models';
const HANDOFF = 'project_uai__handoff';
const MAX_PROTOCOL = 8 * 1024 * 1024;
const MAX_HANDOFF = 1024 * 1024;

function issue(message, code = 'failed') { const error = Error(message); error.clineCode = code; return error; }
function official(value) {
  try { const url = new URL(value); return url.href === ENDPOINT && !url.username && !url.password && !url.search && !url.hash; }
  catch { return false; }
}
function findBinary(env = process.env) {
  const candidates = [];
  if (env.UAI_CLINE_BINARY) candidates.push(env.UAI_CLINE_BINARY);
  const platform = process.platform === 'win32' ? 'windows' : process.platform;
  const executable = process.platform === 'win32' ? 'cline.exe' : 'cline';
  const suffix = path.join('node_modules', 'cline', 'node_modules', '@cline', `cli-${platform}-${process.arch}`, 'bin', executable);
  if (env.APPDATA) candidates.push(path.join(env.APPDATA, 'npm', suffix));
  for (const entry of (env.PATH || env.Path || '').split(path.delimiter).filter(Boolean)) {
    candidates.push(path.join(entry, executable), path.join(entry, suffix),
      path.join(entry, '..', 'lib', suffix));
  }
  for (const candidate of candidates) {
    try { if (path.isAbsolute(candidate) && fs.statSync(candidate).isFile()) return fs.realpathSync(candidate); } catch {}
  }
  return null;
}
function defaultConfigDir(env = process.env) {
  return path.join(env.LOCALAPPDATA || path.join(os.homedir(), '.local', 'share'), 'Project UAI', 'cline');
}
function authConfigDir(env) {
  const dedicated = defaultConfigDir(env);
  if (fs.existsSync(path.join(dedicated,'data','settings','providers.json'))) return dedicated;
  const standard = path.join(os.homedir(),'.cline');
  return fs.existsSync(path.join(standard,'data','settings','providers.json')) ? standard : dedicated;
}
function hasClineCredentials(file) {
  try {
    if (fs.statSync(file).size > MAX_PROTOCOL) return false;
    const entry = JSON.parse(fs.readFileSync(file,'utf8')).providers?.cline?.settings;
    // Match native Cline's credential-presence check without exporting a key
    // or allowing its generic ACP restore loop to select another provider.
    return !!entry && ((typeof entry.auth?.accessToken === 'string' && !!entry.auth.accessToken.trim()) ||
      (typeof entry.apiKey === 'string' && !!entry.apiKey.trim()));
  } catch { return false; }
}
function declarations(input) {
  if (input.tools !== undefined && !Array.isArray(input.tools)) throw issue('Cline requires a valid tool list.');
  const tools = new Map();
  for (const entry of input.tools || []) {
    const tool = entry?.type === 'function' ? entry.function : undefined;
    if (!tool || !/^[A-Za-z_][\w-]{0,63}$/.test(tool.name || '') || tools.has(tool.name)) throw issue('Cline received an invalid or duplicate tool declaration.');
    tools.set(tool.name, { name: tool.name, description: String(tool.description || '').slice(0,16000),
      parameters: tool.parameters && typeof tool.parameters === 'object' ? tool.parameters : { type: 'object' } });
  }
  if (tools.size > 256) throw issue('Cline received too many tool declarations.');
  return tools;
}
function validateBatch(value, tools) {
  if (!value || !Array.isArray(value.calls) || !value.calls.length || value.calls.length > 32 ||
    Object.keys(value).some(key=>key!=='calls') ||
    Buffer.byteLength(JSON.stringify(value)) > MAX_HANDOFF) throw issue('Cline returned an invalid tool handoff.');
  return value.calls.map(call => {
    if (!call || !tools.has(call.name) || !call.arguments || typeof call.arguments !== 'object' || Array.isArray(call.arguments)) {
      throw issue('Cline tried to hand off an undeclared tool or invalid arguments.');
    }
    if (Object.keys(call).some(key=>key!=='name' && key!=='arguments')) throw issue('Cline returned unexpected tool handoff fields.');
    return { id: 'cline-' + crypto.randomUUID(), type: 'function',
      function: { name: call.name, arguments: JSON.stringify(call.arguments) } };
  });
}
function promptInput(input) {
  if (!Array.isArray(input.messages) || !input.messages.length) throw issue('Cline requires conversation messages.');
  for (const message of input.messages) {
    if (!message || typeof message !== 'object') throw issue('Cline received an invalid conversation message.');
    if (Array.isArray(message.content) && message.content.some(part => !part || !['text','input_text'].includes(part.type))) {
      // CLI 3.0.73 advertises ACP images but its prompt implementation extracts
      // only text. Reject attachments instead of silently omitting their bytes.
      throw issue('This Cline CLI connection currently supports text only. Use another provider for images.');
    }
  }
  return 'Continue the supplied conversation as its assistant. The messages include system instructions and tool results. ' +
    'You are serving a Roblox agent through Project UAI; local machine tools cannot perform Roblox actions. ' +
    'For any supplied tool, call project_uai__handoff once with the complete batch of {name, arguments} calls, then stop. ' +
    'Do not run local commands, access local files, browse, or start other agents. If no tool is needed, answer normally.\n\n' + JSON.stringify(input.messages);
}

function createCline({ env = process.env, enabled = env.UAI_CLINE_DISABLED !== '1', binary = findBinary(env),
  binaryArgs = [], configDir, spawnProcess = spawn, fetch = globalThis.fetch,
  startupMs = 30000, onChange = () => {} } = {}) {
  let stopped = false, checking, version, catalog = [], state = !enabled ? 'disabled' : binary ? 'starting' : 'missing';
  let message = !enabled ? 'Cline is turned off.' : binary ? 'Checking Cline sign-in and free models.' : 'Install Cline with npm install -g cline.';
  const jobs = new Set(), downloads = new Set();
  const capability = () => ({ schema: 1, enabled, available: !stopped && state === 'ready', state, message, ...(version ? { version } : {}) });
  const status = (next, text) => { if (!stopped) { state = next; message = text; onChange(capability()); } };
  const assertRunning = () => {
    if (stopped) throw issue('Cline connection stopped.');
    if (!enabled) throw issue('Cline is turned off.', 'disabled');
    if (!binary) throw issue('Install Cline with npm install -g cline.', 'missing');
  };
  function failure(error) {
    if (error?.clineCode === 'auth-required') status('auth-required', 'Sign in to Cline, then refresh models.');
    else if (error?.clineCode === 'disabled' || error?.clineCode === 'missing') status(error.clineCode,error.message);
    else if (!stopped && error?.clineCode !== 'cancelled') status('failed', error?.clineCode ? error.message : 'Cline could not complete the local connection.');
    return error?.clineCode ? error : issue('Cline could not complete the local connection.');
  }
  async function promotions(signal) {
    assertRunning();
    if (signal?.aborted) throw issue('Cline request stopped.','cancelled');
    const controller = new AbortController(); downloads.add(controller);
    const abort = ()=>controller.abort();signal?.addEventListener('abort',abort,{once:true});
    const timer = setTimeout(() => controller.abort(), 10000);
    try {
      const response = await fetch(FREE_MODELS_URL, { signal: controller.signal, redirect: 'error' });
      if (!response.ok) throw issue('Cline free-model availability could not be verified.');
      const chunks=[];let size=0;
      for await (const chunk of response.body) {
        size+=chunk.length;
        if(size>MAX_PROTOCOL){controller.abort();throw issue('Cline free-model catalog exceeded its limit.');}
        chunks.push(Buffer.from(chunk));
      }
      const data = JSON.parse(Buffer.concat(chunks,size).toString('utf8'));
      if (!Array.isArray(data.free)) throw issue('Cline free-model catalog is unavailable.');
      const unique = new Map();
      for (const item of data.free) {
        if (item && typeof item.id === 'string' && /^[A-Za-z0-9][A-Za-z0-9_./:-]{0,199}$/.test(item.id)) {
          unique.set(item.id, { id: item.id, object: 'model', name: String(item.name || item.id).slice(0,200),
            owned_by: 'cline', pricing: { prompt: '0', completion: '0' }, supports_vision: false });
        }
      }
      return [...unique.values()];
    } catch (error) { throw signal?.aborted ? issue('Cline request stopped.','cancelled') : error?.clineCode ? error : issue('Cline free-model availability could not be verified.'); }
    finally { clearTimeout(timer); downloads.delete(controller);signal?.removeEventListener('abort',abort); }
  }
  async function openSession({ tools = new Map(), signal, onFrame = () => {} } = {}) {
    assertRunning();
    if (signal?.aborted) throw issue('Cline request stopped.', 'cancelled');
    if(jobs.size>=4) {const error=issue('Cline is busy. Wait for another request to finish.');error.status=503;throw error;}
    const providerSettings=path.join(configDir || authConfigDir(env),'data','settings','providers.json');
    if(!hasClineCredentials(providerSettings))throw issue('Sign in to Cline, then refresh models.','auth-required');
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'project-uai-cline-'));
    const workspace = path.join(directory, 'workspace'), privateConfig = path.join(directory, 'config'), privateData = path.join(directory, 'data');
    fs.mkdirSync(workspace); fs.mkdirSync(privateConfig); fs.mkdirSync(privateData);
    let child, server, closed = false, closing, sessionId, buffer = '', nextId = 0, promptActive = false;
    const decoder = new StringDecoder('utf8');
    let mcpListed = false, handedOff, approvedBatch, rejectedTools = 0, text = '', reasoning = '';
    const pending = new Map(), sockets = new Set();
    let resolveHandoff;
    const handoff = new Promise(resolve => { resolveHandoff = resolve; });
    function rejectPending(error) { for (const task of pending.values()) { clearTimeout(task.timer); task.reject(error); } pending.clear(); }
    function notify(method, params) { if (!closed && child?.stdin.writable) child.stdin.write(JSON.stringify({ jsonrpc:'2.0', method, params }) + '\n'); }
    function rpc(method, params, timeout = startupMs) {
      if (closed || !child?.stdin.writable) return Promise.reject(issue('Cline local process stopped.'));
      return new Promise((resolve, reject) => {
        const id = ++nextId;
        const timer = timeout ? setTimeout(() => { pending.delete(id); reject(issue('Cline local protocol timed out.')); }, timeout) : undefined;
        pending.set(id, { resolve, reject, timer });
        child.stdin.write(JSON.stringify({ jsonrpc:'2.0', id, method, params }) + '\n');
      });
    }
    const session = {
      directory,
      async close() {
        if (closing) return closing;
        closing = (async () => {
          closed = true; signal?.removeEventListener('abort', abort);
          rejectPending(issue('Cline request stopped.', 'cancelled'));
          if (child && child.exitCode === null && child.signalCode === null) {
            const exited = once(child, 'exit').catch(() => {});
            // The native CLI can own helper processes. Stop this owned process
            // tree only; never touch another CLI or the user's normal hub.
            if (process.platform === 'win32' && child.pid) {
              await new Promise(resolve => execFile('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'],
                { windowsHide:true, timeout:5000 }, () => resolve()));
            } else child.kill();
            await Promise.race([exited, new Promise(resolve => { const timer=setTimeout(resolve,2000); timer.unref?.(); })]);
          }
          for (const socket of sockets) socket.destroy();
          if (server?.listening) await new Promise(resolve => server.close(resolve));
          const resolved = path.resolve(directory);
          if (path.dirname(resolved) === path.resolve(os.tmpdir()) && /^project-uai-cline-[\w-]+$/.test(path.basename(resolved))) {
            await fsp.rm(resolved, { recursive:true, force:true, maxRetries:3, retryDelay:100 })
              .catch(()=>{throw issue('Cline stopped but its temporary session could not be removed.');});
          }
          jobs.delete(session);
        })(); return closing;
      },
      async prompt(input) {
        const selected = await rpc('session/set_config_option', { sessionId, configId:'model', value:input.model });
        if (selected.configOptions?.find(item => item.id === 'model')?.currentValue !== input.model ||
          selected.configOptions?.find(item => item.id === 'provider')?.currentValue !== 'cline' ||
          selected.configOptions?.find(item => item.id === 'auto_approve')?.currentValue !== false) throw issue('Cline did not retain the requested free model and permission settings.');
        promptActive = true;
        const response = await Promise.race([rpc('session/prompt', { sessionId, prompt:[{ type:'text', text:promptInput(input) }] }, 0), handoff]);
        if (signal?.aborted) throw issue('Cline request stopped.', 'cancelled');
        if (!handedOff && response.stopReason !== 'end_turn') throw issue('Cline did not complete its reply.');
        if (!handedOff && !text.trim()) throw issue('Cline returned no completed text or tool handoff.');
        const calls = handedOff || [];
        for (const [index, call] of calls.entries()) onFrame({ choices:[{ index:0, delta:{ tool_calls:[{ ...call,index }] } }] });
        return { status:200, headers:{ 'content-type':'application/json' }, body:JSON.stringify({
          id:'cline-' + crypto.randomUUID(), object:'chat.completion', model:input.model,
          choices:[{ index:0, message:{ role:'assistant', content:text || null, ...(reasoning ? { reasoning_content:reasoning } : {}), ...(calls.length ? { tool_calls:calls } : {}) },
            finish_reason:calls.length ? 'tool_calls' : 'stop' }]
        }) };
      }
    };
    const abort = () => { notify('session/cancel', { sessionId }); void session.close().catch(() => {}); };
    jobs.add(session); signal?.addEventListener('abort', abort, { once:true });
    try {
      const token = crypto.randomBytes(32).toString('hex');
      const reply = (res, statusCode, value) => { res.writeHead(statusCode,{ 'content-type':'application/json' }); res.end(value === undefined ? '' : JSON.stringify(value)); };
      server = http.createServer((req,res) => {
        const expected = Buffer.from('Bearer ' + token), given = Buffer.from(String(req.headers.authorization || ''));
        if (req.url !== '/mcp' || given.length !== expected.length || !crypto.timingSafeEqual(given,expected)) return reply(res,403,{error:'Denied'});
        if (req.method !== 'POST') return reply(res,405,{error:'POST required'});
        let body = '', size = 0; const requestDecoder = new StringDecoder('utf8');
        req.on('data', chunk => { size += chunk.length; if (size > MAX_HANDOFF) req.destroy(); else body += requestDecoder.write(chunk); });
        req.on('error', () => res.destroy());
        req.on('end', () => {
          let message;
          try { message=JSON.parse(body+requestDecoder.end()); } catch { return reply(res,400,{error:'Invalid request'}); }
          if (message.id === undefined) return reply(res,202);
          const result = value => reply(res,200,{jsonrpc:'2.0',id:message.id,result:value});
          if (message.method === 'initialize') return result({protocolVersion:'2024-11-05',capabilities:{tools:{}},serverInfo:{name:'project-uai-handoff',version:'1.0.0'}});
          if (message.method === 'tools/list') {
            mcpListed = true;
            return result({tools:tools.size ? [{name:'handoff',description:'Return the COMPLETE batch of Roblox tool calls to Project UAI. This delegates to Roblox; it does not execute actions on this computer.',
              inputSchema:{type:'object',properties:{calls:{type:'array',minItems:1,maxItems:32,items:{oneOf:[...tools.values()].map(tool=>({type:'object',properties:{name:{const:tool.name,description:tool.description},arguments:tool.parameters},required:['name','arguments'],additionalProperties:false}))}}},required:['calls'],additionalProperties:false}}] : []});
          }
          if (message.method === 'tools/call' && message.params?.name === 'handoff') {
            try {
              if (!promptActive || handedOff || !approvedBatch || JSON.stringify(message.params.arguments) !== approvedBatch) throw issue('Cline handoff was not approved.');
              handedOff = validateBatch(message.params.arguments,tools);
              result({content:[{type:'text',text:'Control is being returned to Roblox. Stop and wait for the tool results.'}]});
              notify('session/cancel',{sessionId}); resolveHandoff({stopReason:'handoff'});
            } catch { result({isError:true,content:[{type:'text',text:'Invalid or unapproved Project UAI handoff.'}]}); }
            return;
          }
          reply(res,200,{jsonrpc:'2.0',id:message.id,error:{code:-32601,message:'Method not supported'}});
        });
      });
      server.on('connection', socket => { sockets.add(socket); socket.on('close',()=>sockets.delete(socket)); });
      server.listen(0,'127.0.0.1'); await once(server,'listening');
      if (closed || signal?.aborted || stopped) throw issue('Cline request stopped.','cancelled');
      const mcpPath=path.join(directory,'mcp.json');
      fs.writeFileSync(mcpPath,JSON.stringify({mcpServers:{project_uai:{type:'streamableHttp',url:`http://127.0.0.1:${server.address().port}/mcp`,headers:{Authorization:'Bearer '+token}}}}));
      const childEnv={...env,CLINE_DIR:privateConfig,CLINE_DATA_DIR:privateData,CLINE_SESSION_BACKEND_MODE:'local',
        CLINE_PROVIDER:'cline',CLINE_PROVIDER_SETTINGS_PATH:providerSettings,
        CLINE_MCP_SETTINGS_PATH:mcpPath,CLINE_GLOBAL_SETTINGS_PATH:path.join(privateData,'settings','global-settings.json'),
        CLINE_SESSION_DATA_DIR:path.join(privateData,'sessions'),CLINE_DB_DATA_DIR:path.join(privateData,'db')};
      for (const name of Object.keys(childEnv)) {
        if (/^(CLINE_API_KEY|CLINE_MODEL|CLINE_AUTH_TOKEN|CLINE_HUB_|CLINE_HOOKS_DIR|CLINE_SANDBOX|CLINE_BASE_URL)/.test(name)) delete childEnv[name];
      }
      child=spawnProcess(binary,[...binaryArgs,'--config',privateConfig,'--data-dir',privateData,'--cwd',workspace,'--acp','--auto-approve','false'],
        {cwd:workspace,env:childEnv,windowsHide:true,stdio:['pipe','pipe','pipe']});
      child.stderr.resume();
      child.stdin.on('error',()=>rejectPending(issue('Cline local process stopped.')));
      child.once('error',()=>rejectPending(issue('Could not start the installed Cline CLI.')));
      child.once('exit',()=>rejectPending(issue('Cline local process stopped.')));
      child.stdout.on('data',chunk=>{
        buffer += decoder.write(chunk);
        if (Buffer.byteLength(buffer)>MAX_PROTOCOL) { rejectPending(issue('Cline protocol output exceeded its limit.')); void session.close().catch(()=>{}); return; }
        let at;
        while((at=buffer.indexOf('\n'))>=0) {
          const line=buffer.slice(0,at);buffer=buffer.slice(at+1);if(!line.trim())continue;
          let item;try{item=JSON.parse(line);}catch{rejectPending(issue('Cline returned invalid local protocol output.'));void session.close().catch(()=>{});return;}
          if(item.id!==undefined && !item.method && pending.has(item.id)) {
            const task=pending.get(item.id);pending.delete(item.id);clearTimeout(task.timer);
            if(item.error) task.reject(item.error.code===-32000 ? issue('Sign in to Cline, then refresh models.','auth-required') : issue('Cline rejected the local request.'));
            else task.resolve(item.result || {});
          } else if(item.method==='session/request_permission' && item.id!==undefined) {
            let approved=false;
            const call=item.params?.toolCall;
            if (promptActive && item.params?.sessionId===sessionId && mcpListed && !handedOff &&
              (call?.title===HANDOFF || call?.title?.startsWith(HANDOFF+': '))) {
              try {validateBatch(call.rawInput,tools);approvedBatch=JSON.stringify(call.rawInput);approved=true;}catch{}
            }
            const option=item.params?.options?.find(entry=>entry.kind===(approved?'allow_once':'reject_once'));
            child.stdin.write(JSON.stringify({jsonrpc:'2.0',id:item.id,result:{outcome:option?{outcome:'selected',optionId:option.optionId}:{outcome:'cancelled'}}})+'\n');
            if(!approved && ++rejectedTools>=8) {rejectPending(issue('Cline kept requesting unavailable local tools.'));void session.close().catch(()=>{});}
          } else if(item.id!==undefined && item.method) {
            child.stdin.write(JSON.stringify({jsonrpc:'2.0',id:item.id,error:{code:-32601,message:'Project UAI does not provide local machine operations'}})+'\n');
          } else if(item.method==='session/update' && item.params?.sessionId===sessionId && promptActive) {
            const update=item.params.update;
            if(['agent_message_chunk','agent_thought_chunk'].includes(update?.sessionUpdate) && update.content?.type==='text' && typeof update.content.text==='string') {
              const delta=update.content.text;
              if(update.sessionUpdate==='agent_message_chunk')text+=delta;else reasoning+=delta;
              if(Buffer.byteLength(text)+Buffer.byteLength(reasoning)>MAX_PROTOCOL){rejectPending(issue('Cline reply exceeded its limit.'));void session.close().catch(()=>{});return;}
              if(!signal?.aborted)onFrame({choices:[{index:0,delta:{[update.sessionUpdate==='agent_message_chunk'?'content':'reasoning_content']:delta}}]});
            }
          }
        }
      });
      const initialized=await rpc('initialize',{protocolVersion:1,clientInfo:{name:'project-uai',version:bridgeVersion},clientCapabilities:{fs:{readTextFile:false,writeTextFile:false},terminal:false}});
      if(initialized.protocolVersion!==1 || initialized.agentInfo?.name!=='cline')throw issue('Installed Cline does not support the required local protocol.');
      if(typeof initialized.agentInfo.version==='string')version=initialized.agentInfo.version.slice(0,60);
      const created=await rpc('session/new',{cwd:workspace,mcpServers:[]});
      sessionId=created.sessionId;
      if(typeof sessionId!=='string' || !created.models?.availableModels ||
        created.configOptions?.find(item=>item.id==='provider')?.currentValue!=='cline' ||
        created.configOptions?.find(item=>item.id==='auto_approve')?.currentValue!==false) throw issue('Cline could not verify its provider and tool permission settings.');
      session.models=new Set(created.models.availableModels.map(item=>item.modelId).filter(item=>typeof item==='string'));
      return session;
    } catch(error) { await session.close();throw error; }
  }
  const api = {
    capability,
    accepts(url, body) { try { return enabled && !stopped && official(url) && typeof JSON.parse(body).model==='string'; } catch { return false; } },
    start() {
      if(checking)return checking;
      checking=(async()=>{
        assertRunning();status('starting','Checking Cline sign-in and free models.');
        let session;
        try {
          session=await openSession();
          // ACP's generic catalog omits some live promotional IDs. Native
          // GatewayRegistry keeps explicitly selected unregistered IDs intact;
          // the official free feed is the authority, as in Cline's own picker.
          catalog=await promotions();
          if(!catalog.length)throw issue('No current Cline free models could be verified.');
          status('ready','Cline is signed in and current free models are available.');
          return capability();
        }catch(error){throw failure(error);}finally{await session?.close();}
      })().finally(()=>{checking=undefined;});
      return checking;
    },
    async models() { await api.start();return {object:'list',data:catalog}; },
    async request({body,url,signal,onFrame}) {
      let session;
      try {
        assertRunning();
        if(!official(url))throw issue('Cline only accepts its Project UAI bridge endpoint.');
        const input=JSON.parse(body);promptInput(input);const tools=declarations(input);
        if(jobs.size>=4) {const error=issue('Cline is busy. Wait for another request to finish.');error.status=503;throw error;}
        const current=await promotions(signal);
        if(!current.some(model=>model.id===input.model))throw issue('The requested model is not currently verified free in Cline.');
        session=await openSession({tools,signal,onFrame});
        catalog=current;
        status('ready','Cline is signed in and current free models are available.');
        return await session.prompt(input);
      }catch(error){throw failure(error);}finally{await session?.close();}
    },
    async close() {
      stopped=true;state='disabled';message='Cline connection stopped.';
      for(const controller of downloads)controller.abort();
      await Promise.allSettled([...jobs].map(job=>job.close()));
      await checking?.catch(()=>{});
    }
  };
  return api;
}
module.exports={createCline,findBinary,official,defaultConfigDir,validateBatch,FREE_MODELS_URL,ENDPOINT};
