# agent-config

Claude Code / OpenAI Codex CLI / Google Antigravity のカスタマイズを集約する個人リポジトリ。
自作物の実体をここに置き、各ツールの配置先へ symlink で配置する。

外部由来プラグイン・各ツールの `config.toml`/DB/cache/session/auth/runtime は管理しない。

## 管理対象

導入状態は `.\scripts\status.ps1` で確認する。

| 実体                                    | 配置先                                 | 種別                         |
| --------------------------------------- | -------------------------------------- | ---------------------------- |
| `AGENTS.md`（正本）                     | `~/.claude/CLAUDE.md` が `@import`     | —                            |
| `claude/CLAUDE.md`                      | `~/.claude/CLAUDE.md`                  | ファイル symlink             |
| `claude/settings.json`                  | `~/.claude/settings.json`              | ファイル symlink             |
| `claude/hooks`                          | `~/.claude/hooks`                      | ディレクトリ symlink         |
| `skills`（正本）                        | `~/.claude/skills`                     | ディレクトリ symlink         |
| `skills/external-memory-rules`（正本）  | `<Vault>/System/external-memory-rules` | フォルダコピー（生成物）     |
| `vault/Home.md`（正本）                 | `<Vault>/Home.md`                      | 単一ファイルコピー（生成物） |
| `AGENTS.md`（正本）                     | `~/.codex/AGENTS.md`                   | ファイル symlink             |
| `skills`（正本）                        | `~/.agents/skills/agent-config`        | ディレクトリ symlink         |
| `codex/plugins/agent-file-backup`       | `~/plugins/agent-file-backup`          | ディレクトリ symlink         |
| `codex/agents-plugins/marketplace.json` | `~/.agents/plugins/marketplace.json`   | ファイル symlink             |
| `gemini/GEMINI.md`                      | `~/.gemini/GEMINI.md`                  | ファイル symlink             |
| `copilot/copilot-instructions.md`       | `~/.copilot/copilot-instructions.md`   | ファイル symlink             |

Codex は「Claude の1レイヤー下の司令塔」として正本 `AGENTS.md`・`skills` を共有する
（skills は公式 USER スコープ `~/.agents/skills` へ `agent-config` サブディレクトリでネスト配置）。
Antigravity / Copilot には委託受け専用の最小指示ファイルのみを配る。

Vault は Google Drive 同期下にあり symlink が同期エラーになるため、Vault側のフレーム
（外部記憶ルール・Homeノート）は実体コピー方式で配置する。正本を編集したら再同期する。
正本ソースは `skills/external-memory-rules/`（ルール）と `vault/`（Vaultフレーム）に置く。

## クイックスタート

```powershell
# 状態確認（非昇格でOK）
.\scripts\status.ps1

# 配置（管理者 PowerShell で実行。symlink 作成に必要）
.\scripts\install.ps1

# 解除
.\scripts\uninstall.ps1

# 外部記憶ルールのミラー再同期（昇格不要。ルール編集後に実行）
.\scripts\sync-vault-mirror.ps1
```

## 運用

### 前提

- Windows 11 / PowerShell 7+。
- symlink 作成には**管理者権限**が必要（`install.ps1` は非昇格だと停止する）。

### 導入

1. 非昇格で状態確認: `.\scripts\status.ps1`
2. 管理者 PowerShell を開き、リポジトリへ移動。
3. `.\scripts\install.ps1`
   - 既存の実体ファイルは `backups/<timestamp>/` へ退避される。
   - 既に正しいリンクなら skip。別ターゲットのリンクがあれば安全のため中断。
4. 再度 `.\scripts\status.ps1` で `Managed=True` を確認。
5. 利用する各ツールを再起動し、配置した指示が効くことを確認。
   Claude Code の初回起動では `@import` の承認ダイアログが出るので許可する。

### 更新

- 実体（`AGENTS.md`、`claude/settings.json` 等）を編集すれば symlink 経由で即反映。
- 新しいスキルは `skills/<name>/SKILL.md` を追加すると Claude / Codex に反映。

### アンインストール

- `.\scripts\uninstall.ps1` で全管理対象を解除。
- 必要なら `backups/<timestamp>/` から実体を手動復元。

### テスト

- `Invoke-Pester tests/AgentConfig.Tests.ps1`（非昇格ではリンク往復テストはスキップ）。

## ドキュメント

- 現状把握（カスタマイズ資材のミラー）の索引: [docs/README.md](docs/README.md)
- 設計書・実装計画（superpowers 生成物）は `docs/superpowers/` に置く。公開用リポジトリには含めない。

## 今後の候補

- プロジェクト単位の展開（コピー同期）。
