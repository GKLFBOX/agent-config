[CmdletBinding()]
param(
    [string]$ProxyExecutable = '<tools-dir>\CLIProxyAPI_7.2.92_windows_amd64\cli-proxy-api.exe',
    [string]$ProxyConfig = '<tools-dir>\CLIProxyAPI_7.2.92_windows_amd64\config.yaml',
    [string]$ProfilePath = $PROFILE.CurrentUserCurrentHost,
    [string]$SecretPath = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'agent-config\claudex\secrets.psd1'),
    [SecureString]$ProxyApiKey,
    [switch]$ReplaceSecret
)

$ErrorActionPreference = 'Stop'
$script:ClaudexTaskName = 'AgentConfig-CLIProxyAPI'
$script:ClaudexTaskDescription = 'Managed by agent-config claudex'
$script:ClaudexProfileBegin = '# BEGIN agent-config claudex'
$script:ClaudexProfileEnd = '# END agent-config claudex'

function Write-ClaudexUtf8File {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Backup-ClaudexFile {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $suffix = "$(Get-Date -Format 'yyyyMMdd-HHmmss-fff').$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $backup = "$Path.claudex-backup.$suffix"
    Copy-Item -LiteralPath $Path -Destination $backup
    return $backup
}

function Set-ClaudexSecretFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][SecureString]$ProxyApiKey,
        [switch]$Replace,
        [scriptblock]$AclSetter = {
            param($Directory)
            $account = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            & icacls.exe $Directory '/inheritance:r' '/grant:r' "${account}:(OI)(CI)F" 'SYSTEM:(OI)(CI)F' | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Failed to restrict secret directory ACL: $Directory" }
        }
    )

    if ((Test-Path -LiteralPath $Path -PathType Leaf) -and -not $Replace) { return $false }
    if ([System.Net.NetworkCredential]::new('', $ProxyApiKey).Password.Length -eq 0) {
        throw 'CLIProxyAPI local API key must not be empty.'
    }

    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    & $AclSetter $directory
    if (Test-Path -LiteralPath $Path -PathType Leaf) { Backup-ClaudexFile -Path $Path | Out-Null }

    $encrypted = ConvertFrom-SecureString -SecureString $ProxyApiKey
    Write-ClaudexUtf8File -Path $Path -Content "@{`n    ProxyApiKey = '$encrypted'`n}`n"
    return $true
}

function Set-ClaudexProfileBlock {
    param(
        [Parameter(Mandatory)][string]$ProfilePath,
        [Parameter(Mandatory)][string]$ClaudexScript
    )

    $existing = if (Test-Path -LiteralPath $ProfilePath -PathType Leaf) {
        Get-Content -Raw -LiteralPath $ProfilePath
    }
    else { '' }

    $normalizedExisting = $existing.Replace("`r`n", "`n")
    $escapedScript = $ClaudexScript.Replace("'", "''")
    $normalizedBlock = "$($script:ClaudexProfileBegin)`n. '$escapedScript'`n$($script:ClaudexProfileEnd)"
    $beginCount = [regex]::Matches($normalizedExisting, [regex]::Escape($script:ClaudexProfileBegin)).Count
    $endCount = [regex]::Matches($normalizedExisting, [regex]::Escape($script:ClaudexProfileEnd)).Count

    if ($beginCount -eq 1 -and $endCount -eq 1 -and $normalizedExisting.Contains($normalizedBlock)) {
        return $false
    }
    if ($beginCount -ne 0 -or $endCount -ne 0) {
        throw "PowerShell profile marker conflict: $ProfilePath"
    }

    $directory = Split-Path -Parent $ProfilePath
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    if (Test-Path -LiteralPath $ProfilePath -PathType Leaf) { Backup-ClaudexFile -Path $ProfilePath | Out-Null }

    $newline = if ($existing.Contains("`r`n")) { "`r`n" } else { "`n" }
    $block = $normalizedBlock.Replace("`n", $newline)
    if ([string]::IsNullOrEmpty($existing)) {
        $content = "$block$newline"
    }
    else {
        $content = $existing
        if (-not $content.EndsWith("`n")) { $content += $newline }
        $content += "$block$newline"
    }
    Write-ClaudexUtf8File -Path $ProfilePath -Content $content
    return $true
}

function New-ClaudexTaskDefinition {
    param(
        [Parameter(Mandatory)][string]$ProxyExecutable,
        [Parameter(Mandatory)][string]$ProxyConfig,
        [Parameter(Mandatory)][string]$UserId
    )

    return [pscustomobject]@{
        TaskName = $script:ClaudexTaskName
        Description = $script:ClaudexTaskDescription
        Execute = $ProxyExecutable
        ConfigPath = $ProxyConfig
        LauncherPath = Join-Path $PSScriptRoot 'proxy-launcher.vbs'
        WorkingDirectory = Split-Path -Parent $ProxyExecutable
        UserId = $UserId
        MultipleInstances = 'IgnoreNew'
        RestartCount = 3
        RestartIntervalMinutes = 1
        AllowStartIfOnBatteries = $true
        DontStopIfGoingOnBatteries = $true
    }
}

function Register-ClaudexTask {
    param(
        [Parameter(Mandatory)]$Definition,
        [scriptblock]$TaskGetter = { param($Name) Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue }
    )

    $existing = & $TaskGetter $Definition.TaskName
    if ($existing -and $existing.Description -ne $Definition.Description) {
        throw "Scheduled task name is already owned by another configuration: $($Definition.TaskName)"
    }

    # コンソール窓を出さないため、GUIサブシステムの wscript.exe からランチャー経由で起動する。
    # proxy-launcher.vbs が Run(cmd, 0, True) で子を隠し（0=SW_HIDE）、待機してタスクを生かすため
    # RestartCount 監視も保つ。powershell -WindowStyle Hidden は対話起動時に窓を隠しきれないため使わない。
    $action = New-ScheduledTaskAction `
        -Execute 'wscript.exe' `
        -Argument "`"$($Definition.LauncherPath)`" `"$($Definition.Execute)`" `"$($Definition.ConfigPath)`"" `
        -WorkingDirectory $Definition.WorkingDirectory
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $Definition.UserId
    $settings = New-ScheduledTaskSettingsSet `
        -MultipleInstances IgnoreNew `
        -RestartCount $Definition.RestartCount `
        -RestartInterval (New-TimeSpan -Minutes $Definition.RestartIntervalMinutes) `
        -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -AllowStartIfOnBatteries:$Definition.AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries:$Definition.DontStopIfGoingOnBatteries `
        -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal -UserId $Definition.UserId -LogonType Interactive -RunLevel Limited
    $task = New-ScheduledTask `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description $Definition.Description
    Register-ScheduledTask -TaskName $Definition.TaskName -InputObject $task -Force | Out-Null
}

function Install-Claudex {
    param(
        [Parameter(Mandatory)][string]$ProxyExecutable,
        [Parameter(Mandatory)][string]$ProxyConfig,
        [Parameter(Mandatory)][string]$ProfilePath,
        [Parameter(Mandatory)][string]$SecretPath,
        [SecureString]$ProxyApiKey,
        [switch]$ReplaceSecret
    )

    foreach ($path in @($ProxyExecutable, $ProxyConfig)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file was not found: $path" }
    }
    $configText = Get-Content -Raw -LiteralPath $ProxyConfig
    if ($configText -notmatch '(?m)^host:\s*["'']?127\.0\.0\.1["'']?\s*$') {
        throw 'CLIProxyAPI host must be 127.0.0.1.'
    }
    if ($configText -notmatch '(?m)^port:\s*8317\s*$') {
        throw 'CLIProxyAPI port must be 8317.'
    }

    if (-not (Test-Path -LiteralPath $SecretPath -PathType Leaf) -or $ReplaceSecret) {
        if ($null -eq $ProxyApiKey) { $ProxyApiKey = Read-Host 'CLIProxyAPI local API key' -AsSecureString }
        Set-ClaudexSecretFile -Path $SecretPath -ProxyApiKey $ProxyApiKey -Replace:$ReplaceSecret | Out-Null
    }

    $claudexScript = Join-Path $PSScriptRoot 'claudex.ps1'
    Set-ClaudexProfileBlock -ProfilePath $ProfilePath -ClaudexScript $claudexScript | Out-Null
    $userId = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $definition = New-ClaudexTaskDefinition -ProxyExecutable $ProxyExecutable -ProxyConfig $ProxyConfig -UserId $userId
    Register-ClaudexTask -Definition $definition
    Start-ScheduledTask -TaskName $definition.TaskName
}

if ($MyInvocation.InvocationName -ne '.') {
    Install-Claudex -ProxyExecutable $ProxyExecutable -ProxyConfig $ProxyConfig -ProfilePath $ProfilePath -SecretPath $SecretPath -ProxyApiKey $ProxyApiKey -ReplaceSecret:$ReplaceSecret
}
