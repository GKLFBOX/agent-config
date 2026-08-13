# Codex 層

Codex CLI 向けの配布物と設定を解説するミラー。Codex は「Claude の1レイヤー下の司令塔」として、
正本 `AGENTS.md` と `skills/` を Claude と共有する。関連: [plugins](../plugins/README.md), [claude](../claude/README.md)。

## 配布物

`Get-AgentConfigTargets` が symlink で配置する。導入状態は `.\scripts\status.ps1` で確認する。

| 実体                                    | 配置先                               | 用途                                                                                                     |
| --------------------------------------- | ------------------------------------ | -------------------------------------------------------------------------------------------------------- |
| `AGENTS.md`（正本）                     | `~/.codex/AGENTS.md`                 | 全ツール共有のユーザールール。Codex がネイティブに読む。                                                 |
| `skills`（正本）                        | `~/.agents/skills/agent-config`      | 共有スキル。公式 USER スコープ `~/.agents/skills` へネスト配置し、skills CLI 管理の実体 dir と共存する。 |
| `codex/plugins/agent-file-backup`       | `~/plugins/agent-file-backup`        | 自作 Codex plugin（下記）。                                                                              |
| `codex/agents-plugins/marketplace.json` | `~/.agents/plugins/marketplace.json` | 自作 plugin を配る `personal` マーケットプレイス定義。                                                   |

`skills` をネスト配置するのは、`~/.agents/skills` を skills CLI（`.skill-lock.json`）が実体 dir として
管理しており、直下を symlink で置換できないため。`agent-config` サブディレクトリへ1本のリンクを張り、
CLI 管理スキルと同居させる。

## 外部 USER skills

`~/.agents/skills` は skills CLI が管理する。`agent-config` は導入状況だけを記録し、実体は管理しない。
Codex 直用では、これらも USER スコープの skill として見える。

| スキル                                                                               | source                                | 用途                                         |
| ------------------------------------------------------------------------------------ | ------------------------------------- | -------------------------------------------- |
| `karpathy-guidelines`                                                                | `forrestchang/andrej-karpathy-skills` | 実装時の過剰設計回避・外科的変更・前提明示。 |
| `defuddle` / `json-canvas` / `obsidian-bases` / `obsidian-cli` / `obsidian-markdown` | `kepano/obsidian-skills`              | Web抽出、JSON Canvas、Obsidian Vault 操作。  |
| `find-skills`                                                                        | `vercel-labs/skills`                  | skills の探索補助。                          |

導入状態の正本は `~/.agents/.skill-lock.json`。更新・追加は `npx skills ...` で行う。

欠落検知:

```powershell
.\scripts\check-external-user-skills.ps1
```

再導入例:

```powershell
npx skills add forrestchang/andrej-karpathy-skills -g -a codex -s karpathy-guidelines -y
npx skills add kepano/obsidian-skills -g -a codex -s defuddle json-canvas obsidian-bases obsidian-cli obsidian-markdown -y
npx skills add vercel-labs/skills -g -a codex -s find-skills -y
```

## 自作 Codex plugin: agent-file-backup

Codex が Git 未追跡ファイルを編集する前にバックアップし、バックアップ不能なら編集を deny する。
`personal` マーケットプレイス（`marketplace.json`）経由で `local` ソースとして提供し、
`~/.codex/config.toml` に `agent-file-backup@personal` として登録される。

実装の正本は Claude 側 `claude/hooks/agent-file-backup/`（仕様は [claude](../claude/README.md)）。
plugin は hook 登録のガワのみ（`plugin.json` + `hooks.json`）で、`hooks.json` が共通入口
`pre-tool-use.ps1` を repo 絶対パス・`-Agent codex` 付きで直接起動する。バックアップ構造・ログ・
応答（`hookSpecificOutput.permissionDecision`）・環境変数（`AGENT_FILE_BACKUP_ROOT`）は Claude 版と完全共通。

- matcher は Codex 準拠（`^(apply_patch|Edit|Write)$`）。`apply_patch` の patch テキスト解析も共通モジュールが担う。
- 実装変更は plugin 再インストールなしで反映される。`hooks.json` 変更時のみ再インストールと trusted hash 再承認が要る。
- 登録は `config.toml` の `[plugins."agent-file-backup@personal"]`（`enabled = true`）。値の変更は Codex が
  実行時に書くため git 管理せず、意図は本カタログに記録する。

delete-guard / markdown-format の Codex 展開は、`shell` ツールの payload と PostToolUse/Stop イベントの
Codex 対応が未検証のため後続対応。

## config.toml カタログ

`~/.codex/config.toml` は Codex が実行時に書き換える（`[hooks.state]` の trusted hash 等）ため git 管理しない。
値の正本は config.toml 側。ここはユーザー意図設定と理由の記録。

| 設定                                                  | 値                | 意図                                                                                                                                                                                                      |
| ----------------------------------------------------- | ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sandbox_mode`                                        | `workspace-write` | 作業ルート配下の書き込みを許可（委託・実装で必要）。                                                                                                                                                      |
| `[windows] sandbox`                                   | `unelevated`      | 非昇格で sandbox を有効化（管理者権限を要求しない）。                                                                                                                                                     |
| `[projects.'<vault-root>'] trust_level`    | `trusted`         | Vault を信頼済みにし、read digest 委託時に確認プロンプトを挟まない。書き込みは Claude＋external-memory スキルが担う。                                                                                     |
| `[projects.'<repo-root>'] trust_level` | `trusted`         | 本リポを信頼済みにする。                                                                                                                                                                                  |
| `[plugins.*] enabled`                                 | `true`            | 外部導入 plugin（`superpowers@openai-curated`・`codex-security@openai-curated`・`context-mode@context-mode`）と自作 `agent-file-backup@personal` を有効化。外部導入分は [plugins](../plugins/README.md)。 |
