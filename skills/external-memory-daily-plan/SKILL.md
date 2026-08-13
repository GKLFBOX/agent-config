---
name: external-memory-daily-plan
description: ユーザーが今日やること、今日の計画、未完了タスク、期限切れタスクの整理を求めたときに使用する。
---

# External Memory: Daily Plan

規約は正本に従う: `../external-memory-rules/core.md`（タスク集約対象は `../external-memory-rules/tasks.md`）。

1. `Daily/YYYY-MM-DD.md` を次の形式で作成または読む。
2. タスク集約対象フォルダの未完了タスクから、期限切れ・本日期限・次の7日間を抽出する。
3. アクティブProjectノートの「Todo」を確認する。
4. `Inbox` の未処理件数を確認する。
5. 今日の計画案を提示する。
6. 優先順位変更・延期はユーザー承認後に反映する。
7. 承認された計画をDailyノートの「今日の計画」へ記録する。

## 新規ノート形式

- Frontmatter: `type: daily`、`created`、`updated`。日付はファイル名 `YYYY-MM-DD.md` で表し、frontmatterへ再掲しない。
- タイトル: `# YYYY-MM-DD`
- 本文: `## 今日の計画`、`## タスク`、`## メモ`、`## 完了・振り返り` の順。
