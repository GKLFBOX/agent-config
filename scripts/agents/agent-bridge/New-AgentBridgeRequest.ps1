param(
    [Parameter(Mandatory = $true)]
    [string]$Repository,

    [Parameter(Mandatory = $true)]
    [ValidateSet('implementation', 'review', 'investigation')]
    [string]$TaskType,

    [Parameter(Mandatory = $true)]
    [string]$Objective,

    [AllowEmptyCollection()]
    [string[]]$Constraints,

    [AllowEmptyCollection()]
    [string[]]$AcceptanceCriteria,

    [AllowEmptyCollection()]
    [string[]]$ReviewScope,

    [string]$ConstraintsJson,

    [string]$AcceptanceCriteriaJson,

    [string]$ReviewScopeJson,

    [string]$RequestId
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

Import-Module (Join-Path $PSScriptRoot 'AgentBridge.psm1') -Force

function Resolve-AgentBridgeCliStringArray {
    param(
        [string]$Name,
        [string[]]$Value,
        [string]$Json,
        [bool]$ValueBound,
        [bool]$JsonBound
    )

    if ($ValueBound -and $JsonBound) {
        throw "Parameters -$Name and -${Name}Json cannot be used together"
    }
    if ($JsonBound) {
        if ($Json -notmatch '^\s*\[') {
            throw "Parameter -${Name}Json must be a JSON array of strings"
        }
        try {
            $Resolved = $Json | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Parameter -${Name}Json must be a JSON array of strings. $($_.Exception.Message)"
        }
        if ($Resolved -isnot [System.Array]) {
            throw "Parameter -${Name}Json must be a JSON array of strings"
        }
        foreach ($Item in $Resolved) {
            if ($Item -isnot [string]) {
                throw "Parameter -${Name}Json must be a JSON array of strings"
            }
        }
        return $Resolved
    }
    if ($ValueBound) {
        return $Value
    }

    throw "Missing required parameter: -$Name or -${Name}Json"
}

$ResolvedConstraints = @(Resolve-AgentBridgeCliStringArray `
    -Name 'Constraints' `
    -Value $Constraints `
    -Json $ConstraintsJson `
    -ValueBound $PSBoundParameters.ContainsKey('Constraints') `
    -JsonBound $PSBoundParameters.ContainsKey('ConstraintsJson'))
$ResolvedAcceptanceCriteria = @(Resolve-AgentBridgeCliStringArray `
    -Name 'AcceptanceCriteria' `
    -Value $AcceptanceCriteria `
    -Json $AcceptanceCriteriaJson `
    -ValueBound $PSBoundParameters.ContainsKey('AcceptanceCriteria') `
    -JsonBound $PSBoundParameters.ContainsKey('AcceptanceCriteriaJson'))
$ResolvedReviewScope = @(Resolve-AgentBridgeCliStringArray `
    -Name 'ReviewScope' `
    -Value $ReviewScope `
    -Json $ReviewScopeJson `
    -ValueBound $PSBoundParameters.ContainsKey('ReviewScope') `
    -JsonBound $PSBoundParameters.ContainsKey('ReviewScopeJson'))

$Parameters = @{
    Repository = $Repository
    TaskType = $TaskType
    Objective = $Objective
    Constraints = $ResolvedConstraints
    AcceptanceCriteria = $ResolvedAcceptanceCriteria
    ReviewScope = $ResolvedReviewScope
}
if ($PSBoundParameters.ContainsKey('RequestId')) {
    $Parameters.RequestId = $RequestId
}

New-AgentBridgeRequest @Parameters | ConvertTo-Json -Compress
