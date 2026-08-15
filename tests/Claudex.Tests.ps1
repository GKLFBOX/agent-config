$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$ClaudexScript = Join-Path $RepoRoot 'scripts\claudex\claudex.ps1'

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "$Message expected=[$Expected] actual=[$Actual]"
    }
}

function Assert-Sequence {
    param([object[]]$Expected, [object[]]$Actual, [string]$Message)
    if (($Expected -join "`0") -ne ($Actual -join "`0")) {
        throw "$Message expected=[$($Expected -join ',')] actual=[$($Actual -join ',')]"
    }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Pattern, [string]$Message)
    try {
        & $Action
    }
    catch {
        if ("$_" -notmatch $Pattern) { throw "$Message unexpected error: $_" }
        return
    }
    throw "$Message did not throw"
}

function Restore-TestEnvironmentVariable {
    param([string]$Name, [AllowNull()][string]$Value)
    if ($null -eq $Value) {
        Remove-Item -LiteralPath "Env:$Name" -ErrorAction SilentlyContinue
    }
    else {
        [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
    }
}

. $ClaudexScript

Remove-Variable -Name claudexStrictModeProbe -ErrorAction SilentlyContinue
try {
    $null = $claudexStrictModeProbe
}
catch {
    throw 'Dot-sourcing claudex.ps1 must not enable StrictMode in the caller scope.'
}

$default = ConvertTo-ClaudexInvocation -Arguments @('--continue')
Assert-Equal 'gpt-5.6-sol' $default.Model 'default model'
Assert-Equal 'xhigh' $default.Effort 'default effort'
Assert-Sequence @('--model', 'gpt-5.6-sol', '--effort', 'xhigh', '--continue') $default.ClaudeArguments 'default arguments'

$terra = ConvertTo-ClaudexInvocation -Arguments @('--model', 'terra', '--effort', 'high', '--resume', 'abc')
Assert-Equal 'gpt-5.6-terra' $terra.Model 'terra model'
Assert-Equal 'high' $terra.Effort 'explicit effort'
Assert-Sequence @('--model', 'gpt-5.6-terra', '--effort', 'high', '--resume', 'abc') $terra.ClaudeArguments 'forwarded arguments'

$equals = ConvertTo-ClaudexInvocation -Arguments @('--model=gpt-5.6-luna', '--effort=max', '--print', 'ok')
Assert-Equal 'gpt-5.6-luna' $equals.Model 'full model'
Assert-Equal 'max' $equals.Effort 'equals effort'

$literal = ConvertTo-ClaudexInvocation -Arguments @('--', '--model', 'terra')
Assert-Sequence @('--model', 'gpt-5.6-sol', '--effort', 'xhigh', '--', '--model', 'terra') $literal.ClaudeArguments 'literal forwarding'

Assert-Throws { ConvertTo-ClaudexInvocation -Arguments @('--model', 'unknown') } 'Unsupported model' 'unknown model'
Assert-Throws { ConvertTo-ClaudexInvocation -Arguments @('--model') } 'requires a value' 'missing model'
Assert-Throws { ConvertTo-ClaudexInvocation -Arguments @('--model', 'sol', '--model', 'terra') } 'specified more than once' 'duplicate model'
Assert-Throws { ConvertTo-ClaudexInvocation -Arguments @('--effort', 'ultra') } 'Unsupported effort' 'unknown effort'
Assert-Throws { ConvertTo-ClaudexInvocation -Arguments @('--effort', 'low', '--effort', 'high') } 'specified more than once' 'duplicate effort'

$help = ConvertTo-ClaudexInvocation -Arguments @('--help')
if (-not $help.IsHelp) { throw 'help flag must short-circuit execution' }
$version = ConvertTo-ClaudexInvocation -Arguments @('--version')
if (-not $version.IsVersion) { throw 'version flag must short-circuit proxy access' }

$helpText = Get-ClaudexHelpText
foreach ($requiredHelpText in @(
    "claudex '--'",
    'AgentConfig-CLIProxyAPI',
    'http://127.0.0.1:8317',
    'Get-ScheduledTaskInfo'
)) {
    if ($helpText -notmatch [regex]::Escape($requiredHelpText)) {
        throw "claudex help must contain [$requiredHelpText]"
    }
}

Write-Host 'Claudex argument tests PASSED'

$originalApiKey = [Environment]::GetEnvironmentVariable('ANTHROPIC_API_KEY', 'Process')
$originalEffort = [Environment]::GetEnvironmentVariable('CLAUDE_CODE_EFFORT_LEVEL', 'Process')
$originalBaseUrl = [Environment]::GetEnvironmentVariable('ANTHROPIC_BASE_URL', 'Process')
$originalSubagent = [Environment]::GetEnvironmentVariable('CLAUDE_CODE_SUBAGENT_MODEL', 'Process')
$originalAuthToken = [Environment]::GetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', 'Process')
$originalOpusModel = [Environment]::GetEnvironmentVariable('ANTHROPIC_DEFAULT_OPUS_MODEL', 'Process')
$originalMaxOutput = [Environment]::GetEnvironmentVariable('CLAUDE_CODE_MAX_OUTPUT_TOKENS', 'Process')
$originalMaxContext = [Environment]::GetEnvironmentVariable('CLAUDE_CODE_MAX_CONTEXT_TOKENS', 'Process')
$originalAutoCompactWindow = [Environment]::GetEnvironmentVariable('CLAUDE_CODE_AUTO_COMPACT_WINDOW', 'Process')
$originalAutoCompactPercent = [Environment]::GetEnvironmentVariable('CLAUDE_AUTOCOMPACT_PCT_OVERRIDE', 'Process')
try {
    [Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY', 'original-api-key', 'Process')
    [Environment]::SetEnvironmentVariable('CLAUDE_CODE_EFFORT_LEVEL', 'medium', 'Process')
    [Environment]::SetEnvironmentVariable('ANTHROPIC_BASE_URL', 'https://original.example', 'Process')
    [Environment]::SetEnvironmentVariable('CLAUDE_CODE_SUBAGENT_MODEL', 'original-subagent', 'Process')
    [Environment]::SetEnvironmentVariable('CLAUDE_CODE_MAX_OUTPUT_TOKENS', '64000', 'Process')
    [Environment]::SetEnvironmentVariable('CLAUDE_CODE_AUTO_COMPACT_WINDOW', '180000', 'Process')
    Remove-Item -LiteralPath 'Env:ANTHROPIC_AUTH_TOKEN' -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath 'Env:ANTHROPIC_DEFAULT_OPUS_MODEL' -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath 'Env:CLAUDE_CODE_MAX_CONTEXT_TOKENS' -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath 'Env:CLAUDE_AUTOCOMPACT_PCT_OVERRIDE' -ErrorAction SilentlyContinue

    $script:inside = $null
    Invoke-WithClaudexEnvironment -Token 'local-token' -Action {
        $script:inside = [pscustomobject]@{
            ApiKey = [Environment]::GetEnvironmentVariable('ANTHROPIC_API_KEY', 'Process')
            Effort = [Environment]::GetEnvironmentVariable('CLAUDE_CODE_EFFORT_LEVEL', 'Process')
            BaseUrl = [Environment]::GetEnvironmentVariable('ANTHROPIC_BASE_URL', 'Process')
            Token = [Environment]::GetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', 'Process')
            Fable = [Environment]::GetEnvironmentVariable('ANTHROPIC_DEFAULT_FABLE_MODEL', 'Process')
            Opus = [Environment]::GetEnvironmentVariable('ANTHROPIC_DEFAULT_OPUS_MODEL', 'Process')
            Sonnet = [Environment]::GetEnvironmentVariable('ANTHROPIC_DEFAULT_SONNET_MODEL', 'Process')
            Haiku = [Environment]::GetEnvironmentVariable('ANTHROPIC_DEFAULT_HAIKU_MODEL', 'Process')
            OpusCapabilities = [Environment]::GetEnvironmentVariable('ANTHROPIC_DEFAULT_OPUS_MODEL_SUPPORTED_CAPABILITIES', 'Process')
            Subagent = [Environment]::GetEnvironmentVariable('CLAUDE_CODE_SUBAGENT_MODEL', 'Process')
            MaxOutput = [Environment]::GetEnvironmentVariable('CLAUDE_CODE_MAX_OUTPUT_TOKENS', 'Process')
            MaxContext = [Environment]::GetEnvironmentVariable('CLAUDE_CODE_MAX_CONTEXT_TOKENS', 'Process')
            AutoCompactWindow = [Environment]::GetEnvironmentVariable('CLAUDE_CODE_AUTO_COMPACT_WINDOW', 'Process')
            AutoCompactPercent = [Environment]::GetEnvironmentVariable('CLAUDE_AUTOCOMPACT_PCT_OVERRIDE', 'Process')
        }
    }
    Assert-Equal $null $script:inside.ApiKey 'API key must be cleared'
    Assert-Equal $null $script:inside.Effort 'effort environment must be cleared'
    Assert-Equal 'http://127.0.0.1:8317' $script:inside.BaseUrl 'proxy base URL'
    Assert-Equal 'local-token' $script:inside.Token 'proxy token'
    Assert-Equal 'gpt-5.6-sol' $script:inside.Fable 'Fable model'
    Assert-Equal 'gpt-5.6-sol' $script:inside.Opus 'Opus model'
    Assert-Equal 'gpt-5.6-terra' $script:inside.Sonnet 'Sonnet model'
    Assert-Equal 'gpt-5.6-luna' $script:inside.Haiku 'Haiku model'
    Assert-Equal 'effort,xhigh_effort,max_effort' $script:inside.OpusCapabilities 'model capabilities'
    Assert-Equal 'original-subagent' $script:inside.Subagent 'generic subagent model must not be changed'
    Assert-Equal '128000' $script:inside.MaxOutput 'maximum output tokens'
    Assert-Equal '372000' $script:inside.MaxContext 'maximum context tokens'
    Assert-Equal '240000' $script:inside.AutoCompactWindow 'auto compact window'
    Assert-Equal '85' $script:inside.AutoCompactPercent 'auto compact percentage'
    Assert-Equal 'original-api-key' ([Environment]::GetEnvironmentVariable('ANTHROPIC_API_KEY', 'Process')) 'API key restore'
    Assert-Equal 'medium' ([Environment]::GetEnvironmentVariable('CLAUDE_CODE_EFFORT_LEVEL', 'Process')) 'effort restore'
    Assert-Equal 'https://original.example' ([Environment]::GetEnvironmentVariable('ANTHROPIC_BASE_URL', 'Process')) 'base URL restore'
    Assert-Equal $null ([Environment]::GetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', 'Process')) 'token removal after success'
    Assert-Equal $null ([Environment]::GetEnvironmentVariable('ANTHROPIC_DEFAULT_OPUS_MODEL', 'Process')) 'model removal after success'
    Assert-Equal '64000' ([Environment]::GetEnvironmentVariable('CLAUDE_CODE_MAX_OUTPUT_TOKENS', 'Process')) 'output token restore after success'
    Assert-Equal $null ([Environment]::GetEnvironmentVariable('CLAUDE_CODE_MAX_CONTEXT_TOKENS', 'Process')) 'context token removal after success'
    Assert-Equal '180000' ([Environment]::GetEnvironmentVariable('CLAUDE_CODE_AUTO_COMPACT_WINDOW', 'Process')) 'compact window restore after success'
    Assert-Equal $null ([Environment]::GetEnvironmentVariable('CLAUDE_AUTOCOMPACT_PCT_OVERRIDE', 'Process')) 'compact percentage removal after success'

    Assert-Throws {
        Invoke-WithClaudexEnvironment -Token 'local-token' -Action { throw 'action failed' }
    } 'action failed' 'environment failure path'
    Assert-Equal 'original-api-key' ([Environment]::GetEnvironmentVariable('ANTHROPIC_API_KEY', 'Process')) 'failure API key restore'
    Assert-Equal $null ([Environment]::GetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', 'Process')) 'token removal after failure'
    Assert-Equal $null ([Environment]::GetEnvironmentVariable('ANTHROPIC_DEFAULT_OPUS_MODEL', 'Process')) 'model removal after failure'
    Assert-Equal '64000' ([Environment]::GetEnvironmentVariable('CLAUDE_CODE_MAX_OUTPUT_TOKENS', 'Process')) 'output token restore after failure'
    Assert-Equal $null ([Environment]::GetEnvironmentVariable('CLAUDE_CODE_MAX_CONTEXT_TOKENS', 'Process')) 'context token removal after failure'
    Assert-Equal '180000' ([Environment]::GetEnvironmentVariable('CLAUDE_CODE_AUTO_COMPACT_WINDOW', 'Process')) 'compact window restore after failure'
    Assert-Equal $null ([Environment]::GetEnvironmentVariable('CLAUDE_AUTOCOMPACT_PCT_OVERRIDE', 'Process')) 'compact percentage removal after failure'
}
finally {
    Restore-TestEnvironmentVariable -Name 'ANTHROPIC_API_KEY' -Value $originalApiKey
    Restore-TestEnvironmentVariable -Name 'CLAUDE_CODE_EFFORT_LEVEL' -Value $originalEffort
    Restore-TestEnvironmentVariable -Name 'ANTHROPIC_BASE_URL' -Value $originalBaseUrl
    Restore-TestEnvironmentVariable -Name 'CLAUDE_CODE_SUBAGENT_MODEL' -Value $originalSubagent
    Restore-TestEnvironmentVariable -Name 'ANTHROPIC_AUTH_TOKEN' -Value $originalAuthToken
    Restore-TestEnvironmentVariable -Name 'ANTHROPIC_DEFAULT_OPUS_MODEL' -Value $originalOpusModel
    Restore-TestEnvironmentVariable -Name 'CLAUDE_CODE_MAX_OUTPUT_TOKENS' -Value $originalMaxOutput
    Restore-TestEnvironmentVariable -Name 'CLAUDE_CODE_MAX_CONTEXT_TOKENS' -Value $originalMaxContext
    Restore-TestEnvironmentVariable -Name 'CLAUDE_CODE_AUTO_COMPACT_WINDOW' -Value $originalAutoCompactWindow
    Restore-TestEnvironmentVariable -Name 'CLAUDE_AUTOCOMPACT_PCT_OVERRIDE' -Value $originalAutoCompactPercent
}

$startTask = { param($TaskName) $script:startCount++ }
$delay = { param($Milliseconds) }
$script:requestCount = 0
$script:startCount = 0
$request = {
    param($Uri, $Headers)
    $script:requestCount++
    if ($script:requestCount -eq 1) { throw 'not listening' }
    return [pscustomobject]@{ StatusCode = 200 }
}
Confirm-ClaudexProxy -Token 'local-token' -WebRequest $request -TaskStarter $startTask -Delay $delay
Assert-Equal 2 $script:requestCount 'proxy retry count'
Assert-Equal 1 $script:startCount 'task start count'

$script:startCount = 0
Confirm-ClaudexProxy -Token 'local-token' -WebRequest { param($Uri, $Headers) [pscustomobject]@{ StatusCode = 200 } } -TaskStarter $startTask -Delay $delay
Assert-Equal 0 $script:startCount 'healthy proxy must not start task'

$script:startCount = 0
Assert-Throws {
    Confirm-ClaudexProxy -Token 'local-token' `
        -WebRequest { param($Uri, $Headers) [pscustomobject]@{ StatusCode = 401 } } `
        -TaskStarter $startTask `
        -Delay $delay
} 'rejected the configured API key' 'unauthorized proxy response'
Assert-Equal 0 $script:startCount 'authentication failure must not start task'

Assert-Throws {
    Confirm-ClaudexProxy -Token 'local-token' `
        -WebRequest { param($Uri, $Headers) throw 'not listening' } `
        -TaskStarter { param($TaskName) throw 'task missing' } `
        -Delay $delay
} 'could not be started' 'missing scheduled task'

$script:timeoutRequestCount = 0
$timeoutFailure = $null
try {
    Confirm-ClaudexProxy -Token 'local-token' `
        -WebRequest { param($Uri, $Headers) $script:timeoutRequestCount++; throw 'not listening' } `
        -TaskStarter { param($TaskName) } `
        -Delay $delay
}
catch {
    $timeoutFailure = "$_"
}
if ($timeoutFailure -notmatch 'did not become ready') { throw "unexpected proxy timeout: $timeoutFailure" }
if ($timeoutFailure -notmatch '\.Actions') { throw 'proxy timeout must point to scheduled-task action inspection' }
Assert-Equal 21 $script:timeoutRequestCount 'proxy timeout request count'

function New-TestAuthStatus {
    param([string]$ProxyState = 'Healthy', [string]$CodexState = 'Healthy', [AllowNull()][object]$Deadline = $null)
    return [pscustomobject]@{
        Proxy    = [pscustomobject]@{ Source = 'CLIProxyAPI'; State = $ProxyState; Deadline = $Deadline }
        CodexCli = [pscustomobject]@{ Source = 'CodexCLI'; State = $CodexState; Deadline = $Deadline }
    }
}

# AuthStatusReaderを省いた呼び出しはテスト用の失効状態へ落とす
function Get-ClaudexAuthStatus { New-TestAuthStatus -ProxyState 'Expired' }

$capturedArguments = $null
$insideToken = $null
$state = [pscustomobject]@{ ExitCode = 0 }
Invoke-Claudex -Arguments @('--model', 'terra', '--print', 'ok') `
    -TokenReader { param($Path) 'local-token' } `
    -AuthStatusReader { New-TestAuthStatus } `
    -WebRequest { param($Uri, $Headers) [pscustomobject]@{ StatusCode = 200 } } `
    -CommandResolver { param($Name) [pscustomobject]@{ Source = 'fake-claude.exe' } } `
    -ClaudeInvoker {
        param($Command, $Arguments, $State)
        $script:capturedArguments = @($Arguments)
        $script:insideToken = [Environment]::GetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', 'Process')
        $State.ExitCode = 7
    }
Assert-Sequence @('--model', 'gpt-5.6-terra', '--effort', 'xhigh', '--print', 'ok') $script:capturedArguments 'launcher arguments'
Assert-Equal 'local-token' $script:insideToken 'launcher environment'
Assert-Equal 7 $global:LASTEXITCODE 'launcher exit code'

$script:capturedCommand = $null
Invoke-Claudex -Arguments @('--print', 'ok') `
    -TokenReader { param($Path) 'local-token' } `
    -AuthStatusReader { New-TestAuthStatus } `
    -WebRequest { param($Uri, $Headers) [pscustomobject]@{ StatusCode = 200 } } `
    -CommandResolver {
        param($Name)
        @(
            [pscustomobject]@{ Source = 'first-claude.exe' },
            [pscustomobject]@{ Source = 'second-claude.cmd' }
        )
    } `
    -ClaudeInvoker {
        param($Command, $Arguments, $State)
        $script:capturedCommand = $Command
        $State.ExitCode = 0
    }
Assert-Equal 'first-claude.exe' $script:capturedCommand 'first Claude command on PATH'

$script:versionTokenReads = 0
$script:versionArguments = $null
Invoke-Claudex -Arguments @('--version') `
    -TokenReader { param($Path) $script:versionTokenReads++; throw 'token must not be read' } `
    -CommandResolver { param($Name) [pscustomobject]@{ Source = 'fake-claude.exe' } } `
    -ClaudeInvoker {
        param($Command, $Arguments, $State)
        $script:versionArguments = @($Arguments)
        $State.ExitCode = 5
    }
Assert-Equal 0 $script:versionTokenReads 'version token reads'
Assert-Sequence @('--version') $script:versionArguments 'version arguments'
Assert-Equal 5 $global:LASTEXITCODE 'version exit code'

$secretFailure = $null
try {
    Confirm-ClaudexProxy -Token 'do-not-print-this' `
        -WebRequest { param($Uri, $Headers) throw 'connection refused' } `
        -TaskStarter { param($TaskName) } `
        -Delay { param($Milliseconds) }
}
catch {
    $secretFailure = "$_"
}
if ($secretFailure -match 'do-not-print-this') { throw 'error message leaked token' }

$authNow = [datetime]::new(2026, 8, 15, 0, 0, 0, [DateTimeKind]::Utc)

# Healthy なら何も出さない
$healthyWarnings = Assert-ClaudexAuth -Status (New-TestAuthStatus) -Now $authNow -ReloginScript 'X:\relogin.ps1' 3>&1
Assert-Equal 0 @($healthyWarnings).Count 'healthy auth warnings'

# CLIProxyAPI の Expired は停止させ、復旧口を示す
Assert-Throws {
    Assert-ClaudexAuth -Status (New-TestAuthStatus -ProxyState 'Expired') -Now $authNow -ReloginScript 'X:\relogin.ps1'
} 'X:\\relogin\.ps1' 'expired proxy auth points to relogin script'
$quotedPathFailure = $null
try {
    Assert-ClaudexAuth -Status (New-TestAuthStatus -ProxyState 'Expired') -Now $authNow -ReloginScript 'X:\path with space\relogin.ps1'
}
catch { $quotedPathFailure = "$_" }
if ($quotedPathFailure -notmatch '-File "X:\\path with space\\relogin\.ps1"') { throw "relogin path must be quoted: $quotedPathFailure" }

# Ending は警告して通す。残り日数と期限を出す
$endingWarnings = @(Assert-ClaudexAuth -Status (New-TestAuthStatus -ProxyState 'Ending' -Deadline $authNow.AddDays(6)) -Now $authNow -ReloginScript 'X:\relogin.ps1' 3>&1)
Assert-Equal 1 $endingWarnings.Count 'ending auth warning count'
$endingText = "$($endingWarnings[0])"
if (-not $endingText.Contains('Codex認証はあと6日で失効する（期限: ')) { throw "unexpected proxy ending warning: $endingText" }
$codexEndingWarnings = @(Assert-ClaudexAuth -Status (New-TestAuthStatus -CodexState 'Ending' -Deadline $authNow.AddDays(6)) -Now $authNow -ReloginScript 'X:\relogin.ps1' 3>&1)
Assert-Equal 1 $codexEndingWarnings.Count 'codex ending warning count'
$codexEndingText = "$($codexEndingWarnings[0])"
if (-not $codexEndingText.Contains('Codex CLIの認証はあと6日で失効する（期限: ')) { throw "unexpected Codex CLI ending warning: $codexEndingText" }

# Unknown は警告して通す
$unknownWarnings = @(Assert-ClaudexAuth -Status (New-TestAuthStatus -ProxyState 'Unknown') -Now $authNow -ReloginScript 'X:\relogin.ps1' 3>&1)
Assert-Equal 1 $unknownWarnings.Count 'unknown auth warning count'

# Codex CLI 単独の失効は警告だけで、影響範囲を書く
$codexWarnings = @(Assert-ClaudexAuth -Status (New-TestAuthStatus -CodexState 'Expired') -Now $authNow -ReloginScript 'X:\relogin.ps1' 3>&1)
Assert-Equal 1 $codexWarnings.Count 'codex cli warning count'
if ("$($codexWarnings[0])" -notmatch 'statusline') { throw "codex warning must state the impact: $($codexWarnings[0])" }

# Codex CLI の Unknown は黙って通す
Assert-Equal 0 @(Assert-ClaudexAuth -Status (New-TestAuthStatus -CodexState 'Unknown') -Now $authNow -ReloginScript 'X:\relogin.ps1' 3>&1).Count 'codex cli unknown is silent'

# 失効時は Claude Code を起動しない
$script:gateInvocations = 0
Assert-Throws {
    Invoke-Claudex -Arguments @('--print', 'ok') `
        -TokenReader { param($Path) 'local-token' } `
        -AuthStatusReader { New-TestAuthStatus -ProxyState 'Expired' } `
        -WebRequest { param($Uri, $Headers) [pscustomobject]@{ StatusCode = 200 } } `
        -CommandResolver { param($Name) [pscustomobject]@{ Source = 'fake-claude.exe' } } `
        -ClaudeInvoker { param($Command, $Arguments, $State) $script:gateInvocations++ }
} 'Codex認証' 'expired auth must stop launch'
Assert-Equal 0 $script:gateInvocations 'expired auth must not launch claude'

# Ending なら起動する
$script:gateInvocations = 0
Invoke-Claudex -Arguments @('--print', 'ok') `
    -TokenReader { param($Path) 'local-token' } `
    -AuthStatusReader { New-TestAuthStatus -ProxyState 'Ending' -Deadline $authNow.AddDays(3) } `
    -WebRequest { param($Uri, $Headers) [pscustomobject]@{ StatusCode = 200 } } `
    -CommandResolver { param($Name) [pscustomobject]@{ Source = 'fake-claude.exe' } } `
    -ClaudeInvoker { param($Command, $Arguments, $State) $script:gateInvocations++; $State.ExitCode = 0 } 3>&1 | Out-Null
Assert-Equal 1 $script:gateInvocations 'ending auth must launch claude'

# --version は判定を通らない
$script:gateReads = 0
Invoke-Claudex -Arguments @('--version') `
    -AuthStatusReader { $script:gateReads++; New-TestAuthStatus } `
    -CommandResolver { param($Name) [pscustomobject]@{ Source = 'fake-claude.exe' } } `
    -ClaudeInvoker { param($Command, $Arguments, $State) $State.ExitCode = 0 }
Assert-Equal 0 $script:gateReads 'version must not read auth status'

# --help も判定を通らない
$script:gateReads = 0
Invoke-Claudex -Arguments @('--help') -AuthStatusReader { $script:gateReads++; New-TestAuthStatus } | Out-Null
Assert-Equal 0 $script:gateReads 'help must not read auth status'

# メッセージに資格情報を含めない
$gateFailure = $null
try {
    Invoke-Claudex -Arguments @('--print', 'ok') `
        -TokenReader { param($Path) 'do-not-print-this' } `
        -AuthStatusReader { New-TestAuthStatus -ProxyState 'Expired' } `
        -CommandResolver { param($Name) [pscustomobject]@{ Source = 'fake-claude.exe' } } `
        -ClaudeInvoker { param($Command, $Arguments, $State) }
}
catch { $gateFailure = "$_" }
if ($gateFailure -match 'do-not-print-this') { throw 'auth gate leaked token' }

Write-Host 'Claudex runtime tests PASSED'

$InstallScript = Join-Path $RepoRoot 'scripts\claudex\install.ps1'
. $InstallScript

$installSource = Get-Content -Raw -LiteralPath $InstallScript
if (-not $installSource.Contains('Install-Claudex -ProxyExecutable $ProxyExecutable -ProxyConfig $ProxyConfig -ProfilePath $ProfilePath -SecretPath $SecretPath -ProxyApiKey $ProxyApiKey -ReplaceSecret:$ReplaceSecret')) {
    throw 'install entrypoint must forward script defaults explicitly'
}

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("claudex-test-" + [guid]::NewGuid().ToString('N'))
$ProfilePath = Join-Path $TempRoot 'Microsoft.PowerShell_profile.ps1'
$SecretPath = Join-Path $TempRoot 'secrets.psd1'
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
try {
    $secure = ConvertTo-SecureString 'test-local-key' -AsPlainText -Force
    $script:aclCount = 0
    Set-ClaudexSecretFile -Path $SecretPath -ProxyApiKey $secure -AclSetter { param($Directory) $script:aclCount++ } | Out-Null
    Assert-Equal 1 $script:aclCount 'secret ACL application count'
    $data = Import-PowerShellDataFile -LiteralPath $SecretPath
    if ($data.ProxyApiKey -eq 'test-local-key') { throw 'secret file stored plaintext' }
    $decrypted = [System.Net.NetworkCredential]::new('', (ConvertTo-SecureString $data.ProxyApiKey)).Password
    Assert-Equal 'test-local-key' $decrypted 'DPAPI round trip'

    [System.IO.File]::WriteAllText($ProfilePath, "function existing { 'keep' }`r`n", [System.Text.UTF8Encoding]::new($false))
    $originalProfilePrefix = Get-Content -Raw -LiteralPath $ProfilePath
    $changed = Set-ClaudexProfileBlock -ProfilePath $ProfilePath -ClaudexScript $ClaudexScript
    if (-not $changed) { throw 'first profile install must change file' }
    $changed = Set-ClaudexProfileBlock -ProfilePath $ProfilePath -ClaudexScript $ClaudexScript
    if ($changed) { throw 'second profile install must be idempotent' }
    $profileText = Get-Content -Raw -LiteralPath $ProfilePath
    Assert-Equal 1 ([regex]::Matches($profileText, '# BEGIN agent-config claudex').Count) 'profile marker count'
    if (-not $profileText.StartsWith($originalProfilePrefix)) { throw 'profile install changed existing user content' }

    $definition = New-ClaudexTaskDefinition `
        -ProxyExecutable 'E:\tools\cli-proxy-api.exe' `
        -ProxyConfig 'E:\tools\config.yaml' `
        -UserId 'DOMAIN\user'
    Assert-Equal 'AgentConfig-CLIProxyAPI' $definition.TaskName 'task name'
    Assert-Equal 'IgnoreNew' $definition.MultipleInstances 'task concurrency'
    Assert-Equal 'E:\tools' $definition.WorkingDirectory 'task working directory'
    Assert-Equal 'E:\tools\config.yaml' $definition.ConfigPath 'task pins config path'
    if (-not $definition.AllowStartIfOnBatteries) { throw 'task must start on battery power' }
    if (-not $definition.DontStopIfGoingOnBatteries) { throw 'task must stay running on battery power' }

    Assert-Throws {
        Register-ClaudexTask -Definition $definition -TaskGetter {
            param($Name) [pscustomobject]@{ Description = 'owned by someone else' }
        }
    } 'already owned by another configuration' 'foreign install task guard'

    [System.IO.File]::WriteAllText($ProfilePath, "# BEGIN agent-config claudex`nconflict`n", [System.Text.UTF8Encoding]::new($false))
    Assert-Throws {
        Set-ClaudexProfileBlock -ProfilePath $ProfilePath -ClaudexScript $ClaudexScript
    } 'marker conflict' 'profile marker conflict'
}
finally {
    if (Test-Path -LiteralPath $TempRoot) { & trash $TempRoot }
}

Write-Host 'Claudex installer tests PASSED'

$UninstallScript = Join-Path $RepoRoot 'scripts\claudex\uninstall.ps1'
. $UninstallScript

$uninstallSource = Get-Content -Raw -LiteralPath $UninstallScript
if (-not $uninstallSource.Contains('Uninstall-Claudex -ProfilePath $ProfilePath -TaskName $TaskName')) {
    throw 'uninstall entrypoint must forward script defaults explicitly'
}

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("claudex-uninstall-test-" + [guid]::NewGuid().ToString('N'))
$ProfilePath = Join-Path $TempRoot 'Microsoft.PowerShell_profile.ps1'
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
try {
    $originalContent = "function existing { 'keep' }`r`n"
    [System.IO.File]::WriteAllText($ProfilePath, $originalContent, [System.Text.UTF8Encoding]::new($false))
    Set-ClaudexProfileBlock -ProfilePath $ProfilePath -ClaudexScript $ClaudexScript | Out-Null

    $changed = Remove-ClaudexProfileBlock -ProfilePath $ProfilePath
    if (-not $changed) { throw 'uninstall must remove managed block' }
    $remaining = Get-Content -Raw -LiteralPath $ProfilePath
    Assert-Equal $originalContent $remaining 'uninstall profile round trip'
    $changed = Remove-ClaudexProfileBlock -ProfilePath $ProfilePath
    if ($changed) { throw 'second uninstall must be idempotent' }

    [System.IO.File]::WriteAllText($ProfilePath, "# BEGIN agent-config claudex`n", [System.Text.UTF8Encoding]::new($false))
    Assert-Throws { Remove-ClaudexProfileBlock -ProfilePath $ProfilePath } 'marker conflict' 'uninstall marker conflict'

    Assert-Throws {
        Unregister-ClaudexTask -TaskName 'AgentConfig-CLIProxyAPI' -TaskGetter {
            param($Name) [pscustomobject]@{ Description = 'owned by someone else' }
        } -TaskRemover { param($Name) }
    } 'owned by another configuration' 'foreign task guard'

    $script:removedTaskCount = 0
    $removed = Unregister-ClaudexTask -TaskName 'AgentConfig-CLIProxyAPI' -TaskGetter {
        param($Name) [pscustomobject]@{ Description = 'Managed by agent-config claudex' }
    } -TaskRemover { param($Name) $script:removedTaskCount++ }
    if (-not $removed) { throw 'managed task must be removed' }
    Assert-Equal 1 $script:removedTaskCount 'managed task removal count'
}
finally {
    if (Test-Path -LiteralPath $TempRoot) { & trash $TempRoot }
}

Write-Host 'Claudex uninstaller tests PASSED'

$ReadmePath = Join-Path $RepoRoot 'docs\claude\README.md'
$readme = Get-Content -Raw -LiteralPath $ReadmePath
foreach ($requiredText in @(
    '## claudex',
    'scripts/claudex/install.ps1',
    'claudex --model terra --effort high',
    "claudex '--' --model terra",
    'AgentConfig-CLIProxyAPI',
    'scripts/claudex/uninstall.ps1'
)) {
    if ($readme -notmatch [regex]::Escape($requiredText)) {
        throw "Claude README must contain [$requiredText]"
    }
}

$ScriptsReadmePath = Join-Path $RepoRoot 'docs\scripts\README.md'
$scriptsReadme = Get-Content -Raw -LiteralPath $ScriptsReadmePath
foreach ($requiredText in @('scripts/claudex/', 'tests/Claudex.Tests.ps1', 'scripts/claudex/relogin.ps1', 'scripts/lib/ClaudexAuth.psm1')) {
    if ($scriptsReadme -notmatch [regex]::Escape($requiredText)) {
        throw "Scripts README must contain [$requiredText]"
    }
}

$sourceText = Get-Content -Raw -LiteralPath $ClaudexScript
foreach ($forbidden in @('dangerously-skip-permissions', 'CLAUDE_CONFIG_DIR', 'settings.json')) {
    if ($sourceText -match [regex]::Escape($forbidden)) { throw "claudex source must not contain [$forbidden]" }
}

$ReloginScript = Join-Path $RepoRoot 'scripts\claudex\relogin.ps1'
. $ReloginScript

$script:proxyLogins = 0
$script:codexLogins = 0
$script:capturedExecutable = $null

$reloginStatus = [pscustomobject]@{
    Proxy    = [pscustomobject]@{ Source = 'CLIProxyAPI'; State = 'Expired'; Deadline = $null }
    CodexCli = [pscustomobject]@{ Source = 'CodexCLI'; State = 'Expired'; Deadline = $null }
}

# エントリポイントのOut-Nullを通しても状態を表示する
$entrypointReport = @(& {
    Invoke-ClaudexRelogin -ProxyOnly `
        -StatusReader { $reloginStatus } `
        -PathResolver { [pscustomobject]@{ Executable = 'proxy.exe'; Config = 'config.yaml' } } `
        -ProxyLogin { param($Executable, $Config) } | Out-Null
} 6>&1)
if (($entrypointReport -join "`n") -notmatch 'CLIProxyAPI') { throw 'relogin entrypoint must show proxy status' }
if (($entrypointReport -join "`n") -notmatch 'CodexCLI') { throw 'relogin entrypoint must show Codex CLI status' }

Invoke-ClaudexRelogin `
    -StatusReader { $reloginStatus } `
    -PathResolver { [pscustomobject]@{ Executable = 'proxy.exe'; Config = 'config.yaml' } } `
    -ProxyLogin { param($Executable, $Config) $script:proxyLogins++; $script:capturedExecutable = $Executable } `
    -CodexLogin { $script:codexLogins++ } | Out-Null
Assert-Equal 1 $script:proxyLogins 'relogin proxy login count'
Assert-Equal 1 $script:codexLogins 'relogin codex login count'
Assert-Equal 'proxy.exe' $script:capturedExecutable 'relogin proxy executable'

# -ProxyOnly は Codex CLI を触らない
$script:proxyLogins = 0
$script:codexLogins = 0
Invoke-ClaudexRelogin -ProxyOnly `
    -StatusReader { $reloginStatus } `
    -PathResolver { [pscustomobject]@{ Executable = 'proxy.exe'; Config = 'config.yaml' } } `
    -ProxyLogin { param($Executable, $Config) $script:proxyLogins++ } `
    -CodexLogin { $script:codexLogins++ } | Out-Null
Assert-Equal 1 $script:proxyLogins 'proxy only proxy login count'
Assert-Equal 0 $script:codexLogins 'proxy only codex login count'

# -CodexOnly は CLIProxyAPI を触らない
$script:proxyLogins = 0
$script:codexLogins = 0
Invoke-ClaudexRelogin -CodexOnly `
    -StatusReader { $reloginStatus } `
    -PathResolver { throw 'must not resolve paths' } `
    -ProxyLogin { param($Executable, $Config) $script:proxyLogins++ } `
    -CodexLogin { $script:codexLogins++ } | Out-Null
Assert-Equal 0 $script:proxyLogins 'codex only proxy login count'
Assert-Equal 1 $script:codexLogins 'codex only codex login count'

# -CodexOnly は判定不能でも再ログインする
$script:codexLogins = 0
$unknownCodexStatus = [pscustomobject]@{
    Proxy    = [pscustomobject]@{ Source = 'CLIProxyAPI'; State = 'Healthy'; Deadline = $null }
    CodexCli = [pscustomobject]@{ Source = 'CodexCLI'; State = 'Unknown'; Deadline = $null }
}
Invoke-ClaudexRelogin -CodexOnly `
    -StatusReader { $unknownCodexStatus } `
    -PathResolver { throw 'must not resolve paths' } `
    -CodexLogin { $script:codexLogins++ } | Out-Null
Assert-Equal 1 $script:codexLogins 'codex only unknown login count'

# Codex CLI が健全なら再ログインしない
$script:codexLogins = 0
$healthyCodexStatus = [pscustomobject]@{
    Proxy    = [pscustomobject]@{ Source = 'CLIProxyAPI'; State = 'Expired'; Deadline = $null }
    CodexCli = [pscustomobject]@{ Source = 'CodexCLI'; State = 'Healthy'; Deadline = $null }
}
Invoke-ClaudexRelogin `
    -StatusReader { $healthyCodexStatus } `
    -PathResolver { [pscustomobject]@{ Executable = 'proxy.exe'; Config = 'config.yaml' } } `
    -ProxyLogin { param($Executable, $Config) } `
    -CodexLogin { $script:codexLogins++ } | Out-Null
Assert-Equal 0 $script:codexLogins 'healthy codex must not relogin'

# ネイティブCLIの非0終了を失敗として扱う
Assert-Throws {
    Invoke-ClaudexRelogin -ProxyOnly `
        -StatusReader { $reloginStatus } `
        -PathResolver { [pscustomobject]@{ Executable = 'proxy.exe'; Config = 'config.yaml' } } `
        -ProxyLogin { param($Executable, $Config) $global:LASTEXITCODE = 7 }
} 'CLIProxyAPI.*7' 'proxy login exit code'
Assert-Throws {
    Invoke-ClaudexRelogin -CodexOnly `
        -StatusReader { $reloginStatus } `
        -CodexLogin { $global:LASTEXITCODE = 9 }
} 'Codex CLI.*9' 'codex login exit code'

# 両方の指定は拒否する
Assert-Throws {
    Invoke-ClaudexRelogin -ProxyOnly -CodexOnly -StatusReader { $reloginStatus }
} '同時に指定できない' 'conflicting switches'

# パスを解決できなければ install を案内する
Assert-Throws {
    Invoke-ClaudexRelogin -StatusReader { $reloginStatus } -PathResolver { $null }
} 'install\.ps1' 'unresolved proxy paths'

Write-Host 'Claudex relogin tests PASSED'

Write-Host 'Claudex documentation contract PASSED'
