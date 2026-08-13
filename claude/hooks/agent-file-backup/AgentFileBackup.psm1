$ErrorActionPreference = 'Stop'

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\AgentHookCommon.psm1') -Force

# NOTE: This module is invoked by Claude Code via powershell.exe (Windows
# PowerShell 5.1), which decodes BOM-less files as the system ANSI codepage
# (CP932 on Japanese Windows). Keep this file ASCII-only so comments cannot
# corrupt parsing of the code that follows. Japanese docs live in docs/.

function Resolve-AgentFileBackupPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $WorkingDirectory $Path))
}

function Get-AgentFileBackupTargetPaths {
    param(
        [Parameter(Mandatory = $true)]
        [object]$HookInput,
        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory
    )

    if ($HookInput.tool_name -in @('Edit', 'Write', 'MultiEdit')) {
        $Path = [string]$HookInput.tool_input.file_path
        if ([string]::IsNullOrWhiteSpace($Path)) {
            throw "Cannot extract target path for $($HookInput.tool_name)"
        }

        return ,(Resolve-AgentFileBackupPath -Path $Path -WorkingDirectory $WorkingDirectory)
    }

    if ($HookInput.tool_name -eq 'NotebookEdit') {
        $Path = [string]$HookInput.tool_input.notebook_path
        if ([string]::IsNullOrWhiteSpace($Path)) {
            throw 'Cannot extract target path for NotebookEdit'
        }

        return ,(Resolve-AgentFileBackupPath -Path $Path -WorkingDirectory $WorkingDirectory)
    }

    if ($HookInput.tool_name -eq 'apply_patch') {
        $Patch = [string]$HookInput.tool_input.command
        if ([string]::IsNullOrWhiteSpace($Patch)) {
            $Patch = [string]$HookInput.tool_input.patch
        }
        if ([string]::IsNullOrWhiteSpace($Patch)) {
            throw 'Cannot extract target path for apply_patch'
        }

        $PathMatches = [regex]::Matches($Patch, '(?m)^\*\*\* (?:Update|Delete) File: (.+)$')
        if ($PathMatches.Count -eq 0 -and $Patch -notmatch '(?m)^\*\*\* Add File: ') {
            throw 'Cannot extract target path for apply_patch'
        }

        return @(
            $PathMatches |
                ForEach-Object {
                    Resolve-AgentFileBackupPath -Path $_.Groups[1].Value.Trim() -WorkingDirectory $WorkingDirectory
                } |
                Select-Object -Unique
        )
    }

    throw "Unsupported tool: $($HookInput.tool_name)"
}

function Test-GitTrackedFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $FullPath = [System.IO.Path]::GetFullPath($Path)
    $Parent = Split-Path -Parent $FullPath
    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        $RepoRoot = git -C $Parent rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($RepoRoot)) {
            return $false
        }

        git -C $RepoRoot ls-files --error-unmatch -- $FullPath 2>$null | Out-Null
        return $LASTEXITCODE -eq 0
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }
}

function Get-AgentFileBackupDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$BackupRoot
    )

    # Mirror the source file's parent directory structure under the backup
    # root; backups of sibling files share one directory, distinguished by
    # the original file name kept in each backup file name.
    # Drive letter "C:" becomes "C"; a leading UNC "\\" is stripped.
    # [IO.Path]::Combine is a pure string join, so (unlike Join-Path) it does
    # not require the backup root's drive to exist when computing the name.
    $ParentPath = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Path))
    $MirroredRelativePath = $ParentPath -replace '^\\\\', '' -replace '^([A-Za-z]):', '$1'
    return [System.IO.Path]::Combine($BackupRoot, $MirroredRelativePath)
}

function Backup-AgentFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$BackupRoot,
        [scriptblock]$TrashAction
    )

    $FullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) {
        throw "Source file does not exist: $FullPath"
    }

    $BackupDirectory = Get-AgentFileBackupDirectory -Path $FullPath -BackupRoot $BackupRoot
    New-Item -ItemType Directory -Force -Path $BackupDirectory | Out-Null

    $Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $OriginalName = Split-Path -Leaf $FullPath
    $Sequence = 0
    do {
        $BackupPath = Join-Path $BackupDirectory ("{0}-{1:D3}_{2}" -f $Timestamp, $Sequence, $OriginalName)
        $Sequence++
    } while (Test-Path -LiteralPath $BackupPath)

    Copy-Item -LiteralPath $FullPath -Destination $BackupPath

    # The directory is shared with sibling files' backups, so retention must
    # match this file's backups exactly: strip the timestamp prefix and
    # compare the remainder to the original name. A wildcard like
    # "*_<name>" would also match backups of a sibling named "foo_<name>".
    $BackupNamePrefixPattern = '^\d{8}-\d{6}-\d{3}-\d{3}_'
    $OldBackups = @(
        Get-ChildItem -LiteralPath $BackupDirectory -File |
            Where-Object {
                $_.Name -match $BackupNamePrefixPattern -and
                ($_.Name -replace $BackupNamePrefixPattern, '') -eq $OriginalName
            } |
            Sort-Object Name -Descending |
            Select-Object -Skip 3
    )
    foreach ($OldBackup in $OldBackups) {
        try {
            if ($null -ne $TrashAction) {
                & $TrashAction $OldBackup.FullName
            }
            else {
                Move-ToRecycleBin -Path $OldBackup.FullName
            }
        }
        catch {
            Write-Warning "Failed to move old backup to recycle bin: $($OldBackup.FullName): $($_.Exception.Message)"
        }
    }

    return $BackupPath
}

function New-AgentFileBackupResponse {
    param(
        [string]$DenyReason
    )

    if ([string]::IsNullOrWhiteSpace($DenyReason)) {
        return New-PreToolUseResponse
    }
    return New-PreToolUseResponse -DenyReason "Agent file backup failed: $DenyReason"
}

function Invoke-AgentFileBackupHook {
    param(
        [Parameter(Mandatory = $true)]
        [object]$HookInput,
        [Parameter(Mandatory = $true)]
        [string]$BackupRoot,
        [string]$Agent = 'claude',
        [scriptblock]$TrashAction
    )

    $WorkingDirectory = if ($HookInput.cwd) { [string]$HookInput.cwd } else { (Get-Location).Path }
    $Targets = @(Get-AgentFileBackupTargetPaths -HookInput $HookInput -WorkingDirectory $WorkingDirectory)
    $NormalizedBackupRoot = [System.IO.Path]::GetFullPath($BackupRoot).TrimEnd('\') + '\'

    foreach ($Path in $Targets) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            continue
        }

        $NormalizedPath = [System.IO.Path]::GetFullPath($Path)
        if ($NormalizedPath.StartsWith($NormalizedBackupRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        if (Test-GitTrackedFile -Path $Path) {
            continue
        }

        $BackupPath = Backup-AgentFile -Path $Path -BackupRoot $BackupRoot -TrashAction $TrashAction
        Write-AgentHookLog -Hook 'agent-file-backup' -HookEvent 'PreToolUse' -SessionId ([string]$HookInput.session_id) -Message "backed up $Path" -Data @{ backup = [string]$BackupPath; agent = $Agent }
    }

    return New-AgentFileBackupResponse
}

Export-ModuleMember -Function Get-AgentFileBackupTargetPaths, Test-GitTrackedFile, Get-AgentFileBackupDirectory, Backup-AgentFile, New-AgentFileBackupResponse, Invoke-AgentFileBackupHook
