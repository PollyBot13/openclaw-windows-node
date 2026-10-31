param([ValidatePattern('^openclaw://hub/[a-z-]+$')][string]$InitialUri='openclaw://hub/voice')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'FinalProof.Common.ps1')
$context = Get-FinalProofContext -RequireCleanSource
if (Test-Path -LiteralPath $context.LaunchRecord) { throw 'Final app launch already recorded; preserve the prior attempt' }
$identityPath = Join-Path $context.Output 'app-identity.json'
if (Test-Path -LiteralPath $identityPath) { throw 'Final app identity evidence already exists' }
$settings = Get-Content -LiteralPath (Join-Path $context.Profile 'settings.json') -Raw | ConvertFrom-Json
if ($settings.GatewayUrl -ne 'ws://127.0.0.1:19515' -or $settings.EnableNodeMode -ne $false -or $settings.NodeSttEnabled -ne $false -or $settings.VoiceTtsEnabled -ne $false -or $settings.EnableManagedLocalGatewayAutoRepair -ne $false -or $settings.AutoStart -ne $false -or $settings.GlobalHotkeyEnabled -ne $false -or $settings.EnableMcpServer -ne $true -or $settings.NodeTtsEnabled -ne $true -or $settings.UseGatewayVoice -ne $true) { throw 'Existing private profile is not direct, quiet and ready for explicit Gateway preview; no settings were changed' }
# Validate the paired record URL without changing or emitting credential-bearing data.
$registry = Get-Content -LiteralPath (Join-Path $context.Profile 'gateways.json') -Raw | ConvertFrom-Json
$records = if ($registry.PSObject.Properties['Gateways']) { @($registry.Gateways) } elseif ($registry -is [array]) { @($registry) } else { throw 'Unknown private Gateway registry shape' }
$record = @($records | Where-Object { $_.Id -eq $context.GatewayId })
if ($record.Count -ne 1 -or $record[0].Url -ne 'ws://127.0.0.1:19515' -or $registry.ActiveId -ne $context.GatewayId) { throw 'Active paired task Gateway is not the expected direct endpoint' }
if (Get-NetTCPConnection -LocalPort 49237 -State Listen -ErrorAction SilentlyContinue) { throw 'Task MCP port occupied; no app started' }
if (-not (Get-NetTCPConnection -LocalPort 19515 -State Listen -ErrorAction SilentlyContinue)) { throw 'Existing task Gateway is not listening' }
$env:OPENCLAW_TRAY_DATA_DIR = $context.Profile
$env:OPENCLAW_TRAY_APPDATA_DIR = Join-Path $context.PrivateRoot 'appdata'
$env:OPENCLAW_TRAY_LOCALAPPDATA_DIR = Join-Path $context.PrivateRoot 'localappdata'
$env:OPENCLAW_MCP_PORT = '49237'
$env:OPENCLAW_SKIP_UPDATE_CHECK = '1'
Remove-Item Env:OPENCLAW_MCP_TOKEN -ErrorAction SilentlyContinue
$process = Start-Process -FilePath $context.App -ArgumentList $InitialUri -PassThru
$launch = [pscustomobject]@{AppPid=$process.Id;AppPath=$context.App;Profile=$context.Profile;StartTime=$process.StartTime.ToUniversalTime().ToString('o');McpPort=49237;GatewayPort=19515;Head=$context.Freeze.head;Tree=$context.Freeze.tree;newProfileCreated=$false}
Write-NewFinalProofJson -Path $context.LaunchRecord -Value $launch
$identity = [pscustomobject]@{at=[DateTime]::UtcNow.ToString('o');head=$context.Freeze.head;tree=$context.Freeze.tree;pid=$process.Id;executable='REPO_ROOT/src/OpenClaw.Tray.WinUI/bin/Debug/net10.0-windows10.0.22621.0/win-x64/OpenClaw.Tray.WinUI.exe';sha256=($context.Freeze.files | Where-Object name -eq 'OpenClaw.Tray.WinUI.exe').sha256;binaries=$context.Freeze.files;buildInvocation=$context.Freeze.buildInvocation;gatewayTransport='direct task-private Gateway on 19515; no relay';taskProfile='existing task-private profile, fresh at fixture creation; reused for final proof';normalProfileUsed=$false;microphoneEnabled=$false;automaticSpeechEnabled=$false;nodeEnabled=$false;sourceBuildAssociation='manual freeze; loaded-module verification remains separate'}
Write-NewFinalProofJson -Path $identityPath -Value $identity
$identity | ConvertTo-Json -Depth 8
