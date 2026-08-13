$ErrorActionPreference = 'Stop'

# NOTE: powershell.exe 5.1 decodes BOM-less files as ANSI (CP932).
# Keep this file ASCII-only. Japanese docs live in docs/.

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\AgentHookCommon.psm1') -Force

# Guardrail, not a security boundary: enforces the AGENTS.md rule that
# files must go to the Recycle Bin instead of being deleted directly.
# Deliberate bypasses (scripts on disk, instance .Delete() calls) are
# documented in the design spec and out of scope.
$script:BashDeleteTokens = @('rm', 'rmdir', 'unlink', 'shred')
$script:PowerShellDeleteTokens = @('remove-item', 'ri', 'rm', 'rmdir', 'rd', 'del', 'erase')
# Tokens whose string arguments run in another interpreter: scan those
# segments for delete words instead of parsing them.
$script:NestedRunnerTokens = @('bash', 'sh', 'zsh', 'cmd', 'powershell', 'pwsh', 'xargs')

function Test-DeleteCommand {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Command,
        [Parameter(Mandatory = $true)]
        [string]$ToolName
    )

    $DenyTokens = if ($ToolName -eq 'Bash') { $script:BashDeleteTokens } else { $script:PowerShellDeleteTokens }
    $AllDeleteTokens = @($script:BashDeleteTokens + $script:PowerShellDeleteTokens | Select-Object -Unique)
    $NestedPattern = '(?i)(^|[\s"''=])(' + (($AllDeleteTokens | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')(\s|$|")'

    foreach ($Segment in @(Split-ShellCommandSegments -Command $Command)) {
        $Token = Get-SegmentCommandToken -Segment $Segment
        if ($Token.Length -eq 0) { continue }
        $TokenName = (($Token -split '[\\/]')[-1]) -replace '\.exe$', ''

        if ($DenyTokens -contains $TokenName) {
            return "command-position delete token '$TokenName'"
        }
        if ($TokenName -eq 'find') {
            if ($Segment -match '(^|\s)-delete(\s|$)' -or $Segment -match '(^|\s)-exec\s+rm(\s|$)') {
                return 'find with -delete or -exec rm'
            }
        }
        if ($script:NestedRunnerTokens -contains $TokenName -and $Segment -match $NestedPattern) {
            return "nested interpreter segment contains a delete token ('$TokenName')"
        }
    }

    if ($Command -match '(?i)\[\s*(System\.)?IO\.(File|Directory)\s*\]\s*::\s*Delete') {
        return 'static .NET Delete call'
    }

    return $null
}

function Invoke-DeleteGuardHook {
    param(
        [Parameter(Mandatory = $true)]
        [object]$HookInput
    )

    if ($env:CLAUDE_DELETE_GUARD -eq 'off') {
        return New-PreToolUseResponse
    }

    $ToolName = [string]$HookInput.tool_name
    if ($ToolName -notin @('Bash', 'PowerShell')) {
        return New-PreToolUseResponse
    }

    $Command = [string]$HookInput.tool_input.command
    $SessionId = [string]$HookInput.session_id
    $Reason = Test-DeleteCommand -Command $Command -ToolName $ToolName

    if ($null -ne $Reason) {
        Write-AgentHookLog -Hook 'delete-guard' -HookEvent 'PreToolUse' -SessionId $SessionId -Level 'warn' -Message "deny: $Reason" -Data @{ tool = $ToolName; command = $Command }
        return New-PreToolUseResponse -DenyReason ("File deletion is blocked by policy ({0}). Send files to the Recycle Bin instead, e.g.: trash <path>. Emergency override: set CLAUDE_DELETE_GUARD=off." -f $Reason)
    }

    Write-AgentHookLog -Hook 'delete-guard' -HookEvent 'PreToolUse' -SessionId $SessionId -Message 'allow' -Data @{ tool = $ToolName; command = $Command }
    return New-PreToolUseResponse
}

Export-ModuleMember -Function Test-DeleteCommand, Invoke-DeleteGuardHook
