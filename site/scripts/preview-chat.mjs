// Local bridge QA only. Never included in the deployed Worker artifact.
import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {fixture} from './local-d1.mjs';
const source=await readFile(new URL('../worker/index.js',import.meta.url),'utf8');
const worker=(await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'))).default;
const env=await fixture();
const server=createServer(async(req,res)=>{
 try{
  const headers=new Headers();for(const [key,value] of Object.entries(req.headers))if(value!==undefined)headers.set(key,Array.isArray(value)?value.join(', '):value);
  if(headers.has('cookie'))headers.set('cookie',headers.get('cookie').replace('tomato_preview=','__Host-tomato_chat='));
  const request=new Request('http://127.0.0.1:'+server.address().port+req.url,{method:req.method,headers,...(['GET','HEAD'].includes(req.method)?{}:{body:req,duplex:'half'})});
  const response=await worker.fetch(request,env,{waitUntil(promise){promise.catch(error=>console.error(error.message))}});
  response.headers.forEach((value,key)=>res.setHeader(key,key==='set-cookie'?value.replace('__Host-tomato_chat=','tomato_preview=').replace('; Secure',''):value));res.statusCode=response.status;
  if(response.headers.get('content-type')?.startsWith('text/html')){const html=await response.text();res.end(html.replace('<body>','<body><div style="position:sticky;top:0;z-index:5;background:#ffe4a0;color:#3b3423;padding:12px;text-align:center;font:700 13px system-ui">LOCAL PREVIEW · real Mac mini bridge · password: test-only</div>'));return;}
  if(!response.body)return res.end();const reader=response.body.getReader();while(true){const {value,done}=await reader.read();if(done)break;res.write(value)}res.end();
 }catch(error){res.statusCode=500;res.end(error.message)}
});
server.listen(49183,'127.0.0.1',()=>console.log('Local chat bridge QA: http://127.0.0.1:49183'));
