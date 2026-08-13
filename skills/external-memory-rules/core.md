---
type: system
status: active
created: 2026-06-30
updated: 2026-07-29
---

# 外部記憶ルール — Core

外部記憶VaultをClaude/Codex/Antigravityから保守するときの共有規約。各スキルはまず本ファイルに従う。

## Vault

- Vaultパス: `<vault-root>`
- 情報の正本はMarkdownファイルとする。特定のAIや外部サービスへ依存しない。
- Vaultは現状 git 管理されていない。履歴・復元をGit前提にしない。

## フォルダ分類と保存先

- `Inbox` 未整理のメモ・タスク・調査結果
- `Daily` 日次ノート
- `Knowledge` 再利用可能な知識
- `Decisions` 重要な判断と理由
- `Handoffs` セッション間の引き継ぎ資料（未消費を作業単位で保持し、`project` で束ねる）
- `Projects` 個人開発・生活上のプロジェクト
- `System` 本ルール群

## 情報の正本（重複させない）

- タスクの正本: 発生した文脈のノート
- プロジェクト状況の正本: 各Projectノート
- 再利用可能な技術知識の正本: Knowledgeノート
- 重要な判断と理由の正本: Decisionノート
- Knowledge / Decision は本文の `## 関連` に、関係するProjectノートへの `[[wikilink]]` を必ず置く。複数のProjectに関わる場合は複数書く。ProjectとKnowledge / Decisionの関連は、この逆向きのリンクとバックリンクだけで辿る。
- Handoff は本文の `## 関連リンク` に、対象Projectノートへの `[[wikilink]]` を必ず置く。Project から Handoff へのリンクは Todo項目内の外向きリンクだけなので、`tasks.md` のバックリンクによる一覧はこの逆リンクで成立する。
- 引き継ぎの正本: `Handoffs` の当該作業ノート（同一Projectに複数存在してよい。消費後は `scripts/archive-external-memory.ps1 -Category Handoffs` で Vault外 `<archive-root>\Handoffs` へ移動）
- 一時的な情報: Inbox または Daily
- 一覧用のBaseファイルは持たない。分類別の一覧はフォルダとバックリンクで代替する（`tasks.md`）。

## ノート形式の正本

- ノート形式は、repo の `skills/external-memory-rules` と各 `external-memory-*` スキルを正本とする。
- 共通Propertiesと種別固有Propertiesは `properties.md`、Projectの見出しは本ファイル、その他の見出しは作成を担当するスキルに置く。
- VaultにTemplatesを常設しない。Obsidianからの手動作成が必要になった時点で、必要な種別だけを追加する。
- Templates を再導入する場合、`{{date}}` `{{title}}` は markdown-format（prettier）が `{ { date } }` へ壊し、Obsidian が変数展開しなくなる。`Test-MarkdownFormatExcluded` へ除外を戻し、`tests/MarkdownFormat.Tests.ps1` の「除外しない」アサーションも同時に反転する。参照: Knowledge「prettier が Obsidian テンプレ構文を破壊する」

## Projectノート構成

Projectノートの標準見出しは次の順序にする。

1. `目的`
2. `現在の状態`
3. `Todo`
4. `作業ログ`

- `現在の状態` は5文以内の散文で書く。箇条書きを使わない。更新時は追記せず本文全体を置換する。
- `Todo` は未完了タスクだけを `- [ ]` で置く。完了分は削除する。
- `Todo` の各項目は動詞で終わる行動として書く。未確認の挙動や未決定の論点も「〜を検証する」「〜を判断する」の形にする。動詞で書けない項目はProjectノートに置かず、Knowledgeへ記録するか捨てる。
- `作業ログ` は直近10件まで、各1行で残す。
- 判断と再利用可能な知識をProjectノートへ列挙しない。正本は `Decisions` / `Knowledge` に置き、そちらからProjectノートへ `[[wikilink]]` する。Projectノートのバックリンクで辿る。
- 標準見出し以外を増やす場合は、Project固有の短期整理に限る。恒久的な知見・判断は Knowledge / Decision へ直接記録する。
- `Projects/雑務.md` は非紐付けタスク用のProjectノートとして扱い、`Todo` だけでもよい。

## 分類・昇格の判断

- Inbox項目は Project / Knowledge / Decision / Daily / Vault外archive へ分類する。判断できなければInboxに残す。
- 生活上の取り組みは、完了条件があればProjectとして扱う。継続的な管理領域の専用分類は、実運用が生じた時点で検討する。
- 作業中に明確なKnowledge・Decisionが出た場合は、`Knowledge` / `Decisions` へ直接記録する。追加確認は不要。
- 昇格確認が必要なのは、既存ノートから後で切り出す場合に限る。例: Project / Daily / Inbox の本文に混ざった知見・判断を、後から Knowledge / Decision へ分離・移動する場合。
- 内容が曖昧、保存先が迷う、秘密情報・資格情報・個人情報を含む、または既存文章の大幅な書き換え・移動・統合・Archive化を伴う場合もユーザー確認後に実行する。

## セッション記録

- 記録漏れの回収は`external-memory-session-digest`が行う。作業セッションの末尾ではなく、単独セッションとして起動する。
- digestは`claude-code-log`でtranscriptをMarkdownへ変換し、`git log`と突き合わせる。実行タイミングはユーザーが選ぶ。
- 処理済みの位置はProjectノートの`digested`がUTCで持つ。digestは処理した最後のセッションの終了時刻をUTCへ変換して進める。
- 引き継ぎは記録とは別の機構である。セッションを跨いで作業を続ける場合は、作業セッション内で`external-memory-handoff`を呼ぶ。

## ノート命名

- repo 連動Projectは `Projects/<repo名>.md` とする。`<repo名>` は対象リポジトリのディレクトリ名と同じ表記にする。
- repo に紐付かないProjectは `Projects/<日本語名>.md` とする。生活・運用・横断タスクなどは用途が分かる日本語名を使う。
- Handoffは `Handoffs/<project> - <work>.md` とする。`<project>` はProjectノート名（repo 連動なら repo 名、それ以外は日本語名）、`<work>` は作業名を使う。

## 記法

- ノートの作成・編集は Obsidian Flavored Markdown で行い、記法は `obsidian-markdown` スキルに従う。
- ノート間参照は wikilink `[[ノート名]]` を使う。

## 安全規則

- ファイルを直接削除しない。不要物は Vault外 `<archive-root>` へ移動する。
- 既存文章の大幅な書き換え・移動・統合・Archive化は事前にユーザー確認する。
- 通常の追記・新規作成は確認なしで実行してよい。
- 秘密情報・資格情報・個人情報は、保存先とバックアップ範囲を確認してから記録する。
- Vault全体を無条件にコンテキストへ読み込まない。必要な情報だけ検索する。
- 永続ノート（Knowledge / Decision）から、アーカイブ退避されうる揮発的ノートへリンクしない。
- Project から Handoff へのリンクは Todo項目内にのみ置く。Todo完了時に項目ごと削除し、リンクも同時に消す。
- ノートを Vault外アーカイブへ退避する前に、そのノートへの Vault内リンク（主に Project内 Todo）を先に除去する。退避後に死にリンクを残さない。
- Projectノートを退避する前に、Knowledge / Decision からの参照を除去または付け替える。永続ノート側に死にリンクを残さない。
- 退避は `scripts/archive-external-memory.ps1` を使う。Handoff は互換入口 `scripts/archive-handoff.ps1` も使える。退避前にVault内リンクを除去し、実行時は `-LinksRemoved` を付ける。日時付きファイル名で移動し、同名衝突を避ける。

## 報告

- Vaultを読み書きしたら、対象ファイルと内容をユーザーへ明示する。サイレントに読み書きしない。

## Git

- Vaultは現状 git 管理外。コミット運用を前提にしない。
- 将来Git化した場合のコミット作成は、明示依頼または承認済み手順に含まれる場合のみ行う。
