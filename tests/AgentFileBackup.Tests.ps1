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
$HookRoot = Join-Path $RepoRoot 'claude\hooks\agent-file-backup'

# Verify the hook is registered in settings.json.
$Settings = Get-Content -Raw (Join-Path $RepoRoot 'claude\settings.json') | ConvertFrom-Json
$EditorMatchers = @($Settings.hooks.PreToolUse | Where-Object { $_.matcher -eq 'Edit|Write|MultiEdit|NotebookEdit' })
Assert-Equal $EditorMatchers.Count 1 'one editor PreToolUse matcher should exist'
Assert-True ($EditorMatchers[0].hooks[0].command -like '*agent-file-backup/pre-tool-use.ps1*') 'hook should invoke pre-tool-use.ps1'

# Entry script: agent-neutral env var only, -Agent parameter, renamed response builder.
$EntryScript = Get-Content -Raw (Join-Path $HookRoot 'pre-tool-use.ps1')
Assert-True ($EntryScript -match 'AGENT_FILE_BACKUP_ROOT') 'entry should read AGENT_FILE_BACKUP_ROOT'
Assert-True ($EntryScript -notmatch 'CLAUDE_AGENT_FILE_BACKUP_ROOT') 'CLAUDE_ env var should be removed'
Assert-True ($EntryScript -match '\[string\]\$Agent') 'entry should accept -Agent parameter'
Assert-True ($EntryScript -match 'New-AgentFileBackupResponse') 'entry should use renamed response builder'
Assert-True ($EntryScript -notmatch 'New-ClaudePreToolUseResponse') 'entry should not use old builder name'

# Codex plugin must be a thin shell that invokes the shared entry script.
$CodexPluginRoot = Join-Path $RepoRoot 'codex\plugins\agent-file-backup'
Assert-True (-not (Test-Path (Join-Path $CodexPluginRoot 'scripts'))) 'codex plugin should have no scripts dir'
$CodexHooks = Get-Content -Raw (Join-Path $CodexPluginRoot 'hooks\hooks.json') | ConvertFrom-Json
$CodexCommand = $CodexHooks.hooks.PreToolUse[0].hooks[0].commandWindows
Assert-True ($CodexCommand -like '*claude\hooks\agent-file-backup\pre-tool-use.ps1*') 'codex hook should invoke shared entry'
Assert-True ($CodexCommand -like '*-Agent codex*') 'codex hook should pass -Agent codex'
$SharedEntryPath = [regex]::Match($CodexCommand, '-File "([^"]+)"').Groups[1].Value
Assert-True (Test-Path $SharedEntryPath) 'shared entry path in hooks.json should exist'
$CodexPlugin = Get-Content -Raw (Join-Path $CodexPluginRoot '.codex-plugin\plugin.json') | ConvertFrom-Json
Assert-Equal $CodexPlugin.version '0.2.0' 'plugin version should be bumped'

Import-Module (Join-Path $HookRoot 'AgentFileBackup.psm1') -Force
$env:CLAUDE_HOOK_LOG_ROOT = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-file-backup-test-logs-" + [guid]::NewGuid().ToString('N'))

# Target path extraction.
$Cwd = 'E:\work\sample'
$EditInput = [pscustomobject]@{
    tool_name = 'Edit'
    tool_input = [pscustomobject]@{ file_path = 'notes\draft.md' }
}
Assert-Equal @(Get-AgentFileBackupTargetPaths -HookInput $EditInput -WorkingDirectory $Cwd)[0] 'E:\work\sample\notes\draft.md' 'Edit relative path should resolve from cwd'

$WriteInput = [pscustomobject]@{
    tool_name = 'Write'
    tool_input = [pscustomobject]@{ file_path = 'E:\abs\file.txt' }
}
Assert-Equal @(Get-AgentFileBackupTargetPaths -HookInput $WriteInput -WorkingDirectory $Cwd)[0] 'E:\abs\file.txt' 'Write absolute path should be preserved'

$MultiEditInput = [pscustomobject]@{
    tool_name = 'MultiEdit'
    tool_input = [pscustomobject]@{ file_path = 'notes\multi.md' }
}
Assert-Equal @(Get-AgentFileBackupTargetPaths -HookInput $MultiEditInput -WorkingDirectory $Cwd)[0] 'E:\work\sample\notes\multi.md' 'MultiEdit should use file_path'

$NotebookInput = [pscustomobject]@{
    tool_name = 'NotebookEdit'
    tool_input = [pscustomobject]@{ notebook_path = 'nb\demo.ipynb' }
}
Assert-Equal @(Get-AgentFileBackupTargetPaths -HookInput $NotebookInput -WorkingDirectory $Cwd)[0] 'E:\work\sample\nb\demo.ipynb' 'NotebookEdit should use notebook_path'

# apply_patch: extract Update/Delete targets, resolve relative against cwd.
$PatchText = "*** Begin Patch`n*** Update File: notes\draft.md`n@@ -1 +1 @@`n*** Delete File: E:\abs\old.txt`n*** Add File: brand-new.txt`n*** End Patch"
$ApplyInput = [pscustomobject]@{
    tool_name = 'apply_patch'
    tool_input = [pscustomobject]@{ command = $PatchText }
}
$ApplyTargets = @(Get-AgentFileBackupTargetPaths -HookInput $ApplyInput -WorkingDirectory $Cwd)
Assert-Equal $ApplyTargets.Count 2 'apply_patch should extract Update and Delete targets only'
Assert-Equal $ApplyTargets[0] 'E:\work\sample\notes\draft.md' 'apply_patch relative path should resolve from cwd'
Assert-Equal $ApplyTargets[1] 'E:\abs\old.txt' 'apply_patch absolute path should be preserved'

# apply_patch: tool_input.patch fallback when command is absent.
$PatchFallbackInput = [pscustomobject]@{
    tool_name = 'apply_patch'
    tool_input = [pscustomobject]@{ patch = "*** Update File: a.txt`n" }
}
Assert-Equal @(Get-AgentFileBackupTargetPaths -HookInput $PatchFallbackInput -WorkingDirectory $Cwd)[0] 'E:\work\sample\a.txt' 'apply_patch should fall back to tool_input.patch'

# apply_patch: Add-only patch has no backup targets (allow, no throw).
$AddOnlyInput = [pscustomobject]@{
    tool_name = 'apply_patch'
    tool_input = [pscustomobject]@{ command = "*** Add File: new.txt`n" }
}
Assert-Equal @(Get-AgentFileBackupTargetPaths -HookInput $AddOnlyInput -WorkingDirectory $Cwd).Count 0 'Add-only patch should yield no targets'

# apply_patch: no extractable paths and no Add -> reject.
try {
    Get-AgentFileBackupTargetPaths -HookInput ([pscustomobject]@{ tool_name = 'apply_patch'; tool_input = [pscustomobject]@{ command = 'garbage' } }) -WorkingDirectory $Cwd
    throw 'garbage patch should fail'
}
catch {
    Assert-True ($_.Exception.Message -like 'Cannot extract target path*') 'garbage patch should be rejected'
}

# Response builder was renamed to an agent-neutral name.
Assert-True ($null -ne (Get-Command New-AgentFileBackupResponse -ErrorAction SilentlyContinue)) 'New-AgentFileBackupResponse should exist'
Assert-True ($null -eq (Get-Command New-ClaudePreToolUseResponse -ErrorAction SilentlyContinue)) 'New-ClaudePreToolUseResponse should be removed'

try {
    Get-AgentFileBackupTargetPaths -HookInput ([pscustomobject]@{ tool_name = 'Write'; tool_input = [pscustomobject]@{} }) -WorkingDirectory $Cwd
    throw 'missing path should fail'
}
catch {
    Assert-True ($_.Exception.Message -like 'Cannot extract target path*') 'missing path should be rejected'
}

# Mirrored directory naming (no per-session dir, no hash, no per-file dir).
Assert-Equal (Get-AgentFileBackupDirectory -Path 'E:\work\sample\notes\draft.md' -BackupRoot 'X:\br') 'X:\br\E\work\sample\notes' 'backup dir should mirror source parent dir with drive letter'

# Git detection and generation retention.
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-file-backup-test-" + [guid]::NewGuid().ToString('N'))
$Repo = Join-Path $TempRoot 'repo'
$Outside = Join-Path $TempRoot 'outside.txt'
$BackupRoot = Join-Path $TempRoot 'backups'
$TrashRoot = Join-Path $TempRoot 'trash'
New-Item -ItemType Directory -Force -Path $Repo, $TrashRoot | Out-Null
try {
    git -C $Repo init --quiet
    git -C $Repo config core.autocrlf false

    $Tracked = Join-Path $Repo 'tracked.txt'
    $Untracked = Join-Path $Repo 'untracked.txt'
    $Ignored = Join-Path $Repo 'ignored.txt'
    Set-Content -LiteralPath $Tracked -Value 'tracked'
    Set-Content -LiteralPath $Untracked -Value 'untracked'
    Set-Content -LiteralPath $Ignored -Value 'ignored'
    Set-Content -LiteralPath $Outside -Value 'outside'
    Set-Content -LiteralPath (Join-Path $Repo '.gitignore') -Value "ignored.txt`n"
    git -C $Repo add tracked.txt .gitignore 2>$null
    git -C $Repo -c user.name=test -c user.email=test@example.com commit -m init --quiet 2>$null

    Assert-Equal (Test-GitTrackedFile -Path $Tracked) $true 'tracked file should be detected'
    Assert-Equal (Test-GitTrackedFile -Path $Untracked) $false 'untracked file should be detected'
    Assert-Equal (Test-GitTrackedFile -Path $Ignored) $false 'ignored file should be detected'
    Assert-Equal (Test-GitTrackedFile -Path $Outside) $false 'outside file should be untracked'

    $TrashAction = {
        param($Path)
        Move-Item -LiteralPath $Path -Destination (Join-Path $TrashRoot (Split-Path -Leaf $Path))
    }.GetNewClosure()

    # Sibling whose name ends with "_untracked.txt": retention pruning of
    # untracked.txt must not cross-match and delete this file's backup.
    $Sibling = Join-Path $Repo 'x_untracked.txt'
    Set-Content -LiteralPath $Sibling -Value 'sibling'
    Backup-AgentFile -Path $Sibling -BackupRoot $BackupRoot -TrashAction $TrashAction | Out-Null
    Start-Sleep -Milliseconds 2

    1..4 | ForEach-Object {
        Set-Content -LiteralPath $Untracked -Value "version-$_"
        Backup-AgentFile -Path $Untracked -BackupRoot $BackupRoot -TrashAction $TrashAction | Out-Null
        Start-Sleep -Milliseconds 2
    }

    $FileBackupDirectory = Get-AgentFileBackupDirectory -Path $Untracked -BackupRoot $BackupRoot
    $AllBackups = @(Get-ChildItem $FileBackupDirectory -File)
    Assert-True (($AllBackups | Where-Object Name -notmatch '^\d{8}-\d{6}-\d{3}-\d{3}_').Count -eq 0) 'backup names should always include sortable sequence'
    $RemainingBackups = @($AllBackups | Where-Object Name -match '^\d{8}-\d{6}-\d{3}-\d{3}_untracked\.txt$')
    Assert-Equal $RemainingBackups.Count 3 'only three generations should remain'
    $SiblingBackups = @($AllBackups | Where-Object Name -match '^\d{8}-\d{6}-\d{3}-\d{3}_x_untracked\.txt$')
    Assert-Equal $SiblingBackups.Count 1 'sibling backups must survive pruning of a similarly named file'
    Assert-Equal @(Get-ChildItem $TrashRoot -File).Count 1 'fourth generation should move oldest backup to trash'

    Backup-AgentFile -Path $Outside -BackupRoot $BackupRoot -TrashAction $TrashAction | Out-Null
    Backup-AgentFile -Path $Outside -BackupRoot $BackupRoot -TrashAction $TrashAction | Out-Null
    $OutsideBackupDirectory = Get-AgentFileBackupDirectory -Path $Outside -BackupRoot $BackupRoot
    Assert-Equal @(Get-ChildItem $OutsideBackupDirectory -File).Count 2 'same content should be backed up every time'
}
finally {
    if (Test-Path -LiteralPath $TempRoot) {
        $TestTrashRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'agent-file-backup-test-trash'
        New-Item -ItemType Directory -Force -Path $TestTrashRoot | Out-Null
        Move-Item -LiteralPath $TempRoot -Destination (Join-Path $TestTrashRoot (Split-Path -Leaf $TempRoot))
    }
}

# Response JSON.
$Allow = New-AgentFileBackupResponse | ConvertFrom-Json
Assert-Equal $Allow.hookSpecificOutput.hookEventName 'PreToolUse' 'allow response should name event'
Assert-True ($null -eq $Allow.hookSpecificOutput.permissionDecision) 'allow response should omit decision'

$Deny = New-AgentFileBackupResponse -DenyReason 'copy failed' | ConvertFrom-Json
Assert-Equal $Deny.hookSpecificOutput.permissionDecision 'deny' 'failure should deny edit'
Assert-Equal $Deny.hookSpecificOutput.permissionDecisionReason 'Agent file backup failed: copy failed' 'deny should explain failure'

# End-to-end: Invoke-AgentFileBackupHook and pre-tool-use.ps1.
$HookTempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-file-backup-hook-test-" + [guid]::NewGuid().ToString('N'))
$HookRepo = Join-Path $HookTempRoot 'repo'
$HookBackupRoot = Join-Path $HookTempRoot 'backups'
New-Item -ItemType Directory -Force -Path $HookRepo | Out-Null
try {
    git -C $HookRepo init --quiet
    git -C $HookRepo config core.autocrlf false
    $HookTracked = Join-Path $HookRepo 'tracked.txt'
    $HookUntracked = Join-Path $HookRepo 'untracked.txt'
    Set-Content -LiteralPath $HookTracked -Value 'tracked'
    Set-Content -LiteralPath $HookUntracked -Value 'untracked'
    git -C $HookRepo add tracked.txt
    git -C $HookRepo -c user.name=test -c user.email=test@example.com commit -m init --quiet

    $HookInput = [pscustomobject]@{
        cwd = $HookRepo
        tool_name = 'Edit'
        tool_input = [pscustomobject]@{ file_path = $HookUntracked }
    }
    $HookResult = Invoke-AgentFileBackupHook -HookInput $HookInput -BackupRoot $HookBackupRoot | ConvertFrom-Json
    Assert-True ($null -eq $HookResult.hookSpecificOutput.permissionDecision) 'successful backup should allow edit'
    $HookFileBackupDirectory = Get-AgentFileBackupDirectory -Path $HookUntracked -BackupRoot $HookBackupRoot
    Assert-Equal @(Get-ChildItem $HookFileBackupDirectory -File).Count 1 'hook should create backup'

    # Agent name is recorded in the success log (default 'claude').
    $HookLogFile = Join-Path $env:CLAUDE_HOOK_LOG_ROOT ((Get-Date).ToString('yyyy-MM-dd') + '.jsonl')
    $LastLog = (Get-Content $HookLogFile | Select-Object -Last 1) | ConvertFrom-Json
    Assert-Equal $LastLog.data.agent 'claude' 'default agent should be claude'

    # Explicit -Agent codex is recorded.
    Set-Content -LiteralPath $HookUntracked -Value 'again'
    Invoke-AgentFileBackupHook -HookInput $HookInput -BackupRoot $HookBackupRoot -Agent 'codex' | Out-Null
    $LastLog = (Get-Content $HookLogFile | Select-Object -Last 1) | ConvertFrom-Json
    Assert-Equal $LastLog.data.agent 'codex' 'explicit agent should be recorded'

    $BeforeTrackedCount = @(Get-ChildItem $HookBackupRoot -Recurse -File).Count
    $TrackedInput = [pscustomobject]@{
        cwd = $HookRepo
        tool_name = 'Edit'
        tool_input = [pscustomobject]@{ file_path = $HookTracked }
    }
    Invoke-AgentFileBackupHook -HookInput $TrackedInput -BackupRoot $HookBackupRoot | Out-Null
    Assert-Equal @(Get-ChildItem $HookBackupRoot -Recurse -File).Count $BeforeTrackedCount 'tracked file should not be backed up'

    $NewInput = [pscustomobject]@{
        cwd = $HookRepo
        tool_name = 'Write'
        tool_input = [pscustomobject]@{ file_path = (Join-Path $HookRepo 'new.txt') }
    }
    Invoke-AgentFileBackupHook -HookInput $NewInput -BackupRoot $HookBackupRoot | Out-Null
    Assert-Equal @(Get-ChildItem $HookBackupRoot -Recurse -File).Count $BeforeTrackedCount 'new file should not be backed up'

    $BackupInsideRoot = Join-Path $HookBackupRoot 'manual.txt'
    Set-Content -LiteralPath $BackupInsideRoot -Value 'backup content'
    $InsideRootInput = [pscustomobject]@{
        cwd = $HookBackupRoot
        tool_name = 'Edit'
        tool_input = [pscustomobject]@{ file_path = $BackupInsideRoot }
    }
    $BeforeInsideRootCount = @(Get-ChildItem $HookBackupRoot -Recurse -File).Count
    Invoke-AgentFileBackupHook -HookInput $InsideRootInput -BackupRoot $HookBackupRoot | Out-Null
    Assert-Equal @(Get-ChildItem $HookBackupRoot -Recurse -File).Count $BeforeInsideRootCount 'backup root should not recursively back itself up'

    $BrokenBackupRoot = Join-Path $HookTempRoot 'backup-root-is-file'
    Set-Content -LiteralPath $BrokenBackupRoot -Value 'not a directory'
    $BackupFailed = $false
    try {
        Invoke-AgentFileBackupHook -HookInput $HookInput -BackupRoot $BrokenBackupRoot
    }
    catch {
        $BackupFailed = $true
    }
    Assert-True $BackupFailed 'backup failure should propagate'

    $PruneFailureRoot = Join-Path $HookTempRoot 'prune-failure'
    $FailingTrashAction = { param($Path) throw "trash failed: $Path" }
    $PruneWarnings = @()
    1..4 | ForEach-Object {
        Backup-AgentFile -Path $HookUntracked -BackupRoot $PruneFailureRoot -TrashAction $FailingTrashAction -WarningAction SilentlyContinue -WarningVariable +PruneWarnings | Out-Null
    }
    $PruneFailureDirectory = Get-AgentFileBackupDirectory -Path $HookUntracked -BackupRoot $PruneFailureRoot
    Assert-Equal @(Get-ChildItem $PruneFailureDirectory -File).Count 4 'prune failure should preserve backups and allow operation'
    Assert-True ($PruneWarnings.Count -gt 0) 'prune failure should emit warning'

    $HookScript = Join-Path $HookRoot 'pre-tool-use.ps1'

    $env:AGENT_FILE_BACKUP_ROOT = $HookBackupRoot
    $HookJson = @{
        cwd = $HookRepo
        tool_name = 'Edit'
        tool_input = @{ file_path = $HookUntracked }
    } | ConvertTo-Json -Compress
    $HookOutputLines = @($HookJson | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $HookScript)
    Assert-Equal $HookOutputLines.Count 1 'hook process should write one JSON line'
    $HookOutput = $HookOutputLines[0] | ConvertFrom-Json
    Assert-True ($null -eq $HookOutput.hookSpecificOutput.permissionDecision) 'successful hook process should allow edit'

    # Regression: Claude Code spawns the hook without a console and sends the
    # JSON as UTF-8 bytes; consoleless PS 5.1 falls back to the ANSI codepage
    # (CP932) for stdin, which corrupts Japanese text and can break JSON
    # parsing into a fail-closed deny. Raw bytes into a CreateNoWindow
    # process reproduce that environment regardless of the test console's
    # codepage (a plain pipe does not: a 65001 console masks the bug). The
    # JSON is built by hand so the Japanese stays as raw characters, and the
    # characters come from codepoints to keep this file ASCII-only.
    $JapaneseText = -join [char[]]@(0x65E5, 0x672C, 0x8A9E)
    $JapaneseJson = '{"cwd":"' + $HookRepo.Replace('\', '\\') +
        '","tool_name":"Edit","tool_input":{"file_path":"' + $HookUntracked.Replace('\', '\\') +
        '","old_string":"' + $JapaneseText + '"}}'
    $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
    $ProcessInfo.FileName = 'powershell.exe'
    $ProcessInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $HookScript + '"'
    $ProcessInfo.RedirectStandardInput = $true
    $ProcessInfo.RedirectStandardOutput = $true
    $ProcessInfo.UseShellExecute = $false
    $ProcessInfo.CreateNoWindow = $true
    $HookProcess = [System.Diagnostics.Process]::Start($ProcessInfo)
    $JsonBytes = [System.Text.Encoding]::UTF8.GetBytes($JapaneseJson)
    $HookProcess.StandardInput.BaseStream.Write($JsonBytes, 0, $JsonBytes.Length)
    $HookProcess.StandardInput.Close()
    $JapaneseOutput = $HookProcess.StandardOutput.ReadToEnd() | ConvertFrom-Json
    $HookProcess.WaitForExit()
    Assert-True ($null -eq $JapaneseOutput.hookSpecificOutput.permissionDecision) 'UTF-8 Japanese payload should not be corrupted into a deny'

    $BadHookJson = '{"cwd":"E:\\work","tool_name":"Write","tool_input":{}}'
    $BadOutput = $BadHookJson | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $HookScript | ConvertFrom-Json
    Assert-Equal $BadOutput.hookSpecificOutput.permissionDecision 'deny' 'unextractable target should deny edit'

    $env:AGENT_FILE_BACKUP_ROOT = $BrokenBackupRoot
    $BackupFailureOutput = $HookJson | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $HookScript | ConvertFrom-Json
    Assert-Equal $BackupFailureOutput.hookSpecificOutput.permissionDecision 'deny' 'backup failure should deny edit'
}
finally {
    $env:AGENT_FILE_BACKUP_ROOT = $null
    if (Test-Path -LiteralPath $env:CLAUDE_HOOK_LOG_ROOT) {
        $LogTrashRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'agent-file-backup-test-trash'
        New-Item -ItemType Directory -Force -Path $LogTrashRoot | Out-Null
        Move-Item -LiteralPath $env:CLAUDE_HOOK_LOG_ROOT -Destination (Join-Path $LogTrashRoot (Split-Path -Leaf $env:CLAUDE_HOOK_LOG_ROOT))
    }
    $env:CLAUDE_HOOK_LOG_ROOT = $null
    if (Test-Path -LiteralPath $HookTempRoot) {
        $TestTrashRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'agent-file-backup-test-trash'
        New-Item -ItemType Directory -Force -Path $TestTrashRoot | Out-Null
        Move-Item -LiteralPath $HookTempRoot -Destination (Join-Path $TestTrashRoot (Split-Path -Leaf $HookTempRoot))
    }
}

Write-Output 'AgentFileBackup.Tests.ps1: ALL PASSED'
