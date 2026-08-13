[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [string]$ArchiveRoot = $env:EXTERNAL_MEMORY_HANDOFF_ARCHIVE_ROOT,

    [switch]$LinksRemoved
)

$ErrorActionPreference = 'Stop'

$SourcePath = [System.IO.Path]::GetFullPath($Path)
if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    throw "Handoff file does not exist: $SourcePath"
}

if ([string]::IsNullOrWhiteSpace($ArchiveRoot)) {
    $ArchiveRoot = '<archive-root>\Handoffs'
}

$ArchiveScript = Join-Path $PSScriptRoot 'archive-external-memory.ps1'
& $ArchiveScript -Path $SourcePath -Category Handoffs -ArchiveDirectory $ArchiveRoot -LinksRemoved:$LinksRemoved -WhatIf:$WhatIfPreference
