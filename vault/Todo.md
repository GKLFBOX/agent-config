---
type: dashboard
status: active
created: 2026-08-15
updated: 2026-08-15
---

<!-- agent-config: generated mirror — 正本は agent-config リポジトリ vault/Todo.md。再同期: ./scripts/sync-vault-mirror.ps1。Obsidian での直接編集は sync で上書きされます。 -->

# Todo

`Projects` 配下の未完了タスクを組み込み検索で横断表示する。タスクの正本は各Projectノートのチェックボックスで、ここは表示だけを持つ。

```query
path:"Projects/" task-todo:/./
```

検索結果のチェックボックスは操作できない。完了するには行をクリックして元のノートを開く。
