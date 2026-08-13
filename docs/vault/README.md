# Vault

## 目的

- 外部記憶 Vault と agent-config リポジトリ側正本の関係をまとめる。
- Vault 側 mirror が symlink ではなく copy である理由と同期方法を明示する。
- 関連: [skills](../skills/README.md), [scripts](../scripts/README.md)

## 構成

- `vault/Home.md` - Vault 直下へ配布する Home ノート（クイックヘルプ＋仕様概要）の正本。
- `skills/external-memory-rules/` - Vault 運用規約の正本。
- `scripts/sync-vault-mirror.ps1` - copy / copy-file mirror を再同期する script。
- `scripts/lib/AgentConfig.psm1` - Vault mirror の配置ターゲットと copy 実装。

## 使い方・挙動

- `vault/Home.md` は `<vault-root>\Home.md` へ CopyFile 配布される。
- `skills/external-memory-rules/` は `<vault-root>\System\external-memory-rules` へ Copy 配布される。
- copy mirror は Google Drive sync と両立させるため symlink / junction を使わない。
- `scripts/sync-vault-mirror.ps1` は `Method` が `Copy` / `CopyFile` のターゲットだけを同期する。対象は Vault 限定ではなく、`~/.local/bin` の codex シムも同じ経路で配る（`docs/scripts/README.md`）。
- `vault/Home.md` には生成 mirror marker があり、Obsidian で直接編集しても sync で上書きされると明記されている。
- `skills/external-memory-rules/index.md` も Vault 側は生成コピーで、編集は正本側で行うと明記する。

## 依存・前提

- Vault path は `<vault-root>`。
- Vault は Google Drive sync 下にあるため symlink / junction が同期エラーになる、という前提が `scripts/lib/AgentConfig.psm1` に記載されている。
- Vault は現状 git 管理外。履歴・復元を Git 前提にしない。
- external-memory 系 skill は `skills/external-memory-rules/core.md` を正本として参照する。

## 現状と既知の課題

- Vault 側 mirror は生成コピーで、直接編集は次回 sync で上書きされる。
- `skills/external-memory-rules/` と `vault/Home.md` の正本はリポジトリ側。
- Vault 全体を無条件に読み込まない、安全規則は `skills/external-memory-rules/core.md` に集約されている。
