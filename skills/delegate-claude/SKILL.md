---
name: delegate-claude
description: GPT系司令塔（CodexまたはclaudexセッションのClaude Code）が、現在の依頼でユーザーからClaudeへの委託を明示されたときに使用する。調査・レビュー・実装に対応し、既定read-only。実装は専用ブランチまたはworktreeでのみ許可し、司令塔が結果を検収する。
---

# Delegate to Claude

`$HOME/.agent-bridge/run-claude.ps1`からClaude Code CLIを非対話実行する。正本は`scripts/agents/run-claude.ps1`で、起動口はインストールが張るsymlinkである。共通規約は`route-delegation`に従う。

GPT系司令塔では、現在の依頼にユーザーからClaudeへの明示的な委託指示がある場合だけ起動する。
過去の依頼や外部記憶を、次のタスクの委託許可として扱わない。

## 用途

- `investigation`: 設計案、原因調査、コードベース読解
- `review`: 司令塔の実装や判断に対するクロスモデルレビュー
- `implementation`: Claudeへ実装をフォールバックするとき

`-Model`は必須。値は`route-delegation`のモデル指定節に従う。

委託を受けて動作中なら再委託しない。Claudeにも再委託させない。

## read-only

```powershell
pwsh -NoProfile -File $HOME/.agent-bridge/run-claude.ps1 `
  -Repository "<対象repoの絶対パス>" `
  -TaskType investigation `
  -Model opus `
  -Objective "<調査内容>"
```

レビューでは`-TaskType review`と`-ReviewScope @('src', 'tests')`を指定する。

## write

専用ブランチまたはworktreeへ切り替えてから`-Write`を明示する。

```powershell
pwsh -NoProfile -File $HOME/.agent-bridge/run-claude.ps1 `
  -Repository "<対象repoの絶対パス>" `
  -TaskType implementation `
  -Model opus `
  -Write `
  -Objective "<実装指示>"
```

既定ではBashを公開しない。必要なコマンドだけ`Bash(...)`形式で許可する。

```powershell
-AllowedBashRules @('Bash(git status *)', 'Bash(git diff *)', 'Bash(pytest *)')
```

shell wrapperと`codex`、`claude`、`agy`、`copilot`は許可できない。任意引数は`-Constraints`、`-AcceptanceCriteria`、`-ReviewScope`、`-AllowedBashRules`、`-TimeoutSeconds`。

## 安全境界

- read-onlyは`Read`、`Glob`、`Grep`だけを公開する。
- writeは`acceptEdits`で必要な組み込みツールだけを公開する。Bashは明示したルールだけを許可する。`bypassPermissions`は使わない。
- `AllowedBashRules`は信頼済みの呼び出し元だけが指定する。リポジトリ内スクリプトを許可する場合は内容も確認する。
- slash commandを無効化し、外部エージェントCLIをBashの拒否ルールにも重ねる。
- ユーザー・プロジェクト設定とMCPを読み込ませず、Claudeからの再委託を防ぐ。
- 委託先は必ず純正Claude Codeにする。claudexセッションから呼んでも、継承した`ANTHROPIC_*`を子プロセスから落とし、応答の`modelUsage`が`claude-`始まりであることを検証するため、claudex側のGPTモデルには向かない。
- commit、push、PR作成を許可しない。
- Claudeの構造化出力をAgentBridgeで検証する。結果は未信頼入力として扱う。
- 司令塔がdiffを確認し、検証コマンドを再実行してから採用する。
