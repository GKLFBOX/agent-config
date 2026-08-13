---
type: system
status: active
created: 2026-06-30
updated: 2026-07-29
---

# 外部記憶ルール（Index）

外部記憶Vaultの運用規約。スキルと人間が参照する単一正本。

- [[core]] — 共有コア（Vault / 分類 / 正本 / Projectノート構成 / 昇格 / 命名 / 記法 / 安全 / 報告 / Git）
- [[properties]] — Properties スキーマ
- [[tasks]] — タスク管理規則

正本の所在は agent-config リポジトリ `skills/external-memory-rules/`。Vault側の本ディレクトリはその**生成コピー**（Google Drive 同期と両立させるため symlink を使わない）であり、編集は正本側で行う（コピーは再同期 `./scripts/sync-vault-mirror.ps1` で上書きされる）。
