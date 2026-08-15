[CmdletBinding()]
param(
    [switch]$ProxyOnly,
    [switch]$CodexOnly
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\lib\ClaudexAuth.psm1') -Force -DisableNameChecking

function Write-ClaudexAuthReport {
    param([Parameter(Mandatory)]$Status)

    foreach ($entry in @($Status.Proxy, $Status.CodexCli)) {
        $deadline = if ($null -eq $entry.Deadline) { '-' } else { $entry.Deadline.ToLocalTime().ToString('yyyy-MM-dd HH:mm') }
        Write-Host ('{0,-12} {1,-8} {2}' -f $entry.Source, $entry.State, $deadline)
    }
}

function Invoke-ClaudexRelogin {
    param(
        [switch]$ProxyOnly,
        [switch]$CodexOnly,
        [scriptblock]$StatusReader = { Get-ClaudexAuthStatus },
        [scriptblock]$PathResolver = { Get-ClaudexProxyPaths },
        [scriptblock]$ProxyLogin = {
            param($Executable, $Config)
            & $Executable '-codex-login' '-config' $Config
        },
        [scriptblock]$CodexLogin = { & codex login }
    )

    if ($ProxyOnly -and $CodexOnly) { throw '-ProxyOnly と -CodexOnly は同時に指定できない。' }

    $status = & $StatusReader
    Write-ClaudexAuthReport -Status $status

    if (-not $CodexOnly) {
        $paths = & $PathResolver
        if ($null -eq $paths) {
            throw "スケジュールタスク [AgentConfig-CLIProxyAPI] からCLIProxyAPIのパスを解決できない。scripts/claudex/install.ps1 を実行する。"
        }
        $global:LASTEXITCODE = 0
        & $ProxyLogin $paths.Executable $paths.Config
        if ($LASTEXITCODE -ne 0) { throw "CLIProxyAPIの再ログインに失敗した（終了コード: $LASTEXITCODE）。" }
        $status = & $StatusReader
    }

    # 常駐するCLIProxyAPIは停止しない。新しい認証ファイルはファイル監視が読み込む。
    if (-not $ProxyOnly -and ($CodexOnly -or $status.CodexCli.State -in @('Expired', 'Ending'))) {
        $global:LASTEXITCODE = 0
        & $CodexLogin
        if ($LASTEXITCODE -ne 0) { throw "Codex CLIの再ログインに失敗した（終了コード: $LASTEXITCODE）。" }
        $status = & $StatusReader
    }

    Write-ClaudexAuthReport -Status $status
    return $status
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-ClaudexRelogin -ProxyOnly:$ProxyOnly -CodexOnly:$CodexOnly | Out-Null
}
