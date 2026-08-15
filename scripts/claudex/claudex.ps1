Import-Module (Join-Path $PSScriptRoot '..\lib\ClaudexAuth.psm1') -Force -DisableNameChecking

$script:ClaudexModelMap = @{
    'sol'           = 'gpt-5.6-sol'
    'terra'         = 'gpt-5.6-terra'
    'luna'          = 'gpt-5.6-luna'
    'gpt-5.6-sol'   = 'gpt-5.6-sol'
    'gpt-5.6-terra' = 'gpt-5.6-terra'
    'gpt-5.6-luna'  = 'gpt-5.6-luna'
}
$script:ClaudexEfforts = @('low', 'medium', 'high', 'xhigh', 'max')

function Resolve-ClaudexModel {
    param([Parameter(Mandatory)][string]$Value)

    $key = $Value.ToLowerInvariant()
    if (-not $script:ClaudexModelMap.ContainsKey($key)) {
        throw "Unsupported model [$Value]. Use sol, terra, or luna."
    }
    return $script:ClaudexModelMap[$key]
}

function Resolve-ClaudexEffort {
    param([Parameter(Mandatory)][string]$Value)

    $key = $Value.ToLowerInvariant()
    if ($key -notin $script:ClaudexEfforts) {
        throw "Unsupported effort [$Value]. Use low, medium, high, xhigh, or max."
    }
    return $key
}

function ConvertTo-ClaudexInvocation {
    param([AllowEmptyCollection()][object[]]$Arguments = @())

    $model = 'gpt-5.6-sol'
    $effort = 'xhigh'
    $modelSeen = $false
    $effortSeen = $false
    $isHelp = $false
    $isVersion = $false
    $forward = [System.Collections.Generic.List[string]]::new()

    for ($index = 0; $index -lt $Arguments.Count; $index++) {
        $token = [string]$Arguments[$index]
        if ($token -eq '--') {
            for (; $index -lt $Arguments.Count; $index++) {
                $forward.Add([string]$Arguments[$index])
            }
            break
        }

        $kind = $null
        $value = $null
        if ($token -eq '--model' -or $token -eq '--effort') {
            $kind = $token.Substring(2)
            if ($index + 1 -ge $Arguments.Count -or [string]$Arguments[$index + 1] -like '--*') {
                throw "$token requires a value."
            }
            $index++
            $value = [string]$Arguments[$index]
        }
        elseif ($token -match '^--(model|effort)=(.*)$') {
            $kind = $Matches[1]
            $value = $Matches[2]
            if ([string]::IsNullOrWhiteSpace($value)) { throw "--$kind requires a value." }
        }
        elseif ($token -eq '--help') {
            $isHelp = $true
            continue
        }
        elseif ($token -eq '--version') {
            $isVersion = $true
            continue
        }
        else {
            $forward.Add($token)
            continue
        }

        if ($kind -eq 'model') {
            if ($modelSeen) { throw '--model was specified more than once.' }
            $modelSeen = $true
            $model = Resolve-ClaudexModel -Value $value
        }
        else {
            if ($effortSeen) { throw '--effort was specified more than once.' }
            $effortSeen = $true
            $effort = Resolve-ClaudexEffort -Value $value
        }
    }

    $claudeArguments = @('--model', $model, '--effort', $effort) + $forward.ToArray()
    return [pscustomobject]@{
        Model = $model
        Effort = $effort
        ClaudeArguments = $claudeArguments
        IsHelp = $isHelp
        IsVersion = $isVersion
    }
}

function Get-ClaudexHelpText {
    return @'
Usage: claudex [--model sol|terra|luna] [--effort low|medium|high|xhigh|max] [Claude Code arguments...]

Defaults:
  --model sol
  --effort xhigh

Passthrough:
  claudex '--' <Claude Code arguments...>
  Quote the separator because PowerShell consumes an unquoted -- for functions.

Proxy:
  URL:  http://127.0.0.1:8317
  Task: AgentConfig-CLIProxyAPI
  Check: Get-ScheduledTaskInfo -TaskName 'AgentConfig-CLIProxyAPI'

Run `claude --help` for standard Claude Code options.
'@
}

$script:ClaudexBaseUrl = 'http://127.0.0.1:8317'
$script:ClaudexTaskName = 'AgentConfig-CLIProxyAPI'
$script:ClaudexSecretPath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'agent-config\claudex\secrets.psd1'
$script:ClaudexCapabilities = 'effort,xhigh_effort,max_effort'
$script:ClaudexReloginScript = Join-Path $PSScriptRoot 'relogin.ps1'

function Format-ClaudexAuthDeadline {
    param(
        [Parameter(Mandatory)][datetime]$Deadline,
        [datetime]$Now = [datetime]::UtcNow
    )

    $days = [math]::Floor(($Deadline - $Now).TotalDays)
    $local = $Deadline.ToLocalTime().ToString('yyyy-MM-dd HH:mm')
    return "あと${days}日で失効する（期限: $local）"
}

function Assert-ClaudexAuth {
    param(
        [Parameter(Mandatory)]$Status,
        [datetime]$Now = [datetime]::UtcNow,
        [string]$ReloginScript = $script:ClaudexReloginScript
    )

    $recover = "復旧: pwsh -NoProfile -File `"$ReloginScript`""
    switch ($Status.Proxy.State) {
        'Expired' { throw "Codex認証が失効している。再ログインするまでCLIProxyAPIはGPTモデルへ応答できない。$recover" }
        'Ending' { Write-Warning "Codex認証は$(Format-ClaudexAuthDeadline -Deadline $Status.Proxy.Deadline -Now $Now)。$recover" }
        'Unknown' { Write-Warning "Codex認証の状態を判定できない。$recover" }
    }
    # Codex CLI の失効は claudex 自体を止めない。影響は委託とstatuslineの使用率表示に限られる。
    switch ($Status.CodexCli.State) {
        'Expired' { Write-Warning "Codex CLIの認証が失効している。codexへの委託とstatuslineの使用率表示が使えない。$recover" }
        'Ending' { Write-Warning "Codex CLIの認証は$(Format-ClaudexAuthDeadline -Deadline $Status.CodexCli.Deadline -Now $Now)。$recover" }
    }
}

function Get-ClaudexToken {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Claudex secret file was not found: $Path"
    }
    $data = Import-PowerShellDataFile -LiteralPath $Path
    if ([string]::IsNullOrWhiteSpace([string]$data.ProxyApiKey)) {
        throw "Claudex secret file does not contain ProxyApiKey: $Path"
    }
    try {
        $secure = ConvertTo-SecureString -String ([string]$data.ProxyApiKey)
        return [System.Net.NetworkCredential]::new('', $secure).Password
    }
    catch {
        throw "Claudex secret could not be decrypted for the current Windows user: $Path"
    }
}

function Get-ClaudexProxyHealth {
    param(
        [Parameter(Mandatory)][string]$Token,
        [string]$BaseUrl = $script:ClaudexBaseUrl,
        [scriptblock]$WebRequest = {
            param($Uri, $Headers)
            Invoke-WebRequest -Uri $Uri -Headers $Headers -Method Get -TimeoutSec 2 -ErrorAction Stop
        }
    )

    try {
        $response = & $WebRequest "$BaseUrl/v1/models" @{ Authorization = "Bearer $Token" }
        $statusCode = [int]$response.StatusCode
        return [pscustomobject]@{ Healthy = ($statusCode -eq 200); StatusCode = $statusCode }
    }
    catch {
        $statusCode = $null
        $responseProperty = $_.Exception.PSObject.Properties['Response']
        if ($null -ne $responseProperty -and $null -ne $responseProperty.Value) {
            $statusProperty = $responseProperty.Value.PSObject.Properties['StatusCode']
            if ($null -ne $statusProperty -and $null -ne $statusProperty.Value) {
                $statusCode = [int]$statusProperty.Value
            }
        }
        return [pscustomobject]@{ Healthy = $false; StatusCode = $statusCode }
    }
}

function Confirm-ClaudexProxy {
    param(
        [Parameter(Mandatory)][string]$Token,
        [string]$BaseUrl = $script:ClaudexBaseUrl,
        [string]$TaskName = $script:ClaudexTaskName,
        [scriptblock]$WebRequest = {
            param($Uri, $Headers)
            Invoke-WebRequest -Uri $Uri -Headers $Headers -Method Get -TimeoutSec 2 -ErrorAction Stop
        },
        [scriptblock]$TaskStarter = { param($Name) Start-ScheduledTask -TaskName $Name -ErrorAction Stop },
        [scriptblock]$Delay = { param($Milliseconds) Start-Sleep -Milliseconds $Milliseconds }
    )

    $health = Get-ClaudexProxyHealth -Token $Token -BaseUrl $BaseUrl -WebRequest $WebRequest
    if ($health.Healthy) { return }
    if ($health.StatusCode -in @(401, 403)) {
        throw 'CLIProxyAPI rejected the configured API key. Re-run scripts/claudex/install.ps1 -ReplaceSecret.'
    }

    try {
        & $TaskStarter $TaskName
    }
    catch {
        throw "CLIProxyAPI is unavailable and scheduled task [$TaskName] could not be started. Run scripts/claudex/install.ps1."
    }

    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        & $Delay 500
        $health = Get-ClaudexProxyHealth -Token $Token -BaseUrl $BaseUrl -WebRequest $WebRequest
        if ($health.Healthy) { return }
        if ($health.StatusCode -in @(401, 403)) {
            throw 'CLIProxyAPI rejected the configured API key. Re-run scripts/claudex/install.ps1 -ReplaceSecret.'
        }
    }
    throw "CLIProxyAPI did not become ready within 10 seconds. Inspect (Get-ScheduledTask -TaskName '$TaskName').Actions and Get-ScheduledTaskInfo -TaskName '$TaskName'."
}

function Invoke-WithClaudexEnvironment {
    param(
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    $setValues = [ordered]@{
        ANTHROPIC_BASE_URL = $script:ClaudexBaseUrl
        ANTHROPIC_AUTH_TOKEN = $Token
        ANTHROPIC_DEFAULT_FABLE_MODEL = 'gpt-5.6-sol'
        ANTHROPIC_DEFAULT_OPUS_MODEL = 'gpt-5.6-sol'
        ANTHROPIC_DEFAULT_SONNET_MODEL = 'gpt-5.6-terra'
        ANTHROPIC_DEFAULT_HAIKU_MODEL = 'gpt-5.6-luna'
        CLAUDE_CODE_MAX_OUTPUT_TOKENS = '128000'
        CLAUDE_CODE_MAX_CONTEXT_TOKENS = '372000'
        CLAUDE_CODE_AUTO_COMPACT_WINDOW = '240000'
        CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = '85'
        ANTHROPIC_DEFAULT_FABLE_MODEL_SUPPORTED_CAPABILITIES = $script:ClaudexCapabilities
        ANTHROPIC_DEFAULT_OPUS_MODEL_SUPPORTED_CAPABILITIES = $script:ClaudexCapabilities
        ANTHROPIC_DEFAULT_SONNET_MODEL_SUPPORTED_CAPABILITIES = $script:ClaudexCapabilities
        ANTHROPIC_DEFAULT_HAIKU_MODEL_SUPPORTED_CAPABILITIES = $script:ClaudexCapabilities
    }
    $removeNames = @('ANTHROPIC_API_KEY', 'CLAUDE_CODE_EFFORT_LEVEL')
    $names = @($setValues.Keys) + $removeNames | Select-Object -Unique
    $snapshot = @{}
    foreach ($name in $names) {
        $value = [Environment]::GetEnvironmentVariable($name, 'Process')
        $snapshot[$name] = [pscustomobject]@{ Exists = ($null -ne $value); Value = $value }
    }

    try {
        foreach ($entry in $setValues.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value, 'Process')
        }
        foreach ($name in $removeNames) {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        }
        & $Action
    }
    finally {
        foreach ($name in $names) {
            $saved = $snapshot[$name]
            try {
                if ($saved.Exists) {
                    [Environment]::SetEnvironmentVariable($name, $saved.Value, 'Process')
                }
                else {
                    Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
                }
            }
            catch {
                Write-Warning "Failed to restore process environment variable [$name]."
            }
        }
    }
}

function Invoke-Claudex {
    param(
        [AllowEmptyCollection()][object[]]$Arguments = @(),
        [string]$SecretPath = $script:ClaudexSecretPath,
        [scriptblock]$TokenReader = { param($Path) Get-ClaudexToken -Path $Path },
        [scriptblock]$AuthStatusReader = { Get-ClaudexAuthStatus },
        [scriptblock]$WebRequest = {
            param($Uri, $Headers)
            Invoke-WebRequest -Uri $Uri -Headers $Headers -Method Get -TimeoutSec 2 -ErrorAction Stop
        },
        [scriptblock]$TaskStarter = { param($Name) Start-ScheduledTask -TaskName $Name -ErrorAction Stop },
        [scriptblock]$Delay = { param($Milliseconds) Start-Sleep -Milliseconds $Milliseconds },
        [scriptblock]$CommandResolver = { param($Name) Get-Command $Name -CommandType Application -ErrorAction Stop },
        [scriptblock]$ClaudeInvoker = {
            param($Command, $Arguments, $State)
            & $Command @Arguments
            $State.ExitCode = $global:LASTEXITCODE
        }
    )

    $invocation = ConvertTo-ClaudexInvocation -Arguments $Arguments
    if ($invocation.IsHelp) {
        Write-Output (Get-ClaudexHelpText)
        return
    }

    try { $command = @(& $CommandResolver 'claude') | Select-Object -First 1 }
    catch { throw 'Claude Code executable was not found in PATH.' }
    if ($null -eq $command -or [string]::IsNullOrWhiteSpace([string]$command.Source)) {
        throw 'Claude Code executable was not found in PATH.'
    }
    if ($invocation.IsVersion) {
        $state = [pscustomobject]@{ ExitCode = 0 }
        & $ClaudeInvoker $command.Source @('--version') $state
        $global:LASTEXITCODE = [int]$state.ExitCode
        return
    }

    $token = & $TokenReader $SecretPath
    Assert-ClaudexAuth -Status (& $AuthStatusReader)
    Confirm-ClaudexProxy -Token $token -WebRequest $WebRequest -TaskStarter $TaskStarter -Delay $Delay
    $state = [pscustomobject]@{ ExitCode = 0 }
    Invoke-WithClaudexEnvironment -Token $token -Action {
        & $ClaudeInvoker $command.Source $invocation.ClaudeArguments $state
    }
    $global:LASTEXITCODE = [int]$state.ExitCode
}

function global:claudex {
    Invoke-Claudex -Arguments @($args)
}
