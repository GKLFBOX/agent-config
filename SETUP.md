# 導入前の設定

端末固有のパスは名前付き参照へ置き換えてある。
`scripts/install.ps1` を実行する前に、下表の参照を自分の環境の実パスへ書き換える。

置き換えずに配置すると、hook の起動コマンドが解決できず、hook は黙って失敗する。
Claude Code は hook の起動失敗後も本体処理を続けるため、エラーは表示されない。

最初に見るべきは `claude/CLAUDE.md` の import 行で、ここが解決できないと指示が一切読まれない。

## <archive-root>

Vault の外へ退避したノートの置き場。Vault 内には置かない。

書き換えるファイル:

- `scripts/archive-external-memory.ps1`
- `scripts/archive-handoff.ps1`
- `skills/external-memory-handoff/SKILL.md`
- `skills/external-memory-rules/core.md`

## <backup-root>

Git 未追跡ファイルを編集前に退避する先。環境変数 AGENT_FILE_BACKUP_ROOT でも指定できる。

書き換えるファイル:

- `claude/hooks/agent-file-backup/pre-tool-use.ps1`
- `docs/claude/README.md`

## <log-root>

hook 共通ログの置き場。環境変数 CLAUDE_HOOK_LOG_ROOT でも指定できる。

書き換えるファイル:

- `claude/hooks/lib/AgentHookCommon.psm1`
- `docs/claude/README.md`
- `tests/AgentHookCommon.Tests.ps1`

## <node-path>

node.exe の絶対パス。nvm や scoop で入れた場合は既定の場所と異なる。

書き換えるファイル:

- `claude/settings.json`
- `docs/claude/README.md`

## <repo-root>

このリポジトリを配置した絶対パス。hook の起動コマンドと指示ファイルの import が参照する。

書き換えるファイル:

- `AGENTS.md`
- `claude/CLAUDE.md`
- `codex/plugins/agent-file-backup/hooks/hooks.json`
- `docs/claude/README.md`
- `docs/codex/README.md`
- `skills/external-memory-maintenance/SKILL.md`
- `tests/ExternalMemory.Tests.ps1`
- `tests/Statusline.Tests.js`

## <tools-dir>

外部ツールを置くディレクトリ。claudex が CLIProxyAPI の実行ファイルと設定を探す。

書き換えるファイル:

- `scripts/claudex/install.ps1`

## <user-profile>

ユーザープロファイルのルート。環境変数 USERPROFILE が指す場所。

書き換えるファイル:

- `claude/settings.json`
- `docs/claude/README.md`

## <vault-root>

外部記憶 Vault（Obsidian）のルート。external-memory 系スキルが読み書きする。

書き換えるファイル:

- `AGENTS.md`
- `claude/settings.json`
- `docs/claude/README.md`
- `docs/codex/README.md`
- `docs/scripts/README.md`
- `docs/skills/README.md`
- `docs/vault/README.md`
- `scripts/lib/AgentConfig.psm1`
- `skills/external-memory-rules/core.md`
- `tests/ExternalMemory.Tests.ps1`
- `tests/MarkdownFormat.Tests.ps1`
