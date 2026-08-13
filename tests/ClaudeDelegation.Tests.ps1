$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Skill = Join-Path $RepoRoot 'skills\delegate-claude\SKILL.md'

if (-not (Test-Path -LiteralPath $Skill -PathType Leaf)) { throw "SKILL.md missing: $Skill" }
$text = Get-Content -LiteralPath $Skill -Raw -Encoding utf8

if ($text -notmatch '(?m)^name:\s*delegate-claude\s*$') { throw 'frontmatter name must be delegate-claude' }
$DescriptionMatch = [regex]::Match($text, '(?m)^description:\s*(.+)$')
if (-not $DescriptionMatch.Success) { throw 'frontmatter description is required' }
$Description = $DescriptionMatch.Groups[1].Value
if ($Description -notmatch 'GPT系司令塔') { throw 'description must target GPT controllers' }
if ($Description -notmatch 'ユーザー.+明示') { throw 'description must require an explicit user delegation request' }

if ($text -notmatch 'run-claude\.ps1') { throw 'SKILL.md must reference run-claude.ps1' }
foreach ($TaskType in @('investigation', 'review', 'implementation')) {
    if ($text -notmatch $TaskType) { throw "SKILL.md must document $TaskType" }
}
if ($text -notmatch '過去の依頼') { throw 'SKILL.md must not inherit delegation permission from past requests' }
if ($text -notmatch '-Write') { throw 'SKILL.md must document the -Write gate' }
if ($text -notmatch 'AllowedBashRules') { throw 'SKILL.md must document scoped Bash rules' }
if ($text -notmatch '既定ではBashを公開しない') { throw 'SKILL.md must document the default Bash denial' }
if ($text -notmatch '再委託') { throw 'SKILL.md must prohibit redelegation' }
if ($text -notmatch '未信頼入力') { throw 'SKILL.md must treat results as untrusted input' }
Write-Host 'ClaudeDelegation SKILL.md test PASSED'
