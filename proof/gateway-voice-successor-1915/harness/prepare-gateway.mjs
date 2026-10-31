import fs from 'node:fs';
import path from 'node:path';
const input=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const root=input.linuxRoot;
for(const dir of [root,path.join(root,'home'),path.join(root,'state'),path.join(root,'tmp'),path.join(root,'workspace')])fs.mkdirSync(dir,{recursive:true,mode:0o700});
const config={gateway:{mode:'local',bind:'loopback',port:input.gatewayPort,auth:{mode:'token',token:input.gatewayToken}},agents:{defaults:{workspace:path.join(root,'workspace')}},logging:{level:'info',file:path.join(root,'gateway.log')},browser:{enabled:false},plugins:{entries:{canvas:{config:{host:{enabled:false}}}}},tts:{auto:'off',provider:'openai',providers:{openai:{apiKey:'local',baseUrl:`http://127.0.0.1:${input.backendPort}/v1`,model:'tts-1',speakerVoice:'alloy',responseFormat:'wav'},microsoft:{enabled:false}}}};
fs.writeFileSync(path.join(root,'state','openclaw.json'),JSON.stringify(config,null,2),{mode:0o600});
fs.writeFileSync(path.join(root,'backend-private.json'),JSON.stringify({backendPort:input.backendPort,controlToken:input.controlToken,backendLedger:path.join(root,'backend-ledger.json')}),{mode:0o600});
console.log('Disposable Gateway configuration prepared; credentials omitted.');
