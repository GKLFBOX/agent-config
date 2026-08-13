BeforeAll {
    $script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    $script:Skills   = Join-Path $script:RepoRoot 'skills'
    $script:Rules    = Join-Path $script:Skills 'external-memory-rules'
    $script:RoleSkills = @(
        'external-memory-capture','external-memory-reference','external-memory-handoff',
        'external-memory-daily-plan','external-memory-inbox',
        'external-memory-session-digest','external-memory-maintenance'
    )
    $script:MirrorDetectionContract = @(
        '`& ''<repo-root>/scripts/status.ps1'' | Out-String -Width 4096`を実行する。`Out-String -Width 4096`は`Managed`列を表示して判定するための前提条件である。',
        '`vault-rules-mirror`と`vault-home`で始まる行を1行ずつ特定し、それぞれの`Managed`列が`True`か確認する。',
        '`Managed=False`は未解決のミラードリフトとして報告する。',
        '対象行の欠落は未解決のミラードリフトとして報告する。',
        '`Managed`列が表示されていない場合は検査未完了として報告する。',
        '`status.ps1`の不在は検査未完了として報告する。',
        '`status.ps1`の実行失敗は検査未完了として報告する。',
        '`sync-vault-mirror.ps1`は自動実行しない。'
    )
    $script:MirrorApplicationContract = @(
        'ドリフトを報告した後も、他の保守を続ける。',
        '検査未完了を報告した後も、他の保守を続ける。'
    )
}

Describe '正本ルールディレクトリ' {
    It 'index.md と core.md が存在する' {
        Test-Path (Join-Path $script:Rules 'index.md') | Should -BeTrue
        Test-Path (Join-Path $script:Rules 'core.md')  | Should -BeTrue
    }
    It 'core.md に正本Vaultパスが含まれる' {
        (Get-Content (Join-Path $script:Rules 'core.md') -Raw) | Should -Match '<vault-root>'
    }
    It 'core.md にフォルダ分類 Handoffs が含まれる' {
        (Get-Content (Join-Path $script:Rules 'core.md') -Raw) | Should -Match '`Handoffs`'
    }
    It '分類別一覧はフォルダとバックリンクで辿る' {
        $core = Get-Content (Join-Path $script:Rules 'core.md') -Raw
        $tasks = Get-Content (Join-Path $script:Rules 'tasks.md') -Raw

        $core | Should -Match '一覧用のBaseファイルは持たない'
        # 不在検査は節へ限定する。ファイル全体で Base を禁じると
        # 「Baseは持たない」という正しい説明自体が落ちる（偽陽性）。
        $folders = [regex]::Match($core, '(?ms)^## フォルダ分類と保存先\r?\n(.*?)(?=^## )').Groups[1].Value
        $folders | Should -Not -BeNullOrEmpty
        $folders | Should -Not -Match '\.base'
        $core | Should -Not -Match 'Dashboard\.md'
        $tasks | Should -Not -Match '\.base'
        $tasks | Should -Not -Match 'Dashboard\.md'
        $tasks | Should -Match 'バックリンクで確認する'
    }
    It 'Handoff は作業単位で、work property と archive script を使う' {
        $core = Get-Content (Join-Path $script:Rules 'core.md') -Raw
        $handoff = Get-Content (Join-Path $script:Skills 'external-memory-handoff/SKILL.md') -Raw
        $reference = Get-Content (Join-Path $script:Skills 'external-memory-reference/SKILL.md') -Raw
        $properties = Get-Content (Join-Path $script:Rules 'properties.md') -Raw

        $core | Should -Match '作業単位'
        $core | Should -Match '<project> - <work>\.md'
        $core | Should -Match 'Projectノート名'
        $core | Should -Not -Match '<Projectノート名>\.md'
        $handoff | Should -Match '<project> - <work>\.md'
        $handoff | Should -Match 'Projectノート名'
        $handoff | Should -Match '/ \\ : \* \? " < > \|'
        $handoff | Should -Match 'ハイフン'
        $handoff | Should -Match 'スクリプトを直接実行する場合'
        $handoff | Should -Match 'scripts/archive-handoff\.ps1'
        $core | Should -Match 'scripts/archive-external-memory\.ps1'
        $reference | Should -Match 'project.+一致'
        $reference | Should -Match 'repo 名'
        $reference | Should -Match '日本語名'
        $properties | Should -Match 'Handoff\s+\|\s+`Handoffs`\s+\|\s+`active`\s+\|\s+`project`, `work`, `next`'
    }
    It 'Project命名ルールとmaintenance検出条件が repo property を基準にする' {
        $core = Get-Content (Join-Path $script:Rules 'core.md') -Raw
        $maintenance = Get-Content (Join-Path $script:Skills 'external-memory-maintenance/SKILL.md') -Raw

        $core | Should -Match 'repo 連動Project'
        $core | Should -Match 'repo に紐付かないProject'
        $core | Should -Not -Match '\d\d (Inbox|Daily|Tasks|Projects|Knowledge|Decisions|Life|Handoffs|System|Archive)'
        $maintenance | Should -Match 'repo` property'
        $maintenance | Should -Match '判断できない英名は候補'
        $maintenance | Should -Match '計画・履歴文書は検出対象外'
        $maintenance | Should -Match '現行運用文書だけを候補'
        $maintenance | Should -Not -Match 'System/Docs'
    }
    It 'maintenance はVaultミラーのドリフトを検査し自動同期しない' {
        $maintenance = Get-Content (Join-Path $script:Skills 'external-memory-maintenance/SKILL.md') -Raw
        $detection = [regex]::Match(
            $maintenance,
            '(?ms)^## 検出\r?\n(.*?)(?=^## )'
        ).Groups[1].Value
        $application = [regex]::Match(
            $maintenance,
            '(?ms)^## 適用\r?\n(.*?)(?=^## |\z)'
        ).Groups[1].Value

        $detection | Should -Not -BeNullOrEmpty
        $application | Should -Not -BeNullOrEmpty
        foreach ($expected in $script:MirrorDetectionContract) {
            $detection | Should -Match (
                '(?m)^\d+\. {0}\r?$' -f [regex]::Escape($expected)
            )
        }
        foreach ($expected in $script:MirrorApplicationContract) {
            $application | Should -Match (
                '(?m)^\d+\. {0}\r?$' -f [regex]::Escape($expected)
            )
        }
    }
    It 'maintenance の契約は意味を反転した本文を拒否する' {
        $invalidMaintenance = @'
## 検出

1. `& '<repo-root>/scripts/status.ps1' | Out-String -Width 4096`を実行するが、`Managed`列は確認しない。
2. `vault-rules-mirror`と`vault-home`の対象行は探すが、`Managed=False`でもドリフトは報告しない。
3. 対象行の欠落や`status.ps1`の不在、実行失敗は検査未完了とは扱わない。
4. `sync-vault-mirror.ps1`を自動実行しないとは限らない。

## 適用

5. ドリフトを報告した後は、他の保守を続けない。
6. 検査未完了を報告した後は、他の保守を続けない。
'@
        $detection = [regex]::Match(
            $invalidMaintenance,
            '(?ms)^## 検出\r?\n(.*?)(?=^## )'
        ).Groups[1].Value
        $application = [regex]::Match(
            $invalidMaintenance,
            '(?ms)^## 適用\r?\n(.*?)(?=^## |\z)'
        ).Groups[1].Value

        foreach ($expected in $script:MirrorDetectionContract) {
            $detection | Should -Not -Match (
                '(?m)^\d+\. {0}\r?$' -f [regex]::Escape($expected)
            )
        }
        foreach ($expected in $script:MirrorApplicationContract) {
            $application | Should -Not -Match (
                '(?m)^\d+\. {0}\r?$' -f [regex]::Escape($expected)
            )
        }
    }
    It 'core.md のProjectノート構成が4見出しで肥大を防ぐ' {
        $core = Get-Content (Join-Path $script:Rules 'core.md') -Raw
        $section = [regex]::Match($core, '(?ms)^## Projectノート構成\r?\n(.*?)(?=^## )').Groups[1].Value
        $section | Should -Not -BeNullOrEmpty

        # 番号付きリストから見出しを取り出して比較する。語の存在確認では
        # 順序の誤りも5個目の見出しの追加も検出できない。
        $headings = @([regex]::Matches($section, '(?m)^\d+\. `(.+?)`') | ForEach-Object { $_.Groups[1].Value })
        $headings | Should -Be @('目的','現在の状態','Todo','作業ログ')

        $section | Should -Match '5文以内の散文'
        $section | Should -Match '箇条書きを使わない'
        $section | Should -Match '直近10件'
        $section | Should -Match '動詞で終わる行動'
        $core | Should -Match '直接記録'
        $core | Should -Match '切り出す'
    }
    It 'tasks.md のTodo記法が動詞形を要求する' {
        $tasks = Get-Content (Join-Path $script:Rules 'tasks.md') -Raw

        $tasks | Should -Match '動詞で終わる行動'
        $tasks | Should -Match 'チェックボックスの横断集約はしない'
    }
    It 'Knowledge と Decision がProjectノートへ逆リンクする' {
        $core = Get-Content (Join-Path $script:Rules 'core.md') -Raw
        $capture = Get-Content (Join-Path $script:Skills 'external-memory-capture/SKILL.md') -Raw

        $core | Should -Match 'Projectノートへの `\[\[wikilink\]\]` を必ず置く'
        $capture | Should -Match '`## 影響`、`## 関連`'
        $capture | Should -Match 'Knowledge / Decision の `## 関連`'

        $maintenance = Get-Content (Join-Path $script:Skills 'external-memory-maintenance/SKILL.md') -Raw
        $core | Should -Match 'Projectノートを退避する前に'
        $maintenance | Should -Match 'Projectノートへの `\[\[wikilink\]\]` を持たない'
    }
    It 'project property は素の文字列と定める' {
        # 書式が `[[名前]]` や引用符付きへ揺れると、reference の property 絞り込みと
        # maintenance の照合が壊れる。property名だけ決めても防げない。
        $properties = Get-Content (Join-Path $script:Rules 'properties.md') -Raw
        $properties | Should -Match 'project` と `repo` はProjectノート名の素の文字列'
        $properties | Should -Match 'wikilink'
    }
    It 'core が digest を単独セッションと定め handoff と役割を分ける' {
        $core = Get-Content (Join-Path $script:Rules 'core.md') -Raw

        $core | Should -Match '## セッション記録'
        $core | Should -Match 'external-memory-session-digest'
        $core | Should -Match '単独セッション'
        $core | Should -Match '`digested`'
        $core | Should -Not -Match 'external-memory-session-close'
    }
    It 'Project が digested property を持ち日時形式を定める' {
        # digest は `--from-date` へこの値を渡す。日付粒度だと同じ日の複数回実行で
        # 処理済みの位置を表せない。
        $properties = Get-Content (Join-Path $script:Rules 'properties.md') -Raw

        $properties | Should -Match 'Project\s+\|\s+`Projects`\s+\|\s+`active` / `planned`\s+\|\s+`repo`, `digested`'
        $properties | Should -Match 'YYYY-MM-DDThh:mm'
        $properties | Should -Match 'UTC'
        $properties | Should -Match 'タイムゾーン接尾辞を持たない'
        $properties | Should -Match 'external-memory-session-digest'
    }
    It 'Handoff も対象Projectノートへ逆リンクする' {
        # tasks.md は Handoff を「Projectノートのバックリンクで確認する」と定めるが、
        # core.md が要求する Project から Handoff へのリンクは Todo 項目内の外向きリンク。
        # 一覧手段を成立させるには Handoff 側からの逆リンクが要る。
        $core = Get-Content (Join-Path $script:Rules 'core.md') -Raw
        $handoff = Get-Content (Join-Path $script:Skills 'external-memory-handoff/SKILL.md') -Raw

        $core | Should -Match 'Handoff は本文の `## 関連リンク`'
        $handoff | Should -Match '`## 関連リンク` には対象Projectノートへの `\[\[wikilink\]\]`'
    }
    It 'ルール群に旧Vaultパス Obsidian Vault が無い' {
        foreach ($f in Get-ChildItem $script:Rules -Filter *.md) {
            (Get-Content $f.FullName -Raw) | Should -Not -Match 'Obsidian Vault'
        }
    }
}

Describe '外部記憶 役割スキル' {
    It '役割スキルが SKILL.md を持つ' {
        foreach ($s in $script:RoleSkills) {
            Test-Path (Join-Path $script:Skills "$s/SKILL.md") | Should -BeTrue
        }
    }
    It '各スキルが external-memory-rules を参照する' {
        foreach ($s in $script:RoleSkills) {
            (Get-Content (Join-Path $script:Skills "$s/SKILL.md") -Raw) | Should -Match 'external-memory-rules'
        }
    }
    It '各スキルに旧Vaultパス Obsidian Vault が無い' {
        foreach ($s in $script:RoleSkills) {
            (Get-Content (Join-Path $script:Skills "$s/SKILL.md") -Raw) | Should -Not -Match 'Obsidian Vault'
        }
    }
    It '各スキルが安全規則「直接削除」を再掲しない' {
        foreach ($s in $script:RoleSkills) {
            (Get-Content (Join-Path $script:Skills "$s/SKILL.md") -Raw) | Should -Not -Match '直接削除'
        }
    }
    It '役割スキルが未解決事項セクションを前提にしない' {
        foreach ($s in $script:RoleSkills) {
            (Get-Content (Join-Path $script:Skills "$s/SKILL.md") -Raw) | Should -Not -Match '未解決事項'
        }
    }
    It 'reference が関連ノートをバックリンク方向で探す' {
        $reference = Get-Content (Join-Path $script:Skills 'external-memory-reference/SKILL.md') -Raw

        $reference | Should -Match 'Projectノートへ `\[\[wikilink\]\]` しているノートを検索'
        $reference | Should -Not -Match 'ProjectノートからリンクされたDecision'
    }
    It 'handoff が現在の状態を散文で置換し作業ログを10件に保つ' {
        $handoff = Get-Content (Join-Path $script:Skills 'external-memory-handoff/SKILL.md') -Raw

        $handoff | Should -Match '散文で置換'
        $handoff | Should -Match '直近10件'
        $handoff | Should -Not -Match '直近5件'
    }
    It 'digest が単独セッションでtranscriptから記録する' {
        $digest = Get-Content (Join-Path $script:Skills 'external-memory-session-digest/SKILL.md') -Raw

        $digest | Should -Match 'claude-code-log'
        $digest | Should -Match '--detail minimal'
        $digest | Should -Match 'PYTHONIOENCODING=utf-8'
        $digest | Should -Match 'git log'
        $digest | Should -Match '単独セッション'
        $digest | Should -Match 'external-memory-capture'
        $digest | Should -Match '`digested`'
    }
    It 'digest が膨張するdetail段を使わない' {
        # high はスキルファイル全文を含んで92kまで膨らむ。full は全部入り。
        $digest = Get-Content (Join-Path $script:Skills 'external-memory-session-digest/SKILL.md') -Raw

        $digest | Should -Not -Match '--detail high'
        $digest | Should -Not -Match '--detail full'
    }
    It 'digest が UTC を CLI ごとの時刻表現へ変換する' {
        $digest = Get-Content (Join-Path $script:Skills 'external-memory-session-digest/SKILL.md') -Raw

        $digest | Should -Match '--from-date <digested-utc>'
        $digest | Should -Match '--since=<digested-utc>Z'
        $digest | Should -Match 'オフセットを解釈しない'
        $digest | Should -Match '同じ瞬間'
    }
    It 'digest が git log --since の時刻補完を警告する' {
        # 時刻なしの日付を渡すと git が現在時刻で補完し、当日のコミットを落とす。
        $digest = Get-Content (Join-Path $script:Skills 'external-memory-session-digest/SKILL.md') -Raw

        $digest | Should -Match '--since`へ時刻なしの日付を渡さない'
        $digest | Should -Match '現在時刻で補完'
    }
    It 'session-close が廃止され参照も残らない' {
        Test-Path (Join-Path $script:Skills 'external-memory-session-close') | Should -BeFalse

        # $home はPowerShellの自動変数のため別名を使う。
        $homeNote = Get-Content (Join-Path $script:RepoRoot 'vault/Home.md') -Raw
        $homeNote | Should -Not -Match 'session-close'
        $homeNote | Should -Match 'external-memory-session-digest'
    }
    It 'ノート形式はスキルとルールを正本にする' {
        $core = Get-Content (Join-Path $script:Rules 'core.md') -Raw
        $capture = Get-Content (Join-Path $script:Skills 'external-memory-capture/SKILL.md') -Raw
        $daily = Get-Content (Join-Path $script:Skills 'external-memory-daily-plan/SKILL.md') -Raw
        $handoff = Get-Content (Join-Path $script:Skills 'external-memory-handoff/SKILL.md') -Raw

        $core | Should -Match 'ノート形式の正本'
        $core | Should -Not -Match '`System` Templates'
        $core | Should -Match 'Templates を再導入する場合'
        $core | Should -Match 'Test-MarkdownFormatExcluded'
        $daily | Should -Match 'type: daily`、`created`、`updated`'
        $daily | Should -Not -Match '`status`'
        $daily | Should -Not -Match '`date`'
        foreach ($skill in @($capture, $daily, $handoff)) {
            $skill | Should -Not -Match 'System/Templates'
        }
        foreach ($text in @('type: daily','## 今日の計画','## タスク','## メモ','## 完了・振り返り')) {
            $daily | Should -Match $text
        }
        foreach ($text in @('type: handoff','status: active','project:','work:','next:','## 現在地','## 次アクション','## 未解決','## 関連リンク')) {
            $handoff | Should -Match $text
        }
        foreach ($text in @('type: decision','## 決定','## 背景','## 選択肢','## 理由','## 影響','type: knowledge','## 要点','## 詳細','## 適用場面','## 関連')) {
            $capture | Should -Match $text
        }
    }
    It 'Properties規約が廃止属性を持たず、status語彙とsource enumを定義する' {
        $properties = Get-Content (Join-Path $script:Rules 'properties.md') -Raw
        $core = Get-Content (Join-Path $script:Rules 'core.md') -Raw
        $capture = Get-Content (Join-Path $script:Skills 'external-memory-capture/SKILL.md') -Raw
        $handoff = Get-Content (Join-Path $script:Skills 'external-memory-handoff/SKILL.md') -Raw

        foreach ($retired in @('`tags`', '`area`', '`review`')) {
            $properties | Should -Not -Match ([regex]::Escape($retired))
        }
        $handoff | Should -Not -Match '`tags`'

        foreach ($kind in @('Project', 'Knowledge', 'Decision', 'Handoff', 'Capture', 'System', 'Dashboard', 'Daily')) {
            $properties | Should -Match "\|\s+$kind\s+\|"
        }

        $properties | Should -Match '`accepted` / `superseded`'
        $properties | Should -Match '`active` / `planned`'
        $properties | Should -Match '`active` / `idea`'
        $properties | Should -Match 'Daily\s+\|\s+`Daily`\s+\|\s+持たない'

        $properties | Should -Match 'local-investigation'
        $properties | Should -Match 'web-research'
        $properties | Should -Match 'hands-on'
        $capture | Should -Match 'local-investigation'

        $properties | Should -Match '機械的移行では更新しない'
        $properties | Should -Match 'supersedes` で参照されたノートは `status: superseded`'

        $core | Should -Not -Match '(?m)^tags:'
        $properties | Should -Not -Match '(?m)^tags:'
    }
}

Describe '外部記憶 SessionStart hook' {
    It 'SessionStart に外部記憶参照 hook が登録されている' {
        $settings = Get-Content (Join-Path $script:RepoRoot 'claude/settings.json') -Raw | ConvertFrom-Json
        $hooks = @($settings.hooks.SessionStart.hooks)
        @($hooks | Where-Object { $_.command -like '*external-memory-start.mjs*' }).Count | Should -Be 1
    }
    It 'hook は external-memory-reference の使用を追加コンテキストへ入れる' {
        $scriptPath = Join-Path $script:RepoRoot 'claude/hooks/external-memory-start.mjs'
        $json = (& node $scriptPath | Out-String) | ConvertFrom-Json
        $json.hookSpecificOutput.hookEventName | Should -Be 'SessionStart'
        $json.hookSpecificOutput.additionalContext | Should -Match 'external-memory-reference'
    }
}

Describe 'External memory archive script' {
    It 'カテゴリ別に元のファイル名で Vault 外へ移動する' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts/archive-external-memory.ps1'
        Test-Path $scriptPath | Should -BeTrue

        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("external-memory-archive-test-" + [guid]::NewGuid().ToString('N'))
        $sourceDir = Join-Path $tempRoot 'source'
        $archiveRoot = Join-Path $tempRoot 'archive'
        New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null

        try {
            $source = Join-Path $sourceDir 'inbox memo.md'
            Set-Content -LiteralPath $source -Value 'inbox body'

            $resultJson = & $scriptPath -Path $source -Category Inbox -ArchiveRoot $archiveRoot -KeepOriginalName -LinksRemoved
            $result = $resultJson | ConvertFrom-Json
            $expectedArchivePath = Join-Path (Join-Path $archiveRoot 'Inbox') 'inbox memo.md'

            Test-Path $source | Should -BeFalse
            $result.archivePath | Should -Be ([System.IO.Path]::GetFullPath($expectedArchivePath))
            $result.category | Should -Be 'Inbox'
            (Get-Content -LiteralPath $result.archivePath -Raw).Trim() | Should -Be 'inbox body'
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot) {
                $testTrashRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'external-memory-archive-test-trash'
                New-Item -ItemType Directory -Force -Path $testTrashRoot | Out-Null
                Move-Item -LiteralPath $tempRoot -Destination (Join-Path $testTrashRoot (Split-Path -Leaf $tempRoot))
            }
        }
    }

    It '環境変数で Vault 外 archive root を上書きできる' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts/archive-external-memory.ps1'
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("external-memory-archive-env-test-" + [guid]::NewGuid().ToString('N'))
        $sourceDir = Join-Path $tempRoot 'source'
        $envArchiveRoot = Join-Path $tempRoot 'env-archive'
        New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null
        $previousArchiveRoot = $env:EXTERNAL_MEMORY_ARCHIVE_ROOT

        try {
            $source = Join-Path $sourceDir 'project note.md'
            Set-Content -LiteralPath $source -Value 'project body'
            $env:EXTERNAL_MEMORY_ARCHIVE_ROOT = $envArchiveRoot

            $resultJson = & $scriptPath -Path $source -Category Projects -LinksRemoved
            $result = $resultJson | ConvertFrom-Json

            $result.archivePath | Should -Match ([regex]::Escape((Join-Path $envArchiveRoot 'Projects')))
            Test-Path $result.archivePath | Should -BeTrue
        }
        finally {
            $env:EXTERNAL_MEMORY_ARCHIVE_ROOT = $previousArchiveRoot
            if (Test-Path -LiteralPath $tempRoot) {
                $testTrashRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'external-memory-archive-test-trash'
                New-Item -ItemType Directory -Force -Path $testTrashRoot | Out-Null
                Move-Item -LiteralPath $tempRoot -Destination (Join-Path $testTrashRoot (Split-Path -Leaf $tempRoot))
            }
        }
    }

    It 'Vault 内リンク確認を促す警告を出せる' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts/archive-external-memory.ps1'
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("external-memory-archive-warning-test-" + [guid]::NewGuid().ToString('N'))
        $sourceDir = Join-Path $tempRoot 'source'
        $archiveRoot = Join-Path $tempRoot 'archive'
        New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null

        try {
            $source = Join-Path $sourceDir 'linked note.md'
            Set-Content -LiteralPath $source -Value 'linked body'
            $warningRecords = @()

            $resultJson = & $scriptPath -Path $source -Category Inbox -ArchiveRoot $archiveRoot -WarningVariable warningRecords
            $result = $resultJson | ConvertFrom-Json

            $result.category | Should -Be 'Inbox'
            ($warningRecords | Out-String) | Should -Match 'Vault links'
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot) {
                $testTrashRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'external-memory-archive-test-trash'
                New-Item -ItemType Directory -Force -Path $testTrashRoot | Out-Null
                Move-Item -LiteralPath $tempRoot -Destination (Join-Path $testTrashRoot (Split-Path -Leaf $tempRoot))
            }
        }
    }

    It 'WhatIf では移動も退避先作成もしない' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts/archive-external-memory.ps1'
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("external-memory-archive-whatif-test-" + [guid]::NewGuid().ToString('N'))
        $sourceDir = Join-Path $tempRoot 'source'
        $archiveRoot = Join-Path $tempRoot 'archive'
        New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null

        try {
            $source = Join-Path $sourceDir 'whatif note.md'
            Set-Content -LiteralPath $source -Value 'whatif body'

            & $scriptPath -Path $source -Category Inbox -ArchiveRoot $archiveRoot -LinksRemoved -WhatIf

            Test-Path $source | Should -BeTrue
            Test-Path $archiveRoot | Should -BeFalse
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot) {
                $testTrashRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'external-memory-archive-test-trash'
                New-Item -ItemType Directory -Force -Path $testTrashRoot | Out-Null
                Move-Item -LiteralPath $tempRoot -Destination (Join-Path $testTrashRoot (Split-Path -Leaf $tempRoot))
            }
        }
    }

    It 'ファイル単位退避のスクリプトであることを明記する' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts/archive-external-memory.ps1'
        $script = Get-Content -LiteralPath $scriptPath -Raw

        $script | Should -Match 'Moves a single file'
        $script | Should -Match 'Directory archives are not supported'
    }

    It 'Category の ValidateSet が7分類だけで Life / Tasks を含まない' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts/archive-external-memory.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
        $categoryParam = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Category' }
        $validateSet = $categoryParam.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateSet' }
        $values = $validateSet.PositionalArguments.Value

        $values | Should -Be @('Inbox', 'Daily', 'Knowledge', 'Decisions', 'Handoffs', 'Projects', 'System')
        $values | Should -Not -Contain 'Life'
        $values | Should -Not -Contain 'Tasks'
    }
}

Describe 'Handoff archive script' {
    It 'Handoff を日時付きファイル名で Vault 外 archive へ移動する' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts/archive-handoff.ps1'
        Test-Path $scriptPath | Should -BeTrue

        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("handoff-archive-test-" + [guid]::NewGuid().ToString('N'))
        $vaultRoot = Join-Path $tempRoot 'vault'
        $archiveRoot = Join-Path $tempRoot 'archive'
        $handoffDir = Join-Path $vaultRoot 'Handoffs'
        New-Item -ItemType Directory -Force -Path $handoffDir | Out-Null

        try {
            $source = Join-Path $handoffDir 'agent-config - handoff-work-items.md'
            Set-Content -LiteralPath $source -Value 'handoff body'

            $resultJson = & $scriptPath -Path $source -ArchiveRoot $archiveRoot -LinksRemoved
            $result = $resultJson | ConvertFrom-Json

            Test-Path $source | Should -BeFalse
            Test-Path $result.archivePath | Should -BeTrue
            Split-Path -Leaf $result.archivePath | Should -Match '^\d{8}-\d{6}-\d{3}-\d{3}_agent-config - handoff-work-items\.md$'
            (Get-Content -LiteralPath $result.archivePath -Raw).Trim() | Should -Be 'handoff body'
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot) {
                $testTrashRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'handoff-archive-test-trash'
                New-Item -ItemType Directory -Force -Path $testTrashRoot | Out-Null
                Move-Item -LiteralPath $tempRoot -Destination (Join-Path $testTrashRoot (Split-Path -Leaf $tempRoot))
            }
        }
    }

    It '環境変数で archive root を上書きできる' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts/archive-handoff.ps1'
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("handoff-archive-env-test-" + [guid]::NewGuid().ToString('N'))
        $sourceDir = Join-Path $tempRoot 'source'
        $envArchiveRoot = Join-Path $tempRoot 'env-archive'
        New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null
        $previousArchiveRoot = $env:EXTERNAL_MEMORY_HANDOFF_ARCHIVE_ROOT

        try {
            $source = Join-Path $sourceDir 'agent-config - env-root.md'
            Set-Content -LiteralPath $source -Value 'env body'
            $env:EXTERNAL_MEMORY_HANDOFF_ARCHIVE_ROOT = $envArchiveRoot

            $resultJson = & $scriptPath -Path $source -LinksRemoved
            $result = $resultJson | ConvertFrom-Json

            $result.archivePath | Should -Match ([regex]::Escape($envArchiveRoot))
            Test-Path $result.archivePath | Should -BeTrue
        }
        finally {
            $env:EXTERNAL_MEMORY_HANDOFF_ARCHIVE_ROOT = $previousArchiveRoot
            if (Test-Path -LiteralPath $tempRoot) {
                $testTrashRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'handoff-archive-test-trash'
                New-Item -ItemType Directory -Force -Path $testTrashRoot | Out-Null
                Move-Item -LiteralPath $tempRoot -Destination (Join-Path $testTrashRoot (Split-Path -Leaf $tempRoot))
            }
        }
    }

    It 'WhatIf を汎用 archive script へ伝播する' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts/archive-handoff.ps1'
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("handoff-archive-whatif-test-" + [guid]::NewGuid().ToString('N'))
        $sourceDir = Join-Path $tempRoot 'source'
        $archiveRoot = Join-Path $tempRoot 'archive'
        New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null

        try {
            $source = Join-Path $sourceDir 'agent-config - whatif.md'
            Set-Content -LiteralPath $source -Value 'whatif body'

            & $scriptPath -Path $source -ArchiveRoot $archiveRoot -LinksRemoved -WhatIf

            Test-Path $source | Should -BeTrue
            Test-Path $archiveRoot | Should -BeFalse
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot) {
                $testTrashRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'handoff-archive-test-trash'
                New-Item -ItemType Directory -Force -Path $testTrashRoot | Out-Null
                Move-Item -LiteralPath $tempRoot -Destination (Join-Path $testTrashRoot (Split-Path -Leaf $tempRoot))
            }
        }
    }

    It '存在しない Handoff は archive せず失敗する' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts/archive-handoff.ps1'
        $missingPath = Join-Path ([System.IO.Path]::GetTempPath()) ("missing-handoff-" + [guid]::NewGuid().ToString('N') + '.md')

        { & $scriptPath -Path $missingPath } | Should -Throw 'Handoff file does not exist*'
    }
}
