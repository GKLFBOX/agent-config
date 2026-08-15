# Scripts

## 目的

- `scripts/` 配下の install / uninstall / status / sync / hook / 共通 library を俯瞰する。
- 配置方式が symlink か copy かを確認できるようにする。
- 関連: [vault](../vault/README.md), [agent-bridge](../agent-bridge/README.md)

## 構成

- `scripts/lib/AgentConfig.psm1` - 配置ターゲット、link/copy 判定、backup、Vault mirror 同期関数。
- `scripts/lib/ClaudexAuth.psm1` - CLIProxyAPI と Codex CLI の認証状態を認証ファイルから判定する関数群。
- `scripts/install.ps1` - 全ターゲットを配置する installer。
- `scripts/uninstall.ps1` - 管理下 link / copy / copy-file を外す uninstaller。
- `scripts/status.ps1` - 配置先の存在、method、managed 状態を表で表示する。
- `scripts/sync-vault-mirror.ps1` - copy / copy-file 方式ターゲットだけを再同期する。
- `scripts/check-external-user-skills.ps1` - skills CLI 管理の外部 USER skills が揃っているか検査する。
- `scripts/pre-commit` - staged 差分を `gitleaks protect` で secret scan する hook。
- `scripts/agents/` - AgentBridge runner 群。詳細は [agent-bridge](../agent-bridge/README.md) を参照。
- `scripts/claudex/` - CLIProxyAPI経由でClaude Codeを起動する関数と導入、ロールバック用スクリプト。
- `scripts/claudex/relogin.ps1` - CLIProxyAPI と Codex CLI の Codex OAuth を再ログインする復旧口。

## 使い方・挙動

- `scripts/lib/AgentConfig.psm1` の `Get-AgentConfigTargets` は全配置ターゲットを返す。
- Symlink 方式:
  - `claude/CLAUDE.md` -> `~/.claude/CLAUDE.md`
  - `claude/settings.json` -> `~/.claude/settings.json`
  - `claude/hooks` -> `~/.claude/hooks`
  - `skills` -> `~/.claude/skills`
  - `AGENTS.md` -> `~/.codex/AGENTS.md`
  - `skills` -> `~/.agents/skills/agent-config`
  - `codex/plugins/agent-file-backup` -> `~/plugins/agent-file-backup`
  - `codex/agents-plugins/marketplace.json` -> `~/.agents/plugins/marketplace.json`
  - `gemini/GEMINI.md` -> `~/.gemini/GEMINI.md`
  - `copilot/copilot-instructions.md` -> `~/.copilot/copilot-instructions.md`
- Copy 方式:
  - `skills/external-memory-rules` -> `<vault-root>\System\external-memory-rules`
- CopyFile 方式:
  - `vault/Home.md` -> `<vault-root>\Home.md`
  - `vault/Todo.md` -> `<vault-root>\Todo.md`
  - `bin/codex.cmd` -> `~/.local/bin/codex.cmd`
  - `bin/codex` -> `~/.local/bin/codex`
  - codex シムは symlink で配れない。PATH 上の reparse point が走査できない問題を回避するのが目的で、
    自身が symlink だと同じ拒否に引っかかる。
- `scripts/install.ps1` は管理者権限を要求し、既存の管理外ファイル・ディレクトリを `backups/<yyyyMMdd-HHmmss>/` 配下へ退避する。
- `scripts/uninstall.ps1` は管理下と判定できる対象だけを外す。
- `scripts/status.ps1` は `Name` / `Method` / `Destination` / `Exists` / `LinkTarget` / `Managed` を表示する。
- `scripts/sync-vault-mirror.ps1` は `Method` が `Copy` または `CopyFile` のターゲットだけを処理する。配置先は Vault 限定ではなく `~/.local/bin` の codex シムも含む。`install.ps1` と同じ退避ガード（`Backup-UnmanagedCopyTarget`）を通し、管理外の実体は上書きせず `backups/<yyyyMMdd-HHmmss>/` へ退避する。
- `scripts/check-external-user-skills.ps1` は `~/.agents/skills` と `~/.agents/.skill-lock.json` を照合する。
- `scripts/pre-commit` は `gitleaks` があれば実行し、無ければ warning を出して skip する。
- `scripts/lib/ClaudexAuth.psm1` は access token の `iat` と `exp` から `Healthy` / `Ending` / `Expired` / `Unknown` を返す。上流へはリクエストを送らない。access token はセッションの終了時刻を超えて発行されないため、寿命が満額（10日）に満たなければ `exp` が再ログイン期限を指す。
- `claudex` は起動前にこの判定を通す。CLIProxyAPI が `Expired` なら Claude Code を起動せず `scripts/claudex/relogin.ps1` を案内する。Codex CLI の失効は起動を止めず、委託と statusline の使用率表示への影響を警告する。
- `scripts/claudex/relogin.ps1` は `-ProxyOnly` と `-CodexOnly` で片方だけ実行できる。常駐する CLIProxyAPI は停止しない。

## 依存・前提

- symlink 作成のため `scripts/install.ps1` は管理者 PowerShell を要求する。
- Vault mirror は Google Drive sync と両立させるため symlink / junction ではなく実体 copy を使う。
- `scripts/pre-commit` は `gitleaks` が PATH 上にある場合だけ scan する。
- `scripts/lib/AgentConfig.psm1` は `<vault-root>` を Vault root として持つ。
- 外部 USER skills は `npx skills ...` で導入し、repo は導入状況と検査だけを管理する。

## 現状と既知の課題

- `scripts/install.ps1` の権限チェックは symlink ターゲットを含む前提で一律に管理者権限を要求する。
- Copy / CopyFile の remove 関数は管理 marker の無い対象を拒否する。
- `scripts/pre-commit` は `.gitleaks.toml` を指定して staged 差分を scan する。

## tests

- `tests/AgentConfig.Tests.ps1` - 16ターゲット、Vault mirror の `Copy`、Home / Todo ノートと codex シムの `CopyFile`、管理外配置先の退避ガード、link/copy/remove 安全性を検証する。
- `tests/ExternalMemory.Tests.ps1` - `skills/external-memory-rules` と external-memoryスキル群の存在・参照関係・旧Vaultパス不使用を検証する。
- `tests/AgentBridge.Tests.ps1` - task/result schema、path 検証、request/result 読み書き、CLI wrapper、期限切れ request のごみ箱移動契約を検証する。
- `tests/AgentFileBackup.Tests.ps1` - agent-file-backup hook の登録、対象 path 抽出、未追跡ファイル backup、世代保持、UTF-8 payload、deny 応答を検証する。
- `tests/AgentHookCommon.Tests.ps1` - hook 共通 log、保持期間 cleanup、PreToolUse 応答、shell command 分割・token 抽出を検証する。
- `tests/DeleteGuard.Tests.ps1` - Bash / PowerShell の削除コマンド検知、許可例、fail-closed、settings 登録を検証する。
- `tests/MarkdownFormat.Tests.ps1` - Markdown queue、除外、pre-commit flush、entry script、settings 登録を検証する。
- `tests/Claudex.Tests.ps1` - `pwsh -NoProfile -File`で実行し、引数、環境分離、プロキシ、導入、ロールバックを検証する。
- `tests/RunAntigravity.Tests.ps1` - fake launcher で `scripts/agents/run-antigravity.ps1` の investigation 成功と `implementation` の `-Write` gate を検証する。
- `tests/RunCopilot.Tests.ps1` - fake launcher で `scripts/agents/run-copilot.ps1` の investigation 成功と `implementation` の `-Write` gate を検証する。
- `tests/CopilotDelegation.Tests.ps1` - `skills/delegate-copilot/SKILL.md` の frontmatter、runner 参照、mode 記述、`-Write` gate 記述、review 委託の不提供を検証する。
