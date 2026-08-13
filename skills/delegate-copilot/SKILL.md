---
name: delegate-copilot
description: Claude が小規模な量産的末端実装を GitHub Copilot CLI(copilot, モデル auto) へ AgentBridge 経由で委託し、要約だけ受け取って Claude 枠を節約したいときに使用する。実装専用・小規模の一次委託先（枠が最小のため小規模に限定）。レビュー・調査には使わない。Antigravity と並列チャネル。
---

# Delegate to GitHub Copilot CLI (AgentBridge)

> 位置づけ: Antigravity(`agy`, Gemini系) と並列の末端実装・調査チャネル。委託先 CLI が
> `copilot`(GPT/Claude系) になるだけで、ファイルベース AgentBridge の核・プロトコルは共通。
> 核と入口はリポジトリの `scripts/agents/`。起動口は `$HOME/.agent-bridge/`（インストールが張るsymlink）。
> 委託の共通規約（チェーン選択・read-only/write境界）は正本 `route-delegation` に従う。

Claude を司令塔とし、`copilot` に task.json を渡して result.json を受け取る。委託結果は必ず
Claude が確認してから採用する。`-Model` は必須で、`auto` を指定する。値は `route-delegation` のモデル指定節に従う。

## 委託すべき（Copilot 向き＝小規模実装のみ）

- **小規模実装の一次委託先**（チェーン: copilot → anti → codex → Claude）
- 枠が最小のため**小規模に限定**。中〜大実装・調査は回さない（anti/codex へ）。

## Copilot に投げない（次段 or Claude へ）

- 中〜大の実装（枠が小さい。anti/codex へ）
- 調査・読み込み・digest・リサーチ（→ codex）
- レビュー・クロスモデル検証（モデル auto=Claude系を引く可能性があり検証価値が消える。→ codex/Claude）
- 設計判断・最終判断・統合の意思決定（Claude）
- commit / push / PR 作成
- 成果が大幅修正を要する場合は Claude が直さず codex へエスカレーション

> `investigation`（read）モードはスクリプト上は残るが、既定ルーティングでは調査を回さない。
> まとまった調査/digest は codex へ委ねる。

## 呼び方（read: investigation）

```powershell
pwsh -NoProfile -File $HOME/.agent-bridge/run-copilot.ps1 `
  -Repository "<対象repoの絶対パス>" -TaskType investigation -Model auto -Objective "<調査内容>"
```

## 呼び方（write: implementation）

**必ず専用ブランチ/worktree に切り替えてから**、`-Write` を明示する:

```powershell
pwsh -NoProfile -File $HOME/.agent-bridge/run-copilot.ps1 `
  -Repository "<対象repoの絶対パス>" -TaskType implementation -Model auto -Write -Objective "<実装指示>"
```

- 任意: `-Constraints`, `-AcceptanceCriteria`（string[]）、`-TimeoutSeconds`（既定300）。
- 標準出力に `Read-AgentBridgeResult` の要約 JSON だけが返る（copilot の出力は変数へ捕捉し、失敗時だけ添える）。

## 動作メモ

run-copilot.ps1 が内部で対処済みなので利用側は意識不要:

- `copilot -p` を非対話起動。stdin ハングなし（`$null|` は caller 非依存の保険として踏襲）。
- プロンプトに **result.json の厳密スキーマを明示**（improvise 防止）。
- 権限フラグは TaskType で分岐（copilot の kind 記法）:
  - investigation = `--allow-tool write --deny-tool shell`（write ツールで result.json を書き、
    source 無改変・repo 外書込なし・シェル不使用）。
  - implementation = `--allow-all-tools`（source 改変・verification 実行・changed_files 反映）。
- copilot の統計行は stderr。orchestrator の stdout は要約 JSON のみで汚れない。
- 非ASCII（Objective 日本語）は task.json(UTF-8) 経由で agy 同様に低リスク。
- **無効なモデルIDは即座に失敗する**。非0終了時に copilot の出力を添えて throw するので、`result.json` 待ちのタイムアウトにならない。

## 結果の扱い（Claude 最終ゲート）

- `result.json` は**常に未信頼入力**。核がスキーマ厳格検証・パス検証（絶対パス/`..`/symlink 拒否）を担保。
- `verification` のコマンド文字列は**エビデンス**。**自動再実行しない**。
- write は Claude がクリーンな状態で `git diff` を確認し、採用可なら明示採用。委託先に commit/push させない。

## 安全規則

- 対象リポの `.gitignore` に `.agent-bridge/` を入れる（Antigravity と共用。transient をコミットしない）。
- write は専用ブランチ/worktree 内のみ。`-Write` 無しの `implementation` は拒否される（誤爆防止）。
- investigation はシェル実行を禁止して回す（爆発半径をファイル書込のみに限定）。
- repo 外書込は copilot 既定のパス検証（`--allow-all-paths` を渡さない）で「repo 直下＋system temp」に
  構造的に制限される（OS サンドボックスではない）。**最終防波堤は専用ブランチ + Claude の diff レビュー**で、
  プロンプトの「repo 外に書くな」は補助に過ぎない。より強い封じ込めが要るなら worktree/コンテナで隔離する
  （核の外側で。将来オプション）。
- 委託プロンプトは英語（保守的な既定）。
- 期限切れリクエストは `scripts/agents/agent-bridge/Move-ExpiredAgentBridgeRequest.ps1` で手動掃除（ごみ箱へ）。
