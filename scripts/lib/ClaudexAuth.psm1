$ErrorActionPreference = 'Stop'

$script:ClaudexTaskName = 'AgentConfig-CLIProxyAPI'
$script:ClaudexTokenLifetime = [TimeSpan]::FromDays(10)
$script:ClaudexLifetimeMargin = [TimeSpan]::FromHours(1)

function ConvertFrom-ClaudexJwtPayload {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Token)

    # 署名は検証しない。期限の表示に使うだけで、認証には使わない。
    $parts = $Token.Split('.')
    if ($parts.Count -lt 2) { return $null }
    $segment = $parts[1].Replace('-', '+').Replace('_', '/')
    switch ($segment.Length % 4) {
        2 { $segment += '==' }
        3 { $segment += '=' }
        1 { return $null }
    }
    try {
        return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($segment)) | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function New-ClaudexTokenState {
    param([Parameter(Mandatory)][string]$State, [AllowNull()][object]$Deadline = $null)

    return [pscustomobject]@{ State = $State; Deadline = $Deadline }
}

function Get-ClaudexTokenState {
    param(
        [AllowEmptyString()][AllowNull()][string]$AccessToken,
        [bool]$Disabled = $false,
        [datetime]$Now = [datetime]::UtcNow,
        [timespan]$Lifetime = $script:ClaudexTokenLifetime,
        [timespan]$Margin = $script:ClaudexLifetimeMargin
    )

    if ($Disabled) { return New-ClaudexTokenState -State 'Expired' }
    if ([string]::IsNullOrWhiteSpace($AccessToken)) { return New-ClaudexTokenState -State 'Unknown' }

    $payload = ConvertFrom-ClaudexJwtPayload -Token $AccessToken
    if ($null -eq $payload) { return New-ClaudexTokenState -State 'Unknown' }

    if ($null -eq $payload.iat -or $null -eq $payload.exp) { return New-ClaudexTokenState -State 'Unknown' }
    $issuedSeconds = $payload.iat -as [long]
    $expiresSeconds = $payload.exp -as [long]
    if ($null -eq $issuedSeconds -or $null -eq $expiresSeconds) { return New-ClaudexTokenState -State 'Unknown' }

    try {
        $issuedAt = [DateTimeOffset]::FromUnixTimeSeconds($issuedSeconds).UtcDateTime
        $expires = [DateTimeOffset]::FromUnixTimeSeconds($expiresSeconds).UtcDateTime
    }
    catch {
        return New-ClaudexTokenState -State 'Unknown'
    }

    if ($expires -le $Now) { return New-ClaudexTokenState -State 'Expired' -Deadline $expires }
    # access token はセッションの終了時刻を超えて発行されない。
    # 寿命が満額に満たなければ、exp がそのままセッションの終了時刻を指す。
    if (($expires - $issuedAt) -lt ($Lifetime - $Margin)) { return New-ClaudexTokenState -State 'Ending' -Deadline $expires }
    return New-ClaudexTokenState -State 'Healthy'
}

function New-ClaudexAuthState {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$State,
        [AllowNull()][object]$Deadline = $null
    )

    return [pscustomobject]@{ Source = $Source; State = $State; Deadline = $Deadline }
}

function Merge-ClaudexAuthState {
    param(
        [Parameter(Mandatory)][string]$Source,
        [AllowEmptyCollection()][object[]]$States = @()
    )

    if ($States.Count -eq 0) { return New-ClaudexAuthState -Source $Source -State 'Expired' }
    # ラウンドロビンで使うため、ひとつでも有効なら応答できる。良い順に並べて先頭を採る。
    $rank = @{ 'Healthy' = 0; 'Ending' = 1; 'Unknown' = 2; 'Expired' = 3 }
    $best = $States |
        Sort-Object -Property @{ Expression = { $rank[$_.State] } }, @{ Expression = { $_.Deadline }; Descending = $true } |
        Select-Object -First 1
    return New-ClaudexAuthState -Source $Source -State $best.State -Deadline $best.Deadline
}

function Get-ClaudexProxyPaths {
    param(
        [scriptblock]$TaskGetter = { param($Name) Get-ScheduledTask -TaskName $Name -ErrorAction Stop }
    )

    # 実行ファイルと config.yaml の正本はタスク定義。install.ps1 の既定値と二重管理しない。
    try { $task = & $TaskGetter $script:ClaudexTaskName }
    catch { return $null }
    if ($null -eq $task -or $null -eq $task.Actions) { return $null }

    $arguments = [string]$task.Actions[0].Arguments
    $quoted = [regex]::Matches($arguments, '"([^"]+)"')
    if ($quoted.Count -lt 3) { return $null }
    return [pscustomobject]@{
        Executable = $quoted[1].Groups[1].Value
        Config     = $quoted[2].Groups[1].Value
    }
}

function Get-ClaudexAuthDirectory {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return $null }
    $text = try { Get-Content -Raw -LiteralPath $ConfigPath } catch { return $null }
    if ($text -notmatch '(?m)^auth-dir:\s*"?([^"\r\n]+?)"?\s*$') { return $null }
    $value = $Matches[1]
    if ($value.StartsWith('~')) { $value = Join-Path $HOME $value.Substring(1).TrimStart('/', '\') }
    return $value
}

function Get-ClaudexCodexHome {
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { return $env:CODEX_HOME }
    return (Join-Path $HOME '.codex')
}

function Get-ClaudexProxyAuthState {
    param(
        [AllowNull()][AllowEmptyString()][string]$AuthDirectory,
        [datetime]$Now = [datetime]::UtcNow,
        [scriptblock]$FileEnumerator = {
            param($Path)
            Get-ChildItem -LiteralPath $Path -Filter 'codex-*.json' -File -ErrorAction Stop
        }
    )

    if ([string]::IsNullOrWhiteSpace($AuthDirectory) -or -not (Test-Path -LiteralPath $AuthDirectory -PathType Container)) {
        return New-ClaudexAuthState -Source 'CLIProxyAPI' -State 'Unknown'
    }

    try { $files = @(& $FileEnumerator $AuthDirectory) }
    catch { return New-ClaudexAuthState -Source 'CLIProxyAPI' -State 'Unknown' }
    $states = foreach ($file in $files) {
        $data = try { Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json } catch { $null }
        if ($null -eq $data) { New-ClaudexTokenState -State 'Unknown' }
        else { Get-ClaudexTokenState -AccessToken ([string]$data.access_token) -Disabled ([bool]$data.disabled) -Now $Now }
    }
    return Merge-ClaudexAuthState -Source 'CLIProxyAPI' -States @($states)
}

function Get-ClaudexCodexCliAuthState {
    param(
        [string]$Path = (Join-Path (Get-ClaudexCodexHome) 'auth.json'),
        [datetime]$Now = [datetime]::UtcNow
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return New-ClaudexAuthState -Source 'CodexCLI' -State 'Expired'
    }
    $data = try { Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json } catch { $null }
    if ($null -eq $data) { return New-ClaudexAuthState -Source 'CodexCLI' -State 'Unknown' }
    $state = Get-ClaudexTokenState -AccessToken ([string]$data.tokens.access_token) -Now $Now
    return New-ClaudexAuthState -Source 'CodexCLI' -State $state.State -Deadline $state.Deadline
}

function Get-ClaudexAuthStatus {
    param(
        [datetime]$Now = [datetime]::UtcNow,
        [scriptblock]$ProxyPathResolver = { Get-ClaudexProxyPaths },
        [scriptblock]$CodexCliPathResolver = { Join-Path (Get-ClaudexCodexHome) 'auth.json' }
    )

    $paths = & $ProxyPathResolver
    $authDirectory = if ($null -eq $paths) { $null } else { Get-ClaudexAuthDirectory -ConfigPath ([string]$paths.Config) }
    return [pscustomobject]@{
        Proxy    = Get-ClaudexProxyAuthState -AuthDirectory $authDirectory -Now $Now
        CodexCli = Get-ClaudexCodexCliAuthState -Path (& $CodexCliPathResolver) -Now $Now
    }
}

Export-ModuleMember -Function ConvertFrom-ClaudexJwtPayload, Get-ClaudexTokenState, Get-ClaudexProxyPaths,
    Get-ClaudexAuthDirectory, Get-ClaudexCodexHome, Get-ClaudexProxyAuthState, Get-ClaudexCodexCliAuthState,
    Get-ClaudexAuthStatus
