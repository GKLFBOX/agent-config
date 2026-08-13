$ErrorActionPreference = 'Stop'

# NOTE: powershell.exe 5.1 decodes BOM-less files as ANSI (CP932).
# Keep this file ASCII-only. Japanese docs live in docs/.

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\AgentHookCommon.psm1') -Force

function Get-MarkdownQueueFile {
    param(
        [AllowEmptyString()]
        [string]$SessionId = ''
    )

    $Root = if ($env:CLAUDE_MD_FORMAT_STATE_ROOT) {
        $env:CLAUDE_MD_FORMAT_STATE_ROOT
    }
    else {
        Join-Path $env:USERPROFILE '.claude\state\markdown-format'
    }
    $Name = if ([string]::IsNullOrWhiteSpace($SessionId)) { 'default' } else { $SessionId }
    return Join-Path $Root ($Name + '.list')
}

function Test-MarkdownFormatExcluded {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ($Path -match '\\node_modules\\' -or $Path -match '\\\.git\\') {
        return $true
    }
    if ($env:CLAUDE_MD_FORMAT_EXCLUDE) {
        foreach ($Root in ($env:CLAUDE_MD_FORMAT_EXCLUDE -split ';')) {
            $Trimmed = $Root.Trim()
            if ($Trimmed.Length -gt 0 -and $Path.StartsWith($Trimmed, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
    }
    return $false
}

function Add-MarkdownQueueEntry {
    param(
        [Parameter(Mandatory = $true)]
        [object]$HookInput
    )

    if (([string]$HookInput.tool_name) -notin @('Edit', 'Write', 'MultiEdit')) {
        return $false
    }
    $Path = [string]$HookInput.tool_input.file_path
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    $WorkingDirectory = if ($HookInput.cwd) { [string]$HookInput.cwd } else { (Get-Location).Path }
    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = Join-Path $WorkingDirectory $Path
    }
    $FullPath = [System.IO.Path]::GetFullPath($Path)

    if ([System.IO.Path]::GetExtension($FullPath) -ne '.md') {
        return $false
    }
    if (Test-MarkdownFormatExcluded -Path $FullPath) {
        return $false
    }

    $QueueFile = Get-MarkdownQueueFile -SessionId ([string]$HookInput.session_id)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $QueueFile) | Out-Null
    [System.IO.File]::AppendAllText($QueueFile, $FullPath + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    return $true
}

function Get-MarkdownQueueEntries {
    param(
        [Parameter(Mandatory = $true)]
        [string]$QueueFile
    )

    if (-not (Test-Path -LiteralPath $QueueFile -PathType Leaf)) {
        return @()
    }

    $Seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $Entries = New-Object System.Collections.Generic.List[string]
    foreach ($Line in [System.IO.File]::ReadAllLines($QueueFile)) {
        $Trimmed = $Line.Trim()
        if ($Trimmed.Length -eq 0) { continue }
        if (-not $Seen.Add($Trimmed)) { continue }
        if (-not (Test-Path -LiteralPath $Trimmed -PathType Leaf)) { continue }
        if (Test-MarkdownFormatExcluded -Path $Trimmed) { continue }
        $Entries.Add($Trimmed)
    }
    return $Entries.ToArray()
}

function Test-GitCommitCommand {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Command
    )

    foreach ($Segment in @(Split-ShellCommandSegments -Command $Command)) {
        $Token = Get-SegmentCommandToken -Segment $Segment
        if ($Token.Length -eq 0) { continue }
        $TokenName = (($Token -split '[\\/]')[-1]) -replace '\.exe$', ''
        # "commit" anywhere in a git segment is close enough: a false
        # positive only costs one extra (usually empty) flush.
        if ($TokenName -eq 'git' -and $Segment -match '(^|\s)commit(\s|$)') {
            return $true
        }
    }
    return $false
}

function Resolve-PrettierCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    $Parent = Split-Path -Parent $FilePath
    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        $RepoRoot = git -C $Parent rev-parse --show-toplevel 2>$null
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }

    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($RepoRoot)) {
        $LocalShim = Join-Path ($RepoRoot -replace '/', '\') 'node_modules\.bin\prettier.cmd'
        if (Test-Path -LiteralPath $LocalShim) {
            # Local install: version-matched with the repo, cache dir exists.
            return [pscustomobject]@{ Executable = $LocalShim; BaseArguments = @('--write', '--cache') }
        }
    }

    $GlobalPrettier = Get-Command 'prettier' -ErrorAction SilentlyContinue
    if ($null -ne $GlobalPrettier) {
        # No --cache: prettier resolves its cache via node_modules, which
        # files outside a package (e.g. vault notes) do not have.
        return [pscustomobject]@{ Executable = $GlobalPrettier.Source; BaseArguments = @('--write') }
    }

    return [pscustomobject]@{ Executable = 'npx.cmd'; BaseArguments = @('--yes', 'prettier', '--write') }
}

function Invoke-PrettierWrite {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    $Prettier = Resolve-PrettierCommand -FilePath $FilePath
    $Output = & $Prettier.Executable @($Prettier.BaseArguments) $FilePath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "prettier failed for ${FilePath}: $Output"
    }
}

function Invoke-MarkdownFlush {
    param(
        [AllowEmptyString()]
        [string]$SessionId = '',
        [scriptblock]$FormatterAction
    )

    $QueueFile = Get-MarkdownQueueFile -SessionId $SessionId
    $Entries = @(Get-MarkdownQueueEntries -QueueFile $QueueFile)
    $Formatted = New-Object System.Collections.Generic.List[string]

    foreach ($Entry in $Entries) {
        try {
            if ($null -ne $FormatterAction) {
                & $FormatterAction $Entry
            }
            else {
                Invoke-PrettierWrite -FilePath $Entry
            }
            $Formatted.Add($Entry)
            Write-AgentHookLog -Hook 'markdown-format' -HookEvent 'flush' -SessionId $SessionId -Message "formatted $Entry"
        }
        catch {
            # Fail-open: formatting is cosmetic, keep going and drop the
            # entry so a broken file does not fail every later flush.
            Write-AgentHookLog -Hook 'markdown-format' -HookEvent 'flush' -SessionId $SessionId -Level 'warn' -Message "prettier failed: $($_.Exception.Message)" -Data @{ file = $Entry }
        }
    }

    if (Test-Path -LiteralPath $QueueFile -PathType Leaf) {
        # Empty the queue in place; deleting files directly is against
        # policy and recycling a transient state file is noise.
        Set-Content -LiteralPath $QueueFile -Value '' -NoNewline
    }

    # Stale queues from dead sessions rot here; sweep them to the bin.
    Remove-AgentHookOldFiles -Directory (Split-Path -Parent $QueueFile) -RetentionDays 7

    return $Formatted.ToArray()
}

Export-ModuleMember -Function Get-MarkdownQueueFile, Test-MarkdownFormatExcluded, Add-MarkdownQueueEntry, Get-MarkdownQueueEntries, Test-GitCommitCommand, Resolve-PrettierCommand, Invoke-PrettierWrite, Invoke-MarkdownFlush
