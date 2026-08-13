[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Import-Module (Join-Path $RepoRoot 'scripts/lib/AgentConfig.psm1') -Force

# 管理者権限チェック（symlink 作成に必要）
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Error "管理者権限が必要です。管理者 PowerShell で再実行してください（symlink 作成のため）。"
    exit 1
}

$BackupRoot = Join-Path $RepoRoot ("backups/" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$Targets = Get-AgentConfigTargets -RepoRoot $RepoRoot

$created = 0; $skipped = 0; $backed = 0
foreach ($t in $Targets) {
    if (-not (Test-Path -LiteralPath $t.SourcePath)) { throw "Source path does not exist: $($t.SourcePath)" }

    if ($t.Method -eq 'Copy') {
        if (Test-AgentConfigCopy -SourcePath $t.SourcePath -DestinationPath $t.DestinationPath) {
            Write-Host "Already synced: $($t.DestinationPath)"; $skipped++; continue
        }
        $bp = Backup-UnmanagedCopyTarget -Method Copy -DestinationPath $t.DestinationPath -BackupRoot $BackupRoot -TargetName $t.Name
        if ($bp) { Write-Host "Backed up: $($t.DestinationPath) -> $bp"; $backed++ }
        Sync-AgentConfigCopy -SourcePath $t.SourcePath -DestinationPath $t.DestinationPath
        Write-Host "Synced (copy): $($t.DestinationPath) <- $($t.SourcePath)"; $created++
        continue
    }

    if ($t.Method -eq 'CopyFile') {
        if (Test-AgentConfigCopyFile -SourcePath $t.SourcePath -DestinationPath $t.DestinationPath) {
            Write-Host "Already synced: $($t.DestinationPath)"; $skipped++; continue
        }
        $bp = Backup-UnmanagedCopyTarget -Method CopyFile -DestinationPath $t.DestinationPath -BackupRoot $BackupRoot -TargetName $t.Name
        if ($bp) { Write-Host "Backed up: $($t.DestinationPath) -> $bp"; $backed++ }
        Sync-AgentConfigCopyFile -SourcePath $t.SourcePath -DestinationPath $t.DestinationPath
        Write-Host "Synced (file): $($t.DestinationPath) <- $($t.SourcePath)"; $created++
        continue
    }

    if (Test-Path -LiteralPath $t.DestinationPath) {
        if (Test-AgentConfigLink -Path $t.DestinationPath -ExpectedTarget $t.SourcePath -ExpectedLinkType $t.LinkType) {
            Write-Host "Already linked: $($t.DestinationPath)"; $skipped++; continue
        }
        $existing = Get-LinkTarget -Path $t.DestinationPath
        if ($null -ne $existing) {
            throw "Refusing to replace different link: $($t.DestinationPath) -> $existing"
        }
        $bp = Backup-ExistingItem -Path $t.DestinationPath -BackupRoot $BackupRoot -TargetName $t.Name
        Write-Host "Backed up: $($t.DestinationPath) -> $bp"; $backed++
    }

    New-AgentConfigLink -SourcePath $t.SourcePath -DestinationPath $t.DestinationPath -LinkType $t.LinkType
    Write-Host "Linked: $($t.DestinationPath) -> $($t.SourcePath)"; $created++
}
Write-Host ""
Write-Host "Summary: created=$created skipped=$skipped backed-up=$backed"
