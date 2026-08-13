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

function Assert-Denied {
    param([string]$Command, [string]$ToolName, [string]$Message)
    $Reason = Test-DeleteCommand -Command $Command -ToolName $ToolName
    Assert-True ($null -ne $Reason) "$Message (should deny): $Command"
}

function Assert-Allowed {
    param([string]$Command, [string]$ToolName, [string]$Message)
    $Reason = Test-DeleteCommand -Command $Command -ToolName $ToolName
    Assert-True ($null -eq $Reason) "$Message (should allow, got [$Reason]): $Command"
}

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Import-Module (Join-Path $RepoRoot 'claude\hooks\delete-guard\DeleteGuard.psm1') -Force

$TempLogRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("delete-guard-test-logs-" + [guid]::NewGuid().ToString('N'))
$env:CLAUDE_HOOK_LOG_ROOT = $TempLogRoot

try {
    # --- Bash tool: deny ---
    Assert-Denied 'rm -rf build' 'Bash' 'plain rm'
    Assert-Denied 'rm file.txt' 'Bash' 'rm single file'
    Assert-Denied '/bin/rm -f x' 'Bash' 'path-prefixed rm'
    Assert-Denied 'cd a && rm b' 'Bash' 'rm after &&'
    Assert-Denied 'ls | xargs rm' 'Bash' 'xargs rm'
    Assert-Denied 'rmdir empty' 'Bash' 'rmdir'
    Assert-Denied 'unlink f' 'Bash' 'unlink'
    Assert-Denied 'shred -u secret.txt' 'Bash' 'shred'
    Assert-Denied 'find . -name "*.tmp" -delete' 'Bash' 'find -delete'
    Assert-Denied 'find . -type f -exec rm {} \;' 'Bash' 'find -exec rm'
    Assert-Denied 'bash -c "rm -rf x"' 'Bash' 'nested bash -c'
    Assert-Denied 'echo $(rm x)' 'Bash' 'command substitution'
    Assert-Denied 'FOO=1 rm x' 'Bash' 'env-prefixed rm'
    Assert-Denied 'powershell -Command "Remove-Item x"' 'Bash' 'nested powershell from bash'

    # --- Bash tool: allow ---
    Assert-Allowed 'git rm --cached file.txt' 'Bash' 'git rm'
    Assert-Allowed 'npm rm some-package' 'Bash' 'npm rm'
    Assert-Allowed 'echo rm' 'Bash' 'rm as argument'
    Assert-Allowed 'trash old-file.txt' 'Bash' 'sanctioned trash CLI'
    Assert-Allowed 'grep -r "rm -rf" docs' 'Bash' 'rm inside quoted argument'
    Assert-Allowed 'echo "rm x" > note.txt' 'Bash' 'quoted rm with redirect'
    Assert-Allowed 'ls -la' 'Bash' 'unrelated command'
    Assert-Allowed 'git commit -m "remove stale rm docs"' 'Bash' 'rm words in commit message'
    Assert-Allowed '' 'Bash' 'empty command'

    # --- PowerShell tool: deny ---
    Assert-Denied 'Remove-Item foo.txt' 'PowerShell' 'Remove-Item'
    Assert-Denied 'remove-item -Recurse -Force dir' 'PowerShell' 'case-insensitive Remove-Item'
    Assert-Denied 'ri x' 'PowerShell' 'ri alias'
    Assert-Denied 'del x' 'PowerShell' 'del alias'
    Assert-Denied 'erase x' 'PowerShell' 'erase alias'
    Assert-Denied 'rd dir' 'PowerShell' 'rd alias'
    Assert-Denied 'Get-ChildItem *.tmp | Remove-Item' 'PowerShell' 'pipeline Remove-Item'
    Assert-Denied '[System.IO.File]::Delete("x")' 'PowerShell' 'static File.Delete'
    Assert-Denied '[IO.Directory]::Delete("d", $true)' 'PowerShell' 'static Directory.Delete short form'
    Assert-Denied 'cmd /c del x' 'PowerShell' 'nested cmd del'
    Assert-Denied 'Remove-Item (Join-Path $a $b)' 'PowerShell' 'Remove-Item with expression arg'

    # --- PowerShell tool: allow ---
    Assert-Allowed 'git rm --cached file.txt' 'PowerShell' 'git rm from powershell'
    Assert-Allowed 'Get-Item x' 'PowerShell' 'unrelated cmdlet'
    Assert-Allowed 'Write-Output "Remove-Item is blocked"' 'PowerShell' 'Remove-Item inside string'
    Assert-Allowed 'Remove-ItemProperty -Path HKCU:\x -Name y' 'PowerShell' 'registry property is out of scope'
    Assert-Allowed 'trash old.txt' 'PowerShell' 'sanctioned trash CLI'

    # --- Invoke-DeleteGuardHook ---
    $DenyInput = [pscustomobject]@{
        session_id = 's1'
        tool_name  = 'Bash'
        tool_input = [pscustomobject]@{ command = 'rm -rf x' }
    }
    $DenyResponse = Invoke-DeleteGuardHook -HookInput $DenyInput | ConvertFrom-Json
    Assert-Equal $DenyResponse.hookSpecificOutput.permissionDecision 'deny' 'hook should deny rm'
    Assert-True ($DenyResponse.hookSpecificOutput.permissionDecisionReason -like '*trash*') 'deny reason should point to trash'

    $AllowInput = [pscustomobject]@{
        session_id = 's1'
        tool_name  = 'Bash'
        tool_input = [pscustomobject]@{ command = 'git rm --cached x' }
    }
    $AllowResponse = Invoke-DeleteGuardHook -HookInput $AllowInput | ConvertFrom-Json
    Assert-True ($null -eq $AllowResponse.hookSpecificOutput.permissionDecision) 'hook should allow git rm'

    # Non-shell tools pass through.
    $OtherInput = [pscustomobject]@{
        session_id = 's1'
        tool_name  = 'Edit'
        tool_input = [pscustomobject]@{ file_path = 'x.md' }
    }
    $OtherResponse = Invoke-DeleteGuardHook -HookInput $OtherInput | ConvertFrom-Json
    Assert-True ($null -eq $OtherResponse.hookSpecificOutput.permissionDecision) 'non-shell tool should pass'

    # Kill switch.
    $env:CLAUDE_DELETE_GUARD = 'off'
    $OffResponse = Invoke-DeleteGuardHook -HookInput $DenyInput | ConvertFrom-Json
    Assert-True ($null -eq $OffResponse.hookSpecificOutput.permissionDecision) 'kill switch should allow rm'
    $env:CLAUDE_DELETE_GUARD = $null

    # --- E2E: run the entry script exactly as Claude Code does ---
    $HookScript = Join-Path $RepoRoot 'claude\hooks\delete-guard\pre-tool-use.ps1'
    Assert-True (Test-Path -LiteralPath $HookScript) 'entry script should exist'

    $DenyJson = '{"session_id":"e2e","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'
    $DenyOut = $DenyJson | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $HookScript | ConvertFrom-Json
    Assert-Equal $DenyOut.hookSpecificOutput.permissionDecision 'deny' 'E2E rm should deny'

    $AllowJson = '{"session_id":"e2e","tool_name":"Bash","tool_input":{"command":"git rm --cached x"}}'
    $AllowOut = $AllowJson | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $HookScript | ConvertFrom-Json
    Assert-True ($null -eq $AllowOut.hookSpecificOutput.permissionDecision) 'E2E git rm should allow'

    # Fail-closed: broken input denies.
    $BadOut = 'not json' | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $HookScript | ConvertFrom-Json
    Assert-Equal $BadOut.hookSpecificOutput.permissionDecision 'deny' 'E2E broken input should deny (fail-closed)'

    # --- settings.json registration ---
    $Settings = Get-Content -Raw (Join-Path $RepoRoot 'claude\settings.json') | ConvertFrom-Json
    $ShellMatchers = @($Settings.hooks.PreToolUse | Where-Object { $_.matcher -eq 'Bash|PowerShell' })
    Assert-Equal $ShellMatchers.Count 1 'one Bash|PowerShell PreToolUse matcher should exist'
    Assert-True (@($ShellMatchers[0].hooks | Where-Object { $_.command -like '*delete-guard/pre-tool-use.ps1*' }).Count -eq 1) 'delete-guard should be registered'
}
finally {
    $env:CLAUDE_DELETE_GUARD = $null
    $env:CLAUDE_HOOK_LOG_ROOT = $null
    if (Test-Path -LiteralPath $TempLogRoot) {
        $TestTrashRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'delete-guard-test-trash'
        New-Item -ItemType Directory -Force -Path $TestTrashRoot | Out-Null
        Move-Item -LiteralPath $TempLogRoot -Destination (Join-Path $TestTrashRoot (Split-Path -Leaf $TempLogRoot))
    }
}

Write-Output 'DeleteGuard.Tests.ps1: ALL PASSED'
