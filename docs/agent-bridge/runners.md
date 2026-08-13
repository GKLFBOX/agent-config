# AgentBridge Runners

## 目的

- AgentBridge を使う runner と fallback をまとめる。
- Antigravity / Copilot の CLI 起動方法、権限 gate、cleanup を確認できるようにする。
- 関連: [overview](README.md), [protocol](protocol.md)

## 構成

- `scripts/agents/run-antigravity.ps1` - `agy -p` で Antigravity を呼ぶ runner。
- `scripts/agents/run-copilot.ps1` - `copilot -p` で GitHub Copilot CLI を呼ぶ runner。
- `scripts/agents/agent-bridge/Move-ExpiredAgentBridgeRequest.ps1` - 古い `.agent-bridge` request をごみ箱へ移す wrapper。

委託スキルは `$HOME/.agent-bridge/run-<agent>.ps1` から起動する。
実体は `scripts/agents/` にあり、`scripts/install.ps1` がディレクトリごと symlink で配る。

## 使い方・挙動

- 共通:
  - `-Repository`, `-TaskType`, `-Objective` は mandatory。
  - `-TaskType` は `investigation` / `implementation`。
  - `implementation` は `-Write` なしで拒否する。
  - `New-AgentBridgeRequest` で task を作り、launcher 実行後に `Wait-AgentBridgeResult` と `Read-AgentBridgeResult` を呼ぶ。
  - stdout は最終的に要約 JSON に寄せる。
- `scripts/agents/run-antigravity.ps1`:
  - repository 直下で `agy -p <prompt>` を実行する。
  - `$null | agy -p ...` で stdin を閉じる。
  - `agy` stdout は捨て、`result.json` を file handoff として受ける。
- `scripts/agents/run-copilot.ps1`:
  - `copilot -p <prompt> -C <repo> --no-color ...` を実行する。
  - investigation は `--allow-tool write --deny-tool shell`。
  - implementation は `--allow-all-tools`。
  - `--allow-all-paths` / `--yolo` は渡さない。
- `Move-ExpiredAgentBridgeRequest.ps1`:
  - `-Repository` と `-AgeDays` を受ける。
  - module の `Move-ExpiredAgentBridgeRequest` を呼び、JSON を返す。

## 依存・前提

- `run-antigravity.ps1` は `agy` CLI を前提にする。
- `run-copilot.ps1` は `copilot` CLI を前提にする。
- cleanup は Windows Recycle Bin API を使う module 実装に依存する。

## 現状と既知の課題

- Copilot runner の path 封じ込めは OS sandbox ではなく、専用ブランチと Claude の diff review が最終防波堤。
