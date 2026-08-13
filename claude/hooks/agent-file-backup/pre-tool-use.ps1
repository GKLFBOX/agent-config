param(
    [string]$Agent = 'claude'
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'AgentFileBackup.psm1') -Force
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\AgentHookCommon.psm1') -Force

$BackupRoot = if ($env:AGENT_FILE_BACKUP_ROOT) {
    $env:AGENT_FILE_BACKUP_ROOT
}
else {
    '<backup-root>'
}

try {
    # Claude Code and Codex send the hook JSON as UTF-8, but Windows
    # PowerShell 5.1 decodes stdin with the ANSI codepage (CP932) by default,
    # which corrupts non-ASCII input and can break JSON parsing (fail-closed
    # deny on any edit whose tool_input contains Japanese text). Read stdin
    # as UTF-8 explicitly, and emit UTF-8 so deny reasons stay readable.
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
    $Response = Invoke-AgentFileBackupHook -HookInput $HookInput -BackupRoot $BackupRoot -Agent $Agent
}
catch {
    Write-AgentHookLog -Hook 'agent-file-backup' -HookEvent 'PreToolUse' -Level 'error' -Message $_.Exception.Message -Data @{ agent = $Agent }
    $Response = New-AgentFileBackupResponse -DenyReason $_.Exception.Message
}

[Console]::Out.WriteLine($Response)
