param(
    [Parameter(Mandatory = $true)]
    [string]$RequestDirectory,

    [int]$TimeoutSeconds = 300,

    [int]$PollMilliseconds = 250
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

Import-Module (Join-Path $PSScriptRoot 'AgentBridge.psm1') -Force

Wait-AgentBridgeResult `
    -RequestDirectory $RequestDirectory `
    -TimeoutSeconds $TimeoutSeconds `
    -PollMilliseconds $PollMilliseconds |
    ConvertTo-Json -Depth 10 -Compress
