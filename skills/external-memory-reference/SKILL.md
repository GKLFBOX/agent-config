---
name: external-memory-reference
description: 個人開発セッションの開始・再開時、または作業中に過去のプロジェクト状態・Todo・判断・知識を参照したいときに、中央の外部記憶Vaultから読み出す。
---

# External Memory: Reference

規約は正本に従う: `../external-memory-rules/core.md`。Vaultは変更しない。

1. 現在のリポジトリ名・パス・ユーザー指定から対象プロジェクトを特定する。
2. `Handoffs` から `project` が対象Projectと一致する未消費Handoffを探す。repo 連動は repo 名、それ以外は日本語名のProjectノート名で照合する。作業名が指定されていれば `work` も一致するHandoffを優先する。
3. 複数の未消費Handoffがある場合は、作業名・`next`・更新日を一覧し、読む対象を絞る。指定がなければ関連しそうなものだけ読む。
4. `Projects` からProjectノートを探す。repo 連動はファイル名または `repo` が一致するノート、それ以外は日本語名のノートを対象にする。
5. Projectノートの目的・現在の状態・Todo・直近の作業ログを読む。
6. `Decisions` と `Knowledge` から、対象Projectノートへ `[[wikilink]]` しているノートを検索し、必要なものだけ読む。Decisionは `project` property でも絞れる。
7. 見つからない場合は不明と伝え、新規Projectノートの作成を提案する。
8. 要点と推奨するTodoを簡潔に提示する。
