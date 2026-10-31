param([ValidateSet('tools/list','tools/call')][string]$Method='tools/call',[string]$Name,[string]$Arguments='{}')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'FinalProof.Common.ps1')
$context = Get-FinalProofContext -RequireCleanSource
$owned = Get-OwnedFinalProofApp -Context $context
if ($Method -eq 'tools/call' -and [string]::IsNullOrWhiteSpace($Name)) { throw 'A tool name is required' }
if (-not (Get-NetTCPConnection -LocalPort $owned.Launch.McpPort -State Listen -ErrorAction SilentlyContinue)) { throw 'Recorded task MCP port is not listening' }
# HTTP.sys can own the listening socket as System. Bind via the exact live app
# record and its private profile token, rather than claiming netstat proves its PID.
$tokenPath = Join-Path $owned.Launch.Profile 'mcp-token.txt'
$token = (Get-Content -LiteralPath $tokenPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($token)) { throw 'Recorded profile has no MCP token' }
$body = @{jsonrpc='2.0';id=1;method=$Method}
if ($Method -eq 'tools/call') { $body.params = @{name=$Name;arguments=($Arguments | ConvertFrom-Json)} }
$reply = Invoke-RestMethod -Uri ('http://127.0.0.1:' + $owned.Launch.McpPort + '/') -Method Post -Headers @{Authorization=('Bearer ' + $token)} -ContentType application/json -Body ($body | ConvertTo-Json -Depth 14)
$null = Get-OwnedFinalProofApp -Context $context
$reply | ConvertTo-Json -Depth 16
