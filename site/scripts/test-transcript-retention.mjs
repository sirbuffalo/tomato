import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import worker from '../worker/index.js';
import {fixture} from './local-d1.mjs';

const env=await fixture(),relay={authorization:'Bearer relay-test-only'};
let cookie='';
async function request(path,body,headers={}){
 return worker.fetch(new Request('https://tomato.test'+path,{method:body===undefined?'GET':'POST',headers:{...(cookie?{cookie}:{}),...(body===undefined?{}:{'content-type':'application/json'}),...headers},...(body===undefined?{}:{body:JSON.stringify(body)})}),env,{waitUntil(){}});
}
try{
 const started=await request('/api/chat/start',{password:'test-only'});
 assert.equal(started.status,201);
 const setCookie=started.headers.get('set-cookie');cookie=setCookie.split(';')[0];
 assert(setCookie.includes('HttpOnly; Secure; SameSite=Strict'));
 const age=Number(setCookie.match(/Max-Age=(\d+)/)[1]);assert(age>=14*86400-2&&age<=14*86400);
 const row=env.DB.raw.prepare('SELECT * FROM chat_conversations').get();
 assert.equal(Date.parse(row.expires_at)-Date.parse(row.created_at),14*86400000);
 // Upgrade an existing cutoff-limited session, preserving its token and absolute creation date.
 env.DB.raw.prepare('UPDATE chat_conversations SET expires_at = ?').run(env.FEEDBACK_CLOSES_AT);
 const migration=await readFile(new URL('../drizzle/0004_transcript_retention.sql',import.meta.url),'utf8');
 env.DB.raw.exec(migration);
 assert.equal(env.DB.raw.prepare('SELECT expires_at FROM chat_conversations').get().expires_at,row.expires_at);
 await request('/api/relay/chat/heartbeat',{},relay);
 const id=crypto.randomUUID();
 assert.equal((await request('/api/chat/message',{id,message:'Keep this transcript'})).status,202);
 assert.equal((await request('/api/relay/chat/reply',{id,content:'Saved answer'},relay)).status,200);
 const waiting=crypto.randomUUID();
 assert.equal((await request('/api/chat/message',{id:waiting,message:'Accepted before cutoff'})).status,202);
 // Closing acceptance does not expire the saved session, including on a fresh request after reload.
 env.FEEDBACK_OPENED_AT=new Date(Date.now()-604800001).toISOString();
 env.FEEDBACK_CLOSES_AT=new Date(Date.parse(env.FEEDBACK_OPENED_AT)+604800000).toISOString();
 let response=await request('/api/chat');assert.equal(response.status,200);
 const history=await response.json();assert.deepEqual(history.messages.map(m=>m.content),['Keep this transcript','Saved answer','Accepted before cutoff']);
 assert.equal(history.expires_at,row.expires_at);
 assert(Number(response.headers.get('set-cookie').match(/Max-Age=(\d+)/)[1])>7*86400);
 assert.equal((await request('/api/chat')).status,200); // Same persisted cookie, fresh request.
 assert.equal(env.DB.raw.prepare('SELECT expires_at FROM chat_conversations').get().expires_at,row.expires_at); // No sliding expiry.
 assert.equal((await request('/api/chat/start',{password:'test-only'})).status,410);
 assert.equal((await request('/api/chat/message',{id:crypto.randomUUID(),message:'Too late'})).status,410);
 // Accepted messages still reach the bridge and complete after closure, including an in-flight reply retry.
 assert.equal((await request('/api/relay/chat/pending')).status,401);
 const queued=await (await request('/api/relay/chat/pending',undefined,relay)).json();assert.equal(queued.requests[0].id,waiting);
 assert.equal((await request('/api/relay/chat/reply',{id:waiting,content:'Finished after cutoff'})).status,401);
 const finished=await (await request('/api/relay/chat/reply',{id:waiting,content:'Finished after cutoff'},relay)).json();
 const retried=await (await request('/api/relay/chat/reply',{id:waiting,content:'Duplicate answer'},relay)).json();assert.equal(retried.id,finished.id);
 assert.equal((await request('/api/relay/chat/reply',{id:crypto.randomUUID(),content:'Unsolicited'},relay)).status,404);
 const completed=await (await request('/api/chat')).json();assert.equal(completed.messages.length,4);assert.equal(completed.messages.at(-1).content,'Finished after cutoff');assert(completed.messages.every(m=>m.state==='complete'));
 assert.deepEqual((await (await request('/api/relay/chat/pending',undefined,relay)).json()).requests,[]);
 assert.equal((await request('/api/chat',undefined,{origin:'https://other.test'})).status,403);
 const savedCookie=cookie;cookie='';assert.equal((await request('/api/chat')).status,401);cookie='__Host-tomato_chat='+crypto.randomUUID()+'-'+crypto.randomUUID();assert.equal((await request('/api/chat')).status,401);cookie=savedCookie;
 // Losing the browser token still permits owner-assisted export through the protected relay.
 const browserCookie=cookie;cookie='';
 assert.equal((await request('/api/relay/chat/conversations')).status,401);
 assert.equal((await request('/api/relay/chat/transcript?id='+row.id)).status,401);
 const listed=await (await request('/api/relay/chat/conversations',undefined,relay)).json();assert.equal(listed.conversations[0].id,row.id);assert(!('token_hash' in listed.conversations[0]));
 assert.equal((await request('/api/relay/chat/conversations?after=bad',undefined,relay)).status,400);
 const recovered=await (await request('/api/relay/chat/transcript?id='+row.id,undefined,relay)).json();assert.equal(recovered.messages.length,4);assert.equal(recovered.messages.at(-1).content,'Finished after cutoff');assert(!('token_hash' in recovered.conversation));
 assert.equal((await request('/api/relay/chat/transcript?id=invalid',undefined,relay)).status,400);
 assert.equal((await request('/api/relay/chat/transcript?id='+crypto.randomUUID(),undefined,relay)).status,404);
 cookie=browserCookie;
 const cleanup=await (await request('/api/relay/cleanup',{},relay)).json();assert.equal(cleanup.deleted.conversations,0);assert.equal((await request('/api/chat')).status,200);
 // Retention still ends: authentication cannot revive an expired conversation.
 env.DB.raw.prepare('UPDATE chat_conversations SET expires_at = ?').run(new Date(Date.now()-1000).toISOString());
 assert.equal((await request('/api/chat')).status,401);
 assert.equal((await request('/api/relay/chat/transcript?id='+row.id,undefined,relay)).status,410);
 assert.equal((await (await request('/api/relay/chat/conversations',undefined,relay)).json()).conversations.length,0);
 const expired=await (await request('/api/relay/cleanup',{},relay)).json();assert.equal(expired.deleted.conversations,1);assert.equal(expired.deleted.messages,4);
 console.log('PASS: legacy expiry migration, fixed 14-day session/cookie retention, post-cutoff authenticated reload/history, denied new browser activity, accepted-message draining/reply retries after cutoff, origin/token isolation, no sliding expiry, and expired cleanup.');
}finally{env.DB.raw.close()}
