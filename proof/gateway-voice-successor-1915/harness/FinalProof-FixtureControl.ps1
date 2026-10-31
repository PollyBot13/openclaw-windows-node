param([ValidateSet('status','hold-next','release','phase','export','stop-observer')][string]$Action='status',[string]$Phase)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'FinalProof.Common.ps1')
$context = Get-FinalProofContext
$out = Join-Path $context.Output 'C'
if (-not (Test-Path -LiteralPath $out)) { New-Item -ItemType Directory -Path $out | Out-Null }
if ($Action -in @('phase','stop-observer')) {
    $observer = Get-OwnedFinalProofObserver -Context $context
    if ($Action -eq 'stop-observer') {
        if (Test-Path -LiteralPath $context.StopFile) { throw 'Observer stop already requested' }
        [IO.File]::WriteAllText($context.StopFile, 'stop')
        if (-not $observer.Process.WaitForExit(15000)) { throw 'Observer did not acknowledge stop; do not force-stop or overwrite state' }
        if (-not (Test-Path -LiteralPath $observer.Record.Output)) { throw 'Observer exited without its report' }
        [pscustomobject]@{at=[DateTime]::UtcNow.ToString('o');action=$Action;pid=$observer.Process.Id;exitCode=$observer.Process.ExitCode;reportExists=$true} | ConvertTo-Json
        return
    }
    if ($Phase -notmatch '^[a-zA-Z0-9_-]{1,64}$') { throw 'Invalid observer phase' }
    $temporary = $context.PhaseFile + '.tmp'
    [IO.File]::WriteAllText($temporary, $Phase)
    [IO.File]::Move($temporary, $context.PhaseFile, $true)
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    do {
        if (Test-Path -LiteralPath $context.StatusFile) {
            # Permit the observer's atomic status replacement while this reader
            # is open. Get-Content can hold a handle without delete sharing.
            $stream = [IO.File]::Open($context.StatusFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
            $reader = [IO.StreamReader]::new($stream)
            try { $status = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
            if ($status.Phase -eq $Phase) { $status | ConvertTo-Json; return }
        }
        if ($observer.Process.HasExited) { throw 'Observer exited before acknowledging phase' }
        Start-Sleep -Milliseconds 50
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Observer phase acknowledgement timeout'
}
$config = Get-Content -LiteralPath (Join-Path $context.PrivateRoot 'fixture-private.json') -Raw | ConvertFrom-Json
if ($config.gatewayPort -ne 19515 -or $config.backendPort -ne 19817) { throw 'Unexpected fixture ports' }
$method = if ($Action -in @('status','export')) { 'Get' } else { 'Post' }
$route = if ($Action -eq 'export') { 'status' } else { $Action }
$response = Invoke-RestMethod -Uri ('http://127.0.0.1:' + $config.backendPort + '/control/' + $route) -Method $method -Headers @{'x-proof-control'=$config.controlToken}
$entry = [pscustomobject]@{at=[DateTime]::UtcNow.ToString('o');head=$context.Freeze.head;action=$Action;result=$response}
($entry | ConvertTo-Json -Depth 14 -Compress) | Add-Content -LiteralPath (Join-Path $out 'controller-events.jsonl')
if ($Action -eq 'export') {
    $index=1
    do { $exportPath=Join-Path $out ('backend-events-{0:D3}.json' -f $index); $index++ } while (Test-Path -LiteralPath $exportPath)
    Write-NewFinalProofJson -Path $exportPath -Value $response
}
$entry | ConvertTo-Json -Depth 14
