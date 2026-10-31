$ErrorActionPreference = 'Stop'

function Write-NewFinalProofJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value)
    $parent = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Value | ConvertTo-Json -Depth 16) + "`n")
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
}

function Get-FinalProofContext {
    param([switch]$RequireCleanSource)
    $support = Split-Path $PSScriptRoot -Parent
    $repo = Join-Path $support 'gateway-voice-successor-20261031'
    $evidence = Join-Path $support 'PR1915-successor-evidence-2026-10-31'
    $freezePath = Join-Path $evidence 'final2-build-identity.json'
    $freeze = Get-Content -LiteralPath $freezePath -Raw | ConvertFrom-Json
    if ($freeze.head -notmatch '^[a-f0-9]{40}$' -or $freeze.tree -notmatch '^[a-f0-9]{40}$') { throw 'Invalid final build identity' }
    $required = @('OpenClaw.Tray.WinUI.exe','OpenClaw.Tray.WinUI.dll','OpenClaw.Shared.dll','OpenClaw.Connection.dll')
    if (@($freeze.files).Count -ne 4 -or @(Compare-Object $required @($freeze.files.name)).Count) { throw 'Final build must freeze exactly four product files' }
    $bin = Join-Path $repo 'src/OpenClaw.Tray.WinUI/bin/Debug/net10.0-windows10.0.22621.0/win-x64'
    foreach ($file in $freeze.files) {
        if ($file.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or (Get-FileHash -LiteralPath (Join-Path $bin $file.name)).Hash -ne $file.sha256) { throw 'Frozen product file changed' }
    }
    if ($RequireCleanSource) {
        $head = & git -C $repo rev-parse HEAD
        if ($LASTEXITCODE -ne 0) { throw 'Cannot read candidate HEAD' }
        $tree = & git -C $repo rev-parse 'HEAD^{tree}'
        if ($LASTEXITCODE -ne 0) { throw 'Cannot read candidate tree' }
        $dirty = @(& git -C $repo status --porcelain)
        if ($LASTEXITCODE -ne 0 -or $head -ne $freeze.head -or $tree -ne $freeze.tree -or $dirty.Count) { throw 'Candidate no longer matches the clean final freeze' }
    }
    $locator = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'private-location.json') -Raw | ConvertFrom-Json
    $privateRoot = [IO.Path]::GetFullPath($locator.PrivateRoot)
    $baseName = [IO.Path]::GetFileName($privateRoot)
    $normalTemp = Join-Path $env:USERPROFILE 'AppData/Local/Temp'
    if ($baseName -notmatch '^OpenClaw-PR1915-Successor-[a-f0-9]{32}$' -or $privateRoot -ne [IO.Path]::GetFullPath((Join-Path $normalTemp $baseName))) { throw 'Unexpected private fixture root' }
    $metadata = Get-Content -LiteralPath (Join-Path $privateRoot 'app-profile-private.json') -Raw | ConvertFrom-Json
    $profile = [IO.Path]::GetFullPath($metadata.profilePath)
    if ($profile -ne (Join-Path $privateRoot 'app-profile')) { throw 'Unexpected task app profile' }
    [pscustomobject]@{
        Support=$support; Repo=$repo; Evidence=$evidence; Output=(Join-Path $evidence 'native-final')
        Freeze=$freeze; FreezePath=$freezePath; Bin=$bin; App=(Join-Path $bin 'OpenClaw.Tray.WinUI.exe')
        PrivateRoot=$privateRoot; Profile=$profile; GatewayId=$metadata.gatewayRecordId
        LaunchRecord=(Join-Path $privateRoot 'app-launch-final-private.json')
        ObserverRecord=(Join-Path $privateRoot 'observer-final-process-private.json')
        PhaseFile=(Join-Path $privateRoot 'observer-final-phase.txt')
        StatusFile=(Join-Path $privateRoot 'observer-final-status.json')
        ReadyFile=(Join-Path $privateRoot 'observer-final-ready.json')
        StopFile=(Join-Path $privateRoot 'observer-final-stop.txt')
    }
}

function Get-OwnedFinalProofApp {
    param([Parameter(Mandatory)]$Context)
    $launch = Get-Content -LiteralPath $Context.LaunchRecord -Raw | ConvertFrom-Json
    if ($launch.AppPath -ne $Context.App -or $launch.Profile -ne $Context.Profile -or $launch.McpPort -ne 49237 -or $launch.GatewayPort -ne 19515 -or $launch.Head -ne $Context.Freeze.head) { throw 'Final app record does not match the frozen task' }
    $process = Get-Process -Id $launch.AppPid -ErrorAction Stop
    if ($process.Path -ne $Context.App -or $process.StartTime.ToUniversalTime().Ticks -ne ([DateTime]$launch.StartTime).ToUniversalTime().Ticks) { throw 'Final app process ownership changed' }
    [pscustomobject]@{ Process=$process; Launch=$launch }
}

function Get-OwnedFinalProofObserver {
    param([Parameter(Mandatory)]$Context)
    $record = Get-Content -LiteralPath $Context.ObserverRecord -Raw | ConvertFrom-Json
    $launch = Get-Content -LiteralPath $Context.LaunchRecord -Raw | ConvertFrom-Json
    $allowedDll = Join-Path $Context.Support 'PR1915-proof3-work-2026-10-30/audio-observer/bin/Release/net10.0-windows10.0.22621.0/win-x64/AudioObserver.dll'
    if ($record.Head -ne $Context.Freeze.head -or $record.TargetAppPid -ne $launch.AppPid -or $record.Dll -ne $allowedDll -or $record.Output -ne (Join-Path $Context.Output 'C/native-render-observer.json')) { throw 'Observer record does not match the final proof task' }
    $process = Get-Process -Id $record.Pid -ErrorAction Stop
    $command = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $record.Pid)
    if ($process.Path -ne $record.HostPath -or $process.StartTime.ToUniversalTime().Ticks -ne ([DateTime]$record.StartTime).ToUniversalTime().Ticks -or (Get-FileHash -LiteralPath $record.Dll).Hash -ne $record.DllSha256 -or -not $command.CommandLine.Contains($record.Dll) -or -not $command.CommandLine.Contains($Context.PhaseFile) -or -not $command.CommandLine.Contains($Context.StopFile)) { throw 'Final observer process ownership changed' }
    [pscustomobject]@{ Process=$process; Record=$record }
}
