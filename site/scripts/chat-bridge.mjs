// Outbound, task-owned relay. This process never exposes byre's owner socket.
import {createServer,request as localRequest} from 'node:http';
import {mkdir,readFile,writeFile,rename,chmod,unlink,lstat} from 'node:fs/promises';
import {homedir} from 'node:os';
import {join} from 'node:path';
const local=process.argv.includes('--local'),uid=process.getuid();
const socketPath=`/tmp/tomato-chat-bridge${local?'-test':''}-${uid}.sock`;
const directory=join(homedir(),'Library/Application Support/byre',local?'tomato-chat-bridge-test':'tomato-chat-bridge');
const configPath=join(directory,'config.json'),expectedOrigin=local?'http://127.0.0.1:49183':'https://tomato-design.tailcecab.ts.net';
await mkdir(directory,{recursive:true,mode:0o700});await chmod(directory,0o700);
let config=null,pending=null,lastNotification=0,lastHeartbeat=0,lastHealth='',windowOpen=null,stopped=false,configuredAt=Date.now();
function validate(value){if(!value||value.baseUrl!==expectedOrigin||typeof value.relayKey!=='string'||value.relayKey.length<(local?10:20))throw Error('Invalid configuration');return {baseUrl:value.baseUrl,relayKey:value.relayKey};}
try{const stat=await lstat(configPath);if(!stat.isFile()||stat.uid!==uid||(stat.mode&0o077))throw Error('Credential file must be owner-only');config=validate(JSON.parse(await readFile(configPath,'utf8')));}catch(error){if(error.code!=='ENOENT')throw error;}
if(local&&!config)config=validate({baseUrl:expectedOrigin,relayKey:'relay-test-only'});
async function saveConfig(value){const valid=validate(value);await writeFile(configPath+'.new',JSON.stringify(valid)+'\n',{mode:0o600});await chmod(configPath+'.new',0o600);await rename(configPath+'.new',configPath);config=valid;configuredAt=Date.now();}
async function remote(path,body){if(!config)throw Error('Bridge not configured');const response=await fetch(config.baseUrl+path,{method:body===undefined?'GET':'POST',headers:{authorization:'Bearer '+config.relayKey,...(body===undefined?{}:{'content-type':'application/json'})},...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(10000)});if(!response.ok){await response.body?.cancel();throw Error('Site returned HTTP '+response.status);}return response.json();}
async function incoming(req){let length=0,chunks=[];for await(const chunk of req){length+=chunk.length;if(length>125000)throw Error('Request too large');chunks.push(chunk);}return JSON.parse(Buffer.concat(chunks).toString('utf8'));}
const server=createServer(async(req,res)=>{
 res.setHeader('content-type','application/json');
 try{
  let output;const controlUrl=new URL(req.url,"http://localhost");
  if(req.method==='GET'&&req.url==='/status')output={configured:Boolean(config),baseUrl:expectedOrigin,pending_id:pending?.id||null,last_heartbeat:lastHeartbeat?new Date(lastHeartbeat).toISOString():null,config_file:configPath};
  else if(req.method==='POST'&&req.url==='/configure'){if(config&&!local)throw Error('Already configured');await saveConfig(await incoming(req));output={ok:true};}
  else if(req.method==='GET'&&req.url==='/pending'){const queue=await remote('/api/relay/chat/pending');pending=queue.requests[0]||null;output={request:pending};}
  else if(req.method==='GET'&&controlUrl.pathname==='/transcripts'){
   const after=Number(controlUrl.searchParams.get('after')||0);if(!Number.isSafeInteger(after)||after<0)throw Error('Invalid cursor');
   output=await remote('/api/relay/chat/conversations?after='+after);
  }
  else if(req.method==='GET'&&controlUrl.pathname==='/transcript'){
   const id=controlUrl.searchParams.get('id');if(!id||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(id))throw Error('Invalid conversation ID');
   output=await remote('/api/relay/chat/transcript?id='+id);
  }
  else if(req.method==='POST'&&req.url==='/reply'){
   const body=await incoming(req);if(!/^[0-9a-f-]{36}$/.test(body.id)||typeof body.content!=='string'||!body.content.trim()||body.content.length>30000)throw Error('Invalid reply');
   const reply=await remote('/api/relay/chat/reply',body),roundTrip=pending?.id===body.id?Date.now()-Date.parse(pending.created_at):null;
   console.log(JSON.stringify({event:'reply_saved',id:body.id,round_trip_ms:roundTrip,at:new Date().toISOString()}));pending=null;lastNotification=0;output={...reply,round_trip_ms:roundTrip};
  }else{res.statusCode=404;output={error:'Not found'};}
  res.end(JSON.stringify(output));
 }catch(error){res.statusCode=503;res.end(JSON.stringify({error:error.message}));}
});
// Refuse another running bridge; remove only a stale, owner-owned Unix socket.
try{const stat=await lstat(socketPath);if(!stat.isSocket()||stat.uid!==uid)throw Error('Unsafe control socket path');const active=await new Promise(resolve=>{const req=localRequest({socketPath,path:'/status'},res=>{res.resume();resolve(true)});req.on('error',()=>resolve(false));req.setTimeout(1000,()=>{req.destroy();resolve(true)});req.end()});if(active)throw Error('Bridge already running');await unlink(socketPath);}catch(error){if(error.code!=='ENOENT')throw error;}
await new Promise(resolve=>server.listen(socketPath,resolve));await chmod(socketPath,0o600);
console.log('Tomato bridge control socket: '+socketPath);console.log(config?'Protected configuration loaded.':'Awaiting protected local configuration.');
function health(message){if(message!==lastHealth){console.log(message);lastHealth=message;}}
async function tick(){
 if(!config||stopped)return;
 try{
  if(Date.now()-lastHeartbeat>10000){const state=await remote('/api/relay/chat/heartbeat',{});lastHeartbeat=Date.now();windowOpen=state.open;}
  const queue=await remote('/api/relay/chat/pending');const next=queue.requests[0]||null;
  const changed=next?.id!==pending?.id;pending=next;
  // Closed acceptance does not cancel messages already in the durable queue.
  health(windowOpen?'Mac mini bridge connected.':'Feedback window closed; draining previously accepted messages.');
  if(next&&(changed||Date.now()-lastNotification>30000)&&Date.now()-configuredAt>1500){
   if(!/^[0-9a-f-]{36}$/.test(next.id))throw Error('Invalid queue identifier');
   lastNotification=Date.now();console.log(JSON.stringify({event:'request_observed',id:next.id,created_at:next.created_at,observed_at:new Date().toISOString()}));
   process.stdout.write('\x1b]9;Tomato private chat request '+next.id+'. Fetch authenticated context with chat-bridge-control pending; reply through chat-bridge-control reply; then re-arm this terminal with terminal_type(empty).\x07');
  }
 }catch(error){health('Bridge waiting: '+error.message);}
}
async function stop(){if(stopped)return;stopped=true;server.close();await unlink(socketPath).catch(()=>{});process.exit(0);}
process.on('SIGTERM',stop);process.on('SIGINT',stop);
while(!stopped){await tick();await new Promise(resolve=>setTimeout(resolve,2000));}
