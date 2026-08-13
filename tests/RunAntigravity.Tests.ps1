$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Script = Join-Path $RepoRoot 'scripts\agents\run-antigravity.ps1'

# 実 agy を使わず result.json を書くだけの偽 Launcher（BOM 無し UTF-8）
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

# 既定Launcherへモデルが渡ることを確認する。run-antigravity は第4引数がモデル。
function New-ModelCapturingLauncher {
    return {
        param($Req, $Repo, [bool]$IsWrite, [string]$Model)
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

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("run-agy-test-" + [guid]::NewGuid().ToString('N'))
$Repository = Join-Path $TempRoot 'repository'
New-Item -ItemType Directory -Force -Path $Repository | Out-Null
try {
    # investigation: dot-source で偽 Launcher を注入し、要約 JSON を捕捉
    $out = . $Script -Repository $Repository -TaskType investigation -Objective 'inspect a file' `
        -Model 'gemini-3.6-flash-medium' -Launcher (New-FakeLauncher)
    $summary = ($out | Out-String).Trim() | ConvertFrom-Json
    if ($summary.status -ne 'completed') { throw "expected status completed, got [$($summary.status)]" }
    if ($summary.task_type -ne 'investigation') { throw 'expected task_type investigation' }
    Write-Host 'RunAntigravity investigation test PASSED'

    # implementation は -Write 無しなら拒否されること（dot-source の throw を捕捉）
    $guardFailed = $false
    try {
        . $Script -Repository $Repository -TaskType implementation -Objective 'x' `
            -Model 'gemini-3.6-flash-medium' -Launcher (New-FakeLauncher)
    }
    catch {
        $guardFailed = $true
        if ("$_" -notmatch 'requires -Write') { throw "unexpected guard error: $_" }
    }
    if (-not $guardFailed) { throw 'implementation without -Write should fail' }
    Write-Host 'RunAntigravity write-guard test PASSED'

    # モデルは呼び出し側が決める。空文字は受け付けない。
    $script:capturedModel = $null
    $out = . $Script -Repository $Repository -TaskType investigation -Objective 'inspect a file' `
        -Model 'gemini-3.6-flash-medium' -Launcher (New-ModelCapturingLauncher)
    if ($script:capturedModel -ne 'gemini-3.6-flash-medium') {
        throw "expected the model to reach the launcher, got [$($script:capturedModel)]"
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
    Write-Host 'RunAntigravity model requirement test PASSED'

    # 既定 Launcher は実 agy 実行を伴いユニット化不可のため、スクリプト本文を静的検査する。
    # implementation 委託時のみ付く品質条項（karpathy 要旨）が焼き込まれていること。
    $scriptText = Get-Content -LiteralPath $Script -Raw -Encoding utf8
    if ($scriptText -notmatch 'Quality requirements') { throw 'run-antigravity.ps1 must contain "Quality requirements"' }
    if ($scriptText -notmatch 'smallest change') { throw 'run-antigravity.ps1 must contain "smallest change"' }
    if ($scriptText -notmatch '--model') { throw 'run-antigravity.ps1 must pass --model to agy' }
    if ($scriptText -notmatch 'agy failed \(exit') { throw 'run-antigravity.ps1 must surface agy failures' }
    if ($scriptText -match '1>\$null') { throw 'run-antigravity.ps1 must capture agy output instead of discarding it' }
    Write-Host 'RunAntigravity quality-clause test PASSED'
}
finally {
    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force
    }
}
