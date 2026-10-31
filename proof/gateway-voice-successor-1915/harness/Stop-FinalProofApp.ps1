param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'FinalProof.Common.ps1')
$context = Get-FinalProofContext
$output = Join-Path $context.Output 'app-stop.json'
if (Test-Path -LiteralPath $output) { throw 'Final app stop already recorded; preserve it' }
$launch = Get-Content -LiteralPath $context.LaunchRecord -Raw | ConvertFrom-Json
$process = Get-Process -Id $launch.AppPid -ErrorAction SilentlyContinue
if (-not $process) {
    Write-NewFinalProofJson -Path $output -Value ([pscustomobject]@{at=[DateTime]::UtcNow.ToString('o');pid=$launch.AppPid;alreadyExited=$true;gatewayOrBackendStopped=$false})
    return
}
$owned = Get-OwnedFinalProofApp -Context $context
# Stop the verified Process object, never an unverified reused numeric PID.
$owned.Process.Kill()
if (-not $owned.Process.WaitForExit(5000)) { throw 'Owned final app did not exit within five seconds' }
$result = [pscustomobject]@{at=[DateTime]::UtcNow.ToString('o');pid=$owned.Process.Id;head=$context.Freeze.head;pathAndStartTimeVerified=$true;productHashesVerified=$true;stopped=$true;gatewayOrBackendStopped=$false;profileRetained=$true}
Write-NewFinalProofJson -Path $output -Value $result
$result | ConvertTo-Json
