[CmdletBinding()]
param()

# コピー方式ミラー（Vaultの生成コピーと、~/.local/bin の codex シム）を正本へ再同期する。
# symlink を使わないため管理者権限は不要。ルール・シム編集後にこれを実行する。
# 配置先はVault限定ではないため、管理外の実体は上書きせず退避する（install.ps1 と同じガード）。

$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Import-Module (Join-Path $RepoRoot 'scripts/lib/AgentConfig.psm1') -Force

$BackupRoot = Join-Path $RepoRoot ("backups/" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$Targets = Get-AgentConfigTargets -RepoRoot $RepoRoot
$copyTargets = @($Targets | Where-Object { $_.Method -in @('Copy','CopyFile') })
if ($copyTargets.Count -eq 0) { Write-Host "コピー方式ミラーのターゲットはありません。"; return }

foreach ($t in $copyTargets) {
    if (-not (Test-Path -LiteralPath $t.SourcePath)) { throw "Source path does not exist: $($t.SourcePath)" }
    if ($t.Method -eq 'CopyFile') {
        if (Test-AgentConfigCopyFile -SourcePath $t.SourcePath -DestinationPath $t.DestinationPath) {
            Write-Host "Already synced: $($t.DestinationPath)"
        } else {
            $bp = Backup-UnmanagedCopyTarget -Method CopyFile -DestinationPath $t.DestinationPath -BackupRoot $BackupRoot -TargetName $t.Name
            if ($bp) { Write-Host "Backed up: $($t.DestinationPath) -> $bp" }
            Sync-AgentConfigCopyFile -SourcePath $t.SourcePath -DestinationPath $t.DestinationPath
            Write-Host "Synced (file): $($t.DestinationPath) <- $($t.SourcePath)"
        }
        continue
    }
    if (Test-AgentConfigCopy -SourcePath $t.SourcePath -DestinationPath $t.DestinationPath) {
        Write-Host "Already synced: $($t.DestinationPath)"
    } else {
        $bp = Backup-UnmanagedCopyTarget -Method Copy -DestinationPath $t.DestinationPath -BackupRoot $BackupRoot -TargetName $t.Name
        if ($bp) { Write-Host "Backed up: $($t.DestinationPath) -> $bp" }
        Sync-AgentConfigCopy -SourcePath $t.SourcePath -DestinationPath $t.DestinationPath
        Write-Host "Synced: $($t.DestinationPath) <- $($t.SourcePath)"
    }
}
