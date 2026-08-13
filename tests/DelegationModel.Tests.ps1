$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

$Route = Join-Path $RepoRoot 'skills\route-delegation\SKILL.md'
$routeText = Get-Content -LiteralPath $Route -Raw -Encoding utf8
# 節は1つだけ。重複すると正本がどちらか分からなくなる。
$SectionCount = ([regex]::Matches($routeText, '(?m)^##\s*モデル指定\s*$')).Count
if ($SectionCount -ne 1) {
    throw "route-delegation must have exactly one モデル指定 section, found $SectionCount"
}
foreach ($Value in @('opus', 'gpt-5.6-sol', 'gemini-3.6-flash-medium', 'auto', '--effort')) {
    if ($routeText -notmatch [regex]::Escape($Value)) {
        throw "route-delegation モデル指定節に [$Value] が必要"
    }
}

# 世代交代で腐るモデルIDは route-delegation だけに置く。delegate-* へ複製しない。
$VolatilePattern = 'gemini-[0-9]|gpt-5\.[0-9]|gpt-oss|claude-(opus|sonnet|haiku)-[0-9]'
foreach ($Name in @('delegate-claude', 'delegate-codex', 'delegate-antigravity', 'delegate-copilot')) {
    $Path = Join-Path $RepoRoot "skills\$Name\SKILL.md"
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "SKILL.md missing: $Path" }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    if ($text -match $VolatilePattern) {
        throw "$Name must not duplicate volatile model IDs; reference route-delegation instead"
    }
    if ($text -notmatch 'route-delegation') { throw "$Name must reference route-delegation" }
    if ($text -notmatch '(?i)model') { throw "$Name must document model specification" }
}

# Gemini の世代は route-delegation だけが持つ。
$AntigravityText = Get-Content -LiteralPath (Join-Path $RepoRoot 'skills\delegate-antigravity\SKILL.md') -Raw -Encoding utf8
if ($AntigravityText -match '3\.[0-9]') {
    throw 'delegate-antigravity must not state a Gemini generation; reference route-delegation'
}

# runner を持つ3経路は -Model の明示を求める。
foreach ($Name in @('delegate-claude', 'delegate-antigravity', 'delegate-copilot')) {
    $text = Get-Content -LiteralPath (Join-Path $RepoRoot "skills\$Name\SKILL.md") -Raw -Encoding utf8
    if ($text -notmatch '-Model') { throw "$Name must document the -Model parameter" }
}

# codex は呼び出し文で --model と --effort を明示する。
$CodexText = Get-Content -LiteralPath (Join-Path $RepoRoot 'skills\delegate-codex\SKILL.md') -Raw -Encoding utf8
foreach ($Required in @('--model', '--effort')) {
    if ($CodexText -notmatch [regex]::Escape($Required)) {
        throw "delegate-codex must require $Required"
    }
}
if ($CodexText -notmatch '省略しない|明示する') {
    throw 'delegate-codex must state that model specification is mandatory'
}

Write-Host 'DelegationModel skill test PASSED'
