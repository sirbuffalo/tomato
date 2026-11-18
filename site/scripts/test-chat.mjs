import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import {fixture} from './local-d1.mjs';
const source=await readFile(new URL('../worker/index.js',import.meta.url),'utf8');
const worker=(await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'))).default;
new vm.Script(source.match(/<script>([\s\S]*?)<\/script>/)[1]);
assert(!source.includes('OPENAI_API_KEY'));assert(!source.includes('api.openai.com'));
const env=await fixture();let cookie='',jobs=[];const relay={authorization:'Bearer relay-test-only'};
async function request(path,body,extra={}){return worker.fetch(new Request('https://tomato.test'+path,{method:body===undefined?'GET':'POST',headers:{...(cookie?{cookie}:{}),...(body===undefined?{}:{'content-type':'application/json'}),...extra},...(body===undefined?{}:{body:JSON.stringify(body)})}),env,{waitUntil(promise){jobs.push(promise)}})}
try{
 const design=await (await request('/api/design')).json();assert.equal(typeof design.revision,'string');assert(design.html.includes('int[length=x]'));assert(!design.html.includes(env.FORM_PASSWORD));assert.equal((await request('/api/design?since='+design.revision)).status,204);
 assert.equal((await request('/api/chat/start',{password:'bad'})).status,403);
 assert.equal((await request('/api/chat/start',{password:'test-only'},{origin:'https://other.test'})).status,403);
 assert.equal((await request('/api/chat/start',{password:'test-only',padding:'a'.repeat(20000)})).status,413);
 assert.equal((await (await request('/api/status')).json()).bridge_online,false);
 let response=await request('/api/chat/start',{password:'test-only'});assert.equal(response.status,201);const setCookie=response.headers.get('set-cookie');assert(setCookie.includes('HttpOnly; Secure; SameSite=Strict'));cookie=setCookie.split(';')[0];
 const first=crypto.randomUUID(),question={id:first,message:'How do integers work?'};
 assert.equal((await request('/api/chat/message',question)).status,503);
 assert.equal((await request('/api/relay/chat/heartbeat',{})).status,401);
 assert.equal((await request('/api/relay/chat/heartbeat',{},relay)).status,200);
 assert.equal((await (await request('/api/status')).json()).bridge_online,true);
 // Failure after insertion must roll back the message as well as its lock.
 env.DB.raw.exec("CREATE TEMP TRIGGER reject_queue_lock BEFORE UPDATE OF active_message ON chat_conversations WHEN NEW.active_message IS NOT NULL BEGIN SELECT RAISE(ABORT, 'injected lock failure'); END");
 assert.equal((await request('/api/chat/message',question)).status,503);
 assert.equal(env.DB.raw.prepare('SELECT COUNT(*) AS n FROM chat_messages').get().n,0);
 assert.equal(env.DB.raw.prepare('SELECT active_message FROM chat_conversations').get().active_message,null);
 env.DB.raw.exec('DROP TRIGGER reject_queue_lock');
 // Concurrent retries deduplicate; a different message cannot steal the lock.
 const outcomes=await Promise.all([
   request('/api/chat/message',question),
   request('/api/chat/message',question),
   request('/api/chat/message',{id:crypto.randomUUID(),message:'Concurrent other message'})
 ]);
 assert.deepEqual(outcomes.map(r=>r.status),[202,202,409]);
 assert.equal(env.DB.raw.prepare('SELECT COUNT(*) AS n FROM chat_messages').get().n,1);
 assert.equal(env.DB.raw.prepare('SELECT active_message FROM chat_conversations').get().active_message,first);
 assert.equal((await request('/api/chat/message',question)).status,202);
 assert.equal((await request('/api/chat/message',{...question,message:'changed'})).status,409);
 assert.equal((await request('/api/chat/message',{id:crypto.randomUUID(),message:'Another'})).status,409);
 let history=await (await request('/api/chat')).json();assert.equal(history.messages.length,1);assert.equal(history.messages[0].state,'pending');
 const savedCookie=cookie;cookie='';assert.equal((await request('/api/chat')).status,401);cookie=savedCookie;
 assert.equal((await request('/api/relay/chat/pending')).status,401);
 let queue=await (await request('/api/relay/chat/pending',undefined,relay)).json();assert.equal(queue.requests.length,1);assert.equal(queue.requests[0].messages[0].content,question.message);
 assert.equal((await request('/api/relay/chat/reply',{id:first,content:'No auth'})).status,401);
 const answer='Confirmed: ordinary integers grow automatically. 🌱';
 assert.equal((await request('/api/relay/chat/reply',{id:first,content:answer},relay)).status,200);
 assert.equal((await request('/api/relay/chat/reply',{id:first,content:'duplicate'},relay)).status,200);
 history=await (await request('/api/chat')).json();assert.equal(history.messages.length,2);assert.equal(history.messages[1].content,answer);assert.equal(history.messages[1].reply_to,first);assert(history.messages.every(m=>m.state==='complete'));
 queue=await (await request('/api/relay/chat/pending',undefined,relay)).json();assert.equal(queue.requests.length,0);
 const second=crypto.randomUUID();assert.equal((await request('/api/chat/message',{id:second,message:'Fixed widths?'})).status,202);
 queue=await (await request('/api/relay/chat/pending',undefined,relay)).json();assert.equal(queue.requests[0].messages.length,3);
 let rows=await (await request('/api/relay/chat',undefined,relay)).json();assert.equal(rows.messages.length,3);
 assert.equal((await request('/api/relay/chat/mark',{ids:rows.messages.map(m=>m.id)},relay)).status,200);
 rows=await (await request('/api/relay/chat',undefined,relay)).json();assert.equal(rows.messages.length,1);assert.equal(rows.messages[0].id,second);
 env.DB.raw.prepare('UPDATE chat_bridge_status SET last_seen = ?').run(new Date(Date.now()-60000).toISOString());assert.equal((await (await request('/api/status')).json()).bridge_online,false);
 assert.equal((await request('/api/relay/cleanup',{})).status,401);
 let cleanup=await (await request('/api/relay/cleanup',{},relay)).json();assert.equal(cleanup.deleted.conversations,0);
 env.DB.raw.prepare('UPDATE chat_conversations SET expires_at = ?').run(new Date(Date.now()-1000).toISOString());assert.equal((await request('/api/relay/chat/reply',{id:second,content:'Late'},relay)).status,410);
 cleanup=await (await request('/api/relay/cleanup',{},relay)).json();assert.equal(cleanup.deleted.conversations,1);assert.equal(cleanup.deleted.messages,3);
 env.FEEDBACK_OPENED_AT=new Date(Date.now()-604800001).toISOString();env.FEEDBACK_CLOSES_AT=new Date(Date.parse(env.FEEDBACK_OPENED_AT)+604800000).toISOString();
 assert.equal((await request('/api/chat/start',{password:'test-only'})).status,410);
 console.log('PASS: no model API dependency; migrations, client syntax, auth/origin/body gates, private sessions, heartbeat expiry, durable queue/replay/concurrency, authenticated context/replies, deduplication, transcript review, cutoff and cleanup.');
}finally{await Promise.all(jobs);env.DB.raw.close()}
