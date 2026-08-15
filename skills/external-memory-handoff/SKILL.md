---
name: external-memory-handoff
description: ユーザーが今日はここまで、引き継いで、外部記憶へ保存してなど、個人開発セッションの終了と引き継ぎ保存を求めたときに使用する。
---

# External Memory: Handoff

規約は正本に従う: `../external-memory-rules/core.md`。

引き継ぎは作業単位。`Handoffs/<project> - <work>.md` に現行の作業Handoffを置く。同一Projectに複数作業のHandoffが存在してよい。`<project>` はProjectノート名に合わせる（repo 連動なら repo 名、それ以外は日本語名）。

1. 対象Projectノートを特定する（repo 連動なら repo 名、それ以外は日本語名）。
2. 作業名を決める。ブランチ名・Issue名・依頼名など、並行作業を区別できる短い名前を使う。ファイル名に使う前に `/ \ : * ? " < > |` をハイフンへ置換する。
3. 同じ `<project> - <work>.md` の現行Handoffがあるか確認する。
4. 作業を継続するか完了するか判定する。セッションを跨ぐ、または次作業が確定していれば継続とする。タスクが完全完了していれば完了とする。
5. 継続する場合、既存HandoffがあればProjectノートのTodoからリンクを外す。そのHandoffを `scripts/archive-handoff.ps1 -LinksRemoved` で Vault外 `<archive-root>\Handoffs` へ退避する。次に新しいHandoffを `Handoffs/<project> - <work>.md` へ次の形式で新規作成し、Todoへリンクを戻す。既存Handoffがなければリンクを追加する。既存Handoffを直接更新しない。
6. 完了する場合、ProjectノートのTodo項目を削除し、既存Handoffがあれば `scripts/archive-handoff.ps1 -LinksRemoved` で退避する。新しいHandoffは作成しない。
7. `scripts/archive-handoff.ps1` は `scripts/archive-external-memory.ps1 -Category Handoffs` の互換入口である。スクリプトを直接実行する場合も、先にVault内リンクを除去する。
8. 同じProjectの別作業Handoffは退避しない。
9. Projectノートの現在の状態を5文以内の散文で置換し、作業ログへ1行追記する（直近10件を超える古い行は削除）。
10. 重要な判断・再利用可能な知識が明確なら、`external-memory-capture` で Decision / Knowledge へ直接保存する。既存ノートから後で切り出す場合だけ候補を提示し、承認後に実行する。
11. 更新したノートの `updated` を当日に更新する。
12. 保存内容と次回の開始点を報告する。

## 新規ノート形式

- Frontmatter: `type: handoff`、`status: active`、`project:`、`work:`、`next:`、`created`、`updated`。
- タイトル: `# 引き継ぎ: <project> - <work>`
- 本文: `## 現在地`、`## 次アクション`、`## 未解決`、`## 関連リンク` の順。`## 関連リンク` には対象Projectノートへの `[[wikilink]]` を必ず置く（Projectノートのバックリンクから辿れるようにするため）。
