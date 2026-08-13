# Claude

## 目的

- Claude Code 向け設定の正本をまとめる。
- 全体ルールは `AGENTS.md` に寄せ、Claude 固有差分だけを `claude/` に置く。
- 関連: [skills](../skills/README.md), [plugins](../plugins/README.md)

## 構成

- `claude/CLAUDE.md` - `AGENTS.md` を読み込む薄いラッパー。現時点の Claude 固有指示は追加なし。
- `claude/settings.json` - Claude Code の hook、plugin、権限、テーマなどの設定。
- `claude/hooks/context-mode-cache-heal.mjs` - context-mode plugin cache の自己修復 hook。
- `claude/hooks/external-memory-start.mjs` - セッション開始時に外部記憶参照の要否を Claude へ注入する SessionStart hook。
- `claude/hooks/agent-file-backup/` - Git 管理外ファイルを編集前に退避する PreToolUse hook。
- `claude/hooks/lib/AgentHookCommon.psm1` - hook 共通の JSONL ログ・ごみ箱送り・応答生成・コマンド区分解析。
- `claude/hooks/delete-guard/` - Bash/PowerShell の直接削除を拒否し `trash` へ誘導する PreToolUse hook。
- `claude/hooks/markdown-format/` - 編集済み Markdown を記録し、ターン終端と `git commit` 前に prettier で一括整形する hook 群。

## claudex

`claudex`は、Claude Codeの設定とセッションを共有したまま、CLIProxyAPI経由でGPT-5.6を起動する。
接続先は子プロセス内で切り替えるため、通常の`claude`には影響しない。

### 導入

`scripts/claudex/install.ps1`を実行する。

```powershell
pwsh -NoProfile -File <repo-root>\scripts\claudex\install.ps1
```

初回はCLIProxyAPIのローカルAPIキーを入力する。
インストーラーはキーをDPAPIで暗号化し、PowerShellプロファイルと`AgentConfig-CLIProxyAPI`タスクを登録する。
反映後にPowerShellを開き直す。

CLIProxyAPIの配置先を変えた場合は、`-ProxyExecutable`と`-ProxyConfig`を指定して再実行する。
APIキーの更新には`-ReplaceSecret`を付ける。

### 利用

```powershell
claudex
claudex --model terra --effort high
claudex --model luna --resume <session-id>
claudex --continue
claudex '--' --model terra
```

| 短縮名  | モデル          | 用途                   |
| ------- | --------------- | ---------------------- |
| `sol`   | `gpt-5.6-sol`   | 既定のメインモデル     |
| `terra` | `gpt-5.6-terra` | Sonnet相当のサブモデル |
| `luna`  | `gpt-5.6-luna`  | Haiku相当のサブモデル  |

既定エフォートは`xhigh`。
指定値は`low`、`medium`、`high`、`xhigh`、`max`である。
`--continue`と`--resume`では、再開対象のモデルを確認する。
Claude Codeへ`--`以降をそのまま渡す場合は、区切りを`'--'`と引用する。
PowerShell関数では、引用しない`--`が引数へ残らないためである。

### コンテキスト制御

`claudex`は、GPT-5.6の上限に合わせて次の環境変数をClaude Code子プロセスへ設定する。
通常の`claude`には影響しない。

| 環境変数                          | 値       | 理由                                               |
| --------------------------------- | -------- | -------------------------------------------------- |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS`   | `128000` | GPT-5.6の最大出力                                  |
| `CLAUDE_CODE_MAX_CONTEXT_TOKENS`  | `372000` | GPT-5.6のコンテキスト上限                          |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | `240000` | 372Kから最大出力128Kを引いた実効入力244Kより小さい |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | `85`     | 204Kで圧縮し、実効入力上限まで約40Kを残す          |

圧縮開始位置は`240000 × 85% = 204000`である。
大きなスキルやツール結果が圧縮判定の間に追加されても、入力上限を飛び越えにくくする。

複数の`claudex`セッションは1つのプロキシを共有する。
プロキシが停止中ならタスクを起動し、起動済みならそのまま利用する。

### ロールバック

`scripts/claudex/uninstall.ps1`を実行する。

```powershell
pwsh -NoProfile -File <repo-root>\scripts\claudex\uninstall.ps1
```

アンインストーラーはPowerShellプロファイルの管理ブロックとスケジュールタスクだけを取り除く。
CLIProxyAPI本体、OAuth情報、暗号化したAPIキー、実行中のプロキシは残す。

## 使い方・挙動

- `claude/CLAUDE.md` は `@<repo-root>/AGENTS.md` を import する。
- `claude/settings.json` は `SessionStart` で `context-mode-cache-heal.mjs` と `external-memory-start.mjs` を Node.js 実行する。
- `enabledPlugins` は 7 件を有効化する。詳細は [plugins](../plugins/README.md) を参照。
- `permissions.additionalDirectories` で `<vault-root>` を追加許可する。
- `theme` は `dark`。
- `context-mode-cache-heal.mjs` は `installed_plugins.json` の `context-mode@context-mode` を対象にする。
- cache 上の install path が欠ける場合、同じ親ディレクトリ内の最新 version dir へ symlink/junction を張る。
- 既存 install path がある場合、`hooks/normalize-hooks.mjs` があれば stale path 正規化を試みる。
- `external-memory-start.mjs` は `additionalContext` で `external-memory-reference` の使用判断を促す。SessionStart はブロックできないため、参照漏れ防止はコンテキスト注入で担保する。
- `agent-file-backup` は `PreToolUse`（`Edit|Write|MultiEdit|NotebookEdit`）で `pre-tool-use.ps1` を実行する。
- ここが Claude / Codex 共通の正本。Codex plugin は同じ入口スクリプトを `-Agent codex` で直接起動する（[codex](../codex/README.md)）。対象抽出は `apply_patch`（Update/Delete File 抽出）にも対応する。
- 編集対象が既存かつ Git 未追跡（無視・リポジトリ外を含む）なら、編集前の内容を `<backup-root>` へ退避する。
- 保存先は元ファイルの親ディレクトリ構造をミラーしたフォルダ。バックアップ名は `タイムスタンプ_元ファイル名`。ファイルごと最新 3 世代を残し、古い世代はごみ箱へ移す。
- バックアップを保証できない場合は `permissionDecision: deny` で編集を止める（fail-closed）。保存先ルートは `AGENT_FILE_BACKUP_ROOT` で上書きできる。
- `delete-guard` は `PreToolUse`（`Bash|PowerShell`）で削除コマンド（`rm` / `Remove-Item` / `del` 等、`find -delete`、ネスト実行、静的 `[IO.File]::Delete`）をコマンド位置トークンで判定し deny する。`git rm` 等は発火しない。fail-closed。`CLAUDE_DELETE_GUARD=off` で停止。
- 削除の公認手段は `trash <path>`（npm グローバルの trash-cli。ごみ箱へ送る）。
- `markdown-format` は `PostToolUse` で編集された `.md` を `~/.claude/state/markdown-format/<session_id>.list` に記録し、`Stop` と `git commit` 直前に prettier で一括整形する。fail-open。除外は `node_modules`・`.git`・`CLAUDE_MD_FORMAT_EXCLUDE`（`;` 区切り）。
- hook 共通ログは `<log-root>\hooks\YYYY-MM-DD.jsonl`（`CLAUDE_HOOK_LOG_ROOT` で上書き）。保持 14 日、超過分はごみ箱へ。`agent-file-backup` は Codex 実行分も同じログへ記録する（`data.agent` で区別）。

## 依存・前提

- `claude/settings.json` の hook は `<node-path>` を前提にする。
- hook script は `<user-profile>/.claude/hooks/context-mode-cache-heal.mjs` に配置される前提。
- `context-mode-cache-heal.mjs` は pure Node.js で shell に依存しない。
- `CLAUDE_CONFIG_DIR` があればそれを使い、無ければ `~/.claude` を使う。
- `agent-file-backup` は `powershell.exe`（Windows PowerShell 5.1）で起動する。`pwsh` は PATH 保証がなく、不在時に fail-closed で全編集を止めるため使わない。
- 5.1 は BOM なしファイルを CP932 として読むため、`agent-file-backup` の PowerShell ソースは ASCII のみとする（日本語コメントは置かない）。同制約は `delete-guard` / `markdown-format` / `lib` の PowerShell ソースにも及ぶ。
- 5.1 は stdin も既定で CP932 として読むため、各 hook の入口スクリプトは入力 JSON を UTF-8 で明示的に読む。日本語を含むパス/コマンドが壊れて fail-closed で拒否される（または誤ったパスがキューへ入る）のを防ぐ。
- `delete-guard` の誘導先として trash-cli、`markdown-format` の整形に prettier を npm グローバルで導入する（`npm install -g trash-cli prettier`）。

## 現状と既知の課題

- Claude 固有指示は `claude/CLAUDE.md` 上では未追加。
- `settings.json` は概要管理で、逐条解説はしない。
- hook は context-mode 固有の自己修復で、他 plugin の cache 修復は対象外。
- `agent-file-backup` はシェルコマンド経由の編集を検知できない。自動復元もなく、`<backup-root>` を手動で確認して戻す。
- 深い階層の元パスでは、ミラー先が MAX_PATH(260) を超えて編集が拒否され得る（Windows の LongPaths 有効化で緩和）。
