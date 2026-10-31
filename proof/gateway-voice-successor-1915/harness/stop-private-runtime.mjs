import fs from 'node:fs';
import path from 'node:path';
const root=process.argv[2];
if(!/^\/tmp\/openclaw-pr1915-successor-[a-f0-9]{32}$/.test(root))throw Error('Unexpected task root');
const nodeReal=fs.realpathSync('/home/openclaw/.openclaw/tools/node/bin/node');
const results=[];
for(const mode of ['gateway','backend']){
 const pid=Number(fs.readFileSync(path.join(root,mode+'.pid'),'utf8').trim());
 if(!Number.isInteger(pid)||pid<2)throw Error('Invalid task PID');
 const proc='/proc/'+pid;
 if(!fs.existsSync(proc)){results.push({mode,pid,alreadyExited:true});continue;}
 const executable=fs.readlinkSync(proc+'/exe');
 const argv=fs.readFileSync(proc+'/cmdline','utf8').split('\0');
 const env=fs.readFileSync(proc+'/environ','utf8').split('\0');
 const stat=fs.readFileSync(proc+'/stat','utf8');
 const startTime=stat.slice(stat.lastIndexOf(')')+2).split(' ')[19];
 const owned=executable===nodeReal && (mode==='gateway'
  ? env.includes('OPENCLAW_STATE_DIR='+root+'/state')&&env.includes('OPENCLAW_CONFIG_PATH='+root+'/state/openclaw.json')&&((argv.includes('gateway')&&argv.includes('19515'))||argv[0]==='openclaw-gateway')
  : argv.includes(root+'/helpers/synthesis-backend.mjs')&&argv.includes(root+'/backend-private.json'));
 if(!owned)throw Error('Task ownership not established');
 const checkedAgain=fs.readFileSync(proc+'/stat','utf8');
 if(checkedAgain.slice(checkedAgain.lastIndexOf(')')+2).split(' ')[19]!==startTime)throw Error('PID changed during verification');
 process.kill(pid,'SIGTERM');
 results.push({mode,pid,executableVerified:true,privateOwnershipVerified:true,startTimeRechecked:true,signal:'SIGTERM'});
}
console.log(JSON.stringify({at:new Date().toISOString(),results,privateStateRetained:true,sharedServicesTouched:false}));
