import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
const source=await readFile(new URL('./chat-bridge.mjs',import.meta.url),'utf8');
const tick=source.slice(source.indexOf('async function tick(){'),source.indexOf('async function stop(){'));
const id='11111111-1111-1111-1111-111111111111';let now=20000,queued=true;
const calls=[],notifications=[],health=[];
const context=vm.createContext({config:true,stopped:false,lastHeartbeat:0,windowOpen:null,pending:null,lastNotification:0,configuredAt:0,Date:class extends Date {static now(){return now}},console:{log(){}},process:{stdout:{write:text=>notifications.push(text)}},health:text=>health.push(text),async remote(path){calls.push(path);if(path.endsWith('heartbeat'))return {open:false};if(path.endsWith('pending'))return {requests:queued?[{id,created_at:'2026-11-14T06:58:48.000Z'}]:[]};throw Error('Unexpected path')}});
vm.runInContext(tick,context);
await vm.runInContext('tick()',context);
assert.deepEqual(calls,['/api/relay/chat/heartbeat','/api/relay/chat/pending']);
assert.equal(notifications.length,1);assert(notifications[0].includes(id));assert.match(health.at(-1),/draining/);
now+=31000;await vm.runInContext('tick()',context);assert.equal(notifications.length,2); // Retries even after closed heartbeat.
queued=false;now+=2000;await vm.runInContext('tick()',context);assert.equal(notifications.length,2);assert.equal(vm.runInContext('pending',context),null);
console.log('PASS: bridge polls/notifies/retries accepted requests after closed heartbeat and becomes idle when drained.');
