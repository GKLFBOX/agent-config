<#
.SYNOPSIS
Archives one external-memory file outside the Vault.

.DESCRIPTION
Moves a single file to the external-memory archive. Directory archives are not supported.
Remove Vault links to the file before running this script; pass -LinksRemoved to record that check.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Inbox', 'Daily', 'Knowledge', 'Decisions', 'Handoffs', 'Projects', 'System')]
    [string]$Category,

    [string]$ArchiveRoot = $env:EXTERNAL_MEMORY_ARCHIVE_ROOT,

    [string]$ArchiveDirectory,

    [switch]$KeepOriginalName,

    [switch]$LinksRemoved
)

$ErrorActionPreference = 'Stop'

$SourcePath = [System.IO.Path]::GetFullPath($Path)
if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    throw "Archive source file does not exist: $SourcePath"
}

if ([string]::IsNullOrWhiteSpace($ArchiveDirectory)) {
    if ([string]::IsNullOrWhiteSpace($ArchiveRoot)) {
        $ArchiveRoot = '<archive-root>'
    }

    $ArchiveDirectory = Join-Path $ArchiveRoot $Category
}

$ArchiveDirectory = [System.IO.Path]::GetFullPath($ArchiveDirectory)

$OriginalName = (Split-Path -Leaf $SourcePath) -replace '[\\/:*?"<>|]+', '-'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$Sequence = 0

if ($KeepOriginalName) {
    $ArchivePath = Join-Path $ArchiveDirectory $OriginalName
    while (Test-Path -LiteralPath $ArchivePath) {
        $ArchivePath = Join-Path $ArchiveDirectory ("{0}-{1:D3}_{2}" -f $Timestamp, $Sequence, $OriginalName)
        $Sequence++
    }
}
else {
    do {
        $ArchivePath = Join-Path $ArchiveDirectory ("{0}-{1:D3}_{2}" -f $Timestamp, $Sequence, $OriginalName)
        $Sequence++
    } while (Test-Path -LiteralPath $ArchivePath)
}

if (-not $LinksRemoved) {
    Write-Warning 'Archive source may still have Vault links. Remove Vault links before archiving, or pass -LinksRemoved after checking.'
}

if ($PSCmdlet.ShouldProcess($SourcePath, "Archive to $ArchivePath")) {
    New-Item -ItemType Directory -Force -Path $ArchiveDirectory | Out-Null
    Move-Item -LiteralPath $SourcePath -Destination $ArchivePath

    [ordered]@{
        sourcePath = $SourcePath
        archivePath = [System.IO.Path]::GetFullPath($ArchivePath)
        category = $Category
    } | ConvertTo-Json -Compress
}
