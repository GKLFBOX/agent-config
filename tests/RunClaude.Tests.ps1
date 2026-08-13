$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Script = Join-Path $RepoRoot 'scripts\agents\run-claude.ps1'
$BridgeModule = Join-Path $RepoRoot 'scripts\agents\agent-bridge\AgentBridge.psm1'

function New-FakeLauncher {
    return {
        param($Req, $Repo, [bool]$IsWrite)
        $result = [ordered]@{
            schema_version = 1; request_id = $Req.RequestId; status = 'completed'
            summary = 'ok'; changed_files = @(); verification = @(); findings = @()
            decisions = @(); risks = @(); review_focus = @(); artifacts = @()
        }
        $json = $result | ConvertTo-Json -Depth 10
        $tmp = Join-Path $Req.RequestDirectory 'result.json.tmp'
        $final = Join-Path $Req.RequestDirectory 'result.json'
        [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $final
    }
}

# 既定Launcherへモデルが渡ることを確認する。run-claude は第5引数がモデル。
function New-ModelCapturingLauncher {
    return {
        param($Req, $Repo, [bool]$IsImplementation, [string[]]$BashRules, [string]$Model)
        $script:capturedModel = $Model
        $result = [ordered]@{
            schema_version = 1; request_id = $Req.RequestId; status = 'completed'
            summary = 'ok'; changed_files = @(); verification = @(); findings = @()
            decisions = @(); risks = @(); review_focus = @(); artifacts = @()
        }
        $json = $result | ConvertTo-Json -Depth 10
        $tmp = Join-Path $Req.RequestDirectory 'result.json.tmp'
        $final = Join-Path $Req.RequestDirectory 'result.json'
        [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $final
    }
}

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("run-claude-test-" + [guid]::NewGuid().ToString('N'))
$Repository = Join-Path $TempRoot 'repository'
New-Item -ItemType Directory -Force -Path $Repository | Out-Null
try {
    $out = . $Script -Repository $Repository -TaskType investigation -Objective 'inspect a file' `
        -Model 'opus' -Launcher (New-FakeLauncher)
    $summary = ($out | Out-String).Trim() | ConvertFrom-Json
    if ($summary.status -ne 'completed') { throw "expected status completed, got [$($summary.status)]" }
    if ($summary.task_type -ne 'investigation') { throw 'expected task_type investigation' }
    Write-Host 'RunClaude investigation test PASSED'

    $out = . $Script -Repository $Repository -TaskType review -Objective 'review a file' `
        -Model 'opus' -ReviewScope @('src') -Launcher (New-FakeLauncher)
    $summary = ($out | Out-String).Trim() | ConvertFrom-Json
    if ($summary.task_type -ne 'review') { throw 'expected task_type review' }
    Write-Host 'RunClaude review test PASSED'

    $guardFailed = $false
    try {
        . $Script -Repository $Repository -TaskType implementation -Objective 'x' `
            -Model 'opus' -Launcher (New-FakeLauncher)
    }
    catch {
        $guardFailed = $true
        if ("$_" -notmatch 'requires -Write') { throw "unexpected guard error: $_" }
    }
    if (-not $guardFailed) { throw 'implementation without -Write should fail' }
    Write-Host 'RunClaude write-guard test PASSED'

    $invalidRuleFailed = $false
    try {
        . $Script -Repository $Repository -TaskType implementation -Write -Objective 'x' `
            -Model 'opus' -AllowedBashRules @('git status') -Launcher (New-FakeLauncher)
    }
    catch {
        $invalidRuleFailed = $true
        if ("$_" -notmatch 'Bash\(\.\.\.\)') { throw "unexpected Bash rule error: $_" }
    }
    if (-not $invalidRuleFailed) { throw 'unscoped Bash rule should fail' }

    $blockedRuleFailed = $false
    try {
        . $Script -Repository $Repository -TaskType implementation -Write -Objective 'x' `
            -Model 'opus' -AllowedBashRules @('Bash(claude *)') -Launcher (New-FakeLauncher)
    }
    catch {
        $blockedRuleFailed = $true
        if ("$_" -notmatch 'external agent CLI') { throw "unexpected blocked Bash rule error: $_" }
    }
    if (-not $blockedRuleFailed) { throw 'external agent Bash rule should fail' }

    $wrapperRuleFailed = $false
    try {
        . $Script -Repository $Repository -TaskType implementation -Write -Objective 'x' `
            -Model 'opus' -AllowedBashRules @('Bash(pwsh *)') -Launcher (New-FakeLauncher)
    }
    catch {
        $wrapperRuleFailed = $true
        if ("$_" -notmatch 'shell wrapper') { throw "unexpected shell wrapper error: $_" }
    }
    if (-not $wrapperRuleFailed) { throw 'shell wrapper Bash rule should fail' }

    $out = . $Script -Repository $Repository -TaskType implementation -Write -Objective 'x' `
        -Model 'opus' -AllowedBashRules @('Bash(git status *)') -Launcher (New-FakeLauncher)
    $summary = ($out | Out-String).Trim() | ConvertFrom-Json
    if ($summary.task_type -ne 'implementation') { throw 'scoped Bash rule should be accepted' }
    Write-Host 'RunClaude Bash-rule validation test PASSED'

    # 継承した claudex 系変数を子プロセスから落とす。無関係な変数は残す。
    $StartInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $StartInfo.UseShellExecute = $false
    $StartInfo.Environment['ANTHROPIC_BASE_URL'] = 'http://127.0.0.1:8317'
    $StartInfo.Environment['ANTHROPIC_DEFAULT_OPUS_MODEL'] = 'gpt-5.6-sol'
    $StartInfo.Environment['RUN_CLAUDE_KEEP_PROBE'] = 'keep'
    Remove-InheritedEnvironmentOverride -StartInfo $StartInfo -Name $ClaudexEnvironmentNames
    foreach ($Removed in @('ANTHROPIC_BASE_URL', 'ANTHROPIC_DEFAULT_OPUS_MODEL')) {
        if ($StartInfo.Environment.ContainsKey($Removed)) { throw "$Removed must not reach the delegated process" }
    }
    if (-not $StartInfo.Environment.ContainsKey('RUN_CLAUDE_KEEP_PROBE')) {
        throw 'unrelated environment variables must survive'
    }
    Write-Host 'RunClaude environment neutralization test PASSED'

    # モデルは呼び出し側が決める。空文字は受け付けない。
    $script:capturedModel = $null
    $out = . $Script -Repository $Repository -TaskType investigation -Objective 'inspect a file' `
        -Model 'opus' -Launcher (New-ModelCapturingLauncher)
    if ($script:capturedModel -ne 'opus') {
        throw "expected model opus to reach the launcher, got [$($script:capturedModel)]"
    }
    $emptyModelFailed = $false
    try {
        . $Script -Repository $Repository -TaskType investigation -Objective 'x' `
            -Model '' -Launcher (New-FakeLauncher)
    }
    catch {
        $emptyModelFailed = $true
        if ("$_" -notmatch 'Model') { throw "unexpected empty model error: $_" }
    }
    if (-not $emptyModelFailed) { throw 'empty -Model should fail' }
    Write-Host 'RunClaude model requirement test PASSED'

    # 実使用モデルの検証。純正 Anthropic 以外が答えたら失敗させる。
    Confirm-DelegatedClaudeModel -Envelope ('{"modelUsage":{"claude-opus-5":{"costUSD":0.1}}}' | ConvertFrom-Json)
    foreach ($Case in @(
            @{ Json = '{"modelUsage":{"gpt-5.6-sol":{}}}'; Pattern = 'non-Anthropic model' },
            @{ Json = '{"result":"ok"}'; Pattern = 'no modelUsage' },
            @{ Json = '{"modelUsage":{}}'; Pattern = 'no modelUsage' }
        )) {
        $modelGuardFailed = $false
        try { Confirm-DelegatedClaudeModel -Envelope ($Case.Json | ConvertFrom-Json) }
        catch {
            $modelGuardFailed = $true
            if ("$_" -notmatch $Case.Pattern) { throw "unexpected model guard error: $_" }
        }
        if (-not $modelGuardFailed) { throw "model guard should reject $($Case.Json)" }
    }
    Write-Host 'RunClaude model verification test PASSED'

    # ドリフト検出。claudex が立てる変数は、すべて run-claude.ps1 の無害化一覧に含まれていること。
    . (Join-Path $RepoRoot 'scripts\claudex\claudex.ps1')
    $envBefore = [Environment]::GetEnvironmentVariables('Process')
    $script:envInside = $null
    Invoke-WithClaudexEnvironment -Token 'drift-test-token' -Action {
        $script:envInside = [Environment]::GetEnvironmentVariables('Process')
    }
    $claudexSetNames = @()
    foreach ($Key in $script:envInside.Keys) {
        if ($envBefore[$Key] -ne $script:envInside[$Key]) { $claudexSetNames += [string]$Key }
    }
    if ($claudexSetNames.Count -eq 0) { throw 'claudex environment probe captured no change' }
    $uncovered = @($claudexSetNames | Where-Object { $_ -notin $ClaudexEnvironmentNames } | Sort-Object)
    if ($uncovered.Count -gt 0) {
        throw "claudex sets [$($uncovered -join ', ')] but run-claude.ps1 does not neutralize them"
    }
    Write-Host 'RunClaude claudex drift test PASSED'

    $scriptText = Get-Content -LiteralPath $Script -Raw -Encoding utf8
    foreach ($RequiredText in @('--json-schema', '--output-format', '--permission-mode', '--setting-sources', '--strict-mcp-config', '--disable-slash-commands', '--disallowedTools', 'No delegation', 'Task]::WaitAll', 'ANTHROPIC_BASE_URL', 'Remove-InheritedEnvironmentOverride', 'Confirm-DelegatedClaudeModel', '--model')) {
        if ($scriptText -notmatch [regex]::Escape($RequiredText)) { throw "run-claude.ps1 must contain [$RequiredText]" }
    }
    if ($scriptText -notmatch 'below artifacts/') { throw 'run-claude.ps1 must constrain artifact paths' }
    if ($scriptText -match 'bypassPermissions') { throw 'run-claude.ps1 must not bypass permissions' }
    if ($scriptText -notmatch 'Read,Glob,Grep') { throw 'read-only modes must expose only read tools' }
    if ($scriptText -notmatch "'Read,Glob,Grep,Edit,Write'") { throw 'implementation must omit Bash by default' }
    foreach ($BlockedCli in @('codex', 'claude', 'agy', 'copilot')) {
        if ($scriptText -notmatch [regex]::Escape("Bash($BlockedCli *)")) { throw "run-claude.ps1 must deny $BlockedCli via Bash" }
    }
    Write-Host 'RunClaude isolation test PASSED'

    $E2EScript = Join-Path $RepoRoot 'tests\RunClaude.E2E.Tests.ps1'
    if (-not (Test-Path -LiteralPath $E2EScript -PathType Leaf)) { throw 'RunClaude E2E test must exist' }
    $e2eText = Get-Content -LiteralPath $E2EScript -Raw -Encoding utf8
    if ($e2eText -notmatch 'RUN_CLAUDE_E2E') { throw 'RunClaude E2E test must be opt-in' }
    if ($e2eText -notmatch 'review') { throw 'RunClaude E2E test must cover review' }
    if ($e2eText -notmatch 'codex --version') { throw 'RunClaude E2E test must cover denied external CLI execution' }
    if ($e2eText -notmatch 'ANTHROPIC_BASE_URL') { throw 'RunClaude E2E test must cover inherited proxy environment' }
    Write-Host 'RunClaude E2E contract test PASSED'
}
finally {
    if (Test-Path -LiteralPath $TempRoot) {
        Import-Module $BridgeModule -Force
        Move-AgentBridgeDirectoryToRecycleBin -Path $TempRoot
    }
}
