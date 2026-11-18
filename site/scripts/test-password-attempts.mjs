import assert from 'node:assert/strict';
import worker from '../worker/index.js';
import {fixture} from './local-d1.mjs';

const env=await fixture();
async function attempt(path,ip,password='incorrect',extra={}){
 return worker.fetch(new Request('https://tomato.test'+path,{method:'POST',headers:{'content-type':'application/json',...(ip?{'cf-connecting-ip':ip}:{}),...extra},body:JSON.stringify({password,message:'Test note'})}),env,{waitUntil(){}});
}
try{
 // One shared per-client budget covers both password gates, concurrently.
 const replies=await Promise.all(Array.from({length:12},(_,i)=>attempt(i%2?'/api/feedback':'/api/chat/start','192.0.2.10')));
 assert.equal(replies.filter(r=>r.status===403).length,10);
 assert.equal(replies.filter(r=>r.status===429).length,2);
 const blocked=await attempt('/api/chat/start','192.0.2.10','test-only');
 assert.equal(blocked.status,429);assert(!blocked.headers.has('set-cookie'));
 assert(Number(blocked.headers.get('retry-after'))>0);
 assert.equal((await attempt('/api/feedback','192.0.2.10','test-only')).status,429);
 assert.equal(env.DB.raw.prepare('SELECT COUNT(*) AS n FROM chat_conversations').get().n,0);
 assert.equal(env.DB.raw.prepare('SELECT COUNT(*) AS n FROM feedback').get().n,0);
 assert.equal((await attempt('/api/chat/start','192.0.2.11')).status,403);
 assert(env.DB.raw.prepare('SELECT bucket_key FROM password_attempts').all().every(row=>!row.bucket_key.includes('192.0.2.')));
 // Expired windows reset; chat starts work and valid legacy submissions get a clear retirement error.
 env.DB.raw.prepare('UPDATE password_attempts SET window_start = ?').run(Date.now()-1200000);
 assert.equal((await attempt('/api/chat/start','192.0.2.10','test-only')).status,201);
 const retired=await attempt('/api/feedback','192.0.2.10','test-only');
 assert.equal(retired.status,410);assert.match((await retired.json()).error,/not saved.*private chat/);
 assert.equal(env.DB.raw.prepare('SELECT COUNT(*) AS n FROM feedback').get().n,0);
 // Missing identity cannot use arbitrary forwarded headers to evade its bucket.
 env.DB.raw.exec('DELETE FROM password_attempts');
 for(let i=0;i<10;i++)assert.equal((await attempt('/api/chat/start',null,'incorrect',{'x-forwarded-for':'198.51.100.'+i})).status,403);
 assert.equal((await attempt('/api/feedback',null)).status,429);
 // Rotating clients still has a global ceiling and bounded stored buckets.
 env.DB.raw.exec('DELETE FROM password_attempts');
 for(let i=0;i<100;i++)assert.equal((await attempt(i%2?'/api/chat/start':'/api/feedback','203.0.113.'+i)).status,403);
 assert.equal((await attempt('/api/chat/start','198.51.100.200')).status,429);
 assert.equal(env.DB.raw.prepare('SELECT COUNT(*) AS n FROM password_attempts').get().n,101);
 env.DB.raw.exec('DROP TABLE password_attempts');
 assert.equal((await attempt('/api/chat/start','192.0.2.1','test-only')).status,503);
 assert.equal((await attempt('/api/feedback','192.0.2.1','test-only')).status,503);
 console.log('PASS: shared atomic client/global password budgets, parallel attempts, expiry, correct-password throttling, missing-identity fallback, and bounded hashed buckets.');
}finally{env.DB.raw.close()}
