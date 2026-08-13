---
name: delegate-antigravity
description: Claude が量産的な末端実装を Antigravity(agy, Gemini flash) へ AgentBridge 経由で委託し、要約だけ受け取って Claude 枠を節約したいときに使用する。実装専用（レビュー・設計判断・調査/digest には使わない。それらは codex）。実装計画が明確な中〜大実装の一次委託先、小規模実装のチェーン2番手。
---

# Delegate to Antigravity (AgentBridge)

> 位置づけ: ファイルベースの AgentBridge 経由で Antigravity(`agy`) に実装を委託する。
> 核と入口はリポジトリの `scripts/agents/`。起動口は `$HOME/.agent-bridge/`（インストールが張るsymlink）。
> 委託の共通規約（チェーン選択・read-only/write境界）は正本 `route-delegation` に従う。

Claude を司令塔とし、`agy` に task.json を渡して result.json を受け取る。委託結果は必ず
Claude がレビューしてから採用する。

## 委託すべき（Antigravity 向き＝実装のみ）

- **実装計画が明確な中〜大実装の一次委託先**（チェーン: anti → codex → Claude）
- **小規模実装のチェーン2番手**（copilot → anti → codex → Claude）
- 計画が決まっていて決定論的に量産できる実装が得意。`-Model`は必須で、値は`route-delegation`のモデル指定節に従う。

## Antigravity に投げない（codex パッケージ or Claude へ）

- 調査・読み込み・digest・リサーチ（→ codex。枠が小さいので大量読みに使わない）
- レビュー・クロスモデル検証（レビューは Claude 主導、必要時 codex `/codex:review`）
- 設計判断・最終レビュー・統合の意思決定（Claude）
- 実装計画が無い/判断を含む実装（→ codex から）
- commit / push / PR 作成
- 成果が大幅修正を要する場合は Claude が直さず codex へエスカレーション

> `investigation`（read）モードはスクリプト上は残るが、既定ルーティングでは調査を回さない。
> 実装の読み取り補助が要る局面に限って使い、まとまった調査/digest は codex へ委ねる。

## 呼び方（read: investigation）

```powershell
pwsh -NoProfile -File $HOME/.agent-bridge/run-antigravity.ps1 `
  -Repository "<対象repoの絶対パス>" -TaskType investigation -Model "<モデルID>" -Objective "<調査内容>"
```

## 呼び方（write: implementation）

**必ず専用ブランチ/worktree に切り替えてから**、`-Write` を明示する:

```powershell
pwsh -NoProfile -File $HOME/.agent-bridge/run-antigravity.ps1 `
  -Repository "<対象repoの絶対パス>" -TaskType implementation -Model "<モデルID>" -Write -Objective "<実装指示>"
```

- 任意: `-Constraints`, `-AcceptanceCriteria`（string[]）、`-TimeoutSeconds`（既定300）。
- 標準出力に `Read-AgentBridgeResult` の要約 JSON だけが返る（agy の出力は変数へ捕捉し、失敗時だけ添える）。

## 動作メモ

run-antigravity.ps1 が内部で対処済みなので利用側は意識不要:

- **stdin を閉じて `agy` を起動**する（開いたままだと `agy -p` は起動直後フリーズ）。ConPTY は不要。
- プロンプトに **result.json の厳密スキーマを明示**する（agy が形状を improvise して検証で弾かれるのを防ぐ）。
- read/write とも `--yolo` / `--add-dir` は不要。`.agent-bridge/`（ドット始まり）への書込も問題なし。
- **無効なモデルIDは即座に失敗する**。非0終了時にagyの出力を添えてthrowするので、`result.json`待ちのタイムアウトにならない。

## 結果の扱い（Claude 最終ゲート）

- `result.json` は**常に未信頼入力**。核がスキーマ厳格検証・パス検証（絶対パス/`..`/symlink 拒否）を担保する。
- `verification` のコマンド文字列は**エビデンス**。**自動再実行しない**。
- write は Claude がクリーンな状態で `git diff` をレビューし、採用可なら明示採用。委託先に commit/push させない。

## 安全規則

- 対象リポの `.gitignore` に `.agent-bridge/` を入れる（transient をコミットしない）。
- write は専用ブランチ/worktree 内のみ。`-Write` 無しの `implementation` は拒否される（誤爆防止）。
- 固定ランチャー文は英語（既定）。日本語 Objective は `task.json`(UTF-8) 経由で渡り**文字化けしない**。英語固定は保守的な既定で、日本語必須ではない。
- 期限切れリクエストは `scripts/agents/agent-bridge/Move-ExpiredAgentBridgeRequest.ps1` で手動掃除（ごみ箱へ）。
