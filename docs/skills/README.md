# Skills

## 目的

- `skills/` 配下のローカル skill と外部記憶規約を俯瞰する。
- delegate 系、route 系、external-memory 系、執筆品質、rules 本体の役割を分けて確認できるようにする。
- 関連: [agent-bridge](../agent-bridge/README.md), [vault](../vault/README.md)

## 構成

| スキル                         | 用途                                                                                                               | 主なトリガー                                                      | 構成                                                                      |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `delegate-antigravity`         | 量産的な末端実装を Antigravity（`agy` / Gemini 系）へ AgentBridge 経由で委託する。実装専用。                       | 実装計画が明確な中〜大実装の一次委託、小規模実装チェーンの2番手。 | `SKILL.md`                                                                |
| `delegate-codex`               | 要件・設計・計画ドラフト、大規模読解、Web/技術リサーチ、レビュー、Vault digest を Codex へ逃がす。既定 read-only。 | 重い読み書きを Claude 枠外へ逃がすとき。                          | `SKILL.md`                                                                |
| `delegate-copilot`             | 小規模な量産的末端実装を Copilot CLI（`copilot`）へ AgentBridge 経由で委託する。実装専用。                         | 小規模実装の一次委託先。                                          | `SKILL.md`                                                                |
| `route-delegation`             | Codex / Antigravity / Copilot への委託先チェーンと read-only / write 境界を判定する。                              | 実装・調査・レビュー・リサーチ・外部記憶 digest を委託する前。    | `SKILL.md`                                                                |
| `route-implementation-quality` | 実装規模に応じて karpathy-guidelines / superpowers の品質スキルを振り分ける。                                      | コード記述・修正・リファクタに着手する前。                        | `SKILL.md`                                                                |
| `external-memory-capture`      | 知識・思考・タスク・生活情報を外部記憶へ保存する。                                                                 | 覚えておく／記録する／後で行う／買い物へ追加する。                | `SKILL.md`                                                                |
| `external-memory-daily-plan`   | 今日の計画と未完了・期限切れタスクを整理する。                                                                     | 今日やること／今日の計画の整理依頼。                              | `SKILL.md`                                                                |
| `external-memory-handoff`      | セッション終了時に実施内容・状態・次アクションを保存する。                                                         | 今日はここまで／引き継いで。                                      | `SKILL.md`                                                                |
| `external-memory-inbox`        | `Inbox` の未整理メモを分類し、移動・統合・Archive 案を作る。                                                       | Inbox 整理／未整理メモの分類。                                    | `SKILL.md`                                                                |
| `external-memory-reference`    | 開始・再開時または随時に Project 状態、次アクション、判断、関連知識を参照する。                                    | セッション開始・再開時／作業中の参照。                            | `SKILL.md`                                                                |
| `public-release-audit`         | allowlist を作り、公開ツリーを組み、公開前の監査を行う。機械判定8観点はスクリプト、判断が要る4観点は手順。         | public 公開／公開ツリーを組む／既存 public への push 前。         | `SKILL.md` / `scripts/Invoke-PublicReleaseAudit.ps1` / `denylist.example` |
| `concise-japanese-writing`     | 日本語コメント・ドキュメントを簡潔に保ち、履歴語りや冗長表現を削る。                                               | 日本語のソースコメント・ドキュメントを書く／推敲する。            | `SKILL.md`                                                                |
| `external-memory-rules/`       | 外部記憶規約の単一正本（skill ではなく規約本文）。                                                                 | スキル経由／直接を問わず Vault 操作時に参照。                     | `core.md` / `index.md` / `properties.md` / `tasks.md`（`SKILL.md` 無し）  |

## 使い方・挙動

- delegate 系は実装（antigravity / copilot）と調査・設計・レビュー（codex）で役割を分ける。詳細な委託方針は `AGENTS.md` を参照。
- route 系は委託先チェーンと実装品質スキルの振り分けを担う。
- external-memory 系は各ロールに対応する操作を Vault に対して行い、安全規則は本文を持たず rules 正本を参照する。
- `public-release-audit` は決定的な判定だけを同梱スクリプトへ外出しし、コミットメッセージや `.gitignore` のように機械判定が届かない観点は手順として人へ残す。
- `concise-japanese-writing` は日本語コメント・ドキュメントの冗長表現と時点語を削る基準を持つ。
- `skills/external-memory-rules/index.md` は規約の単一正本が `skills/external-memory-rules/` にあると明記する。
- `skills/external-memory-rules/core.md` は Vault パス、安全規則、分類、報告、Git 前提を定義する。

## 依存・前提

- delegate 系は `AGENTS.md` の委託方針を共有規約として参照する。
- Antigravity / Copilot delegate は `scripts/agents/agent-bridge/` と各 runner に依存し、起動口 `$HOME/.agent-bridge` を経由する。
- `delegate-codex` は公式プラグイン `openai/codex-plugin-cc` を前提にする。
- route 系は `AGENTS.md` の実装・委託方針から呼ばれる。
- `route-implementation-quality` は外部 USER skill `karpathy-guidelines`（skills CLI 管理）と `superpowers` を前提にする。
- external-memory 系は `skills/external-memory-rules/core.md` を正本として参照する。
- `public-release-audit` のスクリプトは `git` と `gitleaks` に依存する。`gitleaks` が無い環境では終了コード2で止まり、秘密情報の観点を飛ばして続行しない。
- `agents/openai.yaml` はCodex UI向けの未検証メタデータ。新規skillで置く場合は `interface.display_name`、`short_description`、`default_prompt` をテストで検証し、実ロード確認までは動作前提にしない。
- Vault の正本パスは `<vault-root>`。

## 現状と既知の課題

- `skills/external-memory-rules/` には `SKILL.md` が無く、skill ではなく規約本文として扱う。
- external-memory role skill は安全規則を重複掲載せず、rules 参照に寄せている。
- `delegate-antigravity` / `delegate-copilot` の `investigation` mode は runner 上に残るが、skill 上の既定ルーティングでは調査を回さない。
