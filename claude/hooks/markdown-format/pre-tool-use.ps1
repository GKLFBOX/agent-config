$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'MarkdownFormat.psm1') -Force
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\AgentHookCommon.psm1') -Force

# Flush queued markdown before a git commit runs so committed files are
# already formatted (no post-commit diff). Fail-open: never block a commit.
$Response = New-PreToolUseResponse
try {
    # PowerShell 5.1 decodes stdin as CP932 by default, corrupting non-ASCII
    # JSON input (Japanese paths/commands). Read stdin as UTF-8 explicitly.
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $StdInReader = New-Object System.IO.StreamReader(
        [Console]::OpenStandardInput(),
        (New-Object System.Text.UTF8Encoding($false))
    )
    $RawInput = $StdInReader.ReadToEnd()
    if (-not [string]::IsNullOrWhiteSpace($RawInput)) {
        $HookInput = $RawInput | ConvertFrom-Json
        if (([string]$HookInput.tool_name) -in @('Bash', 'PowerShell')) {
            $Command = [string]$HookInput.tool_input.command
            if (Test-GitCommitCommand -Command $Command) {
                [void](Invoke-MarkdownFlush -SessionId ([string]$HookInput.session_id))
            }
        }
    }
}
catch {
    Write-AgentHookLog -Hook 'markdown-format' -HookEvent 'PreToolUse' -Level 'warn' -Message ("pre-commit flush failed (fail-open): " + $_.Exception.Message)
}
[Console]::Out.WriteLine($Response)
