$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'MarkdownFormat.psm1') -Force
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\AgentHookCommon.psm1') -Force

# Fail-open: recording the queue must never disturb the edit itself.
try {
    # PowerShell 5.1 decodes stdin as CP932 by default, corrupting non-ASCII
    # JSON input (Japanese .md paths). Read stdin as UTF-8 explicitly.
    $StdInReader = New-Object System.IO.StreamReader(
        [Console]::OpenStandardInput(),
        (New-Object System.Text.UTF8Encoding($false))
    )
    $RawInput = $StdInReader.ReadToEnd()
    if (-not [string]::IsNullOrWhiteSpace($RawInput)) {
        $HookInput = $RawInput | ConvertFrom-Json
        [void](Add-MarkdownQueueEntry -HookInput $HookInput)
    }
}
catch {
    Write-AgentHookLog -Hook 'markdown-format' -HookEvent 'PostToolUse' -Level 'warn' -Message ("queue append failed (fail-open): " + $_.Exception.Message)
}
exit 0
