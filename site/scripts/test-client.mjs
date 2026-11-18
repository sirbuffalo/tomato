import assert from 'node:assert/strict';
import worker from '../worker/index.js';
import vm from 'node:vm';

const source=await (await worker.fetch(new Request('https://example.com/'),{},{})).text();
const script=source.match(/<script>([\s\S]*?)<\/script>/)[1];
const nodes=new Map();
function node(){return {value:'',disabled:false,hidden:false,open:false,textContent:'',listeners:{},scrollHeight:0,scrollTop:0,clientHeight:0,
 addEventListener(event,callback){this.listeners[event]=callback},querySelectorAll(){return []},append(){},replaceChildren(){},click(){},focus(){},showModal(){this.open=true},close(){this.open=false}}}
const get=id=>{if(!nodes.has(id))nodes.set(id,node());return nodes.get(id)};
let startCalls=0,startGate=null,fail=true,rejection=0,history=[],holdMode=null,release,closed=false,savedBlob;const attempts=[];
const context=vm.createContext({document:{getElementById:get,createElement:node},window:{getSelection:()=>({isCollapsed:true})},setInterval(){},setTimeout(fn){fn()},Blob,URL:{createObjectURL(blob){savedBlob=blob;return "blob:test"},revokeObjectURL(){}},crypto,
 async fetch(path,options){
  if(path==='/api/status')return {ok:true,json:async()=>({open:!closed,bridge_online:true,closes_at:new Date(Date.now()+(closed?-60000:60000)).toISOString()})};
  if(path==='/api/chat/start'){startCalls++;if(startGate)await startGate;return {ok:true,json:async()=>({messages:history})};}
  if(path==='/api/chat')return {ok:true,json:async()=>({messages:history})};
  if(path==='/api/chat/message'){
   const body=JSON.parse(options.body);attempts.push(body);
   if(holdMode){
    history=[{id:body.id,role:'user',content:body.message,state:'pending'}];
    const mode=holdMode;
    return new Promise((resolve,reject)=>{release=()=>mode==='network'?reject(Error('POST response lost')):resolve({ok:true,json:async()=>{throw Error('POST response JSON lost')}})});
   }
   if(fail)throw Error('Simulated network failure before enqueue');
   if(rejection)return {ok:false,status:rejection,json:async()=>({error:'Message rejected'})};
   history=[{id:body.id,role:'user',content:body.message,state:'pending'}];
   return {ok:true,json:async()=>({id:body.id,state:'pending'})};
  }
  throw Error('Unexpected request: '+path);
 }});
vm.runInContext(script,context);
await vm.runInContext('(async()=>{await refreshStatus();await sendMessage("   ","blank");})()',context);
assert.equal(attempts.length,0);
get('message').value='   ';
await get('note-form').listeners.submit({preventDefault(){}});
assert.equal(attempts.length,0);
assert.equal(get('result').textContent,'Write a message of up to 3,000 characters.');
await vm.runInContext('(async()=>{await refreshStatus();await pollChat();await sendMessage("Keep this draft", "first-id");})()',context);
assert.equal(get('chat-message').value,'Keep this draft');
assert.equal(get('retry-chat').hidden,false);
assert.equal(get('chat-send').disabled,true);
assert.equal(get('chat-message').readOnly,true);
assert.equal(get('send').disabled,true);
await vm.runInContext('(async()=>{await refreshStatus();await pollChat();await sendMessage("Overwrite attempt", "other-id");})()',context);
assert.equal(attempts.length,1);
assert.equal(get('chat-message').value,'Keep this draft');
assert.equal(get('chat-send').disabled,true);
assert.equal(get('send').disabled,true);
fail=false;
await vm.runInContext('sendMessage(retryMessage.message,retryMessage.id)',context);
assert.deepEqual(attempts.map(x=>x.id),['first-id','first-id']);
assert.equal(history[0].content,'Keep this draft');
assert.equal(get('chat-message').value,'');
assert.equal(get('chat-send').disabled,true); // Still awaiting the agent reply.
history=[{...history[0],state:'complete'},{id:'answer',role:'assistant',content:'Received',state:'complete'}];
await vm.runInContext('pollChat()',context);
assert.equal(get('chat-send').disabled,false);
assert.equal(get('chat-message').readOnly,false);
assert.equal(get('send').disabled,false);
for(const status of [400,429]){
 rejection=status;
 await vm.runInContext('sendMessage("Rejected draft","rejected-'+status+'")',context);
 assert.equal(get('chat-send').disabled,true);
 assert.equal(get('discard-chat').hidden,false);
 get('discard-chat').listeners.click();
 assert.equal(get('chat-message').value,'Rejected draft');
 assert.equal(get('chat-message').readOnly,false);
 assert.equal(get('chat-send').disabled,false);
 assert.equal(get('retry-chat').hidden,true);
 assert.equal(get('discard-chat').hidden,true);
}
rejection=0;
await vm.runInContext('sendMessage("Edited valid message","edited-id")',context);
assert.equal(history[0].content,'Edited valid message');
assert.equal(history[0].id,'edited-id');
for(const mode of ['network','json']){
 history=history.map(item=>({...item,state:'complete'}));
 await vm.runInContext('pollChat()',context);
 holdMode=mode;
 const sending=vm.runInContext('sendMessage("Observed before POST failure","race-'+mode+'")',context);
 await vm.runInContext('pollChat()',context);
 assert.equal(vm.runInContext('retryMessage',context),null);
 assert.equal(get('chat-message').value,'');
 if(mode==='json'){
  // Even an answer arriving before POST failure must not resurrect a draft.
  history=history.map(item=>({...item,state:'complete'}));
  await vm.runInContext('pollChat()',context);
 }
 release();await sending;
 assert.equal(vm.runInContext('retryMessage',context),null);
 assert.equal(get('chat-message').value,'');
 assert.equal(get('retry-chat').hidden,true);
 assert.equal(get('discard-chat').hidden,true);
 assert.equal(get('chat-send').disabled,mode==='network');
 history=history.map(item=>({...item,state:'complete'}));
 await vm.runInContext('pollChat()',context);
 assert.equal(get('chat-send').disabled,false);
 assert.equal(get('chat-message').value,'');
 holdMode=null;
}
console.log('PASS: blank/rejected/uncertain drafts recover safely; polling acknowledgements survive late network and JSON failures without duplicate drafts.');

// A returning main-form submission must stay visible but unsent behind a pending turn.
history=[{id:'earlier',role:'user',content:'Earlier question',state:'pending'}];
get('message').value='New question';get('chat-message').value='Existing draft';
const countBefore=attempts.length;
await get('note-form').listeners.submit({preventDefault(){}});
assert.equal(attempts.length,countBefore);
assert.equal(get('chat').open,true);
assert.equal(get('message').value,'');
assert.equal(get('chat-message').value,'Existing draft\n\nNew question');
assert.equal(get('chat-draft-notice').hidden,false);
assert.match(get('chat-draft-notice').textContent,/has not been sent/);
await vm.runInContext('(async()=>{await pollChat();await refreshStatus()})()',context);
assert.equal(get('chat-message').value,'Existing draft\n\nNew question');
assert.equal(get('chat-draft-notice').hidden,false);
history=history.map(item=>({...item,state:'complete'}));
await vm.runInContext('pollChat()',context);
assert.equal(attempts.length,countBefore); // Never auto-send after the previous reply.
assert.match(get('chat-draft-notice').textContent,/press Send/);
assert.equal(get('chat-send').disabled,false);
const preservedDraft=get('chat-message').value;
get('chat-message').value='x'.repeat(3001);
await get('chat-form').listeners.submit({preventDefault(){}});
assert.equal(attempts.length,countBefore);
assert.equal(get('chat-message').value.length,3001); // Combined drafts can exceed the send limit; keep them editable.
assert.equal(get('chat-draft-notice').hidden,false);
get('chat-message').value=preservedDraft;
await get('chat-form').listeners.submit({preventDefault(){}});
assert.equal(attempts.length,countBefore+1);
assert.equal(attempts.at(-1).message,'Existing draft\n\nNew question');
assert.equal(get('chat-draft-notice').hidden,true);
console.log('PASS: returning pending conversations preserve visible unsent drafts until explicit send.');

// An idle conversation must not send main-form text over different unsent composer text.
history=history.map(item=>({...item,state:'complete'}));
await vm.runInContext('pollChat()',context);
get('message').value='Second question';get('chat-message').value='Held composer text';
const idleBefore=attempts.length;
await get('note-form').listeners.submit({preventDefault(){}});
assert.equal(attempts.length,idleBefore);
assert.equal(get('chat-message').value,'Held composer text\n\nSecond question');
assert.equal(get('message').value,'');
assert.equal(get('chat-draft-notice').hidden,false);
assert.match(get('chat-draft-notice').textContent,/press Send/);
assert.equal(get('chat-send').disabled,false);
get('message').value='Held composer text\n\nSecond question';
// A status refresh while the conversation is opening must not unlock a second concurrent open.
{
 history=[];get('chat-message').value='';
 let openGate;startGate=new Promise(r=>{openGate=r});
 const callsBefore=startCalls,sendsBefore=attempts.length;
 get('message').value='Opening question';
 const first=get('note-form').listeners.submit({preventDefault(){}});
 await new Promise(r=>setImmediate(r));
 await vm.runInContext('refreshStatus()',context);
 assert.equal(get('send').disabled,true);
 assert.equal(get('message').readOnly,true); // edits cannot be lost mid-open
 get('message').value='Second while opening';
 await get('note-form').listeners.submit({preventDefault(){}});
 assert.equal(startCalls,callsBefore+1);
 assert.equal(get('message').value,'Second while opening'); // not cleared or lost
 openGate();startGate=null;await first;
 assert.equal(attempts.length,sendsBefore+1);
 assert.equal(attempts.at(-1).message,'Opening question');
  assert.equal(get('message').readOnly,false);
console.log('PASS: main form stays locked while opening; concurrent submissions cannot start or lose text.');
}
console.log('PASS: idle conversations hold main-form text with differing composer drafts until explicit send.');

// Closed-window history remains usable and downloadable while composition stays disabled.
closed=true;history=[{id:'saved',role:'user',content:'Saved after cutoff',state:'complete'},{id:'saved-answer',role:'assistant',content:'Retained reply',state:'complete'}];
await vm.runInContext('(async()=>{await refreshStatus();await pollChat()})()',context);
assert.equal(get('reopen-chat').hidden,false);
assert.equal(get('reopen-chat').textContent,'View saved conversation');
assert.equal(get('chat-send').disabled,true);assert.equal(get('chat-message').readOnly,true);
assert.match(get('chat-error').textContent,/read-only/);
get('download-chat').listeners.click();
assert.match(await savedBlob.text(),/Saved after cutoff/);assert.match(await savedBlob.text(),/Retained reply/);
assert.equal(get('chat-message').readOnly,true); // closed drafts stay selectable
assert.equal(get('message').readOnly,true); // unsent main-form text stays selectable
assert.equal(get('message').disabled,false);
assert.equal(get('send').disabled,true);
assert.equal(get('chat-message').disabled,false);
console.log('PASS: closed-window transcript stays visible/downloadable with read-only controls.');
