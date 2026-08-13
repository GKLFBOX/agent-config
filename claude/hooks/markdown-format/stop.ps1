$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'MarkdownFormat.psm1') -Force
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\AgentHookCommon.psm1') -Force

# Fail-open: formatting must never block the turn from ending.
try {
    # PowerShell 5.1 decodes stdin as CP932 by default, corrupting non-ASCII
    # JSON input. Read stdin as UTF-8 explicitly.
    $StdInReader = New-Object System.IO.StreamReader(
        [Console]::OpenStandardInput(),
        (New-Object System.Text.UTF8Encoding($false))
    )
    $RawInput = $StdInReader.ReadToEnd()
    $SessionId = ''
    if (-not [string]::IsNullOrWhiteSpace($RawInput)) {
        $SessionId = [string](($RawInput | ConvertFrom-Json).session_id)
    }
    [void](Invoke-MarkdownFlush -SessionId $SessionId)
}
catch {
    Write-AgentHookLog -Hook 'markdown-format' -HookEvent 'Stop' -Level 'warn' -Message ("flush failed (fail-open): " + $_.Exception.Message)
}
exit 0
