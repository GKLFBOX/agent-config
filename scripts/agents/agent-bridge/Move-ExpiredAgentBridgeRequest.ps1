param(
    [Parameter(Mandatory = $true)]
    [string]$Repository,

    [int]$AgeDays = 7
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

Import-Module (Join-Path $PSScriptRoot 'AgentBridge.psm1') -Force

Move-ExpiredAgentBridgeRequest `
    -Repository $Repository `
    -AgeDays $AgeDays |
    ConvertTo-Json -Depth 10 -Compress
