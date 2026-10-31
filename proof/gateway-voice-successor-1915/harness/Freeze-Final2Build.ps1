param(
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$FinalHead,
    [string]$BuildInvocation
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'FinalProof.Common.ps1')
$support = Split-Path $PSScriptRoot -Parent
$repo = Join-Path $support 'gateway-voice-successor-20261031'
$evidence = Join-Path $support 'PR1915-successor-evidence-2026-10-31'
if (-not $BuildInvocation) { $BuildInvocation = Join-Path $evidence 'final2-full-build/invocation.json' }
$BuildInvocation = [IO.Path]::GetFullPath($BuildInvocation)
$expectedInvocation = [IO.Path]::GetFullPath((Join-Path $evidence 'final2-full-build/invocation.json'))
if ($BuildInvocation -ne $expectedInvocation) { throw 'Select the final2-full-build invocation for this task' }
$freezePath = Join-Path $evidence 'final2-build-identity.json'
if (Test-Path -LiteralPath $freezePath) { throw 'Final2 identity already exists; preserve it and review before another attempt' }
$head = & git -C $repo rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot read candidate HEAD' }
$dirty = @(& git -C $repo status --porcelain)
if ($LASTEXITCODE -ne 0 -or $head -ne $FinalHead -or $dirty.Count) { throw 'Expected clean final candidate required' }
$tree = & git -C $repo rev-parse 'HEAD^{tree}'
if ($LASTEXITCODE -ne 0) { throw 'Cannot read candidate tree' }
$build = Get-Content -LiteralPath $BuildInvocation -Raw | ConvertFrom-Json
if ($null -eq $build.PSObject.Properties['exitCode'] -or $build.exitCode -ne 0 -or $build.head -ne $FinalHead -or @($build.dirty).Count) { throw 'Successful clean final2 build invocation required' }
if (@($build.arguments) -notcontains './build.ps1' -or @($build.arguments) -contains '-Project') { throw 'Invocation must be a full repository build' }
if (-not $build.startedUtc -or -not $build.finishedUtc -or [DateTime]$build.finishedUtc -lt [DateTime]$build.startedUtc) { throw 'Invalid build invocation times' }
if (-not @($build.sources).Count) { throw 'Build invocation has no recorded source hashes' }
foreach ($source in $build.sources) {
    $path = [IO.Path]::GetFullPath((Join-Path $repo $source.path))
    if (-not $path.StartsWith($repo + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash -LiteralPath $path).Hash -ne $source.sha256) { throw 'Build source no longer matches the candidate' }
}
$bin = Join-Path $repo 'src/OpenClaw.Tray.WinUI/bin/Debug/net10.0-windows10.0.22621.0/win-x64'
$files = @('OpenClaw.Tray.WinUI.exe','OpenClaw.Tray.WinUI.dll','OpenClaw.Shared.dll','OpenClaw.Connection.dll') | ForEach-Object {
    $path = Join-Path $bin $_
    if ((Get-Item -LiteralPath $path).LastWriteTimeUtc -gt ([DateTime]$build.finishedUtc).ToUniversalTime().AddSeconds(2)) { throw 'Product file changed after the recorded build' }
    [pscustomobject]@{name=$_;sha256=(Get-FileHash -LiteralPath $path).Hash}
}
$identity = [pscustomobject]@{head=$head;tree=$tree;configuration='Debug';rid='win-x64';buildInvocation='final2-full-build/invocation.json';buildInvocationSha256=(Get-FileHash -LiteralPath $BuildInvocation).Hash;files=@($files);association='manually recorded source/build/files; not signed attestation'}
Write-NewFinalProofJson -Path $freezePath -Value $identity
$identity | ConvertTo-Json -Depth 8
