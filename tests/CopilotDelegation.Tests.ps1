$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Skill = Join-Path $RepoRoot 'skills\delegate-copilot\SKILL.md'

if (-not (Test-Path -LiteralPath $Skill -PathType Leaf)) { throw "SKILL.md missing: $Skill" }
$text = Get-Content -LiteralPath $Skill -Raw

if ($text -notmatch '(?m)^name:\s*delegate-copilot\s*$') { throw 'frontmatter name must be delegate-copilot' }
if ($text -notmatch 'run-copilot\.ps1') { throw 'SKILL.md must reference run-copilot.ps1' }
if ($text -notmatch '(?i)investigation') { throw 'SKILL.md must document investigation' }
if ($text -notmatch '(?i)implementation') { throw 'SKILL.md must document implementation' }
if ($text -notmatch '-Write') { throw 'SKILL.md must document the -Write gate' }
if ($text -match '(?i)review') { throw 'SKILL.md must not offer review delegation' }
Write-Host 'CopilotDelegation SKILL.md test PASSED'
