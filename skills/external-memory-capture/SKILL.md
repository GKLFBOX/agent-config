---
name: external-memory-capture
description: ユーザーが覚えておく、記録する、後で行う、買い物へ追加するなど、知識・思考・タスク・生活情報の外部記憶への保存を求めたときに使用する。
---

# External Memory: Capture

規約はサイドの正本に従う: `../external-memory-rules/core.md`（タスク記法は `../external-memory-rules/tasks.md`）。

1. 保存対象と文脈を短く整理する。
2. 保存先が明確なら Project / Daily / Knowledge / Decision の該当ノートへ追記する。
3. 保存先が不明なら `Inbox/YYYY-MM-DD - Capture.md` へ追記する。
4. タスクは `- [ ] 内容` 形式で、分かる場合だけ期限を付ける。
5. 更新したノートの `updated` を当日に更新する。
6. 保存先と記録内容をユーザーへ報告する。

## 新規ノート形式

共通Propertiesは `../external-memory-rules/properties.md` に従い、日付は作成日を `YYYY-MM-DD` で入れる。

- Decision: frontmatter は `type: decision`、`status: accepted`、`project`、`decided`、`supersedes`。本文は `## 決定`、`## 背景`、`## 選択肢`、`## 理由`、`## 影響`、`## 関連` の順。
- Knowledge: frontmatter は `type: knowledge`、`status: active`（または `idea`）、`topics`、`source`。`source` は `local-investigation` / `web-research` / `session` / `hands-on` から選ぶ。本文は `## 要点`、`## 詳細`、`## 適用場面`、`## 関連` の順。
- Knowledge / Decision の `## 関連` には、関係するProjectノートへの `[[wikilink]]` を必ず置く。Projectノート側は判断・知識を列挙せず、バックリンクで辿る。
