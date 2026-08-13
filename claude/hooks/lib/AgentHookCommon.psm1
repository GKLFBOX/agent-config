$ErrorActionPreference = 'Stop'

# NOTE: Invoked by Claude Code via powershell.exe (Windows PowerShell 5.1),
# which decodes BOM-less files as the system ANSI codepage (CP932 on
# Japanese Windows). Keep this file ASCII-only. Japanese docs live in docs/.

function Move-ToRecycleBin {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Add-Type -AssemblyName Microsoft.VisualBasic
    $Item = Get-Item -LiteralPath $Path -Force
    if ($Item.PSIsContainer) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
            $Item.FullName,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
        )
    }
    else {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
            $Item.FullName,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
        )
    }
}

function Remove-AgentHookOldFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory,
        [Parameter(Mandatory = $true)]
        [int]$RetentionDays,
        [scriptblock]$TrashAction
    )

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return
    }

    $Cutoff = (Get-Date).AddDays(-$RetentionDays)
    foreach ($File in @(Get-ChildItem -LiteralPath $Directory -File | Where-Object { $_.LastWriteTime -lt $Cutoff })) {
        try {
            if ($null -ne $TrashAction) {
                & $TrashAction $File.FullName
            }
            else {
                Move-ToRecycleBin -Path $File.FullName
            }
        }
        catch {
            Write-Warning "Failed to move old file to recycle bin: $($File.FullName): $($_.Exception.Message)"
        }
    }
}

function Get-AgentHookLogRoot {
    if ($env:CLAUDE_HOOK_LOG_ROOT) {
        return $env:CLAUDE_HOOK_LOG_ROOT
    }
    return '<log-root>\hooks'
}

function Write-AgentHookLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Hook,
        [Parameter(Mandatory = $true)]
        [string]$HookEvent,
        [AllowEmptyString()]
        [string]$SessionId = '',
        [ValidateSet('info', 'warn', 'error')]
        [string]$Level = 'info',
        [AllowEmptyString()]
        [string]$Message = '',
        [hashtable]$Data,
        [scriptblock]$TrashAction
    )

    # Logging is observability, not a safety mechanism: never throw.
    try {
        $LogRoot = Get-AgentHookLogRoot
        New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

        $Record = [ordered]@{
            ts         = (Get-Date).ToString('o')
            hook       = $Hook
            event      = $HookEvent
            session_id = $SessionId
            level      = $Level
            message    = $Message
        }
        if ($null -ne $Data) {
            $Record['data'] = $Data
        }
        $Line = ($Record | ConvertTo-Json -Compress -Depth 5) + [Environment]::NewLine
        $LogFile = Join-Path $LogRoot ((Get-Date).ToString('yyyy-MM-dd') + '.jsonl')

        $Mutex = New-Object System.Threading.Mutex($false, 'AgentHookLogMutex')
        $Acquired = $false
        try {
            try {
                $Acquired = $Mutex.WaitOne(2000)
            }
            catch [System.Threading.AbandonedMutexException] {
                $Acquired = $true
            }
            [System.IO.File]::AppendAllText($LogFile, $Line, (New-Object System.Text.UTF8Encoding($false)))
        }
        finally {
            if ($Acquired) { $Mutex.ReleaseMutex() }
            $Mutex.Dispose()
        }

        Remove-AgentHookOldFiles -Directory $LogRoot -RetentionDays 14 -TrashAction $TrashAction
    }
    catch {
    }
}

function New-PreToolUseResponse {
    param(
        [string]$DenyReason
    )

    $HookSpecificOutput = [ordered]@{
        hookEventName = 'PreToolUse'
    }
    if (-not [string]::IsNullOrWhiteSpace($DenyReason)) {
        $HookSpecificOutput['permissionDecision'] = 'deny'
        $HookSpecificOutput['permissionDecisionReason'] = $DenyReason
    }

    return ([ordered]@{
        hookSpecificOutput = $HookSpecificOutput
    } | ConvertTo-Json -Compress -Depth 5)
}

function Split-ShellCommandSegments {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Command
    )

    # Best-effort splitter shared by delete-guard and markdown-format.
    # Splits on unquoted ; | & ( ) backtick and newlines so that every
    # command position (including subshells) starts a new segment.
    # Known limits (guard is conservative, not a security boundary):
    # - PowerShell backtick-escaped double quotes re-open quoting early,
    #   which can only over-split (never under-split).
    # - An unpaired apostrophe (e.g. don't) swallows later separators.
    $Segments = New-Object System.Collections.Generic.List[string]
    $Current = New-Object System.Text.StringBuilder
    $InSingle = $false
    $InDouble = $false

    for ($i = 0; $i -lt $Command.Length; $i++) {
        $Ch = [string]$Command[$i]
        if ($InSingle) {
            if ($Ch -eq "'") { $InSingle = $false }
            [void]$Current.Append($Ch)
        }
        elseif ($InDouble) {
            if ($Ch -eq '\' -and ($i + 1) -lt $Command.Length) {
                [void]$Current.Append($Ch)
                $i++
                [void]$Current.Append([string]$Command[$i])
            }
            elseif ($Ch -eq '"') {
                $InDouble = $false
                [void]$Current.Append($Ch)
            }
            else {
                [void]$Current.Append($Ch)
            }
        }
        elseif ($Ch -eq "'") {
            $InSingle = $true
            [void]$Current.Append($Ch)
        }
        elseif ($Ch -eq '"') {
            $InDouble = $true
            [void]$Current.Append($Ch)
        }
        elseif ($Ch -eq ';' -or $Ch -eq '|' -or $Ch -eq '&' -or $Ch -eq '(' -or $Ch -eq ')' -or $Ch -eq '`' -or $Ch -eq "`n" -or $Ch -eq "`r") {
            if ($Current.ToString().Trim().Length -gt 0) {
                $Segments.Add($Current.ToString())
            }
            [void]$Current.Clear()
        }
        else {
            [void]$Current.Append($Ch)
        }
    }
    if ($Current.ToString().Trim().Length -gt 0) {
        $Segments.Add($Current.ToString())
    }

    return $Segments.ToArray()
}

function Get-SegmentCommandToken {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Segment
    )

    foreach ($RawToken in @($Segment.Trim() -split '\s+')) {
        $Token = $RawToken.Trim('"', "'", '$')
        if ($Token.Length -eq 0) { continue }
        if ($Token -in @('sudo', 'command', 'builtin', 'exec', 'nohup')) { continue }
        if ($Token -match '^[A-Za-z_][A-Za-z0-9_]*=') { continue }
        return $Token
    }
    return ''
}

Export-ModuleMember -Function Move-ToRecycleBin, Remove-AgentHookOldFiles, Get-AgentHookLogRoot, Write-AgentHookLog, New-PreToolUseResponse, Split-ShellCommandSegments, Get-SegmentCommandToken
