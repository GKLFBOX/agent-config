# AgentBridge

## 目的

- Claude を司令塔にし、実装作業を外部 CLI agent へ委託する file-based bridge を説明する。
- Antigravity / Copilot の結果を `result.json` として受け取り、Claude 側の token 消費を抑える。
- 詳細: [protocol](protocol.md), [runners](runners.md)

## 構成

- `$HOME/.agent-bridge/` - `scripts/agents/` への symlink。委託スキルはここから runner を起動する。
- `scripts/agents/agent-bridge/` - task/result JSON と検証・待機・読み取りの中核。
- `scripts/agents/run-antigravity.ps1` - Antigravity (`agy`) runner。
- `scripts/agents/run-copilot.ps1` - GitHub Copilot CLI (`copilot`) runner。
- `skills/delegate-antigravity/SKILL.md` - Antigravity 委託の運用 skill。
- `skills/delegate-copilot/SKILL.md` - Copilot 委託の運用 skill。
- `skills/delegate-codex/SKILL.md` - Codex 委託の運用 skill。

## 使い方・挙動

- Claude が task を作り、runner が対象 agent に `task.json` を読ませる。
- 対象 agent は `.agent-bridge/<request_id>/result.json` を書く。
- Claude は `Read-AgentBridgeResult` の要約 JSON を受け取り、diff / verification を自分で確認する。
- Antigravity:
  - `skills/delegate-antigravity/SKILL.md` は `agy` / Gemini 系として説明する。
  - `scripts/agents/run-antigravity.ps1` は `agy -p` を起動する。
- Copilot:
  - `skills/delegate-copilot/SKILL.md` は `copilot` CLI を使う並列チャネルとして説明する。
  - `scripts/agents/run-copilot.ps1` は `copilot -p` を起動する。
- `result.json` は未信頼入力として扱い、schema と path を検証してから読む。

## 依存・前提

- Antigravity runner は `agy` CLI を前提にする。
- Copilot runner は `copilot` CLI を前提にする。
- AgentBridge 中核は PowerShell module `scripts/agents/agent-bridge/AgentBridge.psm1`。
- write-capable delegation は専用ブランチ / worktree 前提で、runner に `-Write` を明示する。
- 委託先に commit / push はさせない。
- 起動口 `$HOME/.agent-bridge` は `scripts/install.ps1` が張る。未インストール環境では委託スキルの起動例が解決しない。

## 現状と既知の課題

- Antigravity / Copilot の runner は `implementation` を `-Write` なしで拒否する。
- `investigation` mode は runner にあるが、delegate skill 上の既定ルーティングではまとまった調査に使わない。
- `result.json` の verification command はエビデンスであり、自動再実行しない。
