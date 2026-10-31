# Reproduction initializer. This file was syntax-checked, not used to replace
# the already-running recorded fixture. It never reuses or overwrites state.
$ErrorActionPreference='Stop'
$locator=Join-Path $PSScriptRoot 'private-location.json'
if(Test-Path $locator){throw 'A fixture locator already exists. Inventory/reuse it rather than replacing it.'}
foreach($port in 19515,19516,19817,49237){if(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue){throw ('Required task port occupied: '+$port)}}
$privateRoot=Join-Path $env:TEMP ('OpenClaw-PR1915-Successor-'+[Guid]::NewGuid().ToString('N'))
$linuxRoot='/tmp/openclaw-pr1915-successor-'+[Guid]::NewGuid().ToString('N')
New-Item -ItemType Directory -Path $privateRoot -ErrorAction Stop|Out-Null
$inputData=@{windowsRoot=$privateRoot;linuxRoot=$linuxRoot;gatewayPort=19515;backendPort=19817;mcpPort=49237;gatewayToken=[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32));controlToken=[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))}
$inputData|ConvertTo-Json|Set-Content (Join-Path $privateRoot 'fixture-private.json')
@{PrivateRoot=$privateRoot}|ConvertTo-Json|Set-Content $locator
'Fresh private fixture inputs created. Review installed runtime paths before Start-PrivateGateway.ps1. No services started.'
