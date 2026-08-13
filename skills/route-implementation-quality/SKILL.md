---
name: route-implementation-quality
description: 実装（新規コード・修正・リファクタ・バグ修正）を含むタスクに着手する前に使用する。タスク規模に応じて品質スキル（karpathy-guidelines / superpowers）のどれを適用すべきか判断が必要な場面。「これは単純だから品質スキル不要」と感じたときも含む。
---

# 実装品質スキルの振り分け

## 概要

実装を含むタスクは、**着手前に規模を判定し、対応する品質スキルを必ず適用する**。

- `karpathy-guidelines`＝**作法オーバーレイ**。Claude では `andrej-karpathy-skills` plugin、Codex では skills CLI 管理の USER skill として導入する。各コード変更に対する振る舞い（簡潔・外科的変更・前提明示・検証可能なゴール）を担う。ワークフローではない。
- `superpowers`＝**ワークフロー**。起点 `superpowers:brainstorming` → `writing-plans` → 実装 → `test-driven-development` → `verification-before-completion` → `requesting-code-review`。

両者は排他ではない。大規模では併用する。

## 振り分け表

規模の定義は `route-delegation` の**委託サイズ分類**と共有する（二重管理しない）。

| 規模   | 定義                                 | 適用                                                                                                                                    |
| ------ | ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| 極小   | 数行・1ファイル・機械的              | `karpathy-guidelines`（作法のみ。ワークフロー不要）                                                                                     |
| 小規模 | 単一機能の小改修                     | `karpathy-guidelines`                                                                                                                   |
| 中〜大 | 新機能・設計判断が要る・複数ファイル | `superpowers` ワークフロー（起点 `superpowers:brainstorming`）。**実装／TDD 段階で `karpathy-guidelines` を作法オーバーレイとして併用** |

## 複合（中〜大での併用）

`superpowers` の実装／`test-driven-development` 段階に入ったら、各コード変更で `karpathy-guidelines` を同時に効かせる：最小コード、外科的変更（変更行はすべてユーザー要求に直結）、前提明示、検証可能なゴール。手順（superpowers）と作法（karpathy）は層が違うため矛盾しない。

## 委託との両立

実装を copilot / antigravity / codex へ委託する場合、品質スキルは**委託先に課さない**。Claude の採用時 diff レビュー・ゲート再実行に `karpathy-guidelines` 基準（簡潔・外科的・前提明示・検証）を適用して検収する。委託チェーンの選択は `route-delegation`、各委託先の起動は `delegate-*` 参照。

## 判定に迷ったら

- 設計判断・複数の解釈・新規サブシステムがある → 中〜大（`superpowers`、まず `brainstorming`）
- 変更がすべてユーザー要求に直結し機械的 → 極小／小規模（`karpathy-guidelines`）

## Red flags（振り分けを飛ばしている兆候）

- 「これは単純だから品質スキルは不要」→ 極小でも `karpathy-guidelines` は適用する（振る舞いオーバーレイは軽量）。
- 規模を判定する前にコードを書き始めている → 着手前に判定する。
- 中〜大なのに `brainstorming` を飛ばして実装に入っている → ワークフローの起点に戻る。
