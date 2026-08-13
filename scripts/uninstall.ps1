[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Import-Module (Join-Path $RepoRoot 'scripts/lib/AgentConfig.psm1') -Force

$Targets = Get-AgentConfigTargets -RepoRoot $RepoRoot

$failures = @()

foreach ($t in $Targets) {
    try {
        if (-not (Test-Path -LiteralPath $t.DestinationPath)) { Write-Host "Missing: $($t.DestinationPath)"; continue }
        if ($t.Method -eq 'Copy') {
            Remove-AgentConfigCopy -DestinationPath $t.DestinationPath
            Write-Host "Removed copy: $($t.DestinationPath)"
        } elseif ($t.Method -eq 'CopyFile') {
            Remove-AgentConfigCopyFile -DestinationPath $t.DestinationPath
            Write-Host "Removed copy-file: $($t.DestinationPath)"
        } else {
            Remove-AgentConfigLink -Path $t.DestinationPath -ExpectedTarget $t.SourcePath
            Write-Host "Removed link: $($t.DestinationPath)"
        }
    } catch {
        $failures += [pscustomobject]@{ Target = $t.Name; Error = $_.Exception.Message }
    }
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed to remove $($failures.Count) target(s):" -ForegroundColor Red
    foreach ($f in $failures) {
        Write-Host "  - $($f.Target): $($f.Error)" -ForegroundColor Red
    }
    exit 1
}

Write-Host "注: 退避済み実体は backups/<timestamp>/ にあります。必要に応じ手動で復元してください。"
