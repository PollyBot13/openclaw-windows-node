param([Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ObserverSha256)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'FinalProof.Common.ps1')
$context = Get-FinalProofContext -RequireCleanSource
$owned = Get-OwnedFinalProofApp -Context $context
$dll = Join-Path $context.Support 'PR1915-proof3-work-2026-10-30/audio-observer/bin/Release/net10.0-windows10.0.22621.0/win-x64/AudioObserver.dll'
if ((Get-FileHash -LiteralPath $dll).Hash -ne $ObserverSha256) { throw 'Reviewed observer binary hash differs' }
$output = Join-Path $context.Output 'C/native-render-observer.json'
foreach ($path in @($context.ObserverRecord,$context.PhaseFile,$context.ReadyFile,$context.StatusFile,$context.StopFile,$output)) { if (Test-Path -LiteralPath $path) { throw 'Final observer attempt already has state; preserve it' } }
$parent = Split-Path $output -Parent
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
[IO.File]::WriteAllText($context.PhaseFile, 'baseline')
$expected = ($context.Freeze.files | Where-Object name -eq 'OpenClaw.Tray.WinUI.exe').sha256
$hostPath = (Get-Command dotnet -ErrorAction Stop).Source
$psi = [Diagnostics.ProcessStartInfo]::new($hostPath)
$psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
foreach ($argument in @($dll,'--pid',[string]$owned.Process.Id,'--expected-exe',$context.App,'--expected-sha256',$expected,'--out',$output,'--duration-ms','300000','--interval-ms','50','--threshold','0.0001','--phase-file',$context.PhaseFile,'--status-file',$context.StatusFile,'--ready-file',$context.ReadyFile,'--stop-file',$context.StopFile)) { $psi.ArgumentList.Add($argument) }
$observer = [Diagnostics.Process]::Start($psi)
$record = [pscustomobject]@{Pid=$observer.Id;Dll=$dll;DllSha256=$ObserverSha256;HostPath=$hostPath;StartTime=$observer.StartTime.ToUniversalTime().ToString('o');TargetAppPid=$owned.Process.Id;Head=$context.Freeze.head;Output=$output}
Write-NewFinalProofJson -Path $context.ObserverRecord -Value $record
$deadline = [DateTime]::UtcNow.AddSeconds(15)
do {
    if (Test-Path -LiteralPath $context.ReadyFile) {
        $ready = Get-Content -LiteralPath $context.ReadyFile -Raw | ConvertFrom-Json
        if (-not $ready.Ready -or $ready.TargetPid -ne $owned.Process.Id) { throw 'Observer readiness is not bound to final app' }
        $ready | ConvertTo-Json
        return
    }
    if ($observer.HasExited) { throw 'Final observer exited before readiness; retain its report/state' }
    Start-Sleep -Milliseconds 50
} while ([DateTime]::UtcNow -lt $deadline)
throw 'Final observer readiness timeout; preserve the attempt'
