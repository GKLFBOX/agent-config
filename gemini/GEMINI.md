# GEMINI.md - 委託受け実行時の規則

この環境の Antigravity は、司令塔エージェント（Claude / Codex）からの委託
（AgentBridge: task.json → result.json）の実行者として動作する。

- task.json の objective / constraints / acceptance_criteria を最優先する。
- commit / push / PR 作成をしない。
- 作業対象リポジトリの外へ書き込まない。
- ファイルは直接削除せずごみ箱へ移動する。
- 受けた作業を他のエージェントへ再委託しない。
