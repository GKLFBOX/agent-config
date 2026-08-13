[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Import-Module (Join-Path $RepoRoot 'scripts/lib/AgentConfig.psm1') -Force

$Targets = Get-AgentConfigTargets -RepoRoot $RepoRoot
$Targets | ForEach-Object {
    $exists = Test-Path -LiteralPath $_.DestinationPath
    if ($_.Method -eq 'Copy') {
        $managed = if ($exists) { Test-AgentConfigCopy -SourcePath $_.SourcePath -DestinationPath $_.DestinationPath } else { $false }
        $linkTarget = '(copy)'
    } elseif ($_.Method -eq 'CopyFile') {
        $managed = if ($exists) { Test-AgentConfigCopyFile -SourcePath $_.SourcePath -DestinationPath $_.DestinationPath } else { $false }
        $linkTarget = '(copy-file)'
    } else {
        $managed = if ($exists) { Test-AgentConfigLink -Path $_.DestinationPath -ExpectedTarget $_.SourcePath -ExpectedLinkType $_.LinkType } else { $false }
        $linkTarget = if ($exists) { Get-LinkTarget -Path $_.DestinationPath } else { $null }
    }
    [pscustomobject]@{
        Name        = $_.Name
        Method      = $_.Method
        Destination = $_.DestinationPath
        Exists      = $exists
        LinkTarget  = $linkTarget
        Managed     = $managed
    }
} | Format-Table -AutoSize
