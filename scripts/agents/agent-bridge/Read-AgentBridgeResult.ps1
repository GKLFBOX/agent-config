param(
    [Parameter(Mandatory = $true)]
    [string]$RequestDirectory
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

Import-Module (Join-Path $PSScriptRoot 'AgentBridge.psm1') -Force

Read-AgentBridgeResult `
    -RequestDirectory $RequestDirectory |
    ConvertTo-Json -Depth 10 -Compress
