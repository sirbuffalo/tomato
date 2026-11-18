import {request} from 'node:http';
const local=process.argv.includes('--local'),command=process.argv.find(arg=>['status','pending','configure','reply','transcripts','transcript'].includes(arg));
if(!command)throw Error('Use status, pending, configure, reply, transcripts [after], or transcript <conversation-id>');
const socketPath=`/tmp/tomato-chat-bridge${local?'-test':''}-${process.getuid()}.sock`;
let body,path='/'+command;
if(command==='transcripts'){
 const after=Number(process.argv[process.argv.indexOf(command)+1]||0);if(!Number.isSafeInteger(after)||after<0)throw Error('Invalid cursor');path+='?after='+after;
}
if(command==='transcript'){
 const id=process.argv[process.argv.indexOf(command)+1];if(!id||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(id))throw Error('Invalid conversation ID');path+='?id='+id;
}
if(command==='configure'||command==='reply'){
 if(process.stdin.isTTY){process.stdin.setRawMode(true);process.stdout.write('Ready for private JSON on stdin (input is hidden).\n');}
 body=await new Promise((resolve,reject)=>{let text='';process.stdin.setEncoding('utf8');process.stdin.on('data',chunk=>{text+=chunk;if(text.length>125000)reject(Error('Input too large'));if(text.includes('\n')){process.stdin.pause();resolve(text.slice(0,text.indexOf('\n')));}});process.stdin.on('end',()=>resolve(text));process.stdin.on('error',reject);});
 JSON.parse(body);
}
const result=await new Promise((resolve,reject)=>{const req=request({socketPath,path,method:body===undefined?'GET':'POST',headers:body===undefined?{}:{'content-type':'application/json'}},res=>{let output='';res.setEncoding('utf8');res.on('data',chunk=>output+=chunk);res.on('end',()=>res.statusCode===200?resolve(output):reject(Error(output)));});req.on('error',reject);req.end(body);});
console.log(result);process.exit(0);
