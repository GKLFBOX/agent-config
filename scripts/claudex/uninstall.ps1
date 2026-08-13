[CmdletBinding()]
param(
    [string]$ProfilePath = $PROFILE.CurrentUserCurrentHost,
    [string]$TaskName = 'AgentConfig-CLIProxyAPI'
)

$ErrorActionPreference = 'Stop'
$script:ClaudexTaskDescription = 'Managed by agent-config claudex'
$script:ClaudexProfileBegin = '# BEGIN agent-config claudex'
$script:ClaudexProfileEnd = '# END agent-config claudex'

function Backup-ClaudexProfile {
    param([Parameter(Mandatory)][string]$Path)

    $suffix = "$(Get-Date -Format 'yyyyMMdd-HHmmss-fff').$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $backup = "$Path.claudex-backup.$suffix"
    Copy-Item -LiteralPath $Path -Destination $backup
    return $backup
}

function Remove-ClaudexProfileBlock {
    param([Parameter(Mandatory)][string]$ProfilePath)

    if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) { return $false }
    $content = Get-Content -Raw -LiteralPath $ProfilePath
    $begin = [regex]::Escape($script:ClaudexProfileBegin)
    $end = [regex]::Escape($script:ClaudexProfileEnd)
    $beginCount = [regex]::Matches($content, $begin).Count
    $endCount = [regex]::Matches($content, $end).Count

    if ($beginCount -eq 0 -and $endCount -eq 0) { return $false }
    if ($beginCount -ne 1 -or $endCount -ne 1) {
        throw "PowerShell profile marker conflict: $ProfilePath"
    }

    $pattern = "(?ms)^$begin\r?\n.*?^$end(?:\r?\n|$)"
    $matcher = [regex]::new($pattern)
    if (-not $matcher.IsMatch($content)) {
        throw "PowerShell profile marker conflict: $ProfilePath"
    }

    $updated = $matcher.Replace($content, '', 1)
    Backup-ClaudexProfile -Path $ProfilePath | Out-Null
    [System.IO.File]::WriteAllText($ProfilePath, $updated, [System.Text.UTF8Encoding]::new($false))
    return $true
}

function Unregister-ClaudexTask {
    param(
        [Parameter(Mandatory)][string]$TaskName,
        [scriptblock]$TaskGetter = { param($Name) Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue },
        [scriptblock]$TaskRemover = { param($Name) Unregister-ScheduledTask -TaskName $Name -Confirm:$false }
    )

    $task = & $TaskGetter $TaskName
    if ($null -eq $task) { return $false }
    if ($task.Description -ne $script:ClaudexTaskDescription) {
        throw "Scheduled task [$TaskName] is owned by another configuration."
    }
    & $TaskRemover $TaskName
    return $true
}

function Uninstall-Claudex {
    param(
        [Parameter(Mandatory)][string]$ProfilePath,
        [Parameter(Mandatory)][string]$TaskName
    )

    Remove-ClaudexProfileBlock -ProfilePath $ProfilePath | Out-Null
    Unregister-ClaudexTask -TaskName $TaskName | Out-Null
    Write-Host 'Claudex profile block and scheduled task were removed.'
    Write-Host 'CLIProxyAPI files, OAuth data, and the encrypted secret file were preserved.'
}

if ($MyInvocation.InvocationName -ne '.') {
    Uninstall-Claudex -ProfilePath $ProfilePath -TaskName $TaskName
}
