$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'DeleteGuard.psm1') -Force
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\AgentHookCommon.psm1') -Force

try {
    # PowerShell 5.1 decodes stdin as CP932 by default, corrupting non-ASCII
    # JSON input (Japanese paths/commands) and breaking the parse. Under
    # fail-closed that would wrongly deny a legitimate command. Read stdin as
    # UTF-8 explicitly and emit UTF-8 so the deny reason stays readable.
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $StdInReader = New-Object System.IO.StreamReader(
        [Console]::OpenStandardInput(),
        (New-Object System.Text.UTF8Encoding($false))
    )
    $RawInput = $StdInReader.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($RawInput)) {
        throw 'Hook input is empty'
    }

    $HookInput = $RawInput | ConvertFrom-Json
    $Response = Invoke-DeleteGuardHook -HookInput $HookInput
}
catch {
    # Fail-closed: an unparseable command must not slip through the guard.
    Write-AgentHookLog -Hook 'delete-guard' -HookEvent 'PreToolUse' -Level 'error' -Message $_.Exception.Message
    $Response = New-PreToolUseResponse -DenyReason ("delete-guard failed (fail-closed): " + $_.Exception.Message)
}

[Console]::Out.WriteLine($Response)
