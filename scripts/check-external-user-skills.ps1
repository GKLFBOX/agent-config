[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$SkillRoot = Join-Path $env:USERPROFILE '.agents/skills'
$LockPath = Join-Path $env:USERPROFILE '.agents/.skill-lock.json'
$Lock = if (Test-Path -LiteralPath $LockPath -PathType Leaf) {
    Get-Content -LiteralPath $LockPath -Raw | ConvertFrom-Json
} else {
    $null
}

$RequiredSkills = @(
    [pscustomobject]@{ Name='karpathy-guidelines'; Source='forrestchang/andrej-karpathy-skills' },
    [pscustomobject]@{ Name='defuddle'; Source='kepano/obsidian-skills' },
    [pscustomobject]@{ Name='json-canvas'; Source='kepano/obsidian-skills' },
    [pscustomobject]@{ Name='obsidian-bases'; Source='kepano/obsidian-skills' },
    [pscustomobject]@{ Name='obsidian-cli'; Source='kepano/obsidian-skills' },
    [pscustomobject]@{ Name='obsidian-markdown'; Source='kepano/obsidian-skills' },
    [pscustomobject]@{ Name='find-skills'; Source='vercel-labs/skills' }
)

$Rows = foreach ($Skill in $RequiredSkills) {
    $Path = Join-Path $SkillRoot $Skill.Name
    $SkillFile = Join-Path $Path 'SKILL.md'
    $LockEntry = if ($null -ne $Lock) { $Lock.skills.PSObject.Properties[$Skill.Name].Value } else { $null }
    $LockSource = if ($null -ne $LockEntry) { $LockEntry.source } else { $null }
    $LockOk = $LockSource -eq $Skill.Source
    $Ready = (Test-Path -LiteralPath $SkillFile -PathType Leaf) -and $LockOk

    [pscustomobject]@{
        Name       = $Skill.Name
        Source     = $Skill.Source
        Path       = $Path
        SkillFile  = Test-Path -LiteralPath $SkillFile -PathType Leaf
        LockSource = $LockSource
        Ready      = $Ready
    }
}

$Rows | Format-Table -AutoSize

$Missing = @($Rows | Where-Object { -not $_.Ready })
if ($Missing.Count -gt 0) {
    $Names = ($Missing | Select-Object -ExpandProperty Name) -join ', '
    Write-Error "Missing or mismatched external USER skills: $Names"
    exit 1
}
