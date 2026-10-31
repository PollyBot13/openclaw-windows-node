param([switch]$GatewayOnly)
$ErrorActionPreference='Stop'
$location=Get-Content (Join-Path $PSScriptRoot 'private-location.json') -Raw|ConvertFrom-Json
$private=Get-Content (Join-Path $location.PrivateRoot 'fixture-private.json') -Raw|ConvertFrom-Json
# This distribution intentionally has no mounted Windows drive. Transfer only
# reviewed helper bytes and this fixture's synthetic private input over stdin.
$helper=$private.linuxRoot+'/helpers'
$privatePath=$private.linuxRoot+'/fixture-private.json'
$files=@{}
foreach($name in 'prepare-gateway.mjs','synthesis-backend.mjs','run-private-runtime.sh'){$files[$name]=[IO.File]::ReadAllText((Join-Path $PSScriptRoot $name)).Replace("`r`n","`n")}
$upload=@{root=$private.linuxRoot;files=$files;input=$private}|ConvertTo-Json -Depth 12 -Compress
$encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($upload))
$program="const fs=require('node:fs');const path=require('node:path');const d=JSON.parse(Buffer.from('$encoded','base64').toString('utf8'));if(!d.root.startsWith('/tmp/openclaw-pr1915-successor-'))throw Error('bad fixture root');fs.mkdirSync(d.root,{recursive:true,mode:448});fs.mkdirSync(path.join(d.root,'helpers'),{recursive:true,mode:448});for(const [n,t] of Object.entries(d.files)){if(n.includes('/')||n.includes('..'))throw Error('bad helper name');fs.writeFileSync(path.join(d.root,'helpers',n),t,{mode:384});}fs.writeFileSync(path.join(d.root,'fixture-private.json'),JSON.stringify(d.input),{mode:384});console.log('Task fixture input transferred privately.');"
$psi=[Diagnostics.ProcessStartInfo]::new('C:/Windows/System32/wsl.exe')
foreach($argument in @('-d','OpenClawGateway','--','/home/openclaw/.openclaw/tools/node/bin/node','-')){$psi.ArgumentList.Add($argument)}
$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
$transfer=[Diagnostics.Process]::Start($psi);$transfer.StandardInput.Write($program);$transfer.StandardInput.Close();$transferOutput=$transfer.StandardOutput.ReadToEnd();$transferError=$transfer.StandardError.ReadToEnd();$transfer.WaitForExit()
if($transfer.ExitCode -ne 0){throw 'Task fixture stdin transfer failed.'}
& wsl -d OpenClawGateway -- /home/openclaw/.openclaw/tools/node/bin/node ($helper+'/prepare-gateway.mjs') $privatePath
if($LASTEXITCODE -ne 0){throw 'Disposable configuration preparation failed.'}
$records=@()
$recordPath=Join-Path $location.PrivateRoot 'runtime-processes.json'
if($GatewayOnly -and (Test-Path -LiteralPath $recordPath)){$records=@(Get-Content $recordPath -Raw|ConvertFrom-Json|Where-Object{$_.Mode -ne 'gateway'})}
$modes=if($GatewayOnly){@('gateway')}else{@('backend','gateway')}
foreach($mode in $modes){
    $process=Start-Process -FilePath 'C:/Windows/System32/wsl.exe' -ArgumentList @('-d','OpenClawGateway','--','/bin/sh',($helper+'/run-private-runtime.sh'),$private.linuxRoot,$mode,$helper) -WindowStyle Hidden -RedirectStandardOutput (Join-Path $location.PrivateRoot ($mode+'-stdout.log')) -RedirectStandardError (Join-Path $location.PrivateRoot ($mode+'-stderr.log')) -PassThru
    $records += [pscustomobject]@{Mode=$mode;WindowsWslPid=$process.Id}
}
$records|ConvertTo-Json|Set-Content $recordPath
'Task-owned backend and real Gateway foreground processes started; no service registration performed.'
