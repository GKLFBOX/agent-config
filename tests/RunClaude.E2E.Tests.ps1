$ErrorActionPreference = 'Stop'

if ($env:RUN_CLAUDE_E2E -ne '1') {
    Write-Host 'RunClaude E2E tests SKIPPED (set RUN_CLAUDE_E2E=1)'
    exit 0
}

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Script = Join-Path $RepoRoot 'scripts\agents\run-claude.ps1'
$BridgeModule = Join-Path $RepoRoot 'scripts\agents\agent-bridge\AgentBridge.psm1'
$BridgeRoot = Join-Path $RepoRoot '.agent-bridge'
$ExistingRequestDirectories = @{}
if (Test-Path -LiteralPath $BridgeRoot) {
    Get-ChildItem -LiteralPath $BridgeRoot -Directory | ForEach-Object {
        $ExistingRequestDirectories[$_.FullName] = $true
    }
}

function Invoke-ClaudeStream {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$PermissionMode,
        [Parameter(Mandatory = $true)][string]$Tools,
        [Parameter(Mandatory = $true)][string]$AllowedTools,
        [string]$DisallowedTools = ''
    )

    $StartInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $StartInfo.FileName = 'claude'
    $StartInfo.WorkingDirectory = $RepoRoot
    $StartInfo.UseShellExecute = $false
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError = $true
    $Arguments = @(
        '--print', $Prompt,
        '--output-format', 'stream-json',
        '--verbose',
        '--permission-mode', $PermissionMode,
        '--tools', $Tools,
        '--allowedTools', $AllowedTools,
        '--disable-slash-commands',
        '--setting-sources', '',
        '--strict-mcp-config'
    )
    if ($DisallowedTools) {
        $Arguments += @('--disallowedTools', $DisallowedTools)
    }
    foreach ($Argument in $Arguments) { [void]$StartInfo.ArgumentList.Add($Argument) }

    $Process = [System.Diagnostics.Process]::Start($StartInfo)
    $StandardOutputTask = $Process.StandardOutput.ReadToEndAsync()
    $StandardErrorTask = $Process.StandardError.ReadToEndAsync()
    if (-not $Process.WaitForExit(120000)) {
        $Process.Kill($true)
        throw 'Claude CLI stream test timed out.'
    }
    $Tasks = [System.Threading.Tasks.Task[]]@($StandardOutputTask, $StandardErrorTask)
    if (-not [System.Threading.Tasks.Task]::WaitAll($Tasks, 10000)) {
        throw 'Claude CLI stream output timed out.'
    }
    if ($Process.ExitCode -ne 0) {
        throw "Claude CLI stream test failed: $($StandardErrorTask.Result)"
    }
    return @($StandardOutputTask.Result -split "`r?`n" | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
}

try {
    $reviewOutput = & $Script -Repository $RepoRoot -TaskType review `
        -Objective 'Review AGENTS.md for obvious Markdown syntax errors only. Return promptly.' `
        -Model 'opus' -ReviewScope @('AGENTS.md') -TimeoutSeconds 180
    $review = ($reviewOutput | Out-String).Trim() | ConvertFrom-Json
    if ($review.task_type -ne 'review' -or $review.status -ne 'completed') {
        throw 'review E2E should complete'
    }

    $readEvents = @(Invoke-ClaudeStream `
        -Prompt 'Reply OK without using tools.' `
        -PermissionMode plan `
        -Tools 'Read,Glob,Grep' `
        -AllowedTools 'Read,Glob,Grep')
    $ReadInit = $readEvents | Where-Object { $_.type -eq 'system' -and $_.subtype -eq 'init' } | Select-Object -First 1
    if ((@($ReadInit.tools | Sort-Object) -join ',') -ne 'Glob,Grep,Read') { throw 'read-only tools should be restricted' }
    if (@($ReadInit.slash_commands).Count -ne 0 -or @($ReadInit.skills).Count -ne 0) {
        throw 'slash commands and skills should be disabled'
    }
    if (@($ReadInit.mcp_servers).Count -ne 0 -or @($ReadInit.plugins).Count -ne 0) {
        throw 'MCP servers and plugins should be disabled'
    }

    $DeniedTools = 'Bash(codex *),Bash(claude *),Bash(agy *),Bash(copilot *)'
    $writeEvents = @(Invoke-ClaudeStream `
        -Prompt 'Use the Bash tool to run codex --version. Then report whether it was allowed.' `
        -PermissionMode acceptEdits `
        -Tools 'Read,Glob,Grep,Edit,Write,Bash' `
        -AllowedTools 'Read,Glob,Grep,Edit,Write,Bash(git status *)' `
        -DisallowedTools $DeniedTools)
    $WriteResult = $writeEvents | Where-Object { $_.type -eq 'result' } | Select-Object -Last 1
    $CodexDenial = @($WriteResult.permission_denials | Where-Object {
        $_.tool_name -eq 'Bash' -and $_.tool_input.command -eq 'codex --version'
    })
    if ($CodexDenial.Count -ne 1) { throw 'external agent CLI denial should be recorded' }

    # claudex セッションからの委託を再現する。到達不能なプロキシを親へ立てても、委託先は純正
    # Claude Code へ接続して完走しなければならない。
    $PoisonedNames = @('ANTHROPIC_BASE_URL', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_DEFAULT_OPUS_MODEL')
    $PoisonSnapshot = @{}
    foreach ($Name in $PoisonedNames) {
        $PoisonSnapshot[$Name] = [Environment]::GetEnvironmentVariable($Name, 'Process')
    }
    try {
        [Environment]::SetEnvironmentVariable('ANTHROPIC_BASE_URL', 'http://127.0.0.1:1', 'Process')
        [Environment]::SetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', 'poisoned-token', 'Process')
        [Environment]::SetEnvironmentVariable('ANTHROPIC_DEFAULT_OPUS_MODEL', 'gpt-5.6-sol', 'Process')
        $isolatedOutput = & $Script -Repository $RepoRoot -TaskType review `
            -Objective 'Review AGENTS.md for obvious Markdown syntax errors only. Return promptly.' `
            -Model 'opus' -ReviewScope @('AGENTS.md') -TimeoutSeconds 180
        $isolated = ($isolatedOutput | Out-String).Trim() | ConvertFrom-Json
        if ($isolated.status -ne 'completed') {
            throw 'delegation must complete despite an inherited proxy environment'
        }
    }
    finally {
        foreach ($Name in $PoisonedNames) {
            if ($null -eq $PoisonSnapshot[$Name]) {
                Remove-Item -LiteralPath "Env:$Name" -ErrorAction SilentlyContinue
            }
            else {
                [Environment]::SetEnvironmentVariable($Name, $PoisonSnapshot[$Name], 'Process')
            }
        }
    }
    Write-Host 'RunClaude real CLI E2E tests PASSED'
}
finally {
    Import-Module $BridgeModule -Force
    if (Test-Path -LiteralPath $BridgeRoot) {
        Get-ChildItem -LiteralPath $BridgeRoot -Directory | Where-Object {
            -not $ExistingRequestDirectories.ContainsKey($_.FullName)
        } | ForEach-Object {
            Move-AgentBridgeDirectoryToRecycleBin -Path $_.FullName
        }
    }
}
