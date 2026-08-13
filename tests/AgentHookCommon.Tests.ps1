$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param([object]$Actual, [object]$Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "$Message Actual=[$Actual] Expected=[$Expected]"
    }
}

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Import-Module (Join-Path $RepoRoot 'claude\hooks\lib\AgentHookCommon.psm1') -Force

# Default log root is agent-neutral (Codex writes here too).
$SavedLogRoot = $env:CLAUDE_HOOK_LOG_ROOT
$env:CLAUDE_HOOK_LOG_ROOT = $null
Assert-Equal (Get-AgentHookLogRoot) '<log-root>\hooks' 'default log root should be agent-neutral hooks dir'
$env:CLAUDE_HOOK_LOG_ROOT = $SavedLogRoot

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-hook-common-test-" + [guid]::NewGuid().ToString('N'))
$LogRoot = Join-Path $TempRoot 'logs'
$TrashRoot = Join-Path $TempRoot 'trash'
New-Item -ItemType Directory -Force -Path $LogRoot, $TrashRoot | Out-Null
$env:CLAUDE_HOOK_LOG_ROOT = $LogRoot
$TrashAction = { param($Path) Move-Item -LiteralPath $Path -Destination $TrashRoot }

try {
    # JSONL write with all fields.
    Write-AgentHookLog -Hook 'test-hook' -HookEvent 'PreToolUse' -SessionId 's1' -Level 'warn' -Message 'hello' -Data @{ command = 'rm x' } -TrashAction $TrashAction
    $LogFile = Join-Path $LogRoot ((Get-Date).ToString('yyyy-MM-dd') + '.jsonl')
    Assert-True (Test-Path -LiteralPath $LogFile) 'log file should exist'
    $RecordJson = Get-Content -LiteralPath $LogFile | Select-Object -Last 1
    $Record = $RecordJson | ConvertFrom-Json
    Assert-Equal $Record.hook 'test-hook' 'hook field'
    Assert-Equal $Record.event 'PreToolUse' 'event field'
    Assert-Equal $Record.session_id 's1' 'session_id field'
    Assert-Equal $Record.level 'warn' 'level field'
    Assert-Equal $Record.message 'hello' 'message field'
    Assert-Equal $Record.data.command 'rm x' 'data payload'
    Assert-True ($RecordJson -match '"ts":"\d{4}-\d{2}-\d{2}T') 'ts should be ISO8601'

    # Defaults: level info, empty session.
    Write-AgentHookLog -Hook 'test-hook' -HookEvent 'Stop' -TrashAction $TrashAction
    $Record2 = (Get-Content -LiteralPath $LogFile | Select-Object -Last 1) | ConvertFrom-Json
    Assert-Equal $Record2.level 'info' 'default level should be info'

    # Logging must never throw, even with a broken root.
    $env:CLAUDE_HOOK_LOG_ROOT = 'Q:\no\such\drive\logs'
    Write-AgentHookLog -Hook 'x' -HookEvent 'y'
    $env:CLAUDE_HOOK_LOG_ROOT = $LogRoot

    # Retention: old files go to trash, recent files stay.
    $OldFile = Join-Path $LogRoot 'old.jsonl'
    Set-Content -LiteralPath $OldFile -Value 'old'
    (Get-Item -LiteralPath $OldFile).LastWriteTime = (Get-Date).AddDays(-30)
    Remove-AgentHookOldFiles -Directory $LogRoot -RetentionDays 14 -TrashAction $TrashAction
    Assert-True (-not (Test-Path -LiteralPath $OldFile)) 'old log should be moved away'
    Assert-True (Test-Path -LiteralPath (Join-Path $TrashRoot 'old.jsonl')) 'old log should land in trash'
    Assert-True (Test-Path -LiteralPath $LogFile) 'recent log should remain'

    # Missing directory is a no-op.
    Remove-AgentHookOldFiles -Directory (Join-Path $TempRoot 'missing') -RetentionDays 14 -TrashAction $TrashAction

    # PreToolUse response JSON.
    $Allow = New-PreToolUseResponse | ConvertFrom-Json
    Assert-Equal $Allow.hookSpecificOutput.hookEventName 'PreToolUse' 'allow response event name'
    Assert-True ($null -eq $Allow.hookSpecificOutput.permissionDecision) 'allow response should carry no decision'
    $Deny = New-PreToolUseResponse -DenyReason 'nope' | ConvertFrom-Json
    Assert-Equal $Deny.hookSpecificOutput.permissionDecision 'deny' 'deny decision'
    Assert-Equal $Deny.hookSpecificOutput.permissionDecisionReason 'nope' 'deny reason'

    # Segment splitting.
    $Segments = @(Split-ShellCommandSegments -Command 'git add x && rm -rf y | grep z')
    Assert-Equal $Segments.Count 3 'three segments across && and |'
    Assert-Equal $Segments[0].Trim() 'git add x' 'first segment'
    Assert-Equal $Segments[1].Trim() 'rm -rf y' 'second segment'

    $Quoted = @(Split-ShellCommandSegments -Command 'echo "a;b" ; ls')
    Assert-Equal $Quoted.Count 2 'semicolon inside double quotes must not split'

    $SingleQuoted = @(Split-ShellCommandSegments -Command "echo 'a|b' && ls")
    Assert-Equal $SingleQuoted.Count 2 'pipe inside single quotes must not split'

    $Subshell = @(Split-ShellCommandSegments -Command 'echo $(rm x)')
    Assert-True (($Subshell | ForEach-Object { (Get-SegmentCommandToken -Segment $_) }) -contains 'rm') 'command substitution should surface rm as a token'

    Assert-Equal @(Split-ShellCommandSegments -Command '').Count 0 'empty command yields no segments'

    # Command token extraction.
    Assert-Equal (Get-SegmentCommandToken -Segment '  git rm --cached f ') 'git' 'first word wins'
    Assert-Equal (Get-SegmentCommandToken -Segment 'FOO=1 BAR=2 rm x') 'rm' 'env assignments are skipped'
    Assert-Equal (Get-SegmentCommandToken -Segment 'sudo rm -rf /tmp/x') 'rm' 'sudo is skipped'
    Assert-Equal (Get-SegmentCommandToken -Segment '"rm" x') 'rm' 'quotes around token are stripped'
    Assert-Equal (Get-SegmentCommandToken -Segment '   ') '' 'blank segment yields empty token'
}
finally {
    $env:CLAUDE_HOOK_LOG_ROOT = $null
    if (Test-Path -LiteralPath $TempRoot) {
        $TestTrashRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'agent-hook-common-test-trash'
        New-Item -ItemType Directory -Force -Path $TestTrashRoot | Out-Null
        Move-Item -LiteralPath $TempRoot -Destination (Join-Path $TestTrashRoot (Split-Path -Leaf $TempRoot))
    }
}

Write-Output 'AgentHookCommon.Tests.ps1: ALL PASSED'
