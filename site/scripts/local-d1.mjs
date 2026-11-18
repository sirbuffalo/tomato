import {DatabaseSync} from 'node:sqlite';
import {readFile} from 'node:fs/promises';
const root=new URL('../',import.meta.url);
export function database(path=':memory:'){
 const db=new DatabaseSync(path);let batchTail=Promise.resolve();
 return {raw:db,prepare(sql){const stmt=db.prepare(sql);return {values:[],bind(...values){this.values=values;return this},async first(){return stmt.get(...this.values)||null},async all(){return {results:stmt.all(...this.values)}},async run(){const result=stmt.run(...this.values);return {meta:{changes:Number(result.changes)}}}}},async batch(statements){const task=batchTail.then(async()=>{db.exec('BEGIN');try{const out=[];for(const stmt of statements)out.push(await stmt.run());db.exec('COMMIT');return out}catch(error){db.exec('ROLLBACK');throw error}});batchTail=task.catch(()=>{});return task}};
}
export async function fixture(){const DB=database();for(const name of ['0000_feedback','0001_chat','0002_bridge','0003_password_attempts','0004_transcript_retention'])DB.raw.exec(await readFile(new URL('drizzle/'+name+'.sql',root),'utf8'));const now=Date.now();return {DB,FORM_PASSWORD:'test-only',RELAY_KEY:'relay-test-only',FEEDBACK_OPENED_AT:new Date(now-60000).toISOString(),FEEDBACK_CLOSES_AT:new Date(now-60000+604800000).toISOString()};}
