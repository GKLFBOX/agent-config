$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$ModulePath = Join-Path $RepoRoot 'scripts\lib\ClaudexAuth.psm1'
Import-Module $ModulePath -Force -DisableNameChecking

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "$Message expected=[$Expected] actual=[$Actual]"
    }
}

# 署名は検証しないため、ヘッダと署名はダミーで足りる。
function New-TestJwt {
    param([Parameter(Mandatory)][datetime]$IssuedAt, [Parameter(Mandatory)][datetime]$Expires)
    $payload = [ordered]@{
        iat = [DateTimeOffset]::new($IssuedAt, [TimeSpan]::Zero).ToUnixTimeSeconds()
        exp = [DateTimeOffset]::new($Expires, [TimeSpan]::Zero).ToUnixTimeSeconds()
    } | ConvertTo-Json -Compress
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    return "header.$encoded.signature"
}

$now = [datetime]::new(2026, 8, 15, 0, 0, 0, [DateTimeKind]::Utc)

# 満額の寿命なら Healthy
$healthy = Get-ClaudexTokenState -AccessToken (New-TestJwt -IssuedAt $now.AddDays(-1) -Expires $now.AddDays(9)) -Now $now
Assert-Equal 'Healthy' $healthy.State 'full lifetime state'
Assert-Equal $null $healthy.Deadline 'full lifetime deadline'

# 寿命が削られていれば Ending。exp が再ログイン期限になる
$endingExpires = $now.AddDays(5)
$ending = Get-ClaudexTokenState -AccessToken (New-TestJwt -IssuedAt $now.AddDays(-1) -Expires $endingExpires) -Now $now
Assert-Equal 'Ending' $ending.State 'capped lifetime state'
Assert-Equal $endingExpires $ending.Deadline 'capped lifetime deadline'

# exp を過ぎていれば Expired
$expiredExpires = $now.AddMinutes(-1)
$expired = Get-ClaudexTokenState -AccessToken (New-TestJwt -IssuedAt $now.AddDays(-10) -Expires $expiredExpires) -Now $now
Assert-Equal 'Expired' $expired.State 'past expiry state'
Assert-Equal $expiredExpires $expired.Deadline 'past expiry deadline'

# disabled は他の条件より優先する
$disabled = Get-ClaudexTokenState -AccessToken (New-TestJwt -IssuedAt $now.AddDays(-1) -Expires $now.AddDays(9)) -Disabled $true -Now $now
Assert-Equal 'Expired' $disabled.State 'disabled state'

# 解析できない入力は Unknown
Assert-Equal 'Unknown' (Get-ClaudexTokenState -AccessToken 'not-a-jwt' -Now $now).State 'malformed token state'
Assert-Equal 'Unknown' (Get-ClaudexTokenState -AccessToken '' -Now $now).State 'empty token state'
$noExp = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"iat":1}')).TrimEnd('=')
Assert-Equal 'Unknown' (Get-ClaudexTokenState -AccessToken "header.$noExp.signature" -Now $now).State 'missing exp state'
$outOfRangeExp = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"iat":0,"exp":99999999999999}')).TrimEnd('=').Replace('+', '-').Replace('/', '_')
Assert-Equal 'Unknown' (Get-ClaudexTokenState -AccessToken "header.$outOfRangeExp.signature" -Now $now).State 'out of range exp state'
$outOfRangeIat = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"iat":-99999999999999,"exp":0}')).TrimEnd('=').Replace('+', '-').Replace('/', '_')
Assert-Equal 'Unknown' (Get-ClaudexTokenState -AccessToken "header.$outOfRangeIat.signature" -Now $now).State 'out of range iat state'

# 境界。余裕1時間ちょうどまでは Healthy
Assert-Equal 'Healthy' (Get-ClaudexTokenState -AccessToken (New-TestJwt -IssuedAt $now -Expires $now.AddDays(10)) -Now $now).State 'exact lifetime'
Assert-Equal 'Healthy' (Get-ClaudexTokenState -AccessToken (New-TestJwt -IssuedAt $now -Expires $now.AddDays(10).AddHours(-1)) -Now $now).State 'lifetime minus margin'
Assert-Equal 'Ending' (Get-ClaudexTokenState -AccessToken (New-TestJwt -IssuedAt $now -Expires $now.AddDays(10).AddHours(-1).AddSeconds(-1)) -Now $now).State 'just inside margin'

# ペイロードを取り出せること
$payload = ConvertFrom-ClaudexJwtPayload -Token (New-TestJwt -IssuedAt $now -Expires $now.AddDays(10))
Assert-Equal $true ($null -ne $payload.exp) 'payload exp'
Assert-Equal $null (ConvertFrom-ClaudexJwtPayload -Token 'broken') 'malformed payload'

$sandbox = Join-Path ([IO.Path]::GetTempPath()) "claudex-auth-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
try {
    # スケジュールタスクの起動引数からパスを取る
    $fakeTask = [pscustomobject]@{
        Actions = @([pscustomobject]@{ Arguments = '"C:\repo\proxy-launcher.vbs" "C:\tools\cli-proxy-api.exe" "C:\tools\config.yaml"' })
    }
    $paths = Get-ClaudexProxyPaths -TaskGetter { param($Name) $fakeTask }
    Assert-Equal 'C:\tools\cli-proxy-api.exe' $paths.Executable 'proxy executable'
    Assert-Equal 'C:\tools\config.yaml' $paths.Config 'proxy config'
    Assert-Equal $null (Get-ClaudexProxyPaths -TaskGetter { param($Name) throw 'task missing' }) 'missing task'
    Assert-Equal $null (Get-ClaudexProxyPaths -TaskGetter { param($Name) $null }) 'null task'

    # config.yaml から auth-dir を取り、~ を展開する
    $configPath = Join-Path $sandbox 'config.yaml'
    Set-Content -LiteralPath $configPath -Value @('host: "127.0.0.1"', 'auth-dir: "~/.cli-proxy-api"', 'port: 8317')
    Assert-Equal (Join-Path $HOME '.cli-proxy-api') (Get-ClaudexAuthDirectory -ConfigPath $configPath) 'auth dir expansion'
    $plainPath = Join-Path $sandbox 'plain.yaml'
    Set-Content -LiteralPath $plainPath -Value @('auth-dir: D:\auth')
    Assert-Equal 'D:\auth' (Get-ClaudexAuthDirectory -ConfigPath $plainPath) 'auth dir without quotes'
    $emptyPath = Join-Path $sandbox 'empty.yaml'
    Set-Content -LiteralPath $emptyPath -Value @('port: 8317')
    Assert-Equal $null (Get-ClaudexAuthDirectory -ConfigPath $emptyPath) 'auth dir missing'
    Assert-Equal $null (Get-ClaudexAuthDirectory -ConfigPath (Join-Path $sandbox 'absent.yaml')) 'config missing'
    $lockedPath = Join-Path $sandbox 'locked.yaml'
    Set-Content -LiteralPath $lockedPath -Value 'auth-dir: D:\auth'
    $lock = [IO.File]::Open($lockedPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    try {
        Assert-Equal $null (Get-ClaudexAuthDirectory -ConfigPath $lockedPath) 'locked config'
    }
    finally {
        $lock.Dispose()
    }

    # auth-dir を解決できなければ Unknown
    Assert-Equal 'Unknown' (Get-ClaudexProxyAuthState -AuthDirectory $null -Now $now).State 'null auth dir'
    Assert-Equal 'Unknown' (Get-ClaudexProxyAuthState -AuthDirectory (Join-Path $sandbox 'absent') -Now $now).State 'absent auth dir'

    # 列挙失敗は Unknown、認証ファイルがなければ Expired
    $authDir = Join-Path $sandbox 'auth'
    New-Item -ItemType Directory -Path $authDir -Force | Out-Null
    $enumerationFailure = Get-ClaudexProxyAuthState -AuthDirectory $authDir -Now $now -FileEnumerator { param($Path) throw 'access denied' }
    Assert-Equal 'Unknown' $enumerationFailure.State 'auth directory enumeration failure'
    $noFile = Get-ClaudexProxyAuthState -AuthDirectory $authDir -Now $now
    Assert-Equal 'Expired' $noFile.State 'no auth file'
    Assert-Equal 'CLIProxyAPI' $noFile.Source 'proxy source'

    # 複数ある場合は最も良い状態を採る
    Set-Content -LiteralPath (Join-Path $authDir 'codex-a.json') -Value (@{
        access_token = (New-TestJwt -IssuedAt $now.AddDays(-10) -Expires $now.AddMinutes(-1))
        disabled     = $false
    } | ConvertTo-Json)
    Assert-Equal 'Expired' (Get-ClaudexProxyAuthState -AuthDirectory $authDir -Now $now).State 'single expired auth'
    Set-Content -LiteralPath (Join-Path $authDir 'codex-b.json') -Value (@{
        access_token = (New-TestJwt -IssuedAt $now.AddDays(-1) -Expires $now.AddDays(9))
        disabled     = $false
    } | ConvertTo-Json)
    Assert-Equal 'Healthy' (Get-ClaudexProxyAuthState -AuthDirectory $authDir -Now $now).State 'best of multiple auths'

    # disabled は無効として扱う
    $disabledDir = Join-Path $sandbox 'disabled'
    New-Item -ItemType Directory -Path $disabledDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $disabledDir 'codex-a.json') -Value (@{
        access_token = (New-TestJwt -IssuedAt $now.AddDays(-1) -Expires $now.AddDays(9))
        disabled     = $true
    } | ConvertTo-Json)
    Assert-Equal 'Expired' (Get-ClaudexProxyAuthState -AuthDirectory $disabledDir -Now $now).State 'disabled auth'

    # 壊れた JSON は Unknown
    $brokenDir = Join-Path $sandbox 'broken'
    New-Item -ItemType Directory -Path $brokenDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $brokenDir 'codex-a.json') -Value '{ not json'
    Assert-Equal 'Unknown' (Get-ClaudexProxyAuthState -AuthDirectory $brokenDir -Now $now).State 'broken auth json'

    # Codex CLI 側はネストした tokens.access_token を読む
    $codexAuth = Join-Path $sandbox 'auth.json'
    Set-Content -LiteralPath $codexAuth -Value (@{
        tokens = @{ access_token = (New-TestJwt -IssuedAt $now.AddDays(-1) -Expires $now.AddDays(9)) }
    } | ConvertTo-Json -Depth 5)
    $codexState = Get-ClaudexCodexCliAuthState -Path $codexAuth -Now $now
    Assert-Equal 'Healthy' $codexState.State 'codex cli healthy'
    Assert-Equal 'CodexCLI' $codexState.Source 'codex cli source'
    Assert-Equal 'Expired' (Get-ClaudexCodexCliAuthState -Path (Join-Path $sandbox 'absent.json') -Now $now).State 'codex cli missing file'

    # CODEX_HOME があればそちらを見る
    $originalCodexHome = [Environment]::GetEnvironmentVariable('CODEX_HOME', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('CODEX_HOME', 'D:\codex-home', 'Process')
        Assert-Equal 'D:\codex-home' (Get-ClaudexCodexHome) 'codex home override'
        [Environment]::SetEnvironmentVariable('CODEX_HOME', $null, 'Process')
        Assert-Equal (Join-Path $HOME '.codex') (Get-ClaudexCodexHome) 'codex home default'
    }
    finally {
        [Environment]::SetEnvironmentVariable('CODEX_HOME', $originalCodexHome, 'Process')
    }

    # 両系統をまとめて返す
    $status = Get-ClaudexAuthStatus -Now $now `
        -ProxyPathResolver { [pscustomobject]@{ Executable = 'x.exe'; Config = $configPath } } `
        -CodexCliPathResolver { $codexAuth }
    Assert-Equal 'CLIProxyAPI' $status.Proxy.Source 'status proxy source'
    Assert-Equal 'CodexCLI' $status.CodexCli.Source 'status codex source'
    Assert-Equal 'Healthy' $status.CodexCli.State 'status codex state'

    # パスを解決できなければ CLIProxyAPI 側は Unknown。例外にしない
    $unresolved = Get-ClaudexAuthStatus -Now $now `
        -ProxyPathResolver { $null } `
        -CodexCliPathResolver { $codexAuth }
    Assert-Equal 'Unknown' $unresolved.Proxy.State 'unresolved proxy path'
    Assert-Equal 'Healthy' $unresolved.CodexCli.State 'codex unaffected by proxy path'
}
finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'ClaudexAuth token state tests PASSED'
