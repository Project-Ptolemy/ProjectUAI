'use strict';
const $=id=>document.getElementById(id), md=UAIMarkdown.render;
const el=(tag,cls,text)=>{const n=document.createElement(tag);if(cls)n.className=cls;if(text!==undefined)n.textContent=text;return n;};
const button=(text,fn,cls,key)=>{const n=el('button',cls,text);n.type='button';n.onclick=fn;if(key)n.dataset.focusKey=key;return n;};
function icon(name){const n=document.createElementNS('http://www.w3.org/2000/svg','svg'),use=document.createElementNS(n.namespaceURI,'use');n.classList.add('icon');n.setAttribute('aria-hidden','true');use.setAttribute('href','icons.svg#'+name);n.append(use);return n;}
const uuid=()=>crypto.randomUUID();
function stored(storage,key){try{return window[storage].getItem(key);}catch{return null;}}
const fromHash=location.hash.match(/(?:#|&)t=([a-f0-9]{64})(?:$|&)/i);
let requestedSettings=['mcp','obsidian'].includes(new URLSearchParams(location.search).get('settings'))?new URLSearchParams(location.search).get('settings'):null;
let token=fromHash?.[1]?.toLowerCase()||stored('sessionStorage','uai.token')||stored('localStorage','uai.token')||'';
if(fromHash||requestedSettings)history.replaceState(null,'',location.pathname);
let state={},bridgeUpdate={},kiloStatus={},clineStatus={},openCodeStatus={},page='chat',stream,busy=false,connected=false,sending=false,stopping=false,sessionId=null,events=[],uploads=[],instance=stored('sessionStorage','uai.instance');
let drafts={};try{const value=JSON.parse(stored('sessionStorage','uai.drafts')||'{}');if(value&&typeof value==='object'&&!Array.isArray(value))drafts=value;}catch{}
const tools=new Map(),dirtyDrafts=new Set();
let currentResponse=null,responseUser=null,transcriptOrder=0;
let toastTimer,draftTimer,storageWarning=false,renderingSnapshot=false,eventBytes=0,sendOperation=null,connectionRetry,readingFiles=0,modalRefresh=null,panelRefreshPending=false,panelPointerActive=false,panelPointerTimer;
const draftLoads=new Map();
const MAX_DRAFT_BYTES=16*1024*1024,MAX_EVENTS_BYTES=8*1024*1024;
// Explicit operation state machine (contract): the visible/label state is derived
// from link + sendPhase + busy rather than a tangle of loose booleans.
document.body.dataset.page='chat';
let link='connecting';               // disconnected|connecting|online|offline
let sendPhase='idle';                // idle|reading|uploading|submitting|awaiting-turn
let awaitTurnTimer=null;
let lastSend=null;                   // {text,files,pictureIds,sessionId} for retry
// Stable random per-tab browser id (NOT authentication; identifies the upload owner).
let browserId=stored('sessionStorage','uai.browserId')||uuid();try{sessionStorage.setItem('uai.browserId',browserId);}catch{}
// Picture staging lives in pictures.js (UAI.pictures), instantiated once the DOM is ready.
const OP_LABEL={reading:'Reading files…',uploading:'Uploading files…',submitting:'Sending…','awaiting-turn':'Waiting for the agent…',stopping:'Stopping…',uncertain:'Checking message delivery…'};
function toast(text){
  clearTimeout(toastTimer);
  if($('modal').open){$('toast').hidden=true;$('modalNotice').textContent=text;$('modalNotice').scrollIntoView({block:'nearest'});return;}
  $('toast').textContent=text;$('toast').hidden=false;toastTimer=setTimeout(()=>$('toast').hidden=true,4500);
}
function announce(text){if($('status').textContent!==text)$('status').textContent=text;}
// Surface the bridge's real reason: 401/403/405 return plain-text bodies, so read
// res.text() and only fall back to a generic message when there is nothing useful.
async function api(path,body,method,signal){
  const res=await fetch('/api'+path,{method:method||(body===undefined?'GET':'POST'),headers:{Authorization:'Bearer '+token,'X-UAI-Browser-Id':browserId,...((body?.sessionId||sessionId)?{'X-UAI-Session-Id':body?.sessionId||sessionId}:{}),...(body===undefined?{}:{'content-type':'application/json'})},body:body===undefined?undefined:JSON.stringify(body),signal:signal||AbortSignal.timeout(15000)});
  const raw=res.status===204?'':await res.text();
  let data,parsed=false;try{data=raw?JSON.parse(raw):{};parsed=true;}catch{data={};}
  if(!res.ok){
    const plain=(!parsed&&raw&&raw.length<=300)?raw.trim():'';
    const error=Error(res.status===401?'This token no longer works. Open the latest bridge link or paste its new token.':data.error||plain||`Bridge returned ${res.status}`);
    error.status=res.status;error.code=data.code;if(res.status===401)showGate(error.message);throw error;
  }
  return data;
}
const uncertainActions=new Map();
async function command(type,fields={}){
  if(!connected)throw Error('Connect Roblox in Cowork before using this action.');
  const actionKey=JSON.stringify([type,sessionId,fields]),previous=uncertainActions.get(actionKey);
  if(previous){try{const result=await commandResult(previous);uncertainActions.delete(actionKey);return result;}catch(error){if(!error.uncertain)uncertainActions.delete(actionKey);throw error;}}
  const commandId=fields.commandId||uuid(), payload={type,sessionId,...fields,commandId};
  let receipt;
  try{
    for(let i=0;i<2;i++){try{receipt=await api('/command',payload);break;}catch(err){if(err.status||i){if(!err.status)err.uncertain=true;throw err;}}}
    if(!receipt?.id){const error=Error('The bridge did not confirm this action. Check its status before trying again.');error.uncertain=true;throw error;}
    return await commandResult(receipt.id);
  }catch(error){error.commandId=receipt?.id||commandId;if(error.uncertain)uncertainActions.set(actionKey,error.commandId);throw error;}
}
async function commandResult(commandId){
  const deadline=Date.now()+190000;
  try{
    while(Date.now()<deadline){let result;try{result=await api('/commands/'+commandId);}catch(err){if(err.name!=='TypeError'&&err.name!=='TimeoutError'){err.uncertain=true;if(err.status===404)err.message='This action’s receipt is unavailable. Review Roblox before repeating the action.';throw err;}await new Promise(r=>setTimeout(r,1000));continue;}
      if(!['queued','running'].includes(result.state)){if(result.result?.ok===false){const error=Error(result.result.error||'The game could not complete this action.');error.uncertain=!!result.result.uncertain;throw error;}if(result.state!=='completed'){const error=Error('The bridge returned an unknown action status. Check its status before trying again.');error.uncertain=true;throw error;}forgetCommand(commandId);return result.result?.data;}await new Promise(r=>setTimeout(r,250));}
    const error=Error('This action is still pending. Check its status before trying again.');error.uncertain=true;throw error;
  }catch(error){if(!error.uncertain)forgetCommand(commandId);error.commandId=commandId;throw error;}
}
function forgetCommand(commandId){for(const [key,id]of uncertainActions)if(id===commandId)uncertainActions.delete(key);}
function action(type,fields){return command(type,fields).catch(err=>toast(err.message));}
let modalContext=null,modalCloseTimer,modalBackdropStart=false;
function modal(title,build,options={}){
  const dialog=$('modal'),previous=modalContext;
  if(previous?.canClose&&!previous.canClose())return;
  previous?.cleanup?.();
  clearTimeout(modalCloseTimer);dialog.classList.remove('closing');
  // Replacing a dialog retains the original invoker, never a removed child.
  modalContext={opener:previous?.opener||document.activeElement,pending:false,closing:false};
  modalRefresh=null;dialog.dataset.size=options.size||'standard';dialog.removeAttribute('aria-busy');
  $('modalTitle').textContent=title;$('modalDescription').textContent=options.description||'';$('modalDescription').hidden=!options.description;
  $('modalNotice').textContent='';delete $('modalNotice').dataset.state;$('modalFooter').replaceChildren();
  $('modalBody').replaceChildren();$('modalBody').className='';
  build($('modalBody'));if(!$('modalFooter').childElementCount)modalActions(modalCancel('Done'));if(!dialog.open)dialog.showModal();$('modalBody').scrollTop=0;dialog.scrollTop=0;
  const first=$('modalBody').querySelector('[autofocus],input:not([type="hidden"]):not(:disabled),select:not(:disabled),textarea:not(:disabled),button:not(:disabled),[tabindex="0"]');
  (options.focusHeading?$('modalTitle'):first||$('modalClose')).focus({preventScroll:true});
}
function closeModal(immediate=false,restore=true){
  const dialog=$('modal'),context=modalContext;if(!dialog.open)return;
  if(context?.canClose&&!context.canClose())return;
  if(context){context.closing=true;context.restore=restore;}modalRefresh=null;clearTimeout(modalCloseTimer);
  const finish=()=>{if(modalContext===context){dialog.classList.remove('closing');dialog.close();}};
  if(immediate||matchMedia('(prefers-reduced-motion: reduce)').matches)finish();
  else{dialog.classList.add('closing');modalCloseTimer=setTimeout(finish,140);}
}
function modalActions(...controls){$('modalFooter').append(...controls);}
function modalCancel(label='Cancel'){return button(label,()=>closeModal(),'outline');}
async function modalTask(work,{close=false,success='',check=false}={}){
  const context=modalContext;if(!context||context.pending||context.closing||(context.uncertain&&!check))return;
  const focused=document.activeElement;context.pending=true;context.uncertain=false;
  const controls=context.lockedControls||[...$('modal').querySelectorAll('#modalBody button,#modalBody input,#modalBody select,#modalBody textarea,#modalFooter button')].filter(n=>!n.disabled);
  controls.forEach(n=>n.disabled=true);$('modal').setAttribute('aria-busy','true');
  if(context.checkButton)context.checkButton.disabled=true;
  $('modalNotice').textContent='Working…';$('modalNotice').dataset.state='pending';
  try{const result=await work();if(context!==modalContext||context.closing||!$('modal').open)return;
    if(close)closeModal();else{$('modalNotice').textContent=success;$('modalNotice').dataset.state='success';}
    return result;
  }catch(error){if(context===modalContext&&!context.closing&&$('modal').open){$('modalNotice').textContent=error.message;$('modalNotice').dataset.state='error';
    if(error.uncertain){context.uncertain=true;context.lockedControls=controls;if(!context.checkButton){context.checkButton=button('Check status',()=>modalTask(()=>commandResult(error.commandId),{close,success,check:true}),'outline');modalActions(context.checkButton);}context.checkButton.disabled=false;}
  }}
  finally{if(context===modalContext){context.pending=false;$('modal').removeAttribute('aria-busy');
    if(!context.uncertain){controls.forEach(n=>{if(n.isConnected)n.disabled=false;});context.checkButton?.remove();context.checkButton=null;context.lockedControls=null;modalRefresh?.();
      if(!context.closing&&focused?.isConnected&&!focused.disabled&&[document.body,$('modal')].includes(document.activeElement))focused.focus({preventScroll:true});}
    else context.checkButton?.focus({preventScroll:true});
  }}
}
function modalCommand(type,fields){return modalTask(()=>command(type,fields),{close:true});}
$('modalClose').onclick=()=>closeModal();
$('modal').addEventListener('cancel',event=>{event.preventDefault();closeModal();});
$('modal').addEventListener('pointerdown',event=>{modalBackdropStart=event.target===$('modal')&&outsideModal(event);});
$('modal').addEventListener('click',event=>{if(modalBackdropStart&&event.target===$('modal')&&outsideModal(event))closeModal();modalBackdropStart=false;});
function outsideModal(event){const r=$('modal').getBoundingClientRect();return event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom;}
$('modal').addEventListener('close',()=>{
  if($('modal').open)return;
  const context=modalContext;modalContext=null;modalRefresh=null;$('modalNotice').textContent='';
  context?.cleanup?.();
  queueMicrotask(()=>{if($('modal').open||modalContext)return;flushPanelRefresh();if(context?.restore===false)return;
    const opener=context?.opener,key=opener?.dataset?.focusKey,replacement=key&&[...document.querySelectorAll('[data-focus-key]')].find(n=>n.dataset.focusKey===key);
    const target=$('app').hidden?$('gate-token'):(opener?.isConnected?opener:replacement);
    if(target&&!target.closest('[inert]')&&target.getClientRects().length&&!target.disabled)target.focus({preventScroll:true});
    else (document.body.classList.contains('sidebar-open')?$('closeSidebar'):page==='chat'?$('input'):$('panel')).focus({preventScroll:true});
  });
});
function field(parent,label,value,type='text'){const holder=el('label',null,label),input=el(type==='textarea'?'textarea':'input');if(type!=='textarea')input.type=type;input.value=value??'';holder.append(input);parent.append(holder);return input;}
function select(parent,label,values,value){const holder=el('label',null,label),input=el('select');input.setAttribute('aria-label',label);for(const item of values){const pair=typeof item==='string'?[item,item]:item;const option=el('option',null,pair[1]);option.value=pair[0];input.append(option);}input.value=value;holder.append(input);parent.append(holder);return input;}
function persistDrafts(){
  clearTimeout(draftTimer);
  // Small recovery text is synchronous; file bodies and full drafts use IndexedDB.
  const recent=Object.entries(drafts).sort((a,b)=>(b[1].updatedAt||0)-(a[1].updatedAt||0)).slice(0,20);
  const small=Object.fromEntries(recent.map(([id,draft])=>{
    const complete=Array.isArray(draft.uploads)&&!draftLoads.has(id);
    const fileIds=complete?draft.uploads.map(f=>f.id):Array.isArray(draft.fileIds)?[...new Set([...draft.fileIds,...(draft.uploads||[]).map(f=>f.id)])]:undefined;
    return [id,{text:(draft.text||'').slice(0,16000),textLength:draft.textLength??draft.text?.length??0,fileIds,version:draft.version||0,updatedAt:draft.updatedAt}];
  }));
  try{sessionStorage.setItem('uai.drafts',JSON.stringify(small));}catch{}
  for(const id of dirtyDrafts){
    // Wait for old file bodies before saving a recovery copy or newly typed text.
    if(draftLoads.has(id))continue;
    dirtyDrafts.delete(id);const value=drafts[id];
    if(value)UAI.drafts.save(id,value).then(ok=>{if(!ok&&!storageWarning){storageWarning=true;toast('Browser storage is unavailable. Keep this tab open to retain attached files.');}});
  }
}
function saveDraft(){
  if(!sessionId)return;
  const previous=drafts[sessionId]||{},text=$('input').value;
  const oldFiles=previous.uploads||[];
  if((previous.text||'')===text&&oldFiles.length===uploads.length&&oldFiles.every((file,i)=>file.id===uploads[i].id))return;
  drafts[sessionId]={...previous,text,textLength:text.length,uploads:uploads.slice(),version:(previous.version||0)+(previous.text===text?0:1),updatedAt:Date.now()};
  dirtyDrafts.add(sessionId);clearTimeout(draftTimer);draftTimer=setTimeout(persistDrafts,450);
}
function changeSession(id){
  if(!id||id===sessionId)return;
  currentResponse=null;responseUser=null;
  saveDraft();persistDrafts();if(sessionId)renderer.dropSession(sessionId);sessionId=id;
  $('input').value=typeof drafts[id]?.text==='string'?drafts[id].text:'';
  uploads=Array.isArray(drafts[id]?.uploads)?drafts[id].uploads.filter(f=>f&&typeof f.name==='string'&&typeof f.text==='string').map(f=>({...f,id:f.id||uuid()})):[];
  if(window.UAI&&UAI.pictures)UAI.pictures.showSession();
  renderAttachments();resizeComposer();refresh();
  if(draftLoads.has(id)||Array.isArray(drafts[id]?.uploads))return;
  const loading=UAI.drafts.load(id).then(saved=>{
    const current=drafts[id],newer=current&&(!saved||(current.updatedAt||0)>=(saved.updatedAt||0));
    let files=Array.isArray(saved?.uploads)?saved.uploads.filter(f=>f&&typeof f.name==='string'&&typeof f.text==='string').map(f=>({...f,id:f.id||uuid()})):[];
    if(newer&&Array.isArray(current.fileIds))files=files.filter(f=>current.fileIds.includes(f.id));
    for(const file of current?.uploads||[])if(!files.some(f=>f.id===file.id))files.push(file);
    // The synchronous copy may contain only the start of a long draft. Keep its
    // full stored body when both copies identify the same text.
    const truncated=newer&&current.textLength>current.text?.length&&saved?.text?.length===current.textLength&&saved.text.startsWith(current.text);
    const text=newer&&!truncated?current.text||'':saved?.text||current?.text||'';
    drafts[id]={...(newer?current:saved),text,textLength:text.length,uploads:files};delete drafts[id].fileIds;
    if(sessionId===id){$('input').value=text;uploads=files.slice();renderAttachments();resizeComposer();}
  }).finally(()=>{draftLoads.delete(id);if(dirtyDrafts.has(id))persistDrafts();refresh();});draftLoads.set(id,loading);refresh();
}
function resizeComposer(){const input=$('input');const cap=parseFloat(getComputedStyle(input).maxHeight)||230;input.style.height='auto';input.style.height=Math.min(input.scrollHeight,cap)+'px';}
function grow(){resizeComposer();saveDraft();refresh();}
function renderAttachments(){
  const active=document.activeElement,focused=$('attachments').contains(active),focusId=active?.dataset.fileId,index=[...$('attachments').children].indexOf(active);
  $('attachments').replaceChildren();
  uploads.forEach((file,index)=>{
    const remove=button(file.name+' ×',()=>{uploads.splice(index,1);renderAttachments();saveDraft();});
    remove.dataset.fileId=file.id;remove.title='Remove '+file.name;remove.setAttribute('aria-label',remove.title);$('attachments').append(remove);
  });
  if(focused){const remaining=[...$('attachments').children];(remaining.find(n=>n.dataset.fileId===focusId)||remaining[Math.min(index,remaining.length-1)]||$('attach')).focus({preventScroll:true});}
  setBusy(busy);
}
function hasContent(){return !!$('input').value.trim()||uploads.length>0||!!(window.UAI&&UAI.pictures&&UAI.pictures.hasStaged());}
function picturesBusy(){return !!(window.UAI&&UAI.pictures&&UAI.pictures.busy());}
function setBusy(value){busy=!!value;refresh();}
function refresh(){
  const generating=busy;
  const canQueue=!!state.queue,queueing=canQueue&&(generating||state.queue.count>0);
  $('stop').hidden=!generating;$('send').hidden=generating&&!canQueue;
  $('send').title=queueing?'Queue follow-up':'Send message';$('send').setAttribute('aria-label',$('send').title);
  $('stop').disabled=stopping||!connected;
  const blocked=stopping||sending||sendPhase!=='idle'||readingFiles>0||draftLoads.has(sessionId)||!connected||picturesBusy()||UAI.pictures?.hasErrors()||canQueue&&state.queue.count>=state.queue.limit;
  $('send').disabled=blocked||!hasContent();
  $('attachPictures').hidden=!UAI.pictures?.enabled();
  $('transcript').setAttribute('aria-busy',String(generating||sendPhase!=='idle'));
  document.body.dataset.op=generating?'generating':(sendPhase!=='idle'?sendPhase:'idle');
  document.body.dataset.link=link;document.body.dataset.game=connected?'connected':'disconnected';
  $('connectionLabel').textContent=connected?'Game connected':link==='online'?'Connect your game':'Bridge reconnecting';
  $('localConnection').textContent=link==='online'?'Connected locally':'Draft kept here';
  $('connectionBanner').hidden=connected||page==='cowork';
  $('connectionMessage').textContent=link==='online'?'One last step: connect Roblox to this bridge.':'Connection interrupted. Keep the bridge terminal open; your draft is safe here.';
  $('composerHint').textContent=UAI.pictures?.hasErrors()?'Retry or remove the picture that could not be attached.':picturesBusy()?'Preparing images…':readingFiles?'Reading attached files…':draftLoads.has(sessionId)?'Restoring your draft…':stopping?'Stopping the current turn…':sendPhase!=='idle'?(OP_LABEL[sendPhase]||'Working…'):queueing?'Enter to queue a follow-up · Stop ends the current turn':'Enter to send · Shift+Enter for a new line';
  $('deliveryNotice').hidden=sendPhase!=='uncertain';
  $('deliveryMessage').textContent=sendOperation?.lost?'Delivery could not be confirmed. Review your conversation before sending again.':'Still waiting for a delivery receipt. Your draft is safe.';
  $('deliveryReview').hidden=!sendOperation?.lost;
  if(stopping)announce('Stopping the current turn…');
  else if(sendPhase!=='idle')announce(OP_LABEL[sendPhase]||'Working…');
  else if(link==='offline'||link==='disconnected')announce('Bridge reconnecting…');
  else if(!connected)announce('Game offline');
  else announce(state.agent?.status||'Ready');
}
function setPhase(phase){sendPhase=phase;refresh();}
function armAwaitTurn(operation){
  clearTimeout(awaitTurnTimer);
  if(operation.sawTurn||sessionId!==operation.sessionId){setPhase('idle');return;}
  sendPhase='awaiting-turn';refresh();
  awaitTurnTimer=setTimeout(()=>{if(sendPhase==='awaiting-turn'){setPhase('idle');toast('The message was delivered. Roblox has not started a turn yet.');}},10000);
}
function copyText(text){
  if(navigator.clipboard&&window.isSecureContext){return navigator.clipboard.writeText(text).then(()=>toast('Copied')).catch(()=>fallbackCopy(text));}
  return Promise.resolve(fallbackCopy(text));
}
function fallbackCopy(text){
  try{const area=el('textarea');area.value=text;area.setAttribute('readonly','');area.style.position='fixed';area.style.opacity='0';document.body.append(area);area.select();const ok=document.execCommand('copy');area.remove();toast(ok?'Copied':'Clipboard unavailable');}
  catch{toast('Clipboard unavailable');}
}
// Two-step arm/confirm for destructive actions (replaces raw confirm()).
function armButton(btn,confirmLabel,fn){
  const original=[...btn.childNodes].map(n=>n.cloneNode(true)),label=btn.getAttribute('aria-label'),title=btn.getAttribute('title');let armed=false,timer;
  const reset=()=>{armed=false;btn.replaceChildren(...original.map(n=>n.cloneNode(true)));btn.classList.remove('armed');for(const [name,value]of [['aria-label',label],['title',title]]){if(value===null)btn.removeAttribute(name);else btn.setAttribute(name,value);}};
  btn.onclick=()=>{
    if(!armed){armed=true;btn.textContent=confirmLabel;btn.setAttribute('aria-label',confirmLabel);btn.title=confirmLabel;btn.classList.add('armed');timer=setTimeout(reset,4000);return;}
    clearTimeout(timer);reset();fn();
  };
}
function stick(){const t=$('transcript');return t.scrollHeight-t.scrollTop-t.clientHeight<120;}
let composerMotion,composerFrame;
const composerReducedMotion=matchMedia('(prefers-reduced-motion: reduce)');
composerReducedMotion.addEventListener('change',()=>{if(composerReducedMotion.matches){composerMotion?.cancel();cancelAnimationFrame(composerFrame);}});
function chatLayout(empty){
  const next=empty?'empty':'thread',previous=document.body.dataset.chat;
  if(previous===next)return;
  const composer=$('composer'),animate=previous&&!renderingSnapshot&&page==='chat'&&!$('app').hidden&&!composerReducedMotion.matches;
  const before=animate?composer.getBoundingClientRect():null;
  composerMotion?.cancel();cancelAnimationFrame(composerFrame);document.body.dataset.chat=next;$('suggestions').hidden=!empty;
  if(before){
    // Measure after the welcome/message DOM has reached its new layout.
    composerFrame=requestAnimationFrame(()=>{
      if(page!=='chat'||$('app').hidden||composerReducedMotion.matches)return;
      const after=composer.getBoundingClientRect(),distance=before.top-after.top;
      if(Math.abs(distance)>2)composerMotion=composer.animate([{transform:`translateY(${distance}px)`},{transform:'translateY(0)'}],{duration:460,easing:'cubic-bezier(.22,1,.36,1)'});
    });
  }
}
function trimTranscript(){
  const root=$('transcript'),selector='.message,.tool-call,.thinking,.activity-note,.subagent-report';
  // A grouped turn can contain many entries. Bound the leaves as well as the
  // top-level history; never let a focused old control block all later eviction.
  const retained=[...root.querySelectorAll(selector)].sort((a,b)=>a._uaiTranscriptOrder-b._uaiTranscriptOrder);let excess=retained.length-450;
  const remove=node=>{
    const response=responseFor(node);
    renderer.dropNode(node);
    for(const message of [node,...node.querySelectorAll('.message.agent')])if(message._uaiReasoning){message._uaiReasoning.remove();message._uaiReasoning=null;}
    if(node._uaiReasoningOwner)node._uaiReasoningOwner._uaiReasoning=null;
    for(const [key,row]of tools)if(node.contains(row.node))tools.delete(key);
    node.remove();
    if(response){if(!response.node.querySelector(selector))response.node.remove();else updateResponse(response);}
  };
  for(const node of retained){
    if(excess<=0)break;
    if(!node.isConnected){excess--;continue;}
    if(node.contains(document.activeElement)||node._uaiReasoning?.contains(document.activeElement))continue;
    remove(node);excess--;
  }
  for(const node of [...root.children]){if(root.children.length<=450)break;if(!node.contains(document.activeElement))remove(node);}
}
function append(node,parent=$('transcript')){const pinned=!renderingSnapshot&&stick();const root=$('transcript');chatLayout(false);root.querySelector('.welcome')?.remove();if(renderingSnapshot)node.classList.add('restored');node._uaiTranscriptOrder=++transcriptOrder;parent.append(node);trimTranscript();if(pinned)scrollToEnd();}
function resetResponses(){currentResponse=null;responseUser=null;}
function responseFor(node){return node.closest('.response-turn')?._response;}
function updateResponse(response){
  if(!response?.node.isConnected)return;
  const calls=[...response.activity.querySelectorAll('.tool-call>.tool')],running=calls.filter(node=>node.dataset.status==='running');
  const failed=calls.filter(node=>['failed','timeout'].includes(node.dataset.status));
  const declined=calls.filter(node=>node.dataset.status==='declined'),unknown=calls.filter(node=>node.dataset.status==='unknown');
  const thoughts=response.activity.querySelectorAll('.thinking').length,notes=response.activity.querySelectorAll('.activity-note,.subagent-report').length;
  const messages=[...response.content.querySelectorAll('.message.agent')],live=messages.findLast(node=>['waiting','thinking','writing','saving'].includes(node.dataset.responseState));
  const latest=running.at(-1),progress=latest?.querySelector('.tool-progress');
  const working=!response.ended&&(running.length||live);
  const label=live?.dataset.responseState==='writing'?'Writing':live?.dataset.responseState==='thinking'?'Thinking':'Working';
  response.status.textContent=response.stopped?'Stopped':working?label:'';
  response.status.hidden=!response.status.textContent;
  response.node.dataset.state=response.stopped?'stopped':working?'working':'complete';
  response.activity.hidden=!calls.length&&!thoughts&&!notes;
  response.activity.dataset.state=failed.length?'issue':working?'working':'complete';
  response.activityTitle.textContent=working?'Working through your request':'Activity';
  const counts=[];
  if(calls.length)counts.push(calls.length+' '+(calls.length===1?'step':'steps'));
  if(thoughts)counts.push('Reasoning');
  if(notes)counts.push('Updates');
  if(failed.length)counts.push(failed.length+' failed');
  if(declined.length)counts.push(declined.length+' declined');
  if(unknown.length)counts.push(unknown.length+' without a saved result');
  response.activityMeta.textContent=counts.join(' · ');
  const current=progress&&!progress.hidden?progress.textContent:latest?.querySelector('.tool-head>strong')?.textContent;
  const issue=failed.at(-1)?.querySelector('.tool-outcome')?.textContent;
  response.activityDetail.textContent=toolExcerpt(current||issue||'',180);
  response.activityDetail.hidden=!response.activityDetail.textContent;
  response.activityAction.textContent=response.activity.open?'Hide details':'View details';
}
function ensureResponse(model){
  if(currentResponse?.node.isConnected&&!currentResponse.ended){if(model)currentResponse.model.textContent=model;return currentResponse;}
  const node=el('section','response-turn'),heading=el('header','response-heading'),mark=el('span','answer-mark');
  node.setAttribute('aria-label','Cowork response');mark.setAttribute('aria-hidden','true');
  const modelName=el('small','response-model',model||state.agent?.model||''),status=el('span','response-status');
  status.hidden=true;status.setAttribute('role','status');status.setAttribute('aria-live','polite');
  heading.append(mark,el('span','response-author','Cowork'),modelName,status);
  const content=el('div','response-content'),activity=el('details','response-activity'),summary=el('summary','activity-summary'),activityTitle=el('span','activity-title','Activity');
  const activityMeta=el('span','activity-meta'),activityDetail=el('span','activity-current'),activityAction=el('span','activity-action','View details'),list=el('div','activity-list');
  summary.append(el('span','activity-dot'),activityTitle,activityMeta,activityAction,activityDetail);activity.append(summary,list);activity.hidden=true;
  summary.querySelector('.activity-dot').setAttribute('aria-hidden','true');
  const footer=el('footer','response-footer'),copy=button('Copy response',()=>copyText([...content.querySelectorAll('.message.agent')].map(message=>message._uaiText||'').filter(Boolean).join('\n\n')),'response-copy');
  footer.hidden=true;footer.append(copy);node.append(heading,content,activity,footer);
  const response={node,model:modelName,status,content,activity,list,activityTitle,activityMeta,activityDetail,activityAction,footer,user:responseUser,ended:false};
  node._response=response;currentResponse=response;
  activity.addEventListener('toggle',()=>updateResponse(response));append(node);return response;
}
function appendActivity(node,response=ensureResponse()){append(node,response.list);updateResponse(response);return response;}
function finishResponse(stopped=false){
  if(!currentResponse)return;
  currentResponse.ended=true;currentResponse.stopped=stopped;responseUser=null;
  for(const row of tools.values())if(responseFor(row.node)===currentResponse&&row.node.dataset.status==='running'){
    row.node.dataset.status=stopped?'stopped':'unknown';row.verdict.textContent=stopped?'Stopped':'No saved result';row.progress.hidden=true;
  }
  updateResponse(currentResponse);
}
function message(who,text,model){
  const node=el('article','message '+who),byline=el('div','byline');
  if(who==='agent'){const mark=el('span','answer-mark');mark.setAttribute('aria-hidden','true');byline.append(mark);}
  byline.append(el('span','message-author',who==='user'?(state.player||'You'):'Cowork'),el('small','message-model',model||''));
  const body=el('div','body');if(who==='user')body.textContent=text;else body.innerHTML=md(text);node.append(byline,body);
  const result={node,body};if(who==='user')decorateMessage(result,text);append(node,who==='agent'?ensureResponse(model).content:$('transcript'));return result;
}
function decorateMessage(message,text,model){
  message.node._uaiText=text;
  if(model)message.node.querySelector('.message-model').textContent=model;
  const response=responseFor(message.node);
  if(response){if(model)response.model.textContent=model;response.footer.hidden=![...response.content.querySelectorAll('.message.agent')].some(node=>node._uaiText);updateResponse(response);return;}
  if(message.node.querySelector('.message-actions'))return;
  const actions=el('span','message-actions'),copy=button('',()=>copyText(message.node._uaiText),'icon-button');copy.append(icon('copy'));copy.title='Copy message';copy.setAttribute('aria-label','Copy message');actions.append(copy);
  if(message.node.classList.contains('agent')){const footer=el('div','message-footer');copy.append(el('span',null,'Copy'));footer.append(actions);message.node.append(footer);}
  else message.node.querySelector('.byline').append(actions);
}
function welcome(){
  const empty=!busy&&!state.queue?.count&&!events.some(e=>e.kind==='user'||e.kind==='assistant:text')&&![...$('transcript').children].some(node=>!node.classList.contains('welcome'));
  chatLayout(empty);if(!empty){$('transcript').querySelector('.welcome')?.remove();return;}
  const signature=JSON.stringify([state.player,state.place?.name,state.providers?.length,connected]);
  const previous=$('transcript').querySelector('.welcome');if(previous?.dataset.signature===signature||previous?.contains(document.activeElement))return;
  const node=el('section','welcome');
  node.dataset.signature=signature;
  node.append(el('p','welcome-greeting',state.player?'Hello, '+state.player+'.':'A little space for your next idea.'),el('h1',null,"What's on your mind?"));
  if(state.place?.name){const context=el('div','welcome-context');context.append(el('span','status-dot'),el('span',null,state.place.name));node.append(context);}
  const suggestions=$('suggestions');
  if(!suggestions.children.length)starters.forEach(([title,detail,prompt],index)=>{const item=button('',()=>insert(prompt),'starter');item.title=prompt;item.append(icon(['explore','spark','activity','player'][index]),el('span',null,title));suggestions.append(item);});
  if(!connected)node.append(button('Connect Roblox to get started',()=>show('cowork'),'welcome-action'));
  else if(!state.providers?.length)node.append(button('Add a provider to get started',()=>providerEditor(),'welcome-action'));
  $('transcript').replaceChildren(node);
}
const starters=[['Explore this game','Find your bearings in the world.','Explore this game. Inspect the workspace and tell me what is here, how it is organised, and what we could do next.'],['Create something','Turn an idea into a working script.','Help me build a Luau script for this game. First inspect the relevant game context, then ask what I would like to create.'],['Check performance','Understand FPS, memory, and latency.','Check client performance, memory usage, and network latency. Explain the results and suggest practical improvements.'],['Inspect my character',"See your character’s current state.",'Inspect my character and explain its position, humanoid state, and any useful attributes or attached scripts.']];
function insert(text){show('chat');$('input').value+=($('input').value?'\n\n':'')+text;grow();$('input').focus();}
function metric(value,label){const n=el('div');n.append(el('strong',null,typeof value==='number'?value.toLocaleString():value),el('small',null,label));return n;}
function deadlineHelp(root,message,status){
  if(root.querySelector('.deadline-help'))return;
  const link=el('a','deadline-help','Get help and updates on Discord');link.href='https://discord.gg/9xYyyYuKap';link.target='_blank';link.rel='noopener noreferrer';root.append(link);
}
function toolKey(e){return (e.kind?.startsWith('subagent:')?'child:'+e.id+':':'main:')+(e.callId||e.id||'')+':'+(e.name||'');}
function codeListing(text,label,options={}){
  const listing=el('div','code-block tool-listing'),head=el('div','code-head');
  const copy=button('Copy',()=>copyText(text));
  copy.setAttribute('aria-label','Copy '+label);head.append(el('span',null,label),copy);
  if(options.wrap)listing.classList.add('tool-wrap');
  const pre=el('pre'),code=el('code',null,options.display??text);pre.tabIndex=0;pre.setAttribute('aria-label',label);pre.append(code);listing.append(head,pre);return listing;
}
function toolDetail(label,content,open=false){
  const detail=el('details','tool-detail');detail.open=open;detail.append(el('summary',null,label),content);return detail;
}
function toolExcerpt(value,limit=160){
  const text=String(value??'').replace(/\s+/g,' ').trim();return text.length>limit?text.slice(0,limit-1)+'…':text;
}
function toolTarget(args){
  if(!args||typeof args!=='object')return 'No input';
  for(const key of ['path','query','url','target','name','task','command'])if(typeof args[key]==='string'&&args[key].trim())return toolExcerpt(args[key]);
  for(const key of ['code','source','content','new_text'])if(typeof args[key]==='string'){const lines=args[key].split('\n').length;return lines+' '+(lines===1?'line':'lines')+(key==='code'?' of Luau':' of '+key.replaceAll('_',' '));}
  const keys=Object.keys(args);return keys.length?keys.length+' input '+(keys.length===1?'field':'fields'):'No input';
}
function toolLabel(name){return String(name||'Tool').replaceAll('_',' ').replace(/\b(?:luau|lua|json|http|api|ui|mcp)\b/gi,value=>({luau:'Luau',lua:'Lua'}[value.toLowerCase()]||value.toUpperCase())).replace(/^./,value=>value.toUpperCase());}
function toolInput(args,raw){
  const input=el('div','tool-input'),fields=el('dl','tool-fields');
  if(args&&typeof args==='object'&&!Array.isArray(args))for(const [key,value]of Object.entries(args)){
    if(['code','source','content','old_text','new_text'].includes(key)||value!==null&&typeof value==='object')continue;
    const row=el('div');row.append(el('dt',null,toolLabel(key)),el('dd',null,toolExcerpt(value===null?'null':value,500)));fields.append(row);
  }
  if(fields.children.length)input.append(fields);
  if(state.settings?.ui?.showToolCode!==false)for(const [key,label]of [['code','Luau'],['source','Source'],['content','File contents'],['old_text','Before'],['new_text','After']]){
    if(typeof args?.[key]==='string'){const listing=codeListing(args[key],label);listing.classList.add('tool-code-input');input.append(listing);}
  }
  input.append(toolDetail('Raw arguments',codeListing(raw,'Arguments',{wrap:true,display:args!==undefined?JSON.stringify(args,null,2):raw})));
  return input;
}
function toolErrorText(event,text){
  let parsed;try{parsed=JSON.parse(text);}catch{}
  const candidates=[event.data?.error?.message,event.data?.message,parsed?.error?.message,typeof parsed?.error==='string'?parsed.error:null,parsed?.message];
  let message=candidates.find(value=>typeof value==='string'&&value.trim());
  if(!message&&parsed&&typeof parsed==='object')message='The tool reported an error. Open the call to inspect its result.';
  if(!message){
    const lines=String(text||event.error||'The tool did not complete.').trim().split(/\r?\n/),kept=[];
    for(const line of lines){if(kept.length&&/^\s*(?:stack (?:trace|begin)|traceback|at\s|\[C\]:)/i.test(line))break;if(!line.trim()&&kept.length)break;kept.push(line);if(kept.length===3)break;}
    message=kept.join(' ');
  }
  return toolExcerpt(message,420);
}
function failureInfo(event,raw,tool=false){
  const text=raw.replace(/\s*Help and updates:\s*https:\/\/discord\.gg\/9xYyyYuKap\s*/gi,'').trim();
  const status=Number(event.status)||Number(text.match(/\b(?:HTTP|status|returned)\s*[:(]?\s*(\d{3})\b/i)?.[1]);
  const stopped=event.state==='cancelled'||event.error==='aborted'||event.data?.status==='aborted';
  const declined=event.denied===true;
  if(stopped)return {title:tool?'Step stopped':'Request stopped',message:tool?'This step was stopped before it finished.':event.hasPreview?'The partial response is kept above. You can continue when you are ready.':'You can continue the conversation when you are ready.',tone:'neutral'};
  if(declined)return {title:'Permission declined',message:'This step was skipped because permission was not granted.',tone:'neutral'};
  if(tool)return {title:/timeout|timed out/i.test(text)||event.error==='timeout'?'This step took too long':'This step could not finish',message:toolErrorText(event,text),tone:'error'};
  if(/invalid\s*executor.?request|companion could not read the executor|request encoding|invalid gzip request/i.test(text))return {title:'Update UAI Relay to continue',message:'Update the UAI Relay app and reload the UAI script. Keep your current pairing.',action:'connection',tone:'warning'};
  if(/(?:bridge|relay)[\s\S]{0,120}(?:token|unauthorized|authentication|authorization)|(?:token|unauthorized|authentication|authorization)[\s\S]{0,80}(?:bridge|relay)|token no longer works/i.test(text))return {title:'Check your bridge connection',message:'The bridge did not accept this connection. Open Connection to check the current pairing details.',action:'connection',tone:'warning'};
  if(status===429||/rate.?limit|too many requests/i.test(text))return {title:'Request limit reached',message:'The provider is limiting requests. Wait a moment before trying again.',tone:'warning'};
  if(status===401||status===403||/invalid.{0,12}(?:api.?key|token)|authentication/i.test(text))return {title:'Check your provider access',message:'The request was not authorized. Check the selected provider’s API key and account access.',action:'providers',tone:'warning'};
  if(/timeout|timed out|deadline/i.test(text))return {title:'The request took too long',message:'The provider or connection stopped waiting for a response. You can review your message before trying again.',tone:'warning'};
  if(/stream.{0,40}(?:ended|closed|interrupted)|incomplete stream/i.test(text))return {title:'The response was interrupted',message:'The provider stopped sending before the response was complete.'+(event.hasPreview?' The partial text is kept above.':''),tone:'warning'};
  if(/ECONN|ENOTFOUND|network|fetch failed|connection/i.test(text))return {title:'The connection was interrupted',message:'Your conversation is still here. Check the connection before trying again.',action:'connection',tone:'warning'};
  if(status>=500)return {title:'The service could not complete the request',message:'The service returned an error. Review your message and try again when it is available.',tone:'error'};
  const readable=toolErrorText(event,text).replace(/^Error:\s*/i,'');
  const technical=!readable||/^\s*[<{\[]|stack|exception|traceback|\b(?:HTTP|ERR_|TypeError|SyntaxError)\b/i.test(readable)||readable.length>300;
  return {title:'The request could not be completed',message:technical?'An error interrupted this request. You can review the details below before trying again.':readable,tone:'error'};
}
function renderFailure(root,event,{tool=false,raw:provided}={}){
  const value=provided??event.message??event.error??event.providerError??'Unknown error';
  let raw=typeof value==='string'?value:JSON.stringify(value,null,2);
  if(!tool&&typeof event.providerError==='string'&&event.providerError!==value)raw+='\n\nProvider detail:\n'+event.providerError;
  const info=failureInfo(event,raw,tool);
  root.classList.add('response-error');root.dataset.tone=info.tone;
  const copy=el('div','error-copy'),head=el('div','error-heading'),mark=el('span','error-mark',info.tone==='neutral'?'—':'!');
  mark.setAttribute('aria-hidden','true');head.append(mark,el('h3','error-title',info.title));
  copy.append(head,el('p','error-message',info.message));
  const details=el('details','error-details');details.append(el('summary',null,'Technical details'),codeListing(raw,tool?'Full error':'Error details',{wrap:true}));
  const actions=el('div','error-actions');
  if(info.action==='providers')actions.append(button('Open providers',()=>show('providers'),'outline'));
  if(info.action==='connection')actions.append(button('Check connection',()=>show('cowork'),'outline'));
  if(!tool&&info.tone!=='neutral')deadlineHelp(actions,raw,event.status);
  root.replaceChildren(copy,actions,details);return actions;
}
function toolResultSummary(event,text){
  if(typeof event.summary==='string'&&event.summary.trim())return toolExcerpt(event.summary);
  let parsed;try{parsed=JSON.parse(text);}catch{}
  if(parsed&&typeof parsed==='object'){const message=[parsed.message,parsed.summary].find(value=>typeof value==='string'&&value.trim());return toolExcerpt(message||(Array.isArray(parsed)?parsed.length+' items returned':'Result available'));}
  if(/^(done|success|ok)[.!]?$/i.test(text.trim()))return '';
  const first=text.split(/\r?\n/).find(line=>line.trim())||'';
  if(/^\s*(?:`{3,}|~{3,})/.test(first))return 'Code result available';
  return toolExcerpt(first.replace(/^\s*(?:#{1,6}|>|[-*+])\s+/,'').replace(/\[([^\]]+)\]\([^)]*\)/g,'$1')
    .replace(/(`+)(.*?)\1/g,'$2').replace(/\*\*(.+?)\*\*/g,'$1').replace(/\*([^*]+)\*/g,'$1'));
}
function toolOutput(text){
  let parsed;try{parsed=JSON.parse(text);}catch{}
  if(parsed!==undefined)return codeListing(text,'Result',{wrap:true,display:JSON.stringify(parsed,null,2)});
  const output=el('div','tool-output'),head=el('div','code-head'),copy=button('Copy',()=>copyText(text));
  copy.setAttribute('aria-label','Copy Result');head.append(el('span',null,'Result'),copy);
  const body=el('div','body tool-result-content');body.innerHTML=md(text);output.append(head,body);return output;
}
function openTool(e){
  const wrapper=el('section','tool-call'),node=el('details','tool'),head=el('summary','tool-head');
  node.dataset.status='running';
  const raw=typeof e.arguments==='string'?e.arguments:JSON.stringify(e.arguments||{});
  let args;try{args=JSON.parse(raw);}catch{}
  const preview=el('span','arguments',args?toolTarget(args):'Input available');
  const verdict=el('small','tool-status','Running');verdict.setAttribute('role','status');
  preview.title=args?toolTarget(args):'';
  const duration=el('small','tool-duration'),outcome=el('span','tool-outcome');outcome.hidden=true;
  const progress=el('span','tool-progress');progress.hidden=true;progress.setAttribute('role','status');
  const name=el('strong',null,toolLabel(e.name));name.title=e.name||'Tool';
  head.append(name,verdict,duration,preview,progress,outcome);node.append(head);
  const body=el('div','tool-body'),identity=el('div','tool-identity');
  identity.append(el('code',null,e.name||'Tool'),el('span',null,e.kind==='subagent:tool'?'Subagent tool call':'Tool call'));
  body.append(identity,toolDetail('Input',toolInput(args,raw)));node.append(body);wrapper.append(node);
  appendActivity(wrapper);tools.set(toolKey(e),{node,body,preview,progress,verdict,duration,outcome,restored:renderingSnapshot});
}
function finishTool(e){
  const key=toolKey(e),row=tools.get(key);
  if(!row)return;
  const stopped=e.error==='aborted'||e.data?.status==='aborted',timeout=e.error==='timeout'||e.data?.status==='timeout';
  const failed=e.kind==='tool:error'||e.ok===false||stopped||timeout||e.denied===true;
  row.node.dataset.status=stopped?'stopped':timeout?'timeout':e.denied?'declined':failed?'failed':'done';
  row.verdict.textContent=stopped?'Stopped':timeout?'Timed out':e.denied?'Declined':failed?'Failed':'Done';
  row.progress.hidden=true;
  if(Number.isFinite(e.ms))row.duration.textContent=e.ms<1000?Math.round(e.ms)+' ms':(e.ms/1000).toFixed(1)+' s';
  const text=typeof e.text==='string'?e.text:String(e.summary||e.error||(e.data?JSON.stringify(e.data,null,2):'(No output)'));
  row.outcome.textContent=failed?toolErrorText(e,text):toolResultSummary(e,text);row.outcome.hidden=!row.outcome.textContent;
  const output=el('div');
  if(failed){const error=el('div');renderFailure(error,e,{tool:true,raw:text});output.append(error);}
  else output.append(toolOutput(text));
  if(e.data&&typeof e.data==='object')output.append(toolDetail('Result data',codeListing(JSON.stringify(e.data,null,2),'Result data',{wrap:true})));
  if(e.truncated)output.append(el('p','tool-retention-note','This is the retained excerpt. Ask the agent for a narrower result if you need more.'));
  if(timeout)deadlineHelp(output,e.error||e.text,e.status);
  row.body.append(toolDetail(stopped||e.denied?'Details':failed?'Error details':'Result',output,true));
  updateResponse(responseFor(row.node));
  tools.delete(key);
}
function renderEvent(e){
  if(e.sessionId&&sessionId&&e.sessionId!==sessionId)return;
  const pinned=!renderingSnapshot&&stick();
  switch(e.kind){
    case 'user':{
      const pending=currentResponse?.node.querySelector('.message:is([data-response-state=waiting],[data-response-state=thinking],[data-response-state=writing],[data-response-state=saving]),.tool[data-status=running]');
      const early=currentResponse?.node.isConnected&&!currentResponse.user&&!currentResponse.ended&&pending?currentResponse:null;
      if(!early)currentResponse=null;
      const m=message('user',e.text||'');responseUser=m.node;const anchored=renderer.anchorUser(e,m.node);
      if(early&&anchored===early.node)early.user=m.node;
      else if(early)currentResponse=null;
      if(window.UAI&&UAI.pictures)UAI.pictures.correlateUser(m,e);break;
    }
    case 'assistant:text':renderer.commitText(e);break;
    case 'assistant:reasoning':renderer.commitReasoning(e);break;
    case 'tool:call':case 'subagent:tool':openTool(e);break;
    case 'tool:result':case 'tool:error':case 'subagent:tool:done':finishTool(e);break;
    case 'tool:progress':{const row=tools.get(toolKey(e))||(!e.id&&tools.size===1?[...tools.values()][0]:null);if(row){row.progress.textContent=e.text||'';row.progress.hidden=!e.text;updateResponse(responseFor(row.node));}break;}
    case 'error':{const error=el('div','error');error.setAttribute('role','alert');const actions=renderFailure(error,e);actions.prepend(button('Review message',()=>resendLast(e.sessionId||sessionId),'retry'));append(error);break;}
    case 'status':announce(e.text||'Ready');break;
    case 'turn:start':if(sendOperation&&sendOperation.sessionId===sessionId)sendOperation.sawTurn=true;clearTimeout(awaitTurnTimer);if(sendPhase!=='uncertain')sendPhase='idle';setBusy(true);break;
    case 'turn:end':case 'abort':if(sendOperation&&sendOperation.sessionId===sessionId)sendOperation.sawTurn=true;clearTimeout(awaitTurnTimer);if(sendPhase!=='uncertain')sendPhase='idle';renderer.endTurn(sessionId,e.kind==='abort');finishResponse(e.kind==='abort');setBusy(false);break;
    case 'cleared':events=[];renderer.reset();tools.clear();resetResponses();if(window.UAI&&UAI.pictures)UAI.pictures.clearSession(sessionId);$('transcript').replaceChildren();welcome();break;
    case 'provider:switch':append(el('div','note','Switched provider to '+e.to));break;
    case 'model:route':append(el('div','note',e.text||('Automatic free routing selected '+e.model+'. Turn it off in Settings → Agent → Automatic free routing.')));break;
    case 'request:retry':append(el('div','note',`Retrying ${e.provider||'provider'} · ${e.reason||''}`));break;
    case 'subagent:start':appendActivity(el('div','note activity-note','Subagent · '+(e.task||e.label||'')));break;
    case 'subagent:done':appendActivity(el('div','note activity-note','Subagent finished · '+(e.label||'')));break;
    case 'subagent:text':{const report=el('details','subagent-report'),body=el('div','body');report.append(el('summary',null,(e.label||'Subagent')+' · report'));body.innerHTML=md(e.text||'');report.append(body);appendActivity(report);break;}
    case 'compact':append(el('div','note','Older context compacted'));break;
  }
  if(pinned)scrollToEnd();
  if(!renderingSnapshot)$('latest').hidden=stick();
}
function scrollToEnd(){$('transcript').scrollTop=$('transcript').scrollHeight;}
function resendLast(target){
  if(target&&target!==sessionId){toast('Open the original conversation to retry.');return;}
  show('chat');
  if(lastSend&&lastSend.sessionId===sessionId&&typeof lastSend.text==='string'){
    if(!$('input').value.trim()){$('input').value=lastSend.text;if(!uploads.length)uploads=(lastSend.files||[]).map(f=>({...f,id:uuid()}));renderAttachments();}
  }else if(lastSend&&lastSend.sessionId!==sessionId){toast('Switch back to that conversation to retry.');}
  grow();$('input').focus();
}
const renderer=window.UAIStreamRenderer.create({
  md, escape:UAIMarkdown.escape,
  createAgentMessage:model=>message('agent','',model),
  responseRoot:node=>node.closest('.response-turn')||node,
  attachReasoning:(entry,details)=>{details.dataset.reasoningRequestId=entry.requestId||'';details._uaiReasoningOwner=entry.node;entry.node._uaiReasoning=details;appendActivity(details,responseFor(entry.node));},
  onState:entry=>updateResponse(responseFor(entry.node)),
  getSession:()=>sessionId,
  defaultModel:()=>state.agent?.model,
  isPinned:stick,
  scrollToEnd,
  onActivity:active=>{document.body.dataset.streaming=active?'on':'off';},
  onRetry:resendLast,
  onCopyReasoning:copyText,
  onError:renderFailure,
  onFinal:decorateMessage,
});
UAI.pictures=UAI.createPictures({token,browserId,getSession:()=>sessionId,api,toast,tray:$('pictureTray'),input:$('pictureInput'),pickerButton:$('attachPictures'),dropZone:$('composer'),onTextFiles:attachFiles,onChange:refresh});
function apply(e){
  if(typeof e.kind!=='string')return;
  if(e.kind==='bridge:update'){bridgeUpdate=e.update||{};if(page==='cowork')requestPanelRefresh();return;}
  if(e.kind==='kilo:state'){kiloStatus=e.kilo||{};if(page==='cowork'||page==='tunnels')requestPanelRefresh();return;}
  if(e.kind==='cline:state'){clineStatus=e.cline||{};if(page==='tunnels')requestPanelRefresh();return;}
  if(e.kind==='opencode:state'){openCodeStatus=e.opencode||{};if(page==='tunnels')requestPanelRefresh();return;}
  if(e.kind==='bridge:reset'){events=[];eventBytes=0;renderer.reset();tools.clear();resetResponses();UAI.pictures.resetMessages();$('transcript').replaceChildren();welcome();if(e.resync)toast('Connection restored. Reloaded the latest saved conversation.');return;}
  if(e.kind==='bridge:snapshot'){
    const readingSession=sessionId,readingY=$('transcript').scrollTop,wasPinned=stick();
    events=[];eventBytes=0;for(const event of Array.isArray(e.events)?e.events:[])retainEvent(event);
    renderer.reset();tools.clear();resetResponses();UAI.pictures.resetMessages();$('transcript').replaceChildren();changeSession(e.sessionId);
    renderingSnapshot=true;
    try{for(const event of events)renderEvent(event);}finally{renderingSnapshot=false;}
    welcome();
    if(readingSession===sessionId&&!wasPinned)$('transcript').scrollTop=readingY;else scrollToEnd();
    $('latest').hidden=stick();return;
  }
  if(e.kind==='bridge:state'){
    const next=e.state||{};changeSession(next.sessionId);state=next;renderState();
    if(requestedSettings){const section=requestedSettings;requestedSettings=null;openSettings(section);}
    if(!state.agent?.busy)for(const row of tools.values())if(row.restored){
      row.restored=false;row.node.dataset.status='unknown';row.verdict.textContent='No saved result';
      row.outcome.textContent='No result was kept in this transcript.';row.outcome.hidden=false;
      updateResponse(responseFor(row.node));
    }
    return;
  }
  if(e.kind==='bridge:game'){const changed=connected!==!!e.connected;connected=!!e.connected;setBusy(state.agent?.busy);renderQueue();welcome();if(changed&&page==='cowork')requestPanelRefresh();return;}
  if(e.kind==='inference:start'){renderer.start(e);return;}
  if(e.kind==='inference:delta'){renderer.delta(e);return;}
  if(e.kind==='inference:done'){renderer.done(e);return;}
  if(e.kind==='inference:resync'){renderer.resync(e);return;}
  if(e.kind==='bridge:picture'){if(window.UAI&&UAI.pictures)UAI.pictures.handleEvent(e);return;}
  if(e.kind.startsWith('bridge:'))return;
  if(e.sessionId&&sessionId&&e.sessionId!==sessionId)return;
  retainEvent(e);renderEvent(e);
}
function retainEvent(e){
  if(!e||typeof e.kind!=='string')return;
  const bytes=new TextEncoder().encode(JSON.stringify(e)).length;
  if(bytes>MAX_EVENTS_BYTES)return;
  events.push(e);eventBytes+=bytes;
  while(events.length>400||eventBytes>MAX_EVENTS_BYTES){eventBytes-=new TextEncoder().encode(JSON.stringify(events.shift())).length;}
}
const appliedThemeVars=new Set();
// Apply the game-provided #rrggbb theme, clearing any var that has disappeared so
// the stylesheet default returns; reject invalid values. Runtime model colour is
// kept in --model-accent so it never overwrites the structural accent roles.
function applyTheme(colors){
  const next=new Set();
  const allowed=new Set(['canvas','sidebar','surface','surfaceRaised','surfaceActive','border','text','textSecondary','textTertiary','accent','accentHot','solid','onSolid']);
  for(const [name,value]of Object.entries(UAI.theme.get()==='game'?(colors||{}):{})){
    if(!allowed.has(name))continue;
    if(typeof value==='string'&&/^#[a-f0-9]{6}$/i.test(value)){document.documentElement.style.setProperty('--'+name,value);next.add(name);}
  }
  for(const name of appliedThemeVars)if(!next.has(name))document.documentElement.style.removeProperty('--'+name);
  appliedThemeVars.clear();for(const n of next)appliedThemeVars.add(n);
  if(/^#[a-f0-9]{6}$/i.test(colors?.canvas||'')){const rgb=colors.canvas.slice(1).match(/../g).map(v=>parseInt(v,16));UAI.theme.game((rgb[0]*.2126+rgb[1]*.7152+rgb[2]*.0722)<128);}
  const mc=colors?.modelAccent||colors?.['model-accent']||state.agent?.accent||state.agent?.color;
  if(typeof mc==='string'&&/^#[a-f0-9]{6}$/i.test(mc))document.documentElement.style.setProperty('--model-accent',mc);
  else document.documentElement.style.removeProperty('--model-accent');
}
function renderState(){
  applyTheme(state.theme||{});
  const ui=state.settings?.ui||{};
  document.documentElement.style.setProperty('--reading',({narrow:'640px',medium:'780px',wide:'920px'})[ui.transcriptWidth]||'780px');
  document.documentElement.style.setProperty('--chat-font-size',(16*Math.max(.85,Math.min(1.4,ui.fontScale||1)))+'px');
  document.body.dataset.reasoning=ui.showReasoning===false?'hidden':'visible';document.body.dataset.density=ui.density||'comfortable';document.body.dataset.codeTheme=ui.codeTheme||UAI.theme.resolved();
  $('playerName').textContent=state.player||'you';$('providerName').textContent=state.agent?.provider||'No provider connected';$('modelLabel').textContent=state.agent?.model||'Select model';$('runtimeBadge').textContent=state.runtime==='web'?'Web · streaming':'Game runtime';
  $('modelButton').setAttribute('aria-label',state.agent?.model?'Select model, current model '+state.agent.model:'Select model');
  const activeProvider=(state.providers||[]).find(p=>p.id===state.activeProvider),freeModel=isFreeModel(activeProvider,state.agent?.model);
  $('modelButton').classList.toggle('is-free',freeModel);$('modelFree').hidden=!freeModel;
  renderContext();
  $('runtimeBadge').dataset.runtime=state.runtime||'game';$('playerInitial').textContent=(state.player||'U').slice(0,1).toUpperCase();
  const permission=({readonly:'Read only',ask:'Ask first',auto:'Auto',full:'Allow all'})[state.permissions?.mode]||'Ask first';$('permissionBadge').querySelector('span').textContent=permission;
  setBusy(state.agent?.busy);
  renderThreads();renderQuestions();renderStrips();renderQueue();welcome();if($('modal').open)modalRefresh?.();if(page!=='chat')requestPanelRefresh();
}
function editQueued(item,owner){
  modal('Edit follow-up',root=>{
    const form=el('form','dialog-form');root.append(form);
    const input=field(form,'Message',item.text,'textarea');input.rows=6;input.required=true;
    const count=el('small','queue-edit-count');form.append(count);
    const save=button('Save changes',()=>form.requestSubmit(),'primary');
    const update=()=>{const bytes=new TextEncoder().encode(input.value).length;count.textContent=bytes.toLocaleString()+' / 8,000 bytes';save.disabled=!input.value.trim()||bytes>8000;};
    input.addEventListener('input',update);update();
    form.onsubmit=event=>{event.preventDefault();if(!save.disabled)modalCommand('queue:edit',{sessionId:owner,messageId:item.id,text:input.value,expectedText:item.text});};
    modalActions(modalCancel(),save);
  },{description:'Your composer draft and this message’s attached images stay in place.'});
}
function clearQueued(items,owner){
  const ids=items.map(item=>item.id);
  modal('Clear queued follow-ups?',root=>{
    root.append(el('p','muted','Remove these '+ids.length+' queued messages. The current response keeps running.'));
    const list=el('ol','queue-clear-list');for(const item of items)list.append(el('li',null,toolExcerpt(item.text||'Attached input',180)));root.append(list);
    modalActions(modalCancel(),button('Clear queued',()=>modalCommand('queue:clear',{sessionId:owner,messageIds:ids}),'danger outline'));
  });
}
async function queueAction(row,type,fields){
  const owner=sessionId,focused=document.activeElement;let succeeded=false;
  row.dataset.pending='true';row.querySelectorAll('button').forEach(node=>node.disabled=true);
  try{await command(type,{sessionId:owner,...fields});succeeded=true;}
  catch(error){toast(error.message);}
  finally{
    delete row.dataset.pending;delete $('queuedMessages').dataset.signature;renderQueue();
    if(owner===sessionId&&[document.body,focused].includes(document.activeElement)){
      const target=succeeded&&type==='queue:remove'?$('input'):focused?.isConnected&&!focused.disabled&&focused.getClientRects().length?focused:row.querySelector('summary')||$('input');
      if(target.isConnected)target.focus({preventScroll:true});
    }
  }
}
function renderQueue(){
  const root=$('queuedMessages'),queue=state.queue||{},items=Array.isArray(queue.items)?queue.items:[],operations=queue.operations||{};
  const hadFocus=root.contains(document.activeElement);root.hidden=!items.length;if(!items.length){root.replaceChildren();delete root.dataset.signature;if(hadFocus)$('input').focus({preventScroll:true});return;}
  const signature=JSON.stringify([sessionId,queue,connected]);if(root.dataset.signature===signature)return;root.dataset.signature=signature;
  if(root.dataset.session!==sessionId){root.replaceChildren();root.dataset.session=sessionId;}
  root.dataset.state=queue.held?'paused':'queued';
  const focused=hadFocus?document.activeElement?.dataset.focusKey:null,oldRows=new Map([...root.querySelectorAll('.queued-item')].map(row=>[row.dataset.messageId,row]));
  let heading=root.querySelector('.queued-heading'),list=root.querySelector('.queued-list');
  if(!heading){
    heading=el('div','queued-heading');const title=el('div','queued-title');title.append(el('strong'),el('small'));
    const clear=button('Clear',()=>clearQueued(state.queue.items,sessionId),'queue-clear','queue:clear');
    const resume=button('Resume queue',()=>queueAction(heading,'queue:resume',{}),'outline queue-resume','queue:resume');
    heading.append(title,clear,resume);list=el('div','queued-list');list.setAttribute('role','list');root.append(heading,list);
  }
  heading.querySelector('strong').textContent=queue.held?'Follow-ups paused':items.length+' follow-up'+(items.length===1?'':'s')+' queued';
  heading.querySelector('small').textContent=queue.held?items.length+' waiting for you':'Added after the current response or tool batch';
  const resume=heading.querySelector('.queue-resume');resume.hidden=!queue.held;resume.disabled=!connected||heading.dataset.pending==='true';
  const clear=heading.querySelector('.queue-clear');clear.hidden=!operations.clear;clear.disabled=!connected||heading.dataset.pending==='true';
  let reason=root.querySelector('.queue-reason');if(queue.held&&queue.reason){if(!reason){reason=el('p','queue-reason');root.insertBefore(reason,list);}reason.textContent=queue.reason;}else reason?.remove();
  const wanted=new Set(items.map(item=>String(item.id)));for(const [id,row]of oldRows)if(!wanted.has(id))row.remove();
  items.forEach((item,index)=>{
    const id=String(item.id);let row=oldRows.get(id);
    if(!row){
      row=el('div','queued-item');row.dataset.messageId=id;row.setAttribute('role','listitem');
      const order=el('span','queue-order'),detail=el('details','queued-copy'),summary=el('summary');summary.dataset.focusKey='queue:review:'+id;
      summary.append(el('p'),el('small'));const body=el('div','queued-detail'),full=el('p','queued-full'),actions=el('div','queue-actions');
      const edit=button('Edit',()=>editQueued(row._item,sessionId),'queue-edit','queue:edit:'+id);
      const move=direction=>{const liveItems=state.queue?.items||[],at=liveItems.findIndex(value=>String(value.id)===id),neighbor=liveItems[at+direction];if(neighbor)queueAction(row,'queue:move',{messageId:id,direction,neighborId:neighbor.id});};
      const up=button('Move up',()=>move(-1),'queue-up','queue:up:'+id),down=button('Move down',()=>move(1),'queue-down','queue:down:'+id);
      const copy=button('Copy',()=>copyText(row._item.text||''),'queue-copy','queue:copy:'+id);
      actions.append(edit,up,down,copy);body.append(full,actions);detail.append(summary,body);
      const remove=button('Remove',()=>queueAction(row,'queue:remove',{messageId:id}),'queue-remove','queue:remove:'+id);
      row.append(order,detail,remove);
    }
    row._item=item;row.querySelector('.queue-order').textContent=String(index+1);
    row.querySelector('summary p').textContent=item.text||'Attached input';row.querySelector('.queued-full').textContent=item.text||'Attached input';
    const images=Array.isArray(item.images)?item.images.length:0,files=Array.isArray(item.files)?item.files.length:0;
    row.querySelector('summary small').textContent=(item.state==='preparing'?'Preparing attachments':queue.held?'Paused':index===0?'Up next':'Waiting')+(files?' · '+files+' file'+(files===1?'':'s'):'')+(images?' · '+images+' image'+(images===1?'':'s'):'');
    row.querySelectorAll('button').forEach(node=>node.disabled=!connected||row.dataset.pending==='true');
    row.querySelector('.queue-edit').hidden=!operations.edit||item.state!=='queued'||files>0;
    for(const [selector,neighbor]of [['.queue-up',items[index-1]],['.queue-down',items[index+1]]]){const control=row.querySelector(selector);control.hidden=!operations.move||!neighbor;control.disabled=control.disabled||item.state!=='queued'||neighbor?.state!=='queued';}
    row.querySelector('.queue-remove').setAttribute('aria-label','Remove queued message '+(index+1));
    if(list.children[index]!==row)list.insertBefore(row,list.children[index]||null);
  });
  if(focused&&!root.contains(document.activeElement)){const replacement=[...root.querySelectorAll('[data-focus-key]')].find(node=>node.dataset.focusKey===focused&&!node.disabled&&node.getClientRects().length)||root.querySelector('.queued-copy summary')||$('input');replacement.focus({preventScroll:true});}
}
function renderThreads(){
  const search=$('threadSearch').value.toLowerCase(),root=$('threads'),signature=JSON.stringify([search,state.threads]);
  if(root.dataset.signature===signature)return;root.dataset.signature=signature;
  const focused=document.activeElement?.closest('.thread'),focusId=focused?.dataset.id,menu=document.activeElement?.classList.contains('thread-menu');
  root.replaceChildren();const groups=new Map();
  for(const t of state.threads||[]){if(search&&!String(t.title||'New chat').toLowerCase().includes(search))continue;const group=t.place||'Current game';if(!groups.has(group))groups.set(group,[]);groups.get(group).push(t);}
  for(const [name,list]of groups){root.append(el('div','place-heading',name));for(const thread of list){
    const row=el('div','thread'+(thread.active?' active':''));row.dataset.id=thread.id;
    const open=button((thread.busy?'◌ ':'')+(thread.title||'New chat'),()=>openConversation(thread.id));open.title=thread.title||'New chat';if(thread.active)open.setAttribute('aria-current','true');
    const more=button('···',()=>threadMenu(thread),'thread-menu');more.setAttribute('aria-label','Options for '+(thread.title||'New chat'));row.append(open);if(thread.queuedCount>0){const queued=el('span','thread-queued',String(thread.queuedCount));queued.title=thread.queuedCount+' queued'+(thread.queueHeld?' · paused':'');queued.setAttribute('aria-label',queued.title);row.append(queued);}row.append(more);root.append(row);
    if(thread.id===focusId)(menu?more:open).focus({preventScroll:true});
  }}
  if(!groups.size)root.append(el('p','history-empty',search?'No matching conversations.':'Your conversations will appear here.'));
}
function threadMenu(thread){modal('Conversation details',root=>{
  const form=el('form','dialog-form');form.id='modalForm';root.append(form);
  const name=field(form,'Title',thread.title);name.maxLength=60;name.required=true;
  form.onsubmit=event=>{event.preventDefault();modalCommand('thread:rename',{id:thread.id,title:name.value.trim()});};
  const privacy=el('section','dialog-section');privacy.append(el('h3',null,thread.ephemeral?'Isolated conversation':'Saved conversation'),el('p','muted',thread.ephemeral?'This conversation is temporary. Save it to keep it in your history.':'Isolate this conversation to keep it out of saved history.'),button(thread.ephemeral?'Save conversation':'Make isolated',()=>modalCommand('thread:isolate',{sessionId:thread.id,value:!(state.threads?.find(t=>t.id===thread.id)||thread).ephemeral}),'outline'));root.append(privacy);
  const del=button('Delete',()=>{},'danger outline');armButton(del,'Confirm delete?',()=>modalCommand('thread:delete',{id:thread.id}));
  const rename=el('button','primary','Rename');rename.type='submit';rename.setAttribute('form',form.id);
  modalActions(del,el('span','spacer'),modalCancel(),rename);
},{description:'Rename, save, or manage this conversation.',size:'compact'});}
function renderStrips(){
  const todos=state.todos||[],root=$('taskStrip'),signature=JSON.stringify([sessionId,todos]);root.hidden=!todos.length;
  if(root.dataset.signature!==signature){
    let details=root.querySelector('details');
    if(!details){details=el('details');details.append(el('summary'),el('div','task-list'));root.append(details);}
    if(root.dataset.session!==sessionId)details.open=false;
    details.querySelector('summary').textContent=`${todos.filter(t=>t.status==='done').length}/${todos.length} tasks completed`;
    details.querySelector('.task-list').replaceChildren(...todos.map(t=>el('div',null,`${t.status==='done'?'✓':'○'} ${t.text}`)));
    root.dataset.signature=signature;root.dataset.session=sessionId||'';
  }
  const loops=(state.loops||[]).filter(l=>l.state==='running'),strip=$('loopStrip');strip.hidden=!loops.length;
  if(!strip.children.length)strip.append(button('',()=>show('loops')),button('Stop all',()=>action('loops:stop',{id:'all'}),'danger'));
  strip.firstElementChild.textContent=`${loops.length} chat loop(s) running`;
}
function renderQuestions(){
  const root=$('questions'),entries=[...(state.pendingPermissions||[]).map(req=>({type:'permission',req})),...(state.questions||[]).map(req=>({type:'question',req}))];
  for(const entry of entries){const req=entry.req;entry.key=entry.type+':'+req.id;entry.context=req.sessionTitle||state.threads?.find(t=>t.id===req.sessionId)?.title||req.sessionId||'Current conversation';}
  const signature=JSON.stringify(entries);if(root.dataset.signature===signature)return;root.dataset.signature=signature;
  const focused=root.contains(document.activeElement)?document.activeElement:null,selection=focused&&typeof focused.selectionStart==='number'?[focused.selectionStart,focused.selectionEnd,focused.selectionDirection]:null;
  const existing=new Map([...root.children].map(card=>[card.dataset.requestKey,card])),keys=new Set(entries.map(entry=>entry.key));
  for(const [key,card]of existing)if(!keys.has(key))card.remove();
  entries.forEach(({type,req,key,context},index)=>{
    let card=existing.get(key);
    if(!card){
      card=el('section','question');card.dataset.requestKey=key;
      const title=el('strong'),caption=el('small','question-context');title.id='request-title-'+uuid();caption.id=title.id+'-context';
      card.setAttribute('aria-labelledby',title.id);card.setAttribute('aria-describedby',caption.id);card.append(title,caption);card._title=title;card._context=caption;
      if(type==='permission'){
        const args=el('pre');args.tabIndex=0;card._args=args;card.append(args);
        const remember=el('input');remember.type='checkbox';const label=el('label',null,'Remember this decision');label.prepend(remember);
        const row=el('div','row');
        for(const allowed of [true,false])row.append(button(allowed?'Allow':'Deny',()=>{const current=card._request;return action('permission',{id:current.id,allow:allowed,remember:remember.checked,...(current.sessionId?{sessionId:current.sessionId}:{})});},allowed?'primary':'danger'));
        row.append(label);card.append(row);
      }else{
        const form=el('form','row'),options=el('div','row question-options'),input=el('input'),send=el('button','primary','Send');input.type='text';input.required=true;input.placeholder='Or type an answer';input.setAttribute('aria-labelledby',title.id);input.setAttribute('aria-describedby',caption.id);send.type='submit';
        form.onsubmit=event=>{event.preventDefault();action('ask:answer',{id:card._request.id,text:input.value});};
        form.append(options,input,send,button('Dismiss',()=>action('ask:answer',{id:card._request.id,text:''})));card.append(form);card._options=options;
      }
    }
    card._request=req;card._title.textContent=type==='permission'?'Allow '+req.name+'?':req.question;card._context.textContent='Conversation: '+context;
    if(type==='permission'){card._args.textContent=JSON.stringify(req.args||{},null,2);card._args.setAttribute('aria-label','Arguments for '+req.name);}
    else{const optionsSignature=JSON.stringify(req.options||[]);if(card._options.dataset.signature!==optionsSignature){card._options.replaceChildren(...(req.options||[]).map(option=>button(option,()=>action('ask:answer',{id:card._request.id,text:option}))));card._options.dataset.signature=optionsSignature;}}
    if(root.children[index]!==card)root.insertBefore(card,root.children[index]||null);
  });
  if(focused){const target=focused.isConnected?focused:root.querySelector('button,input,[tabindex="0"]')||$('input');if(document.activeElement!==target)target.focus({preventScroll:true});if(selection&&target===focused)focused.setSelectionRange(...selection);}
}
const workspaceViews={cowork:['Connection','Bring Roblox, your tools, and this conversation together.'],providers:['Providers','Choose the models and connections you work with.'],tools:['Tools','Browse available tools and control what they can do.'],agents:['Subagents','Follow delegated work and inspect its results.'],loops:['Chat loops','Manage recurring conversations and game workflows.'],memory:['Memory & skills','Keep useful context and reusable workflows close.'],logs:['Activity','Review requests, execution details, and diagnostic messages.']};
workspaceViews.tunnels=['Tunnels','Free model connections owned by your local bridge.'];
let workspaceOpener=null,workspaceRestore=true,workspaceBackdropStart=false;
function markPage(){document.querySelectorAll('button[data-page]').forEach(b=>{b.classList.toggle('selected',b.dataset.page===page);if(b.dataset.page===page)b.setAttribute('aria-current','page');else b.removeAttribute('aria-current');});}
function show(next){
  if(next==='settings'){openSettings();return;}if(next!=='chat'&&!workspaceViews[next])return;
  const dialog=$('workspaceModal');if(next!=='chat'&&!dialog.open)workspaceOpener=document.activeElement;
  page=next;document.body.dataset.page=page;closeSidebar();$('chatPage').hidden=false;$('panel').hidden=page==='chat';$('pageTitle').textContent='Chat';markPage();
  if(page==='chat'){if(dialog.open){workspaceRestore=false;dialog.close();}welcome();resizeComposer();$('input').focus({preventScroll:true});}
  else{
    const [title,description]=workspaceViews[page];$('workspaceTitle').textContent=title;$('workspaceDescription').textContent=description;dialog.dataset.page=page;
    renderPanel();if(!dialog.open){workspaceRestore=true;dialog.showModal();}else $('panel').scrollTop=0;
    $('workspaceTabs').querySelector('[aria-current=page]')?.scrollIntoView({block:'nearest',inline:'nearest'});
    $('workspaceTitle').focus({preventScroll:true});
  }refresh();
}
function closeWorkspace(restore=true){workspaceRestore=restore;if($('workspaceModal').open)$('workspaceModal').close();}
for(const [id,[label]]of Object.entries(workspaceViews)){const tab=button(label,()=>show(id));tab.dataset.page=id;$('workspaceTabs').append(tab);}
$('workspaceTabs').append(button('Settings',()=>show('settings')));
$('workspaceClose').onclick=()=>closeWorkspace();$('workspaceDone').onclick=()=>show('chat');
$('workspaceModal').addEventListener('cancel',event=>{event.preventDefault();closeWorkspace();});
$('workspaceModal').addEventListener('pointerdown',event=>{workspaceBackdropStart=event.target===$('workspaceModal')&&outsideWorkspace(event);});
$('workspaceModal').addEventListener('click',event=>{if(workspaceBackdropStart&&event.target===$('workspaceModal')&&outsideWorkspace(event))closeWorkspace();workspaceBackdropStart=false;});
function outsideWorkspace(event){const r=$('workspaceModal').getBoundingClientRect();return event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom;}
$('workspaceModal').addEventListener('close',()=>{
  if($('workspaceModal').open)return;const opener=workspaceOpener,restore=workspaceRestore;workspaceOpener=null;page='chat';document.body.dataset.page='chat';$('panel').hidden=true;markPage();welcome();resizeComposer();refresh();
  if($('app').hidden||$('modal').open)return;
  const target=restore&&opener?.isConnected&&opener.getClientRects().length?opener:restore?$('sidebarToggle'):$('input');if(!target.disabled)target.focus({preventScroll:true});
});
async function openConversation(id){
  try{await command(id?'thread':'thread:new',id?{id}:{});show('chat');}catch(error){toast(error.message);}
}
function heading(root,title,control){const h=el('div','panel-heading');h.append(el('h1',null,title));if(control)h.append(control);root.append(h);}
function card(root,title){const n=el('section','card');if(title)n.append(el('h3',null,title));root.append(n);return n;}
let toolFilter='',logFilter='';
function buildPanel(root){root.replaceChildren();
  if(page==='memory'){heading(root,'Memory & skills');root.append(el('p','panel-description','Keep useful context and reusable workflows close to your conversation.'));const list=el('div','tool-grid knowledge-list');root.append(list);for(const tool of state.tools||[]){if(tool.name.startsWith('memory_')||tool.name.startsWith('skills_')){const c=card(list),copy=el('div','catalog-copy');copy.append(el('span','pill',tool.name.startsWith('memory_')?'Memory':'Skill'),el('h3',null,tool.name),el('p',null,tool.description));c.append(copy,button('Open',()=>runTool(tool.name),'outline'));}}return;}
  if(page==='cowork'){renderCowork(root);}
  else if(page==='tunnels'){renderTunnels(root);}
  else if(page==='providers'){
    heading(root,'Providers',button('Add provider',()=>providerEditor(),'primary','provider:add'));
    root.append(el('p','panel-description','Manage your connections, check their health, and choose which provider powers your conversation.'));
    for(const p of state.providers||[]){const c=card(root),active=state.activeProvider===p.id;c.classList.add('provider-card');c.dataset.active=String(active);
      const header=el('div','provider-heading');header.append(el('h2',null,p.label),el('span','pill',active?'Active provider':p.enabled===false?'Disabled':'Available'));c.append(header,el('p','provider-url',p.baseUrl||'No endpoint configured'));
      const model=el('div','provider-model');model.append(el('span','eyebrow','CURRENT MODEL'),el('strong',null,p.model||'No model selected'));if(isFreeModel(p,p.model)){model.classList.add('is-free');model.append(el('span','free-label','Free'));}c.append(model);if(freeRouteText(p))c.append(el('p','free-route',freeRouteText(p)));
      const row=el('div','provider-actions'),health=el('span','provider-health',`${p.health?.ok||0} successful · ${p.health?.fail||0} failed`),use=button(active?'Active':'Use',()=>action('provider',{id:p.id}),active?'selected':'outline','provider:'+p.id+':use');use.setAttribute('aria-pressed',String(active));use.disabled=!connected;
      row.append(health,el('span','spacer'),button('Test connection',async()=>{try{const result=await command('provider:test',{id:p.id});toast(result.text+' · '+result.ms+' ms');}catch(error){toast(error.message);}},null,'provider:'+p.id+':test'),use,button('Edit',()=>providerEditor(p),'outline','provider:'+p.id+':edit'));c.append(row);if(p.health?.lastError)c.append(el('p','provider-error',p.health.lastError));}
  }
  else if(page==='tools'){const filter=el('input');filter.type='search';filter.placeholder='Search tools';filter.setAttribute('aria-label','Search tools');filter.value=toolFilter;filter.oninput=()=>{toolFilter=filter.value;renderToolCards(list);};heading(root,'Tools',filter);root.append(el('p','panel-description','Explore the actions available in your game. Review permissions or run a tool directly.'));const list=el('div','tool-grid');root.append(list);renderToolCards(list);}
  else if(page==='agents'){heading(root,'Subagents');root.append(el('p','panel-description','Follow delegated work, review results, and stop a task when you need to.'));for(const a of state.subagents||[]){const c=card(root);c.classList.add('agent-card');const head=el('div','item-heading');head.append(el('h3',null,a.label||a.id),el('span','pill',agentStatus(a)));c.append(head,el('p','agent-task-excerpt',a.currentTask||a.task));const facts=[a.provider,a.model,agentElapsed(a.elapsedMs??a.ms)];c.append(el('small','agent-card-meta',facts.filter(Boolean).join(' · ')));const actions=el('div','agent-card-actions');actions.append(button('Preview',()=>agentDetails(a.id),'outline','agent:'+a.id+':preview'));if(['running','queued'].includes(a.status))actions.append(button('Stop',()=>action('subagent:stop',{id:a.id}),'danger outline'));c.append(actions);}}
  else if(page==='loops'){heading(root,'Chat loops',button('Start chatbot',()=>runTool('chat_bot',{instructions:'Be friendly, casual, and helpful.'}),'primary'));root.append(el('p','panel-description','Set up a repeating conversation and keep track of what is running.'));const row=el('div','loop-launchers');for(const [name,title,detail]of [['quiz_bot','Run a quiz','Host questions and keep score.'],['auto_chat','Auto chat','Send messages on a schedule.'],['auto_reply','Auto reply','Respond to incoming messages.']]){const launch=button('',()=>runTool(name),'loop-launcher');launch.append(el('strong',null,title),el('small',null,detail));row.append(launch);}root.append(row);for(const l of state.loops||[]){const c=card(root);c.classList.add('loop-card');const head=el('div','item-heading');head.append(el('h3',null,l.kind==='bot'?'Chatbot':l.kind),el('span','pill',l.state));c.append(head,el('p','muted',`${l.channel} · ${l.sent}/${l.count} messages sent`));if(l.reason)c.append(el('small',null,l.reason));for(const score of Object.values(l.scores||{}))c.append(el('div','score-row',`${score.name}: ${score.points}`));if(l.state==='running')c.append(button('Stop',()=>action('loops:stop',{id:l.id}),'danger outline'));}}
  else if(page==='logs'){heading(root,'Activity',button('Clear logs',()=>action('logs:clear'),'outline'));root.append(el('p','panel-description','Requests, connection events, and diagnostic messages from your workspace.'));const filter=field(root,'Filter activity',logFilter);filter.type='search';filter.placeholder='Search by message, provider, or endpoint';const list=el('div','activity-list');root.append(list);filter.oninput=()=>{logFilter=filter.value;renderLogs(list);};renderLogs(list);}
}
function renderToolCards(root){root.replaceChildren();for(const t of state.tools||[]){if(!`${t.name} ${t.description}`.toLowerCase().includes(toolFilter.toLowerCase()))continue;const c=card(root),copy=el('div','catalog-copy'),head=el('div','item-heading');head.append(el('h3',null,t.name),el('span','pill',t.risk||'Tool'));copy.append(head,el('p',null,t.description));if(!t.available)copy.append(el('small','unavailable','Unavailable on this executor'));const row=el('div','tool-actions');const rule=select(row,'Permission',['default','ask','allow','deny'],t.rule||'default');rule.onchange=()=>action('tool:rule',{name:t.name,rule:rule.value});row.append(button('Run…',()=>runTool(t.name),'outline'),button(t.enabled?'Disable group':'Enable group',()=>action('tool:group',{group:t.group,enabled:!t.enabled})));c.append(copy,row);}if(toolFilter&&!root.childElementCount)root.append(el('p','model-empty','No tools match your search.'));}
function renderLogs(root){root.replaceChildren();const query=logFilter.trim().toLowerCase();
  for(const request of [...(state.requests||[])].reverse()){if(query&&!JSON.stringify(request).toLowerCase().includes(query))continue;
    const c=card(root),heading=el('div','activity-heading');heading.append(el('strong',null,request.tag||request.method||'Request'),el('span','pill',String(request.status||'Error')),el('small',null,(request.ms||0)+' ms'));c.append(heading,el('p','provider-url',request.url||'Local request'));if(request.via)c.append(el('small','muted','Via '+request.via));if(request.error){c.append(el('p','provider-error',request.error));deadlineHelp(c,request.error,request.status);}}
  for(const entry of [...(state.logs||[])].reverse()){const text=typeof entry==='string'?entry:JSON.stringify(entry);if(query&&!text.toLowerCase().includes(query))continue;const row=el('div','log-entry'),level=typeof entry==='object'?entry.level||entry.kind||'Log':'Log';row.append(el('span','pill',level),el('p',null,typeof entry==='string'?entry:entry.message||entry.text||text));root.append(row);}
  if(query&&!root.childElementCount)root.append(el('p','model-empty','No activity matches this filter.'));
}
function runTool(name,initial){
  const tool=state.tools?.find(t=>t.name===name);
  modal(name,root=>{
    root.append(el('p','muted',tool?.description||''));
    const form=el('form','tool-form'),fields=el('div','form-grid'),inputs={};
    const required=new Set(tool?.parameters?.required||[]);
    form.append(fields);root.append(form);
    for(const [key,schema]of Object.entries(tool?.parameters?.properties||{})){
      const value=initial?.[key]??schema.default,type=schema.type;
      const label=key.replace(/_/g,' ')+(required.has(key)?' *':'');
      let input;
      if(schema.enum||type==='boolean'){
        const choices=schema.enum||[true,false];
        input=select(fields,label,[['',required.has(key)?'Choose a value':'Use default'],...choices.map(v=>[String(v),String(v)])],value===undefined?'':String(value));
      }else{
        const multiline=['array','object'].includes(type)||/^(code|source|script|content|body|text|instructions|old_text|new_text|patch|diff)$/.test(key)||String(value||'').includes('\n');
        input=field(fields,label,value===undefined?'':typeof value==='object'?JSON.stringify(value,null,2):value,multiline?'textarea':['number','integer'].includes(type)?'number':'text');
        if(multiline){input.rows=key==='code'?9:4;input.spellcheck=false;input.classList.add('code-input');input.parentElement.classList.add('field-wide');}
        if(type==='integer')input.step='1';else if(type==='number')input.step='any';
        if(schema.minimum!==undefined)input.min=schema.minimum;
        if(schema.maximum!==undefined)input.max=schema.maximum;
        if(schema.maxLength!==undefined)input.maxLength=schema.maxLength;
        if(schema.minLength!==undefined)input.minLength=schema.minLength;
      }
      input.name=key;input.dataset.parameter=key;
      input.required=required.has(key)&&(!!schema.enum||type!=='string'||schema.minLength>0);
      inputs[key]={input,schema};
      if(schema.description){const help=el('small','field-help',schema.description);help.id='tool-help-'+key;input.parentElement.append(help);input.setAttribute('aria-describedby',help.id);}
    }
    const output=el('p','form-error');output.setAttribute('role','alert');output.hidden=true;
    const run=el('button','primary','Run tool');run.type='submit';form.id='modalForm';run.setAttribute('form',form.id);
    run.disabled=tool?.available===false||tool?.enabled===false||!connected;
    form.append(el('small','field-help','* Required parameter. Your current permissions apply.'),output);modalActions(modalCancel(),run);
    let running=false;
    form.onsubmit=async event=>{
      event.preventDefault();if(running)return;
      output.hidden=true;
      const args={};
      try{
        for(const [key,{input,schema}]of Object.entries(inputs)){
          const raw=input.value,type=schema.type;
          if(raw===''&&!required.has(key))continue;
          let value=raw;
          if(['array','object','boolean'].includes(type)){
            try{value=JSON.parse(raw);}catch{throw Error(key+': enter valid '+(type==='boolean'?'true or false':'JSON')+'.');}
            if(type==='array'&&!Array.isArray(value))throw Error(key+': enter a JSON array.');
            if(type==='object'&&(!value||typeof value!=='object'||Array.isArray(value)))throw Error(key+': enter a JSON object.');
            if(type==='boolean'&&typeof value!=='boolean')throw Error(key+': choose true or false.');
          }else if(['number','integer'].includes(type)){
            value=Number(raw);
            if(!raw.trim()||!Number.isFinite(value)||(type==='integer'&&!Number.isInteger(value)))throw Error(key+': enter a valid '+type+'.');
          }
          args[key]=value;
        }
      }catch(err){output.textContent=err.message;output.hidden=false;return;}
      running=true;run.disabled=true;
      const originSession=sessionId;
      // Approvals live in the transcript, so release the dialog before waiting.
      closeModal(true,false);show('chat');toast('Running '+name+'…');
      try{
        const result=await command('tool:run',{name,arguments:args});
        if(!$('modal').open&&sessionId===originSession&&page==='chat')modal(name+' result',body=>body.append(codeListing(result?.text||JSON.stringify(result,null,2),result?.ok===false?'Execution details':'Result')));
        else toast(name+' finished. Its result is in the conversation.');
      }catch(err){output.textContent=err.message;output.hidden=false;toast(err.message);}
      finally{running=false;run.disabled=false;}
    };
  },{description:'Review the parameters before running this tool. Your workspace permissions apply.',size:'wide'});
}
function providerEditor(provider){modal(provider?'Edit provider':'Add provider',root=>{
  const form=el('form','dialog-form');form.id='modalForm';root.append(form);
  const connection=el('section','dialog-section');connection.append(el('h3',null,'Connection'));form.append(connection);
  const fields=el('div','form-grid');connection.append(fields);
  const presets=(state.presets||[]).map(p=>[p.id,p.label]);if(!presets.some(p=>p[0]==='custom'))presets.push(['custom','Custom']);
  const preset=select(fields,'Preset',presets,provider?.preset||'custom'),label=field(fields,'Name',provider?.label||''),url=field(fields,'Base URL',provider?.baseUrl||'');
  url.parentElement.classList.add('field-wide');url.autocapitalize='off';url.spellcheck=false;url.placeholder='https://your-provider.example/v1';
  const apiStyle=select(fields,'API',[['openai','OpenAI compatible'],['anthropic','Anthropic Messages'],['gemini','Gemini generateContent']],provider?.api||'openai');
  const defaultAuth=()=>apiStyle.value==='gemini'&&!/\/go\/v1(?:\/|$)/i.test(url.value)?'x-goog-api-key':'bearer';
  const auth=select(fields,'Authentication',[['bearer','Bearer token'],['x-api-key','x-api-key header'],['api-key','api-key header'],['x-goog-api-key','Google API key header'],['both','Bearer + x-api-key'],['none','No authentication']],provider?.authStyle||defaultAuth());
  apiStyle.onchange=()=>{if(apiStyle.value==='gemini'||auth.value==='x-goog-api-key')auth.value=defaultAuth();};
  const credentials=el('section','dialog-section');credentials.append(el('h3',null,'Credentials and model'));form.append(credentials);
  const key=field(credentials,provider?.hasKey?'API key (blank keeps current key)':'API key','','password');key.autocomplete='new-password';key.spellcheck=false;key.autocapitalize='off';
  const model=field(credentials,'Model',provider?.model||'');model.spellcheck=false;model.placeholder='Exact model ID from your provider';
  credentials.append(el('small','field-help','Use an exact model ID. Saved providers can discover their available models in the model picker.'));
  const disclosure=el('p','provider-disclosure');form.append(disclosure);
  function describeEndpoint(){
    // Match the registry's normalized routes without URL path canonicalization.
    const raw=url.value.trim().replace(/^\/\//,''),input=/^[a-z][\w+.-]*:\/\//i.test(raw)?raw:'https://'+raw;
    const parsed=/\s/.test(input)?null:input.match(/^(https?):\/\/([a-z\d_.-]+)(?::(\d+))?(\/[^?#]*)?(?:\?[^#]*)?(?:#.*)?$/i);
    const scheme=parsed?.[1].toLowerCase(),host=parsed?.[2].toLowerCase().replace(/\.$/,''),port=parsed?.[3];
    const path=(parsed?.[4]||'').replace(/\/+$/,'')||'/v1',base=path.replace(/\/(?:chat\/completions|messages|models|responses)$/,'');
    const standard=!!parsed&&(!port||port===(scheme==='https'?'443':'80'));
    const proxy=standard&&scheme==='https'&&host==='puai-proxy.davidzk.tech'&&base==='/agentrouter/v1';
    const vendor=standard&&/^(?:[a-z\d.-]+\.)?agentrouter\.org$/.test(host)&&base==='/v1';
    const retired=standard&&['puai-proxy.davidzk.tech','puai-free-gateway.renern.workers.dev'].includes(host)&&/^\/opencode(?:\/|$)/i.test(path);
    const openCode=host==='opencode.ai'||retired;
    const go=standard&&scheme==='https'&&host==='opencode.ai'&&['/inference/go/v1','/zen/go/v1'].includes(base);
    disclosure.hidden=!proxy&&!vendor&&!openCode;
    disclosure.textContent=go?'This is the OpenCode Go subscription endpoint. Use your Go API key here. Go requests use this endpoint directly, including in Cowork.':openCode?(retired?'This OpenCode proxy route has retired. ':'')+'OpenCode free models use the direct desktop workaround. Free models can also use an installed OpenCode CLI through Cowork. Mobile OpenCode requires the UAI Relay app from Discord.':proxy?'This AgentRouter endpoint uses the Project UAI proxy. Requests and API keys pass through it, with a shared limit of 90,000 requests per day. The Base URL remains editable.':vendor?'If AgentRouter explicitly refuses the client identity, UAI can retry through the Project UAI proxy. Requests and API keys then pass through that proxy, which has a shared daily limit of 90,000 requests.':'';
    if(!disclosure.hidden)deadlineHelp(disclosure);
  }
  preset.onchange=()=>{const p=state.presets?.find(p=>p.id===preset.value);if(p){label.value=p.label||'';url.value=p.baseUrl||'';apiStyle.value=p.api||'openai';auth.value=p.authStyle||defaultAuth();}describeEndpoint();};url.oninput=describeEndpoint;describeEndpoint();
  form.onsubmit=event=>{event.preventDefault();const value={id:provider?.id,preset:preset.value,label:label.value.trim(),baseUrl:url.value.trim(),api:apiStyle.value,authStyle:auth.value,model:model.value.trim()};if(key.value)value.apiKey=key.value;modalCommand('provider:save',{provider:value});};
  if(provider){const del=button('Delete',()=>{},'danger outline');armButton(del,'Confirm delete?',()=>modalCommand('provider:remove',{id:provider.id}));modalActions(del);}
  const save=el('button','primary','Save');save.type='submit';save.setAttribute('form',form.id);modalActions(el('span','spacer'),modalCancel(),save);
},{description:'Connect the provider you want to use in this workspace.',size:'wide'});}
function isFreeModel(provider,id){
  if(!id)return false;
  if(Array.isArray(provider?.freeModels))return provider.freeModels.includes(id);
  if(provider?.free===true&&id===provider.model)return true;
  const metadata=provider?.modelInfo?.[id]||provider?.modelMetadata?.[id];
  if(metadata?.free===true)return true;
  return /(?:^|[-_:/])free(?:$|[-_:/])|^big-pickle$/i.test(id);
}
function freeRouteText(provider){const route=provider?.freeRoute;if(!route)return '';if(route.supported&&route.enabled===false)return 'Automatic free routing is off. Requests keep provider Auto. Change this in Settings → Agent → Automatic free routing.';if(route.running)return 'Checking available models for a faster response…';if(route.ready&&route.model)return 'Auto route: '+route.model+(Number.isFinite(route.ms)?' · '+(route.ms/1000).toFixed(1)+' s probe':'');return '';}
function tokenCount(value){if(!Number.isFinite(value)||value<0)return 'Unknown';return value>=1000000?(value/1000000).toFixed(value%1000000===0?0:1)+'M':value>=1000?(value/1000).toFixed(value%1000===0?0:1)+'K':Math.round(value).toLocaleString();}
function contextSnapshot(){const value=state.context;if(!value||!Number.isFinite(value.usedTokens)||value.usedTokens<0||value.sessionId&&value.sessionId!==sessionId)return null;return value;}
function contextRatio(value){return value?.windowTokens>0?value.usedTokens/value.windowTokens:null;}
function renderContext(){
  const value=contextSnapshot(),control=$('contextButton');control.hidden=!value;if(!value)return;
  const ratio=contextRatio(value),percent=ratio===null?'?':Math.round(ratio*100)+'%';
  control.style.setProperty('--context-used',Math.max(0,Math.min(1,ratio||0))*360+'deg');
  control.dataset.level=ratio>=1?'full':value.compactionTokens>0&&value.usedTokens>=value.compactionTokens||ratio>=.8?'high':'normal';
  $('contextPercent').textContent=percent;control.title=ratio===null?'Context window size is unknown':percent+' of context used';control.setAttribute('aria-label',control.title+'. View context details');
}
function contextDetails(){modal('Context window',root=>{
  root.className='context-details';const summary=el('div','context-overview'),total=el('strong'),caption=el('span'),meter=el('div','context-meter'),fill=el('span'),threshold=el('i');meter.append(fill,threshold);summary.append(total,caption);root.append(summary,meter);
  const note=el('p','context-note'),breakdown=el('div','context-breakdown');root.append(note,breakdown);
  const values=new Map();for(const [key,label]of [['systemTokens','Instructions & tools'],['messageTokens','Conversation'],['summaryTokens','Compacted history'],['remaining','Remaining capacity']]){const row=el('div'),count=el('strong');row.append(el('span',null,label),count);breakdown.append(row);values.set(key,count);}
  const compact=el('p','field-help'),model=el('p','field-help');root.append(compact,model);
  function paint(){const value=contextSnapshot();if(!value){total.textContent='Unavailable';caption.textContent='Connect your conversation to see context usage.';meter.hidden=true;breakdown.hidden=true;note.textContent='';compact.textContent='';model.textContent='';return;}
    meter.hidden=false;breakdown.hidden=false;const ratio=contextRatio(value);total.textContent=tokenCount(value.usedTokens);caption.textContent='of '+tokenCount(value.windowTokens)+' tokens';
    fill.style.width=Math.max(0,Math.min(1,ratio||0))*100+'%';meter.dataset.level=ratio>=1?'full':ratio>=.8?'high':'normal';
    threshold.hidden=!(value.compactionTokens>0&&value.windowTokens>0);threshold.style.left=Math.max(0,Math.min(1,(value.compactionTokens||0)/(value.windowTokens||1)))*100+'%';
    note.textContent=value.partial?'Partial estimate. Instruction and tool overhead is still being prepared.':value.calibrated?'Estimated from this conversation, calibrated with provider usage.':'Estimated from this conversation. The provider’s actual token count can differ.';
    for(const [key,node]of values)node.textContent=key==='remaining'?(value.windowTokens>0?tokenCount(Math.max(0,value.windowTokens-value.usedTokens)):'Unknown'):tokenCount(value[key]);
    compact.textContent=value.compactionTokens>0?'History compaction starts near '+tokenCount(value.compactionTokens)+' tokens.'+(threshold.hidden?'':' The marker shows that threshold.'):'The model’s context limit is not known yet.';
    model.textContent=value.model||state.agent?.model||'';
  }modalRefresh=paint;paint();
},{description:'See how much room this conversation has left.',size:'compact'});}
function models(){modal('Models & reasoning',root=>{
  root.className='model-picker';const filters=el('div','model-filters');root.append(filters);
  const provider=select(filters,'Provider',(state.providers||[]).map(p=>[p.id,p.label]),state.activeProvider),search=field(filters,'Search models','');search.type='search';search.placeholder='Search by model name';search.autofocus=true;
  provider.parentElement.classList.add('model-provider');search.parentElement.classList.add('model-search');filters.prepend(search.parentElement);
  const meta=el('div','model-meta'),count=el('span','muted'),freeLabel=el('label','row'),free=el('input');free.type='checkbox';freeLabel.append(free,document.createTextNode('Free only'));meta.append(count,freeLabel);root.append(meta);
  const routeStatus=el('p','free-route');root.append(routeStatus);
  const workspace=el('div','model-workspace'),results=el('div','model-results'),list=el('div','model-list'),empty=el('div','model-empty'),detail=el('section','model-detail');results.append(list,empty);workspace.append(results,detail);root.append(workspace);
  const selectedEyebrow=el('span','eyebrow','CURRENT CHOICE'),selectedName=el('h3'),selectedProvider=el('p','model-detail-provider'),capabilities=el('div','model-capabilities');detail.append(selectedEyebrow,selectedName,selectedProvider,capabilities);
  const reasoning=el('div','model-reasoning'),reasoningTitle=el('h4',null,'Reasoning effort'),efforts=el('div','effort-options'),reasoningHelp=el('p','field-help');efforts.setAttribute('role','group');efforts.setAttribute('aria-label','Reasoning effort');reasoning.append(reasoningTitle,efforts,reasoningHelp);detail.append(reasoning);
  const sampling=el('div','model-sampling'),samplingTitle=el('h4',null,'Temperature');sampling.append(samplingTitle);
  const handling=select(sampling,'Temperature handling',[['auto','Automatic'],['send','Send temperature'],['omit','Omit temperature']],'auto');
  const temperature=field(sampling,'Temperature',state.settings?.agent?.temperature??.4,'number');temperature.min=0;temperature.max=2;temperature.step=.1;temperature.required=true;
  const samplingHelp=el('p','field-help');sampling.append(samplingHelp);detail.append(sampling);
  handling.onchange=()=>{const model=state.providers?.find(p=>p.id===provider.value)?.model;if(model)modalTask(()=>command('model:temperature',{model,value:handling.value}),{success:'Temperature handling saved.'});};
  temperature.onchange=()=>{if(temperature.reportValidity())modalTask(()=>command('setting',{path:'agent.temperature',value:Number(temperature.value)}),{success:'Temperature saved.'});};
  const effortLabels={off:'Provider default',low:'Low',medium:'Medium',high:'High',xhigh:'Extra high',max:'Max'};
  function paintDetail(p){
    const id=p?.model||'',info=p?.modelInfo?.[id]||{},signature=JSON.stringify([p?.id,p?.label,id,info,state.settings?.agent?.effort,state.settings?.agent?.temperature,connected,!!modalContext?.pending,!!modalContext?.uncertain]);
    if(detail.dataset.signature===signature)return;detail.dataset.signature=signature;
    selectedName.textContent=id||'Choose a model';selectedProvider.textContent=p?.label||'Add a provider to get started';
    capabilities.replaceChildren();for(const [label,value]of [['Context window',info.contextWindow],['Max output',info.maxOutputTokens]]){const row=el('div');row.append(el('span',null,label),el('strong',null,tokenCount(value)));capabilities.append(row);}
    const levels=Array.isArray(info.efforts)?info.efforts.filter(level=>typeof level==='string'&&effortLabels[level]):[];
    const current=info.effectiveEffort||state.settings?.agent?.effort,old=new Map([...efforts.children].map(n=>[n.dataset.effort,n]));
    for(const [level,node]of old)if(!levels.includes(level))node.remove();
    for(const [index,level]of levels.entries()){let choice=old.get(level);if(!choice){choice=button(effortLabels[level],()=>modalTask(()=>command('setting',{path:'agent.effort',value:level}),{success:'Reasoning effort saved.'}),'effort-choice');choice.dataset.effort=level;}choice.classList.toggle('selected',current===level);choice.setAttribute('aria-pressed',String(current===level));choice.disabled=!connected||!!modalContext?.pending||!!modalContext?.uncertain;if(efforts.children[index]!==choice)efforts.insertBefore(choice,efforts.children[index]||null);}
    efforts.hidden=!levels.length;reasoningTitle.textContent=levels.length?'Reasoning effort':info.reasoning===false?'Standard response':'Reasoning';
    reasoningHelp.textContent=levels.length?(info.effortSource==='manual'?'Using your custom reasoning settings. ':info.effortSource==='global'?'This model uses the shared reasoning preference. ':'')+'More effort can improve difficult answers and take longer. Provider default leaves the choice to the provider.':info.reasoning===false?'This model does not advertise reasoning controls.':info.reasoning===true?'This model manages its reasoning automatically.':'No documented reasoning control for this model.';
    sampling.hidden=typeof info.temperatureAllowed!=='boolean';
    if(!sampling.hidden){const locked=!connected||!!modalContext?.pending||!!modalContext?.uncertain;handling.disabled=locked;temperature.disabled=locked||!info.temperatureAllowed;
      if(document.activeElement!==handling)handling.value=info.temperatureOverride||'auto';
      if(document.activeElement!==temperature)temperature.value=state.settings?.agent?.temperature??.4;
      samplingHelp.textContent=info.temperatureSource==='manual'?'Your model override '+(info.temperatureAllowed?'sends the shared temperature.':'omits temperature from requests.'):info.temperatureSource==='learned'?'This provider has rejected temperature for this model. Automatic leaves it out.':!info.temperatureAllowed?'This model does not use a custom temperature. Automatic leaves it out.':info.temperatureSource==='documented'?'This model supports temperature. Lower values give more consistent responses.':'No temperature restriction is known for this model. Automatic sends the shared value.';
    }
  }
  let listSignature;
  function syncProviders(){
    const providers=(state.providers||[]).filter(item=>item&&typeof item.id==='string'),oldValue=provider.value,existing=new Map([...provider.options].map(option=>[option.value,option])),wanted=new Set(providers.map(item=>item.id));
    for(const [id,option]of existing)if(!wanted.has(id))option.remove();
    providers.forEach((item,index)=>{let option=existing.get(item.id);if(!option){option=el('option');option.value=item.id;}const label=item.label||item.id;if(option.textContent!==label)option.textContent=label;if(provider.options[index]!==option)provider.insertBefore(option,provider.options[index]||null);});
    provider.value=wanted.has(oldValue)?oldValue:wanted.has(state.activeProvider)?state.activeProvider:providers[0]?.id||'';
  }
  function paint(){
    syncProviders();
    const p=state.providers?.find(p=>p.id===provider.value),query=search.value.toLowerCase(),models=Array.isArray(p?.models)?p.models:[];
    const ids=[...new Set(models.filter(id=>typeof id==='string'&&id.trim()))].filter(id=>id.toLowerCase().includes(query)&&(!free.checked||isFreeModel(p,id)));
    routeStatus.textContent=freeRouteText(p);routeStatus.hidden=!routeStatus.textContent;
    const signature=JSON.stringify([p?.id,p?.model,connected,!!modalContext?.pending,!!modalContext?.uncertain,query,free.checked,ids.map(id=>{const info=p?.modelInfo?.[id]||{};return[id,isFreeModel(p,id),info.contextWindow,info.reasoning,info.maxOutputTokens];})]);
    if(signature===listSignature){paintDetail(p);return;}listSignature=signature;
    count.textContent=ids.length+' model'+(ids.length===1?'':'s');empty.hidden=!!ids.length;empty.textContent=!state.providers?.length?'Add a provider to choose a model.':search.value||free.checked?'No models match these filters.':'No models available yet. Refresh the list, or enter an exact model ID in your provider settings.';
    const focused=list.contains(document.activeElement)?document.activeElement:null,existing=new Map([...list.children].map(n=>[n.dataset.model,n])),wanted=new Set(ids);
    for(const [id,node]of existing)if(!wanted.has(id))node.remove();
    ids.forEach((id,index)=>{let node=existing.get(id);if(!node){node=button('',()=>modalTask(()=>command('model',{provider:provider.value,model:id}),{success:'Model selection saved.'}));const head=el('span','model-row-head');head.append(el('span','model-name',id),el('span','free-label','Free'),el('span','model-check','Selected'));node.append(head,el('span','model-row-meta'));}const isFree=isFreeModel(p,id),info=p?.modelInfo?.[id]||{};node.dataset.model=id;node.classList.toggle('selected',p.model===id);node.classList.toggle('is-free',isFree);node.setAttribute('aria-pressed',String(p.model===id));node.setAttribute('aria-label',id+(isFree?', free':''));node.querySelector('.free-label').hidden=!isFree;node.querySelector('.model-check').hidden=p.model!==id;const meta=node.querySelector('.model-row-meta'),parts=[];if(info.contextWindow>0)parts.push(tokenCount(info.contextWindow)+' context');if(info.reasoning===true)parts.push('Reasoning');if(info.maxOutputTokens>0)parts.push(tokenCount(info.maxOutputTokens)+' output');meta.textContent=parts.join(' · ');meta.hidden=!parts.length;node.disabled=!connected||!!modalContext?.pending||!!modalContext?.uncertain;if(list.children[index]!==node)list.insertBefore(node,list.children[index]||null);});
    if(focused&&document.activeElement!==focused)(focused.isConnected?focused:search).focus({preventScroll:true});
    paintDetail(p);
  }
  provider.onchange=paint;search.oninput=paint;free.onchange=paint;paint();
  modalRefresh=paint;
  modalActions(button('Refresh models',()=>modalTask(()=>command('models:discover',{provider:provider.value}),{success:'Model list refreshed.'}),'outline'),button('Manage providers',()=>{closeModal(true,false);show('providers');}),el('span','spacer'),modalCancel('Done'));
},{description:'Find the right model and tune how it thinks.',size:'models'});}
function emptyState(root,symbol,title,detail,control){const n=el('section','empty-state');n.append(el('h2',null,title),el('p',null,detail));if(control)n.append(control);root.append(n);}
function agentElapsed(ms){if(!Number.isFinite(ms))return '';const seconds=Math.max(0,Math.floor(ms/1000));return seconds<60?seconds+'s':Math.floor(seconds/60)+'m '+seconds%60+'s';}
function agentStatus(agent){return agent?.stopping?'Stopping':({queued:'Queued',running:'Working',done:'Completed',failed:'Failed',stopped:'Stopped'})[agent?.status]||'Unavailable';}
function agentDetails(id){
  const initial=state.subagents?.find(agent=>agent.id===id);if(!initial)return;
  modal(initial.label||id,root=>{
    root.className='agent-preview';const context=modalContext;let section='overview',submitting=false,stoppingAgent=false,lastRecord=null,receivedAt=Date.now();
    const summary=el('div','agent-preview-summary'),status=el('strong'),current=el('p'),meta=el('span');summary.append(status,current,meta);root.append(summary);
    const tabs=el('nav','agent-preview-tabs'),panels=el('div','agent-preview-panels'),views=new Map();tabs.setAttribute('aria-label','Subagent preview sections');root.append(tabs,panels);
    for(const [key,title]of [['overview','Overview'],['tools','Tools'],['task','Task & access']]){const panel=el('section','agent-preview-page'),tab=button(title,()=>{section=key;paint();panels.scrollTop=0;});tab.dataset.section=key;tabs.append(tab);views.set(key,panel);panels.append(panel);}
    const output=views.get('overview'),messageTitle=el('h3',null,'Latest message'),message=el('div','body'),thoughts=el('details','agent-thoughts'),thoughtTitle=el('summary',null,'Latest reasoning'),reasoning=el('div','body'),resultTitle=el('h3',null,'Report'),result=el('div','body agent-result');thoughts.append(thoughtTitle,reasoning);output.append(messageTitle,message,thoughts,resultTitle,result);
    const activity=views.get('tools'),activityHint=el('p','field-help'),activityList=el('div','agent-activity-list');activity.append(activityHint,activityList);
    const task=views.get('task'),taskText=el('p','agent-full-task'),access=el('dl','agent-access');task.append(el('h3',null,'Current task'),taskText,access);
    const form=el('form','agent-followup'),input=el('textarea'),hint=el('p','field-help'),send=el('button','primary','Send follow-up');input.placeholder='A question or next task…';input.rows=2;input.maxLength=24000;input.setAttribute('aria-label','Subagent follow-up');send.type='submit';form.append(input,el('div','agent-followup-actions'));form.lastChild.append(hint,send);root.append(form);
    const stop=button('Stop subagent',async()=>{if(stoppingAgent)return;stoppingAgent=true;paint();try{await command('subagent:stop',{id});}catch(error){toast(error.message);}finally{stoppingAgent=false;if(context===modalContext)paint();}},'danger outline');
    const copy=button('Copy report',()=>copyText(state.subagents?.find(agent=>agent.id===id)?.report||''),'outline');modalActions(stop,el('span','spacer'),copy,modalCancel('Done'));
    function reading(node){const selection=document.getSelection();return node.contains(document.activeElement)||selection&&!selection.isCollapsed&&(node.contains(selection.anchorNode)||node.contains(selection.focusNode));}
    function rich(node,text){if(node.dataset.source===text||reading(node))return;node.innerHTML=md(text);node.dataset.source=text;}
    function plain(node,text){if(node.textContent!==text&&!reading(node))node.textContent=text;}
    function paint(){
      if(context!==modalContext)return;const position=panels.scrollTop,bodyPosition=root.scrollTop,a=state.subagents?.find(agent=>agent.id===id),live=['running','queued'].includes(a?.status);if(a!==lastRecord){lastRecord=a;receivedAt=Date.now();}
      status.textContent=agentStatus(a);summary.dataset.status=a?.status||'unavailable';
      const pending=Math.max(0,(a?.calls||0)-(a?.finishedCalls||0));current.textContent=!a?'This subagent is no longer retained.':a.stopping?'Finishing the current step before stopping':pending?(pending>1?pending+' tool calls in progress':'Running '+(a.currentTool||'a tool')):a.preview?.text?'Writing a response':a.preview?.reasoning?'Reasoning':a.statusText||(a.reportExcerpt?'Report available as an excerpt':live?'Waiting for the next step':'Ready to review');
      meta.textContent=[a?.provider,a?.model,agentElapsed((a?.elapsedMs??a?.ms??0)+(live?Date.now()-receivedAt:0)),a?`${a.finishedCalls||0} of ${a.calls||0} tool calls finished`:''].filter(Boolean).join(' · ');
      for(const [key,panel]of views){panel.hidden=key!==section;const tab=tabs.querySelector('[data-section="'+key+'"]');tab.setAttribute('aria-current',key===section?'page':'false');}
      const latest=a?.preview?.text||a?.latestText||'',reason=a?.preview?.reasoning||a?.latestReasoning||'';
      messageTitle.textContent=(a?.preview?.text?'Live message':'Latest message')+((a?.preview?.textExcerpt||a?.textExcerpt)?' · excerpt':'');rich(message,latest||(live?'No message delivered yet.':'No intermediate message was delivered.'));
      thoughts.hidden=!reason;thoughtTitle.textContent='Latest reasoning'+((a?.preview?.reasoningExcerpt||a?.reasoningExcerpt)?' · excerpt':'');rich(reasoning,reason);
      resultTitle.hidden=result.hidden=!a?.report;resultTitle.textContent=a?.reportExcerpt?'Report · excerpt':'Report';rich(result,a?.report||'');
      const entries=a?.activity||[],oldRows=new Map([...activityList.children].map(node=>[node.dataset.call,node]));activityHint.textContent=entries.length?(a.activityOmitted?'Earlier tool activity is omitted. ':'')+'Open a call to inspect its progress or result.':'Tool calls appear here when the subagent starts using them.';
      const wanted=new Set(entries.map((item,index)=>String(item.index??index)));for(const [key,node]of oldRows)if(!wanted.has(key)&&!reading(node))node.remove();
      entries.forEach((item,index)=>{const key=String(item.index??index);let row=oldRows.get(key);if(!row){row=el('details','agent-tool');row.dataset.call=key;row.append(el('summary'),el('p'));activityList.append(row);}const outcome=item.interrupted?'No result':item.done?(item.ok?'Finished':'Failed'):'In progress';row.dataset.status=item.interrupted?'stopped':item.done?(item.ok?'done':'failed'):'running';plain(row.querySelector('summary'),item.name+' · '+outcome+(Number.isFinite(item.ms)?' · '+agentElapsed(item.ms):''));plain(row.querySelector('p'),item.done?(item.summary||item.progress||'No result text was retained.'):(item.progress||'Waiting for progress.'));if(activityList.children[index]!==row)activityList.insertBefore(row,activityList.children[index]||null);});
      plain(taskText,a?.currentTask||a?.task||'');const facts=[['Provider',a?.provider||'Not selected'],['Model',a?.model||'Not selected'],['Tools',a?.toolAccess||a?.preset||'Inherited'],['Parent conversation',a?.parentTitle||'Original conversation'],['Run',String(a?.runs||1)],['Reference',id]];const signature=JSON.stringify(facts);if(access.dataset.signature!==signature&&!reading(access)){access.replaceChildren();for(const [key,value]of facts)access.append(el('dt',null,key),el('dd',null,value));access.dataset.signature=signature;}
      form.hidden=!a||!Object.hasOwn(a,'canFollowup');send.disabled=submitting||!connected||!a?.canFollowup||!input.value.trim();hint.textContent=submitting?'Sending follow-up…':live?'Draft now; send when this run finishes.':a?.canFollowup?'Continue with the same context and tool access.':'This subagent’s context has been released.';
      stop.hidden=!live;stop.disabled=!connected||stoppingAgent||a?.stopping;stop.textContent=stoppingAgent||a?.stopping?'Stopping…':'Stop subagent';copy.disabled=!a?.report;
      panels.scrollTop=position;root.scrollTop=bodyPosition;
    }
    input.oninput=paint;form.onsubmit=async event=>{event.preventDefault();const a=state.subagents?.find(agent=>agent.id===id),text=input.value;if(submitting||!a?.canFollowup||!text.trim())return;submitting=true;paint();try{await command('subagent:followup',{id,text:text.trim()});if(context===modalContext&&input.value===text)input.value='';toast('Follow-up sent.');}catch(error){toast(error.message);}finally{submitting=false;if(context===modalContext)paint();}};
    modalRefresh=paint;const timer=setInterval(paint,1000);context.cleanup=()=>clearInterval(timer);paint();
  },{description:'Follow the work and continue the same context.',size:'agent'});
}
function panelIsEditing(){
  if($('modal').open||panelPointerActive)return true;
  const root=$('panel'),active=document.activeElement;if(root.querySelector('.setting[data-state="saving"]')||(root.contains(active)&&active.matches('input,textarea,select')))return true;
  const selection=document.getSelection();return !!selection&&!selection.isCollapsed&&(root.contains(selection.anchorNode)||root.contains(selection.focusNode));
}
function requestPanelRefresh(){panelRefreshPending=true;flushPanelRefresh();}
function flushPanelRefresh(){if(panelRefreshPending&&page!=='chat'&&!$('app').hidden&&!panelIsEditing())renderPanel();}
function renderPanel(){
  const root=$('panel'),position=root.scrollTop,active=root.contains(document.activeElement)?document.activeElement:null,focusKey=active?.dataset.focusKey,open=new Set([...root.querySelectorAll('details[open]')].map(d=>d.querySelector('summary')?.textContent));panelRefreshPending=false;
  const errors=new Map([...root.querySelectorAll('.setting[data-state="error"]')].map(row=>{const input=row.querySelector('[data-setting]');return [input.dataset.setting,{value:input.value,checked:input.checked,message:row.querySelector('.save-status').textContent}];}));
  buildPanel(root);
  $('workspaceStatus').textContent=connected?'Roblox connected · '+(state.place?.name||'Workspace ready'):link==='online'?'Bridge ready · waiting for Roblox':'Bridge reconnecting';
  for(const input of root.querySelectorAll('[data-setting]')){const error=errors.get(input.dataset.setting);if(error){input.value=error.value;if(input.type==='checkbox')input.checked=error.checked;const row=input.closest('.setting');row.dataset.state='error';row.querySelector('.save-status').textContent=error.message;}}
  if(page==='providers'){
    if(!state.providers?.length)emptyState(root,'providers','Choose who you think with.','Connect an AI provider and choose a model to start working in your game.',button('Add provider',()=>providerEditor(),'primary'));
  }
  if(page==='agents'&&!state.subagents?.length)emptyState(root,'agents','No delegated tasks yet','Ask the assistant to split a larger task into smaller parts. Their progress and results will appear here.',button('Open chat',()=>show('chat'),'outline'));
  if(page==='memory'&&!root.querySelector('.tool-grid .card'))emptyState(root,'memory','A place for what matters.','Connect your game to see the memory and skill tools available in this workspace.');
  if(page==='tools'&&!state.tools?.length)emptyState(root,'tools','Your game’s tools, within reach.','Connect Roblox to browse available tools, review permissions, and run an action.');
  if(page==='logs'&&!state.logs?.length&&!state.requests?.length)emptyState(root,'logs','No activity yet','Requests and diagnostic messages will appear here as you work.');
  if(page==='loops'&&!state.loops?.length)emptyState(root,'loop','No active chat loops','Start a chatbot or choose a workflow above. You can stop any running loop from this page.');
  for(const details of root.querySelectorAll('details'))if(open.has(details.querySelector('summary')?.textContent))details.open=true;
  for(const control of root.querySelectorAll('button,summary'))if(!control.dataset.focusKey){const scope=control.closest('.card,.setup-step,.setup-faq details,.panel-heading,.empty-state')||root,heading=scope.querySelector('h1,h2,summary,h3')?.textContent||scope.className,index=[...scope.querySelectorAll('button,summary')].indexOf(control);control.dataset.focusKey='panel:'+page+':'+heading+':'+index;}
  if(active){const replacement=focusKey&&[...root.querySelectorAll('[data-focus-key]')].find(n=>n.dataset.focusKey===focusKey);(replacement&&!replacement.disabled?replacement:root).focus({preventScroll:true});}
  root.scrollTop=position;
}

let installSource=stored('localStorage','uai.installSource')||'executor';
function tunnelModels(id,name){
  modal(name+' free models',content=>{
    const context=modalContext,controller=new AbortController();
    const timer=setTimeout(()=>controller.abort(new DOMException('The model list took too long to load. Try again.','TimeoutError')),15000);
    context.cleanup=()=>{clearTimeout(timer);controller.abort();};
    content.append(el('p','muted','Loading current free models...'));
    modalActions(modalCancel('Done'));
    (async()=>{
      try{
        const response=await api(id==='cline'?'/tunnels/cline/models':'/opencode/models',undefined,undefined,controller.signal);
        if(context!==modalContext||context.closing)return;
        const rows=(Array.isArray(response?.data)?response.data:[]).filter(row=>row&&typeof row.id==='string'&&row.id.trim()).slice(0,100);
        content.replaceChildren(el('p','muted','Copy a model ID into the matching provider. Availability and free promotions can change.'));
        for(const row of rows){const line=el('div','tool-actions');line.append(el('code',null,row.id),button('Copy ID',()=>copyText(row.id),'outline'));content.append(line);}
        if(!rows.length)content.append(el('p',null,'No free models are currently available.'));
      }catch(error){if(context===modalContext&&!context.closing){content.replaceChildren(el('p','form-error',error.message),button('Try again',()=>tunnelModels(id,name),'outline'));}}
      finally{clearTimeout(timer);}
    })();
  });
}
function renderTunnels(root){
  heading(root,'Tunnels',button('Refresh status',async()=>{
    try{const hello=await api('/hello');kiloStatus=hello.capabilities?.kilo||{};clineStatus=hello.capabilities?.cline||{};openCodeStatus=hello.capabilities?.opencode||{};requestPanelRefresh();}
    catch(error){toast(error.message);}
  },'outline'));
  root.append(el('p','panel-description','Use free models through your local bridge. Configure connections in the desktop app while the bridge is stopped. Select the matching provider and fetch its models in Roblox or Cowork.'));
  const labels={standby:'Ready when needed',disabled:'Off',missing:'Setup needed','auth-required':'Sign in required',starting:'Connecting',downloading:'Downloading helper',ready:'Ready',limited:'Quota reached',rotating:'Changing connection',failed:'Needs attention',stopped:'Stopped'};
  for(const [id,name,status,detail,docs]of [
    ['opencode','OpenCode',openCodeStatus,'Free models through your separately installed OpenCode CLI. Choose OpenCode Zen in Providers.','https://opencode.ai'],
    ['kilo','Kilo',kiloStatus,'Anonymous Kilo quota recovery. Shared exits retain their provider allowances. Choose Kilo Code in Providers.','https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/KILO_TUNNEL.md'],
    ['cline','Cline',clineStatus,'Free promotional models through the signed-in Cline CLI. Choose Cline (Bridge) in Providers; this route requires the connected bridge.','https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/CLINE_TUNNEL.md']
  ]){
    const box=card(root);box.dataset.tunnel=id;box.append(el('h2',null,name),el('span','pill',link==='online'?(labels[status.state]||'Unavailable'):'Disconnected'),el('p',null,link==='online'?(status.message||detail):'Reconnect the bridge to read its tunnel status.'));
    if(status.message)box.append(el('small','muted',detail));
    const actions=el('div','tool-actions'),guide=el('a','outline','Setup guide');guide.href=docs;guide.target='_blank';guide.rel='noopener noreferrer';actions.append(guide);
    if(id!=='kilo'){
      const models=button('Free models',()=>tunnelModels(id,name),'outline');models.disabled=link!=='online'||status.state==='disabled'||status.state==='missing';actions.append(models);
    }
    box.append(actions);
  }
}
function renderCowork(root){
  const hero=el('section','connection-hero'),copy=el('div'),eyebrow=el('p','connection-eyebrow');hero.dataset.connected=String(connected);eyebrow.append(el('span','status-dot'),document.createTextNode(connected?'CONNECTED':'READY TO CONNECT'));
  copy.append(eyebrow,el('h2',null,connected?'Your workspace is connected.':'One connection. Your whole workspace.'),el('p',null,connected?(state.place?.name||'Roblox')+' is connected to this browser. Your conversations, tools, and changes stay in sync.':'Load Project UAI in Roblox, then connect it to this bridge to start working together.'));
  const actions=el('div','connection-hero-actions');actions.append(connected?button('Open chat',()=>show('chat'),'primary'):button('View setup steps',()=>{const guide=$('connectionGuide');guide.open=true;guide.scrollIntoView({block:'start',behavior:'smooth'});},'primary'),button('Copy bridge token',()=>copyText(token),'outline'));hero.append(copy,actions);root.append(hero);
  const path=el('div','connection-path');path.setAttribute('aria-label','Browser, bridge, and Roblox connection status');
  for(const [name,detail,symbol,ready]of [['This browser','Open and ready','chat',true],['Local bridge',link==='online'?'Running on port '+location.port:'Reconnecting…','bridge',link==='online'],['Roblox',connected?(state.place?.name||'Connected'):'Waiting to connect','player',connected]]){
    const n=el('div','connection-node');n.dataset.ready=String(ready);n.append(el('span','status-dot'),el('strong',null,name),el('small',null,detail));path.append(n);
  }root.append(path);
  const runtime=card(root);runtime.classList.add('runtime-summary');const runtimeHead=el('div','provider-heading');runtimeHead.append(el('h2',null,state.runtime==='web'?'Web runtime':'Game runtime'),el('span','pill','Automatic'));runtime.append(runtimeHead,el('p',null,'Web runtime starts as soon as Roblox connects. Disconnecting returns your game to Game runtime.'),el('small','muted','The bridge waits without a time limit for completion, a provider error, or Stop. Roblox continues to run tools and save your conversation.'));
  const kilo=card(root),kiloLabels={standby:'Ready when needed',disabled:'Off',starting:'Connecting',downloading:'Downloading helper',ready:'Ready',limited:'Quota reached',rotating:'Changing connection',failed:'Unavailable'};
  kilo.append(el('h2',null,'Kilo tunnel'),el('span','pill',link==='online'?(kiloLabels[kiloStatus.state]||'Unavailable'):'Disconnected'),el('p',null,link==='online'?(kiloStatus.message||'Update the bridge to use automatic Kilo quota recovery.'):'Reconnect the bridge to read its Kilo tunnel status.'),el('small','muted','Anonymous Kilo free models only. Each outbound address still has an allowance. Manage this connection in the desktop app or with UAI_KILO_TUNNEL.'));
  const usage=card(root),unknownCosts=Number.isFinite(state.usage?.unpriced)?Math.max(0,Math.floor(state.usage.unpriced)):0,requests=state.usage?.requests||0;
  const allCostsUnknown=unknownCosts>0&&unknownCosts>=requests;
  usage.classList.add('metrics');usage.append(metric(state.usage?.total||0,state.usage?.estimated?'Tokens · estimated':'Tokens used'),metric(requests,'Requests'),metric(allCostsUnknown?'Unknown':'$'+(state.usage?.cost||0).toFixed(4),unknownCosts>0&&!allCostsUnknown?'Known estimated cost':'Estimated cost'));
  if(unknownCosts)root.append(el('p','field-help cost-coverage',unknownCosts+' request'+(unknownCosts===1?' has':'s have')+' unknown cost and '+(unknownCosts===1?'is':'are')+' excluded from this estimate.'));
  const update=el('section','bridge-update'),updateCopy=el('div');updateCopy.append(el('h3',null,'Bridge updates'),el('p',null,bridgeUpdate.currentVersion?'Version '+bridgeUpdate.currentVersion+(bridgeUpdate.availableVersion?' · '+bridgeUpdate.availableVersion+' available':''):'Automatic updates'));
  const labels={current:'Up to date',checking:'Checking for updates',staged:'Ready when the workspace is idle',restarting:'Installing update',updated:'Updated',error:'Update check unavailable'};update.append(updateCopy,el('span','pill',labels[bridgeUpdate.state]||'Automatic'));if(bridgeUpdate.error)update.append(el('small','update-error',bridgeUpdate.error));root.append(update);
  const guide=el('details','setup-guide');guide.id='connectionGuide';guide.open=!connected;guide.append(el('summary',null,'Setup instructions'));root.append(guide);
  const steps=el('div','setup-steps');guide.append(steps);
  function step(number,title,complete){const n=el('section','setup-step');n.dataset.complete=String(complete);n.append(el('span','step-number',String(number)),el('h3',null,title));steps.append(n);return n;}
  const one=step(1,'Start the bridge',link==='online');
  one.append(el('p',null,'Install Node.js 18+ on this computer. Download the bridge in Roblox → UAI → Cowork, then open a terminal in your executor workspace.'));
  const source=select(one,'Your installation',[['executor','Downloaded in Roblox'],['repo','Git checkout']],installSource);
  const code=el('code',null,installSource==='repo'?'node bridge/server.js':'node UAI/bridge/start.txt');
  source.onchange=()=>{installSource=source.value;code.textContent=installSource==='repo'?'node bridge/server.js':'node UAI/bridge/start.txt';try{localStorage.setItem('uai.installSource',installSource);}catch{}};
  one.append(code,button('Copy start command',()=>copyText(code.textContent),'outline'),el('small','setup-detail','Keep this terminal open. No npm install or file renaming needed.'));
  const two=step(2,'Connect Roblox',connected);
  two.append(el('p',null,'In Roblox, open UAI → Cowork. Paste the bridge token, set the port below, then turn Enabled on.'),el('code',null,'Port '+location.port),button('Copy bridge token',()=>copyText(token),'outline'),el('small','setup-detail','The token is the long code from the terminal. Automatic updates keep it; a manual restart creates a new one.'));
  const three=step(3,'Open your workspace',connected);
  three.append(el('p',null,'Open the browser link printed by the terminal. Choose a provider and model, then send your first message. Your game stays in control of tools and permissions.'));
  three.append(button(connected?'Open chat →':'Check connection',async()=>{if(connected){show('chat');$('input').focus();return;}try{const hello=await api('/hello');connected=!!hello.connected;refresh();renderPanel();if(!connected)toast('Still waiting. Paste the token into Roblox’s Cowork panel and turn Enabled on.');}catch(e){toast(e.message);}},connected?'primary':'outline'));
  three.append(el('small','setup-detail',connected?'Browser and Roblox share the active conversation.':'Your connection status updates automatically.'));
  const faq=el('div','setup-faq');
  for(const [question,answer]of [
    ['Roblox is still waiting to connect','Keep Roblox and the terminal open on the same computer. Match the port shown above, paste the latest token, and turn Enabled on in UAI → Cowork. After a manual bridge restart, both windows need the new token. Automatic updates preserve your connection token.'],
    ['Node or the start file cannot be found','Install Node.js, then reopen your terminal. Open it in your executor’s workspace folder—the one containing UAI. If you downloaded this repository instead, choose Git checkout in step 1 and run its command from the repository folder.'],
    ['Can the AI see attached pictures?','Yes, when your selected model supports vision. PNG, JPEG, and WebP images are sent with your message. Keep the bridge running; if an image expires or the bridge restarts, attach it again. Reload the updated game client to enable image sends.'],
    ['What happens if I refresh or close the browser?','Refreshing reconnects to the conversation. Drafts are saved in this browser when storage is available. Closing the browser does not stop work in Roblox. Use Stop to cancel a turn. Pictures expire after 15 minutes of inactivity and are cleared when the bridge stops.']
  ]){const detail=el('details');detail.append(el('summary',null,question),el('p',null,answer));faq.append(detail);}root.append(faq);
}

// Mirrors the choices enforced by net/bridge_commands.lua for protocol-2 clients.
const SETTING_CHOICES={
  'ui.density':['comfortable','compact'],'ui.accent':['claude','aurora','indigo','amber','rose'],
  'ui.layout':['auto','sheet','panel','window','tv'],'ui.codeTheme':['dark','light'],'ui.transcriptWidth':['narrow','medium','wide'],
  'iy.mode':['off','hidden','visible'],'agent.effort':['low','medium','high','xhigh','max']
};
const SETTING_RANGES={'ui.fontScale':[.85,1.4,.05],'agent.temperature':[0,2,.1],'agent.toolConcurrency':[1,8,1],
  'agent.maxTurns':[1,1000,1],'agent.toolTimeout':[1,86400,1],'agent.requestTimeout':[1,86400,1],'agent.retries':[1,10,1],
  'agent.contextTokens':[1000,2000000,1],'agent.contextFraction':[.3,.95,.05],'agent.maxTokens':[1,1000000,1]};
function openSettings(initial='general'){
  modal('Settings',root=>{
    root.className='settings-layout';const nav=el('nav','settings-nav'),content=el('div','settings-content');nav.setAttribute('aria-label','Settings sections');root.append(nav,content);
    const panels=new Map(),tabs=new Map(),choices=[['general','General'],['appearance','Appearance'],['agent','Agent'],['obsidian','Obsidian'],['mcp','MCP'],['advanced','Advanced'],['data','Data']];
    for(const [id,title]of choices){
      const panel=el('section','settings-page');panel.id='settings-'+id;panel.hidden=true;panel.setAttribute('aria-labelledby','settings-tab-'+id);content.append(panel);panels.set(id,panel);
      const tab=button(title,()=>activate(id),'settings-tab');tab.id='settings-tab-'+id;tab.setAttribute('aria-controls',panel.id);nav.append(tab);tabs.set(id,tab);
    }
    function activate(id){for(const [key,panel]of panels){panel.hidden=key!==id;const tab=tabs.get(key);tab.classList.toggle('selected',key===id);if(key===id)tab.setAttribute('aria-current','true');else tab.removeAttribute('aria-current');}content.scrollTop=0;const activeTab=tabs.get(id);queueMicrotask(()=>{if(activeTab?.isConnected)activeTab.scrollIntoView({block:'nearest',inline:'nearest'});});if(id==='mcp')loadMcp();if(id==='obsidian')vaultPanel.load();}
    const vaultPanel=UAI.vaults.mount(panels.get('obsidian'),{request:api,copyText,download});
    const navigationSize=new ResizeObserver(()=>{nav.querySelector('[aria-current="true"]')?.scrollIntoView({block:'nearest',inline:'nearest'});});navigationSize.observe(nav);
    modalContext.cleanup=()=>{navigationSize.disconnect();vaultPanel.dispose();};
    modalContext.canClose=()=>!vaultPanel.dirty()||confirm('Discard the unsaved note changes? Download or copy the draft first if you want to keep it.');
    const general=panels.get('general');general.append(el('h3',null,'Make yourself at home'),el('p','settings-intro','Your browser, your workspace. Changes save as you go.'));
    const appearance=card(general,'Browser theme'),themeChoices=el('div','theme-choices');appearance.append(themeChoices);
    for(const [id,title]of [['light','Light'],['dark','Dark'],['system','System'],['game','Roblox']]){const choice=button('',()=>{UAI.theme.set(id);sync();},'theme-choice');choice.dataset.themeChoice=id;const preview=el('span','theme-preview');preview.setAttribute('aria-hidden','true');preview.append(el('i'),el('i'),el('i'));choice.append(preview,el('span',null,title));themeChoices.append(choice);}
    appearance.append(el('small','setup-detail','Saved in this browser. Roblox follows your game’s palette.'));
    const permissions=card(general,'Permissions'),modes=el('div','segments permission-modes');
    for(const [mode,name]of [['readonly','Read only'],['ask','Ask first'],['auto','Auto'],['full','Allow all']]){const n=button(name,()=>modalTask(()=>command('permission-mode',{mode}),{success:'Permission mode saved.'}),'','permission:'+mode);n.dataset.permission=mode;modes.append(n);}permissions.append(modes,el('small','setup-detail','Ask first lets you review actions that change your game.'));
    panels.get('appearance').append(el('h3',null,'Conversation appearance'),el('p','settings-intro','Tune reading comfort and the details shown in your conversations.'));
    panels.get('agent').append(el('h3',null,'Agent behavior'),el('p','settings-intro','Set the instructions and limits shared with Roblox.'));
    panels.get('advanced').append(el('h3',null,'Advanced settings'),el('p','settings-intro','Connection, logging, and provider preferences shared with Roblox.'));
    for(const [section,values]of Object.entries(state.settings||{})){
      const destination=panels.get(section==='ui'?'appearance':section==='agent'?'agent':'advanced');
      const details=el('section','settings-section');details.append(el('h4',null,({ui:'Display',agent:'Agent',logs:'Logging',iy:'Infinite Yield',identity:'Provider identity',bridge:'Bridge',relay:'Relay'})[section]||section));
      renderSettingFields(details,section,values);if(details.childElementCount>1)destination.append(details);
    }
    const extras=panels.get('data');extras.append(el('h3',null,'Your configuration'),el('p','settings-intro','Move your configuration between installations. Full exports include API keys.'));
    const row=el('div','row');row.append(button('Export full config',()=>modalTask(async()=>{const data=await command('config:export');download('uai-config.json',data.text,'application/json');},{success:'Configuration exported.'}),'outline'),button('Import full config',importConfig,'outline'));extras.append(row);
    const mcpRoot=panels.get('mcp');mcpRoot.append(el('h3',null,'Connect your AI tools'),el('p','settings-intro','Give your desktop AI harness access to the tools in your Roblox workspace.'));
    const mcpStatus=el('div','mcp-status'),mcpControls=el('div','mcp-controls');mcpRoot.append(mcpStatus,mcpControls);let mcpLoading=false,mcpLoaded=false;
    async function loadMcp(force=false){
      if(mcpLoading||(mcpLoaded&&!force))return;mcpLoading=true;mcpStatus.textContent='Checking MCP connection…';
      try{const data=await api('/mcp/config');if(!root.isConnected)return;mcpLoaded=true;renderMcp(mcpStatus,mcpControls,data,()=>loadMcp(true));}
      catch(error){if(root.isConnected){mcpStatus.replaceChildren(el('p','form-error',error.message),button('Try again',()=>loadMcp(true),'outline'));}}
      finally{mcpLoading=false;}
    }
    function sync(){
      for(const choice of themeChoices.children){const selected=choice.dataset.themeChoice===UAI.theme.get();choice.classList.toggle('selected',selected);choice.setAttribute('aria-pressed',String(selected));}
      for(const choice of modes.children){const selected=choice.dataset.permission===state.permissions?.mode;choice.classList.toggle('selected',selected);choice.setAttribute('aria-pressed',String(selected));choice.disabled=!connected||!!modalContext?.pending;}
      for(const input of root.querySelectorAll('[data-setting]')){if(document.activeElement===input||['saving','error'].includes(input.closest('.setting').dataset.state))continue;const [section,key]=input.dataset.setting.split('.'),value=state.settings?.[section]?.[key];input.disabled=!connected||!!modalContext?.pending||!!modalContext?.uncertain;if(value===undefined)continue;if(input.type==='checkbox')input.checked=!!value;else input.value=value;}
    }
    modalRefresh=sync;sync();activate(panels.has(initial)?initial:'general');modalActions(modalCancel('Done'));
  },{size:'settings',focusHeading:true});
}
function renderSettingFields(details,section,values){
    for(const [key,value]of Object.entries(values)){
      if(['lastSeenVersion','lastSeenChangelog','panel'].includes(key)||(section==='ui'&&key==='reduceMotion')||(section==='bridge'&&key==='requestTimeout')||typeof value==='object')continue;
      const path=section+'.'+key,row=el('label','setting'),caption=el('span',null,path==='agent.autoFreeRouting'?'Automatic free routing':key.replace(/([A-Z])/g,' $1').replace(/^./,c=>c.toUpperCase())),status=el('small','save-status');status.setAttribute('aria-live','polite');
      if(path==='agent.autoFreeRouting')caption.append(el('small','field-help','Choose a recently verified model when Project UAI Free uses Auto. Add this optional route from the Providers library. HCNSEC uses its own connection and key. Off keeps provider Auto and stops new local routing probes; an active request continues.'));
      caption.append(status);row.append(caption);
      let input;
      if(typeof value==='boolean'){input=el('input');input.type='checkbox';input.checked=value;}
      else if(SETTING_CHOICES[path]){input=el('select');for(const item of SETTING_CHOICES[path]){const [id,title]=Array.isArray(item)?item:[item,item[0].toUpperCase()+item.slice(1)];const option=el('option',null,title);option.value=id;input.append(option);}input.value=value;}
      else{input=el(key==='customInstructions'?'textarea':'input');if(input.tagName==='INPUT')input.type=typeof value==='number'?'number':'text';input.value=value;if(typeof value==='number'){const [min,max,step]=SETTING_RANGES[path]||[0,10000000,1];input.min=min;input.max=max;input.step=step;}else input.maxLength=16000;}
      input.dataset.setting=path;input.disabled=!connected;
      let saveVersion=0;
      input.onchange=async()=>{
        const version=++saveVersion;
        if(!input.reportValidity()){status.textContent=input.validationMessage;row.dataset.state='error';return;}
        status.textContent='Saving…';row.dataset.state='saving';
        try{await command('setting',{path,value:typeof value==='boolean'?input.checked:typeof value==='number'?Number(input.value):input.value});if(version===saveVersion){status.textContent='Saved';row.dataset.state='saved';}}
        catch(e){if(version===saveVersion){status.textContent=e.message;row.dataset.state='error';toast(e.message);}}
        finally{queueMicrotask(flushPanelRefresh);}
      };
      row.append(input);details.append(row);
    }
}
function renderMcp(status,root,data,refresh){
  status.replaceChildren();const summary=el('div','mcp-status-line');summary.append(el('span','status-dot'),el('strong',null,data.available?'Ready for your harness':data.connected?'Update the UAI script':'Waiting for Roblox'),button('Refresh',refresh,'outline'));status.dataset.ready=String(!!data.available);status.append(summary,el('small',null,data.available?(data.tools||0)+' tools available. Your workspace permissions apply.':data.connected?'Reload the latest UAI script to enable MCP tools.':'Load UAI in Roblox and connect this bridge to expose your tools.'));
  root.replaceChildren();const endpoint=el('div','mcp-endpoint');endpoint.append(el('span','eyebrow','SERVER URL'),el('code',null,data.endpoint));root.append(endpoint);
  const harness=select(root,'Harness',[['claude','Claude Desktop / Claude Code'],['cursor','Cursor'],['vscode','VS Code / Copilot'],['opencode','OpenCode'],['codex','Codex'],['http','Streamable HTTP']], 'claude');
  const location=el('p','field-help'),preview=el('pre','mcp-config');preview.setAttribute('aria-label','MCP configuration preview');root.append(location,preview);
  function config(secret,format=harness.value){
    const env={UAI_BRIDGE_TOKEN:secret?token:'YOUR_BRIDGE_TOKEN'},stdio={command:data.stdio?.command||'node',args:data.stdio?.args||[],...(!data.stdio?.discovery?{env}:{})};
    if(format==='http')return JSON.stringify({mcpServers:{projectuai:{url:data.endpoint,headers:{Authorization:'Bearer '+env.UAI_BRIDGE_TOKEN}}}},null,2);
    if(format==='vscode')return JSON.stringify({servers:{projectuai:{type:'stdio',...stdio}}},null,2);
    if(format==='opencode')return JSON.stringify({mcp:{projectuai:{type:'local',command:[stdio.command,...stdio.args],...(!data.stdio?.discovery?{environment:env}:{}),enabled:true}}},null,2);
    if(format==='codex')return '[mcp_servers.projectuai]\ncommand = '+JSON.stringify(stdio.command)+'\nargs = '+JSON.stringify(stdio.args)+'\ntool_timeout_sec = 300\n'+(!data.stdio?.discovery?'\n[mcp_servers.projectuai.env]\nUAI_BRIDGE_TOKEN = '+JSON.stringify(env.UAI_BRIDGE_TOKEN)+'\n':'');
    return JSON.stringify({mcpServers:{projectuai:stdio}},null,2);
  }
  function paint(){location.textContent=({claude:'Add to claude_desktop_config.json, or your project’s .mcp.json for Claude Code.',cursor:'Add to .cursor/mcp.json in your project, or your global Cursor MCP settings.',vscode:'Add to .vscode/mcp.json in your workspace.',opencode:'Add this MCP entry to opencode.json.',codex:'Add to ~/.codex/config.toml.',http:'Use this URL and Authorization header with a Streamable HTTP client.'})[harness.value];preview.textContent=config(false);}
  function setupPrompt(){
    const readTools=['client_status','place_info'].filter(name=>(state.tools||[]).some(tool=>tool.name===name));
    const discoveryHttp=data.stdio?.discovery&&harness.value==='http';
    return 'Connect your harness to my local Project UAI MCP server and verify the connection.\n\n'+
      'Inspect your harness and its supported MCP configuration first. Preserve all unrelated settings and existing MCP entries. Register this server as projectuai. Prefer stdio for broad compatibility; use Streamable HTTP if your harness supports it.\n\n'+
      'Exact stdio command: '+JSON.stringify(data.stdio?.command||'node')+'\nExact stdio arguments: '+JSON.stringify(data.stdio?.args||[])+'\n'+
      (data.stdio?.discovery?'The desktop app supplies credentials through local discovery; do not add a token environment variable.\n':'Stdio environment: '+JSON.stringify({UAI_BRIDGE_TOKEN:token})+'\n')+
      'Streamable HTTP endpoint: '+data.endpoint+'\n'+
      (harness.value==='http'&&!data.stdio?.discovery?'HTTP authorization: Bearer '+token+'\n':'')+
      '\nConfiguration for '+(discoveryHttp?'universal stdio with desktop discovery':harness.selectedOptions[0].textContent)+':\n'+config(true,discoveryHttp?'claude':harness.value)+'\n\n'+
      'Write the configuration using the syntax your harness supports, without replacing unrelated entries. Reload or restart the MCP connection as needed. Initialize the server, list its tools, and verify Roblox is connected. Run only '+(readTools.length?'a harmless read-only check such as '+readTools.join(' or '):'an advertised read-only status or place-information tool')+' to verify it; do not run code or mutate the game as a setup test.\n\n'+
      'Report the configuration location, discovered tool count, and actual verification result. Keep credentials out of your report. If you cannot access local configuration or MCP tools, explain that limitation and provide the exact remaining steps instead of claiming success.';
  }
  harness.onchange=paint;paint();const actions=el('div','row mcp-setup-actions');actions.append(button('Copy setup prompt',()=>copyText(setupPrompt()),'primary'),button('Copy configuration',()=>copyText(config(true)),'outline'));root.prepend(actions,el('p','field-help','Paste the setup prompt into your agent to connect it for you.'));
  root.append(el('p','field-help',data.stdio?.discovery?'Desktop stdio connects through local discovery. HTTP configuration includes this bridge’s token.':'Copy includes this bridge’s token. Keep the configuration private. Restart or refresh your harness after saving it.'));
  const sessions=data.sessions||[];const clients=card(root,'Connected harnesses');
  if(!sessions.length)clients.append(el('p','muted','No harness connected yet.'));
  else for(const client of sessions){const row=el('div','mcp-client');row.append(el('strong',null,client.clientName||'MCP client'),el('small',null,(client.activeCalls||0)+' active calls'));clients.append(row);}
}
function importConfig(){modal('Import configuration',root=>{
  const form=el('form','dialog-form');form.id='modalForm';root.append(form);
  const input=field(form,'Paste configuration JSON','','textarea');input.className='code-input';input.spellcheck=false;input.required=true;input.placeholder='Paste your full config export.';
  const preview=el('p','field-help','Your JSON stays in this dialog until you import it.');form.append(preview);
  input.oninput=()=>{try{const parsed=JSON.parse(input.value);if(!parsed||typeof parsed!=='object'||Array.isArray(parsed))throw Error();preview.textContent='Valid JSON object. Import will replace the current configuration.';input.setCustomValidity('');}catch{preview.textContent=input.value?'Enter a valid configuration JSON object.':'Your JSON stays in this dialog until you import it.';input.setCustomValidity(input.value?'Enter a valid JSON object.':'');}};
  form.onsubmit=event=>{event.preventDefault();modalCommand('config:import',{text:input.value});};
  const submit=el('button','primary','Import configuration');submit.type='submit';submit.setAttribute('form',form.id);modalActions(modalCancel(),submit);
},{description:'This replaces your saved settings and provider credentials. Stop running work before importing.',size:'wide'});}
async function submit(){
  if(stopping||sending||sendPhase!=='idle'||readingFiles||draftLoads.has(sessionId)||(busy&&!state.queue)||!connected||state.queue?.count>=state.queue?.limit)return;
  const text=$('input').value;
  const pictureIds=UAI.pictures.ids();
  if(!text.trim()&&!uploads.length&&!pictureIds.length)return;
  if(UAI.pictures.busy()){toast('Wait for pictures to finish uploading.');return;}
  if(UAI.pictures.hasErrors()){toast('Retry or remove the picture that could not be attached.');return;}
  const encode=new TextEncoder(),max=state.attachments?.maxBytes||10*1024*1024;
  if(encode.encode(text).length>max){toast('This message exceeds 10 MiB. Split it into smaller files.');return;}
  if(draftBytes(text,uploads)>MAX_DRAFT_BYTES){toast('Use up to 16 MiB of text and code per message.');return;}
  saveDraft();
  const original=text,files=uploads.slice(),sentSession=sessionId;
  const operation={sessionId:sentSession,commandId:uuid(),sawTurn:false,instance,createdAt:Date.now(),sentVersion:drafts[sentSession]?.version,fileIds:files.map(f=>f.id)};
  sendOperation=operation;
  sending=true;setPhase('submitting');
  try{
    const limit=state.attachments?.inlineLimit||8000;
    const parts=[],references=[];
    const attach=async(text,name)=>{setPhase('uploading');const file=await uploadText(text,name,sentSession);references.push({path:file.path,bytes:file.bytes});return file.reference;};
    if(encode.encode(text).length>limit)parts.push(await attach(text,'pasted-input.txt'),'Read the file for the complete user input, including any request at the end.');
    else if(text.trim())parts.push(text.trim());
    else if(!pictureIds.length)parts.push('Please read the attached input.');
    for(const file of files){
      if(encode.encode(file.text).length>limit)parts.push(await attach(file.text,file.name));
      else parts.push(`[Attached: ${file.name}]\n${file.text}`);
    }
    setPhase('submitting');
    const fields={text:parts.join('\n\n'),files:references,sessionId:sentSession,commandId:operation.commandId};
    if(pictureIds.length)fields.pictureIds=pictureIds;
    lastSend={text:original,files,sessionId:sentSession};
    // Correlate before POST: the game can emit its user event before the receipt.
    if(pictureIds.length)UAI.pictures.attachToCommand(operation.commandId,pictureIds);
    operation.submitted=true;persistOperation();
    const admitted=await command('send',fields);
    await clearSentDraft(operation);forgetOperation();if(admitted?.queued){setPhase('idle');toast('Follow-up queued.');}else armAwaitTurn(operation);
  }catch(e){
    toast(e.message);
    if(operation.submitted&&e.uncertain){setPhase('uncertain');persistOperation();}
    else{UAI.pictures.releaseCommand(operation.commandId);forgetOperation();setPhase('idle');}
  }
  finally{sending=false;refresh();}
}
function persistOperation(){try{sessionStorage.setItem('uai.pendingSend',JSON.stringify(sendOperation));}catch{}}
function forgetOperation(){sendOperation=null;try{sessionStorage.removeItem('uai.pendingSend');}catch{}}
async function clearSentDraft(operation){
  await draftLoads.get(operation.sessionId);
  if(sessionId===operation.sessionId)saveDraft();
  const current=drafts[operation.sessionId]||await UAI.drafts.load(operation.sessionId)||{},sentIds=new Set(operation.fileIds||[]);
  const clear=current.version===operation.sentVersion;
  drafts[operation.sessionId]={...current,text:clear?'':current.text||'',textLength:clear?0:(current.text||'').length,version:(current.version||0)+(clear?1:0),uploads:(current.uploads||[]).filter(f=>!sentIds.has(f.id)),updatedAt:Date.now()};
  dirtyDrafts.add(operation.sessionId);
  if(sessionId===operation.sessionId){$('input').value=drafts[sessionId].text;uploads=drafts[sessionId].uploads.slice();renderAttachments();resizeComposer();}
  persistDrafts();
}
async function checkDelivery(){
  const operation=sendOperation;if(!operation||sending)return;
  $('deliveryCheck').disabled=true;
  try{
    if(operation.instance!==instance){operation.lost=true;toast('The bridge restarted. Review the conversation before sending this draft again.');return;}
    const receipt=await api('/commands/'+operation.commandId);
    if(['queued','running'].includes(receipt.state)){toast('Roblox is still processing this message. Keep the game and bridge open.');return;}
    if(receipt.result?.uncertain){operation.lost=true;toast(receipt.result.error);return;}
    if(receipt.result?.ok===false){UAI.pictures.releaseCommand(operation.commandId);forgetOperation();setPhase('idle');toast(receipt.result.error||'Message was not delivered. Your draft was kept.');return;}
    await clearSentDraft(operation);forgetOperation();setPhase('idle');toast('Message delivered.');
  }catch(e){if(e.status===404){operation.lost=true;toast('The receipt is no longer available. Review the conversation before sending again.');}else toast(e.message);}
  finally{if(sendOperation)persistOperation();$('deliveryCheck').disabled=false;refresh();}
}
async function uploadText(text,name,target){
  const encode=new TextEncoder(),max=state.attachments?.maxBytes||10*1024*1024;
  if(encode.encode(text).length>max)throw Error(name+' exceeds 10 MiB. Split it into smaller files.');
  const uploadId=uuid();let offset=0,result;
  for(let at=0;at<text.length;){
    let end=Math.min(at+32768,text.length);
    if(end<text.length&&text.charCodeAt(end-1)>=0xd800&&text.charCodeAt(end-1)<=0xdbff)end--;
    const content=text.slice(at,end);
    result=await command('attachment:upload',{sessionId:target,uploadId,name,offset,content,final:end===text.length});
    offset+=encode.encode(content).length;at=end;
  }
  if(!result?.reference||!result.path||result.bytes!==offset)throw Error('The saved attachment could not be verified. Your draft was kept.');
  return result;
}
function pasteInput(event){
  if(window.UAI&&UAI.pictures&&UAI.pictures.handlePaste(event))return;
  const text=event.clipboardData?.getData('text/plain');
  if(!text||!sessionId||new TextEncoder().encode(text).length<=(state.attachments?.inlineLimit||8000))return;
  event.preventDefault();
  if(new TextEncoder().encode(text).length>(state.attachments?.maxBytes||10*1024*1024)){toast('This paste exceeds 10 MiB. Split it into smaller files.');return;}
  if(uploads.length>=16||draftBytes($('input').value,uploads)+new TextEncoder().encode(text).length>MAX_DRAFT_BYTES){toast('Use up to 16 text files and 16 MiB per message.');return;}
  const input=$('input');input.setRangeText('',input.selectionStart,input.selectionEnd,'end');
  uploads.push({id:uuid(),name:'pasted-input.txt',text});renderAttachments();grow();
}
function draftBytes(text,files){const encode=new TextEncoder();return encode.encode(text||'').length+(files||[]).reduce((sum,f)=>sum+encode.encode(f.text||'').length,0);}
async function attachFiles(source){
  const selected=Array.isArray(source)?source:Array.from($('fileInput').files),target=sessionId;
  $('fileInput').value='';
  if(!target){toast('Connect to Roblox before attaching files.');return;}
  saveDraft();
  readingFiles++;refresh();
  try{for(const file of selected.slice(0,16)){
    if(file.size>(state.attachments?.maxBytes||10*1024*1024)){toast(file.name+' exceeds 10 MiB');continue;}
    if(/^(image|audio|video)\//.test(file.type)){toast(file.name+': attach a text or code file.');continue;}
    try{
      const text=await file.text();
      if(text.includes('\0')){toast(file.name+': binary files are not supported.');continue;}
      const draft=sessionId===target?{text:$('input').value,uploads}:drafts[target]||{};
      if((draft.uploads?.length||0)>=16||draftBytes(draft.text,draft.uploads)+new TextEncoder().encode(text).length>MAX_DRAFT_BYTES){toast('Use up to 16 text files and 16 MiB per message.');break;}
      const item={id:uuid(),name:file.name,text};
      if(sessionId===target){uploads.push(item);renderAttachments();saveDraft();setBusy(busy);}
      else{const previous=drafts[target]||{text:'',version:0,uploads:[]};drafts[target]={...previous,uploads:[...(previous.uploads||[]),item],updatedAt:Date.now()};dirtyDrafts.add(target);persistDrafts();}
    }catch(err){toast('Could not read '+file.name+': '+err.message);}
  }}finally{readingFiles--;refresh();}
}
function download(name,text,type){const url=URL.createObjectURL(new Blob([text],{type}));const a=el('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
$('send').onclick=submit;$('stop').onclick=async()=>{if(stopping)return;stopping=true;refresh();try{await command('abort');}catch(e){toast(e.message);}finally{stopping=false;refresh();}};armButton($('clear'),'Confirm clear',()=>action('clear'));
$('input').oninput=grow;
$('input').onpaste=pasteInput;
$('input').onkeydown=e=>{if(e.key==='Enter'&&!e.shiftKey&&!e.isComposing&&e.keyCode!==229){e.preventDefault();submit();}};
$('newThread').onclick=$('newConversation').onclick=()=>openConversation();$('modelButton').onclick=models;
$('contextButton').onclick=contextDetails;
$('attach').onclick=()=>$('fileInput').click();$('fileInput').onchange=attachFiles;
$('attachPictures').onclick=()=>{if(window.UAI&&UAI.pictures)UAI.pictures.openPicker();};
$('themeToggle').onclick=()=>{if(window.UAI&&UAI.theme)UAI.theme.toggle();};
$('setupHelp').onclick=$('connectionAction').onclick=()=>{show('cowork');$('connectionGuide').open=true;};
$('permissionBadge').onclick=()=>show('settings');
$('deliveryCheck').onclick=checkDelivery;
$('deliveryReview').onclick=()=>{const operation=sendOperation;if(!operation?.lost)return;UAI.pictures.releaseCommand(operation.commandId);forgetOperation();setPhase('idle');show('chat');$('input').focus();toast('Draft kept. Check the conversation before sending it again.');};
$('sidebarOverlay').onclick=()=>closeSidebar(true);
$('options').onclick=()=>modal('Conversation options',root=>{
  const choices=el('div','option-list');root.append(choices);
  function option(title,description,handler){const n=button('',handler,'option-row');const copy=el('span');copy.append(el('strong',null,title),el('small',null,description));n.append(copy,el('span','option-arrow','›'));choices.append(n);}
  option('Model and effort','Choose a provider, model, and reasoning level.',models);
  option('Permissions','Review what the agent is allowed to do.',()=>{closeModal(true,false);show('settings');});
  option('Chat loops','Manage chatbots and automatic replies.',()=>{closeModal(true,false);show('loops');});
  option('Export JSON','Download conversation events and picture metadata.',()=>download('uai-events.json',JSON.stringify({events,pictures:UAI.pictures.manifest(),pictureNote:'Picture metadata only. Images are sent to the selected model but their bytes are not included in this export.'},null,2),'application/json'));
  root.append(el('h3','dialog-section-title','Start with an idea'));const prompts=el('div','prompt-options');for(const [title,,prompt]of starters)prompts.append(button(title,()=>{closeModal(true,false);insert(prompt);},'outline'));root.append(prompts);modalActions(modalCancel('Done'));
},{description:'Tune this conversation or pick a starting point.',size:'compact'});
$('sidebarToggle').onclick=()=>{const mobile=innerWidth<=768;document.body.classList.toggle(mobile?'sidebar-open':'sidebar-hidden');syncSidebar();if(mobile&&document.body.classList.contains('sidebar-open'))$('closeSidebar').focus();};
$('headerMenu').addEventListener('toggle',()=>{$('headerMenu').querySelector('summary').setAttribute('aria-expanded',String($('headerMenu').open));});
document.addEventListener('pointerdown',event=>{if(!$('headerMenu').contains(event.target))$('headerMenu').open=false;});
document.addEventListener('keydown',event=>{if(event.key==='Escape'&&$('headerMenu').open){$('headerMenu').open=false;$('headerMenu').querySelector('summary').focus();}});
$('headerMenu').addEventListener('click',event=>{const action=event.target.closest('button');if(action&&action.id!=='clear'){$('headerMenu').open=false;if(action.id==='exportChat')$('headerMenu').querySelector('summary').focus();}});
document.addEventListener('keydown',e=>{
  if(innerWidth>768||!document.body.classList.contains('sidebar-open')||$('modal').open)return;
  if(e.key==='Escape'){e.preventDefault();closeSidebar(true);}
  if(e.key==='Tab'){
    const focusable=[...$('sidebar').querySelectorAll('button,input,summary,a[href]')].filter(n=>!n.disabled&&!n.hidden&&n.getClientRects().length&&getComputedStyle(n).visibility!=='hidden');
    const first=focusable[0],last=focusable.at(-1);
    if(e.shiftKey&&document.activeElement===first){e.preventDefault();last?.focus();}
    else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus();}
  }
});
$('closeSidebar').onclick=()=>{if(innerWidth>768)document.body.classList.add('sidebar-hidden');closeSidebar(true);$('sidebarToggle').focus();};
$('searchThreads').onclick=()=>{$('threadSearch').hidden=!$('threadSearch').hidden;$('searchThreads').setAttribute('aria-expanded',String(!$('threadSearch').hidden));if(!$('threadSearch').hidden)$('threadSearch').focus();};
$('threadSearch').oninput=renderThreads;document.querySelectorAll('button[data-page]').forEach(b=>b.onclick=()=>show(b.dataset.page));
$('panel').addEventListener('focusout',()=>queueMicrotask(flushPanelRefresh));
$('panel').addEventListener('pointerdown',()=>{panelPointerActive=true;clearTimeout(panelPointerTimer);},true);
const releasePanelPointer=()=>{panelPointerActive=false;clearTimeout(panelPointerTimer);flushPanelRefresh();};
document.addEventListener('pointerup',()=>{if(panelPointerActive)panelPointerTimer=setTimeout(releasePanelPointer,400);});
document.addEventListener('pointercancel',()=>{if(panelPointerActive)panelPointerTimer=setTimeout(releasePanelPointer,0);});
document.addEventListener('click',()=>{if(panelPointerActive)queueMicrotask(releasePanelPointer);});
window.addEventListener('blur',releasePanelPointer);
document.addEventListener('selectionchange',()=>queueMicrotask(flushPanelRefresh));
$('latest').onclick=scrollToEnd;
$('transcript').onscroll=()=>$('latest').hidden=stick();
$('exportChat').onclick=()=>{
  const transcript=events.filter(e=>['user','assistant:text'].includes(e.kind)).map(e=>`### ${e.kind==='user'?'You':'Assistant'}\n\n${e.text}\n`).join('\n');
  const pictures=UAI.pictures.manifest();
  const appendix=pictures.length?'\n### Picture previews\n\nMetadata only; image bytes sent to the selected model are not included in this export.\n\n'+pictures.map(p=>`- ${String(p.name).replace(/[\r\n]/g,' ')} · ${p.width} × ${p.height} · ${p.bytes} bytes`).join('\n'):'';
  download('uai-transcript.md',transcript+appendix,'text/markdown');
};
document.addEventListener('click',e=>{const b=e.target.closest('.copy-code');if(b)copyText(b.closest('.code-block')?.querySelector('pre code')?.textContent||'');});
function closeSidebar(restore=false){const opened=document.body.classList.contains('sidebar-open');document.body.classList.remove('sidebar-open');syncSidebar();if(opened&&(restore||$('sidebar').contains(document.activeElement)))$('sidebarToggle').focus();}
function syncSidebar(){
  const mobile=innerWidth<=768;if(!mobile)document.body.classList.remove('sidebar-open');
  const open=mobile?document.body.classList.contains('sidebar-open'):!document.body.classList.contains('sidebar-hidden');
  $('sidebarToggle').setAttribute('aria-expanded',String(open));$('sidebar').inert=!open;
  $('sidebarOverlay').hidden=!mobile||!open;$('workspace').inert=mobile&&open;
  if(mobile&&open){$('sidebar').setAttribute('role','dialog');$('sidebar').setAttribute('aria-modal','true');}
  else{$('sidebar').removeAttribute('role');$('sidebar').removeAttribute('aria-modal');}
}
function themeChanged(){
  applyTheme(state.theme||{});const next=UAI.theme.resolved()==='dark'?'light':'dark';
  $('themeToggle').setAttribute('aria-label','Switch to '+next+' theme');$('themeToggle').title='Switch to '+next+' theme';
  document.body.dataset.codeTheme=state.settings?.ui?.codeTheme||UAI.theme.resolved();
}
document.addEventListener('uai:theme',themeChanged);themeChanged();
window.addEventListener('resize',()=>{syncSidebar();resizeComposer();});syncSidebar();
window.addEventListener('pagehide',()=>{saveDraft();persistDrafts();});
function showGate(reason=''){
  saveDraft();persistDrafts();stream?.close();clearTimeout(connectionRetry);closeSidebar();if($('modal').open)closeModal(true,false);closeWorkspace(false);
  connected=false;link='disconnected';$('app').hidden=true;$('gate').hidden=false;$('gate-error').textContent=reason;
  $('gate-connect').disabled=false;refresh();$('gate-token').focus({preventScroll:true});
}
async function checkConnection(){
  try{await api('/hello');}catch(error){if(error.status===401)return;}
  if(!$('app').hidden&&stream?.readyState!==EventSource.OPEN)connectionRetry=setTimeout(checkConnection,3000);
}
async function enter(){
  clearTimeout(connectionRetry);const hello=await api('/hello');
  if(hello.protocol!==2)throw Error('Update the bridge files, then restart the bridge to connect.');
  if(instance&&hello.instance!==instance){
    UAI.pictures.reset();renderer.reset();events=[];eventBytes=0;tools.clear();state={};$('transcript').replaceChildren();
    if(sendOperation){sendOperation.lost=true;setPhase('uncertain');persistOperation();}
  }
  instance=hello.instance;connected=!!hello.connected;bridgeUpdate=hello.update||{};kiloStatus=hello.capabilities?.kilo||{};clineStatus=hello.capabilities?.cline||{};openCodeStatus=hello.capabilities?.opencode||{};link='online';
  UAI.pictures.setToken(token);await UAI.pictures.configure(hello);
  try{sessionStorage.setItem('uai.token',token);sessionStorage.setItem('uai.instance',instance);localStorage.removeItem('uai.token');}catch{}
  $('gate').hidden=true;$('gate-error').textContent='';$('gate-token').value='';$('app').hidden=false;refresh();welcome();syncSidebar();(page==='chat'?$('input'):$('panel')).focus({preventScroll:true});
  stream?.close();stream=new EventSource('/api/stream?token='+encodeURIComponent(token));
  stream.onopen=()=>{clearTimeout(connectionRetry);link='online';refresh();if(page==='cowork'||page==='tunnels')requestPanelRefresh();};
  stream.onmessage=e=>{try{apply(JSON.parse(e.data));}catch(err){console.error(err);toast('Could not render bridge update: '+err.message);}};
  stream.onerror=()=>{link='offline';connected=false;refresh();if(page==='cowork'||page==='tunnels')requestPanelRefresh();clearTimeout(connectionRetry);connectionRetry=setTimeout(checkConnection,2000);};
  if(requestedSettings&&!connected){const section=requestedSettings;requestedSettings=null;openSettings(section);}
}
$('gate-form').onsubmit=async e=>{e.preventDefault();token=$('gate-token').value.trim().toLowerCase();$('gate-connect').disabled=true;$('gate-error').textContent='';try{await enter();}catch(err){showGate(err.message);}finally{$('gate-connect').disabled=false;}};
window.addEventListener('hashchange',async()=>{
  const supplied=location.hash.match(/(?:#|&)t=([a-f0-9]{64})(?:$|&)/i);if(!supplied)return;
  token=supplied[1].toLowerCase();history.replaceState(null,'',location.pathname);$('gate-connect').disabled=true;
  try{await enter();}catch(error){showGate(error.message);}finally{$('gate-connect').disabled=false;}
});
try{const pending=JSON.parse(stored('sessionStorage','uai.pendingSend')||'null');if(pending&&/^[\w-]{8,100}$/.test(pending.commandId)&&typeof pending.sessionId==='string'){sendOperation=pending;sendPhase='uncertain';}}catch{}
(async()=>{try{if(!token){showGate();return;}await enter();}catch(err){showGate(err.message||'Keep the bridge terminal open, then try connecting again.');}})();
