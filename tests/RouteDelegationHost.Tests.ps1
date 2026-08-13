$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Route = Join-Path $RepoRoot 'skills\route-delegation\SKILL.md'
$text = Get-Content -LiteralPath $Route -Raw -Encoding utf8

foreach ($Heading in @('## Claude系司令塔', '## GPT系司令塔')) {
    $Count = ([regex]::Matches($text, '(?m)^' + [regex]::Escape($Heading))).Count
    if ($Count -ne 1) { throw "route-delegation must have exactly one [$Heading] section, found $Count" }
}

if ($text -match '(?m)^##\s*呼び出し元が Codex の場合') {
    throw 'route-delegation must fold the Codex caller section into the GPT section'
}

$ClaudeSection = [regex]::Match($text, '(?ms)^## Claude系司令塔.*?(?=^## |\z)').Value
$ClaudeTableRows = @([regex]::Matches($ClaudeSection, '(?m)^\|.*\|\s*$'))
if ($ClaudeTableRows.Count -lt 5) { throw 'Claude系司令塔の節に既存のチェーン表が無い' }
if ($ClaudeSection -notmatch '(?m)^\|\s*実装以外\s*\|\s*codex\s*\|\s*$') {
    throw 'Claude系司令塔の実装以外は codex へ委託する'
}

$GptSection = [regex]::Match($text, '(?ms)^## GPT系司令塔.*?(?=^## |\z)').Value
$GptTableRows = @([regex]::Matches($GptSection, '(?m)^\|.*\|\s*$'))
if ($GptTableRows.Count -ne 0) { throw 'GPT系司令塔の節に自動委託チェーン表を置かない' }

foreach ($Phrase in @(
        '既定では別エージェントへ委託せず、自分で処理する',
        '現在の依頼でユーザーが委託を明示した場合だけ',
        'タスクの規模や種類、別モデルの有用性を理由に、委託を推測しない',
        '過去の依頼や外部記憶を次のタスクの許可として扱わない',
        '組み込みのサブエージェントを含む委託全般に適用する'
    )) {
    if ($GptSection -notmatch [regex]::Escape($Phrase)) {
        throw "GPT系司令塔の節に明示指示規約が無い: $Phrase"
    }
}

foreach ($Caller in @('claudex', '`codex` CLI')) {
    if ($GptSection -notmatch [regex]::Escape($Caller)) {
        throw "GPT系司令塔の節が呼び出し元を扱っていない: $Caller"
    }
}

if ($text -notmatch 'GPT系司令塔は、ユーザーが指定していない委託先へ自動フォールバックしない') {
    throw 'GPT系司令塔の自動フォールバック禁止が無い'
}

foreach ($Forbidden in @(
        'claudeへの委託は実装チェーンの最終backstop',
        'GPT系ならclaude',
        'それらは codex'
    )) {
    if ($text -match [regex]::Escape($Forbidden)) {
        throw "GPT系の自動委託へ戻す旧規約が残っている: $Forbidden"
    }
}

Write-Host 'RouteDelegationHost test PASSED'
