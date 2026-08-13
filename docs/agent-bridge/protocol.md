# AgentBridge Protocol

## 目的

- AgentBridge の task -> result 受け渡し契約をまとめる。
- request directory、schema、atomic handoff、write gate を確認できるようにする。
- 関連: [overview](README.md), [runners](runners.md)

## 構成

- `scripts/agents/agent-bridge/AgentBridge.psm1` - 中核 module。request 作成、result 待機、schema/path 検証、cleanup を実装する。
- `scripts/agents/agent-bridge/New-AgentBridgeRequest.ps1` - `New-AgentBridgeRequest` の CLI wrapper。
- `scripts/agents/agent-bridge/Wait-AgentBridgeResult.ps1` - `Wait-AgentBridgeResult` の CLI wrapper。
- `scripts/agents/agent-bridge/Read-AgentBridgeResult.ps1` - `Read-AgentBridgeResult` の CLI wrapper。
- `scripts/agents/agent-bridge/Move-ExpiredAgentBridgeRequest.ps1` - 期限切れ request cleanup の CLI wrapper。
- `scripts/agents/agent-bridge/schemas/task.schema.json` - task JSON schema。
- `scripts/agents/agent-bridge/schemas/result.schema.json` - result JSON schema。

## 使い方・挙動

- request id は `yyyyMMddTHHmmssZ-xxxxxx` 形式。
- request directory は `.agent-bridge/<yyyyMMddTHHmmssZ-xxxxxx>/`。
- `New-AgentBridgeRequest` は以下を作る。
  - `.agent-bridge/.pending-<guid>/task.json`
  - `.agent-bridge/.pending-<guid>/artifacts/`
  - publish 時に `.pending-<guid>` を `.agent-bridge/<request_id>` へ directory move
- task は `task.json` として配置され、`output_path` は `.agent-bridge\<request_id>\result.json`。
- runner prompt は `result.json.tmp` に書いてから `result.json` へ rename するよう要求する。
- `Wait-AgentBridgeResult` は `task.json` を読み、`result.json` 出現まで polling し、result schema を検証する。
- `Read-AgentBridgeResult` は task type に応じて要約 JSON を返す。
- task schema:
  - `schema_version`, `request_id`, `task_type`, `repository`, `objective`, `constraints`, `acceptance_criteria`, `review_scope`, `output_path` が required。
  - `task_type` は `implementation` / `review` / `investigation`。
  - `additionalProperties` は false。
- result schema:
  - `schema_version`, `request_id`, `status`, `summary`, `changed_files`, `verification`, `findings`, `decisions`, `risks`, `review_focus`, `artifacts` が required。
  - `status` は `completed` / `partial` / `failed`。
  - `summary` は max 500。
  - `verification` / `findings` / `review_focus` は object 配列。
  - `additionalProperties` は false。
- `Assert-AgentBridgeTask` / `Assert-AgentBridgeResult` は絶対 path、`..` traversal、repo 外 path、reparse point を拒否する。

## 依存・前提

- JSON は UTF-8 without BOM で扱う wrapper 実装。
- `AgentBridge.psm1` は Windows Recycle Bin API (`Microsoft.VisualBasic.FileIO.FileSystem.DeleteDirectory`) を cleanup に使う。
- `New-AgentBridgeRequest` は repository が存在する absolute path であることを要求する。
- write-capable delegation は runner 側で `-Write` 明示が必要。`implementation` かつ `-Write` なしは拒否される。

## 現状と既知の課題

- schema file はあるが、runtime 検証は `AgentBridge.psm1` 内の PowerShell 関数でも実装されている。
- `Read-AgentBridgeResult` は task type ごとに返す field を絞るため、raw `result.json` の全 field をそのまま返さない。
- cleanup は request id pattern に一致する directory のみ対象にする。
