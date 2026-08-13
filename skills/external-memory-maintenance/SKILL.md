---
name: external-memory-maintenance
description: 外部記憶Vaultのリンク切れ・属性不整合・フォルダやファイル名のゆれ・重複ノート・Vaultミラードリフトを検出して正規化したいときに使用する。
---

# External Memory: Maintenance

規約は正本に従う: `../external-memory-rules/core.md`（分類）、`../external-memory-rules/properties.md`（属性）、`../external-memory-rules/tasks.md`（タスク）。記法は `obsidian-markdown` スキルに従う。

## 検出

1. wikilink の切れ（参照先ノート不在）を洗い出す。
2. Properties がスキーマに合わないノートを洗い出す。
3. トップレベルが Inbox / Daily / Knowledge / Decisions / Handoffs / Projects / System の7分類だけか確認し、番号付き・未使用フォルダを洗い出す。
4. ファイル名のゆれを洗い出す。Projectは `repo` property があれば repo 名と比較し、なければ日本語名か確認する。Handoffは `project` property と `<project> - <work>.md` の `<project>` を比較する。判断できない英名は候補に留める。
5. 同一 repo・同一主題の重複ノートを洗い出す。
6. Knowledge / Decision のうち、関係するProjectノートへの `[[wikilink]]` を持たないノートを洗い出す。
7. 旧パスなどの古い記述を探す場合、計画・履歴文書は検出対象外にし、現行運用文書だけを候補にする。
8. `& '<repo-root>/scripts/status.ps1' | Out-String -Width 4096`を実行する。`Out-String -Width 4096`は`Managed`列を表示して判定するための前提条件である。
9. `vault-rules-mirror`と`vault-home`で始まる行を1行ずつ特定し、それぞれの`Managed`列が`True`か確認する。
10. `Managed=False`は未解決のミラードリフトとして報告する。
11. 対象行の欠落は未解決のミラードリフトとして報告する。
12. `Managed`列が表示されていない場合は検査未完了として報告する。
13. `status.ps1`の不在は検査未完了として報告する。
14. `status.ps1`の実行失敗は検査未完了として報告する。
15. `sync-vault-mirror.ps1`は自動実行しない。

## 適用

16. ドリフトを報告した後も、他の保守を続ける。
17. 検査未完了を報告した後も、他の保守を続ける。
18. 安全な修正（リンク張り直し、属性補完）は自動で適用する。
19. 危険な操作（移動・統合・Archive化・大幅な書き換え）は core.md 安全規則に従い、一覧で提示してユーザー承認後に実行する。
20. 検出結果・適用内容・残件をレポートする。
