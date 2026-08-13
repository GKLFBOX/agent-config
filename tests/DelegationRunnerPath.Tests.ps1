$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

# 起動口は $HOME 起点の固定パス。checkout 位置とユーザー名に依存させない。
$Runners = [ordered]@{
    'delegate-claude'      = 'run-claude.ps1'
    'delegate-antigravity' = 'run-antigravity.ps1'
    'delegate-copilot'     = 'run-copilot.ps1'
}

foreach ($Name in $Runners.Keys) {
    $Path = Join-Path $RepoRoot "skills\$Name\SKILL.md"
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "SKILL.md missing: $Path" }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding utf8

    # 起動行にドライブレターの絶対パスを書かない。
    foreach ($Line in [regex]::Matches($text, '(?m)^.*pwsh .*$')) {
        if ($Line.Value -match '[A-Za-z]:[\\/]') {
            throw "$Name launches the runner through an absolute checkout path: $($Line.Value)"
        }
    }

    $Expected = '$HOME/.agent-bridge/' + $Runners[$Name]
    if ($text -notmatch [regex]::Escape($Expected)) {
        throw "$Name must launch the runner through $Expected"
    }
}

Write-Host 'DelegationRunnerPath test PASSED'
