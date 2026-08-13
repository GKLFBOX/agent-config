# docs — カスタマイズ資材の現状把握

本ディレクトリは、リポジトリが管理するカスタマイズ資材を**ミラー構造**で解説する
現状把握用リファレンスの索引。各ユニットの「何のための資材か / どう動くか / 何に依存するか」を
実体に沿って記述する。

`AGENTS.md`（全ツール共有のユーザールール正本）が全体の土台。各 doc はその上で
個別ユニットを扱う。

## 索引

| ユニット               | doc                                                                                                     | 概要                                                             |
| ---------------------- | ------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| Claude 層              | [claude/README.md](claude/README.md)                                                                    | `CLAUDE.md` ラッパー・`settings.json`・hooks                     |
| Codex 層               | [codex/README.md](codex/README.md)                                                                      | `AGENTS.md`/skills 共有・自作 plugin・`config.toml` カタログ     |
| スキル                 | [skills/README.md](skills/README.md)                                                                    | `skills/` 配下のスキル一覧（委託・振り分け・外部記憶・執筆品質） |
| ライフサイクル scripts | [scripts/README.md](scripts/README.md)                                                                  | install/uninstall/status/sync・pre-commit・tests                 |
| AgentBridge（委託）    | [agent-bridge/README.md](agent-bridge/README.md)                                                        | エージェント委託の全体像                                         |
| └ プロトコル           | [agent-bridge/protocol.md](agent-bridge/protocol.md)                                                    | task→result のジョブ受け渡し・schema・命名規則                   |
| └ ランナー             | [agent-bridge/runners.md](agent-bridge/runners.md)                                                      | run-antigravity / run-copilot / fallback                         |
| 委託受け指示           | [gemini/GEMINI.md](../gemini/GEMINI.md) / [copilot-instructions.md](../copilot/copilot-instructions.md) | Antigravity / Copilot CLI の委託受け規則                         |
| Vault 連携             | [vault/README.md](vault/README.md)                                                                      | 外部記憶 Vault へのコピーミラー配布                              |
| プラグイン             | [plugins/README.md](plugins/README.md)                                                                  | 導入プラグイン一覧（外部由来・リポ管理外）                       |

## このディレクトリの位置づけ

- **現状把握 doc（本ディレクトリ直下のミラー）**: 「今ある資材がどうなっているか」を
  説明する静的リファレンス。上表がその全体地図。
- **`docs/superpowers/`**: superpowers スキルが生成する spec（設計書）と
  plan（実装計画）＝プロセス成果物。時点ごとの記録であり、現状把握 doc とは責務が異なる。
  公開用リポジトリには含めない。

運用手順（導入/更新/アンインストール/テスト）はリポジトリのルート
[README.md](../README.md) にまとめている。
