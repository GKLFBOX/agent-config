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
$GitAttributes = Get-Content -LiteralPath (Join-Path $RepoRoot '.gitattributes') -Raw -Encoding utf8
Assert-True ($GitAttributes -match '(?m)^\*\.md\s+text\s+eol=lf\s*$') 'Markdown files must use LF in the working tree'
Import-Module (Join-Path $RepoRoot 'claude\hooks\markdown-format\MarkdownFormat.psm1') -Force

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("markdown-format-test-" + [guid]::NewGuid().ToString('N'))
$StateRoot = Join-Path $TempRoot 'state'
$WorkRoot = Join-Path $TempRoot 'work'
New-Item -ItemType Directory -Force -Path $StateRoot, $WorkRoot | Out-Null
$env:CLAUDE_MD_FORMAT_STATE_ROOT = $StateRoot
$env:CLAUDE_HOOK_LOG_ROOT = Join-Path $TempRoot 'logs'
$env:CLAUDE_MD_FORMAT_EXCLUDE = $null

try {
    $MdFile = Join-Path $WorkRoot 'note.md'
    Set-Content -LiteralPath $MdFile -Value '# t'
    $TxtFile = Join-Path $WorkRoot 'plain.txt'
    Set-Content -LiteralPath $TxtFile -Value 't'

    # Queue append: md only.
    $MdInput = [pscustomobject]@{
        session_id = 'sess1'
        cwd        = $WorkRoot
        tool_name  = 'Edit'
        tool_input = [pscustomobject]@{ file_path = 'note.md' }
    }
    Assert-True (Add-MarkdownQueueEntry -HookInput $MdInput) 'md edit should queue'

    $TxtInput = [pscustomobject]@{
        session_id = 'sess1'
        cwd        = $WorkRoot
        tool_name  = 'Write'
        tool_input = [pscustomobject]@{ file_path = 'plain.txt' }
    }
    Assert-True (-not (Add-MarkdownQueueEntry -HookInput $TxtInput)) 'non-md should not queue'

    $BashInput = [pscustomobject]@{
        session_id = 'sess1'
        cwd        = $WorkRoot
        tool_name  = 'Bash'
        tool_input = [pscustomobject]@{ command = 'ls' }
    }
    Assert-True (-not (Add-MarkdownQueueEntry -HookInput $BashInput)) 'non-editor tool should not queue'

    $QueueFile = Get-MarkdownQueueFile -SessionId 'sess1'
    Assert-True (Test-Path -LiteralPath $QueueFile) 'queue file should exist'

    # Duplicate + missing-file filtering.
    [void](Add-MarkdownQueueEntry -HookInput $MdInput)
    $Missing = Join-Path $WorkRoot 'gone.md'
    [System.IO.File]::AppendAllText($QueueFile, $Missing + [Environment]::NewLine)
    $Entries = @(Get-MarkdownQueueEntries -QueueFile $QueueFile)
    Assert-Equal $Entries.Count 1 'dedupe and drop missing files'
    Assert-Equal $Entries[0] $MdFile 'queued path should be absolute'

    # Exclusions.
    Assert-True (Test-MarkdownFormatExcluded -Path 'C:\proj\node_modules\pkg\README.md') 'node_modules excluded'
    Assert-True (Test-MarkdownFormatExcluded -Path 'C:\proj\.git\COMMIT_EDITMSG.md') '.git excluded'
    Assert-True (-not (Test-MarkdownFormatExcluded -Path '<vault-root>\System\Templates\Project.md')) 'retired Templates path is not specially excluded'
    Assert-True (-not (Test-MarkdownFormatExcluded -Path '<vault-root>\Projects\Agent Config.md')) 'non-template vault note not excluded'
    Assert-True (-not (Test-MarkdownFormatExcluded -Path $MdFile)) 'normal file not excluded'
    $env:CLAUDE_MD_FORMAT_EXCLUDE = $WorkRoot
    Assert-True (Test-MarkdownFormatExcluded -Path $MdFile) 'env exclude root applies'
    Assert-Equal @(Get-MarkdownQueueEntries -QueueFile $QueueFile).Count 0 'excluded entries are dropped on read'
    $env:CLAUDE_MD_FORMAT_EXCLUDE = $null

    # git commit detection.
    Assert-True (Test-GitCommitCommand -Command 'git commit -m "x"') 'plain git commit'
    Assert-True (Test-GitCommitCommand -Command 'git -C E:\repo commit -am "y"') 'git -C commit'
    Assert-True (Test-GitCommitCommand -Command 'git add x && git commit -m "y"') 'commit after &&'
    Assert-True (-not (Test-GitCommitCommand -Command 'git log --oneline')) 'git log is not commit'
    Assert-True (-not (Test-GitCommitCommand -Command 'echo commit')) 'echo commit is not git'
    Assert-True (-not (Test-GitCommitCommand -Command 'git status')) 'git status is not commit'
    Assert-True (-not (Test-GitCommitCommand -Command '')) 'empty command'

    # --- Flush with an injected formatter (no real prettier needed) ---
    Set-Content -LiteralPath $QueueFile -Value ''
    $FlushMd1 = Join-Path $WorkRoot 'flush1.md'
    $FlushMd2 = Join-Path $WorkRoot 'flush2.md'
    Set-Content -LiteralPath $FlushMd1 -Value '# a'
    Set-Content -LiteralPath $FlushMd2 -Value '# b'
    [System.IO.File]::AppendAllText($QueueFile, $FlushMd1 + [Environment]::NewLine)
    [System.IO.File]::AppendAllText($QueueFile, $FlushMd2 + [Environment]::NewLine)

    $Script:FormattedFiles = @()
    $Recorder = { param($Path) $Script:FormattedFiles += $Path }
    $Result = @(Invoke-MarkdownFlush -SessionId 'sess1' -FormatterAction $Recorder)
    Assert-Equal $Result.Count 2 'both files should be formatted'
    Assert-Equal $Script:FormattedFiles.Count 2 'formatter should run per file'
    Assert-Equal @(Get-MarkdownQueueEntries -QueueFile $QueueFile).Count 0 'queue should be empty after flush'

    # Fail-open: one failing file does not abort the rest.
    [System.IO.File]::AppendAllText($QueueFile, $FlushMd1 + [Environment]::NewLine)
    [System.IO.File]::AppendAllText($QueueFile, $FlushMd2 + [Environment]::NewLine)
    $Failing = { param($Path) if ($Path -eq $FlushMd1) { throw 'boom' } }
    $PartialResult = @(Invoke-MarkdownFlush -SessionId 'sess1' -FormatterAction $Failing)
    Assert-Equal $PartialResult.Count 1 'failing file is skipped, the rest continue'
    Assert-Equal @(Get-MarkdownQueueEntries -QueueFile $QueueFile).Count 0 'queue is cleared even after failures'

    # Empty queue flush is a no-op.
    Assert-Equal @(Invoke-MarkdownFlush -SessionId 'no-such-session' -FormatterAction $Recorder).Count 0 'missing queue flushes nothing'

    # Prettier resolution falls back to a global command or npx.
    $Prettier = Resolve-PrettierCommand -FilePath $FlushMd1
    Assert-True ($null -ne $Prettier.Executable -and $Prettier.Executable.Length -gt 0) 'prettier executable resolved'
    Assert-True (@($Prettier.BaseArguments) -contains '--write') 'prettier args include --write'

    # --- E2E: entry scripts ---
    $PostScript = Join-Path $RepoRoot 'claude\hooks\markdown-format\post-tool-use.ps1'
    $StopScript = Join-Path $RepoRoot 'claude\hooks\markdown-format\stop.ps1'
    $PreScript = Join-Path $RepoRoot 'claude\hooks\markdown-format\pre-tool-use.ps1'
    Assert-True (Test-Path -LiteralPath $PostScript) 'post-tool-use.ps1 should exist'
    Assert-True (Test-Path -LiteralPath $StopScript) 'stop.ps1 should exist'
    Assert-True (Test-Path -LiteralPath $PreScript) 'pre-tool-use.ps1 should exist'

    # JSON escaping: each backslash becomes two (.NET substitution treats backslash literally).
    $E2eMd = (Join-Path $WorkRoot 'e2e.md') -replace '\\', '\\'
    $PostJson = '{"session_id":"e2e-md","cwd":"","tool_name":"Write","tool_input":{"file_path":"' + $E2eMd + '"}}'
    Set-Content -LiteralPath (Join-Path $WorkRoot 'e2e.md') -Value '# e2e'
    $PostJson | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PostScript | Out-Null
    Assert-Equal $LASTEXITCODE 0 'post hook should exit 0'
    $E2eQueue = Get-MarkdownQueueFile -SessionId 'e2e-md'
    Assert-True (Test-Path -LiteralPath $E2eQueue) 'E2E queue file should exist'
    Assert-Equal @(Get-MarkdownQueueEntries -QueueFile $E2eQueue).Count 1 'E2E write should queue one entry'

    # Stop with an empty session queue is a harmless no-op.
    '{"session_id":"e2e-empty"}' | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $StopScript | Out-Null
    Assert-Equal $LASTEXITCODE 0 'stop hook should exit 0'

    # Pre hook always answers allow, even on broken input (fail-open).
    $PreOut = 'not json' | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PreScript | ConvertFrom-Json
    Assert-True ($null -eq $PreOut.hookSpecificOutput.permissionDecision) 'pre hook must never deny'
    $PreOut2 = '{"session_id":"e2e-md","tool_name":"Bash","tool_input":{"command":"git status"}}' | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PreScript | ConvertFrom-Json
    Assert-True ($null -eq $PreOut2.hookSpecificOutput.permissionDecision) 'non-commit command passes through'

    # --- settings.json registration ---
    $Settings = Get-Content -Raw (Join-Path $RepoRoot 'claude\settings.json') | ConvertFrom-Json
    $ShellMatchers = @($Settings.hooks.PreToolUse | Where-Object { $_.matcher -eq 'Bash|PowerShell' })
    Assert-True (@($ShellMatchers[0].hooks | Where-Object { $_.command -like '*markdown-format/pre-tool-use.ps1*' }).Count -eq 1) 'md pre-commit flush should be registered'
    $PostMatchers = @($Settings.hooks.PostToolUse | Where-Object { $_.matcher -eq 'Edit|Write|MultiEdit' })
    Assert-True (@($PostMatchers[0].hooks | Where-Object { $_.command -like '*markdown-format/post-tool-use.ps1*' }).Count -eq 1) 'md queue hook should be registered'
    $StopHooks = @($Settings.hooks.Stop)
    Assert-True (@($StopHooks[0].hooks | Where-Object { $_.command -like '*markdown-format/stop.ps1*' }).Count -eq 1) 'md stop flush should be registered'
}
finally {
    $env:CLAUDE_MD_FORMAT_STATE_ROOT = $null
    $env:CLAUDE_MD_FORMAT_EXCLUDE = $null
    $env:CLAUDE_HOOK_LOG_ROOT = $null
    if (Test-Path -LiteralPath $TempRoot) {
        $TestTrashRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'markdown-format-test-trash'
        New-Item -ItemType Directory -Force -Path $TestTrashRoot | Out-Null
        Move-Item -LiteralPath $TempRoot -Destination (Join-Path $TestTrashRoot (Split-Path -Leaf $TempRoot))
    }
}

Write-Output 'MarkdownFormat.Tests.ps1: ALL PASSED'
