import http from 'node:http';
import fs from 'node:fs';
import crypto from 'node:crypto';
const config=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const events=[];let count=0;let holdNext=false;const pending=new Map();
const record=(event,extra={})=>{events.push({event,at:new Date().toISOString(),...extra});fs.writeFileSync(config.backendLedger,JSON.stringify({provider:'openai',count,pending:[...pending.keys()],events},null,2));};
function wav(){const rate=16000,seconds=4,n=rate*seconds,b=Buffer.alloc(44+n*2);b.write('RIFF',0);b.writeUInt32LE(b.length-8,4);b.write('WAVEfmt ',8);b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(rate,24);b.writeUInt32LE(rate*2,28);b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);b.write('data',36);b.writeUInt32LE(n*2,40);for(let i=0;i<n;i++){let fade=Math.min(1,i/800,(n-i)/800);b.writeInt16LE(Math.round(5000*fade*Math.sin(2*Math.PI*660*i/rate)),44+i*2);}return b;}
const audio=wav();const audioHash=crypto.createHash('sha256').update(audio).digest('hex');
const sendJson=(res,status,value)=>{res.writeHead(status,{'content-type':'application/json'});res.end(JSON.stringify(value));};
const server=http.createServer(async(req,res)=>{
  try{
    if(req.url?.startsWith('/control/')){
      if(req.headers['x-proof-control']!==config.controlToken)return sendJson(res,403,{error:'control denied'});
      if(req.method==='GET'&&req.url==='/control/status')return sendJson(res,200,{provider:'openai',count,pending:[...pending.keys()],audioSHA256:audioHash,events});
      if(req.method==='POST'&&req.url==='/control/hold-next'){holdNext=true;record('barrier_armed');return sendJson(res,200,{armed:true});}
      if(req.method==='POST'&&req.url==='/control/release'){const ids=[...pending.keys()];for(const id of ids){const reply=pending.get(id);pending.delete(id);record('barrier_released',{id});reply();}return sendJson(res,200,{released:ids});}
      return sendJson(res,404,{error:'unknown control'});
    }
    if(req.method!=='POST'||req.url!=='/v1/audio/speech')return sendJson(res,404,{error:'not found'});
    const chunks=[];let length=0;for await(const chunk of req){length+=chunk.length;if(length>10000)throw new Error('request too large');chunks.push(chunk);}
    const body=JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if(typeof body.input!=='string'||body.input.length>4096)throw new Error('invalid synthetic request');
    const id=++count;const held=holdNext;holdNext=false;
    record('synthesis_received',{id,held,textChars:body.input.length,textSHA256:crypto.createHash('sha256').update(body.input).digest('hex'),requestedFormat:body.response_format});
    let finished=false;res.on('close',()=>{if(!finished)record('backend_response_closed_before_finish',{id});});
    const reply=()=>{if(res.destroyed){record('release_found_closed_response',{id});return;}record('audio_response_released',{id,bytes:audio.length,audioSHA256:audioHash});res.writeHead(200,{'content-type':'audio/wav','content-length':audio.length});res.end(audio,()=>{finished=true;record('audio_response_finished',{id});});};
    if(held){pending.set(id,reply);record('barrier_waiting',{id});}else reply();
  }catch{if(!res.headersSent)sendJson(res,400,{error:'fixture request rejected'});else res.destroy();}
});
server.listen(config.backendPort,'127.0.0.1',()=>record('backend_ready',{audioSHA256:audioHash,audioBytes:audio.length}));
process.on('SIGTERM',()=>server.close(()=>process.exit(0)));
