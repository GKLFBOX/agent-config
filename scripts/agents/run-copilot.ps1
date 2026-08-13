param(
    [Parameter(Mandatory = $true)][string]$Repository,
    [Parameter(Mandatory = $true)][ValidateSet('investigation', 'implementation')][string]$TaskType,
    [Parameter(Mandatory = $true)][string]$Objective,
    [Parameter(Mandatory = $true)][string]$Model,
    [string[]]$Constraints = @(),
    [string[]]$AcceptanceCriteria = @(),
    [switch]$Write,
    [int]$TimeoutSeconds = 300,
    [scriptblock]$Launcher
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

# write は専用ブランチ前提。明示的 -Write が無い implementation は拒否する（誤爆防止）。
if ($TaskType -eq 'implementation' -and -not $Write) {
    throw 'implementation (write) requires -Write. Switch to a dedicated branch/worktree first.'
}

$BridgeRoot = Join-Path $PSScriptRoot 'agent-bridge'
Import-Module (Join-Path $BridgeRoot 'AgentBridge.psm1') -Force

$Request = New-AgentBridgeRequest `
    -Repository $Repository -TaskType $TaskType -Objective $Objective `
    -Constraints $Constraints -AcceptanceCriteria $AcceptanceCriteria -ReviewScope @()

if (-not $PSBoundParameters.ContainsKey('Launcher')) {
    # 既定 Launcher: リポジトリ直下(-C)で copilot を起動。stdout は使わず result.json をファイルで受ける。
    # 【2026-07-02 実機 E2E 確定】権限フラグ（read/write とも完動。文法は `copilot help permissions` の kind 記法）:
    #   investigation: `--allow-tool write --deny-tool shell`。copilot のネイティブ write ツールが
    #     result.json.tmp→rename を shell 無しで処理。source 無改変・repo 外書込なしを実証。
    #   implementation: `--allow-all-tools`（非対話で書込作業に必須）。source 改変・verification 実行・
    #     changed_files 反映を実証。
    # パス封じ込め: `--allow-all-paths`/`--yolo` は**意図的に渡さない**。copilot 既定のパス検証が
    #   ファイルアクセスを「cwd(=-C の repo 直下)＋システム temp」に構造的に制限する（OS サンドボックス
    #   ではない＝残る抜け穴は system temp）。repo 外書込防止の最終防波堤は「専用ブランチ + Claude の
    #   diff レビュー」。プロンプトの "Do not write outside this repository" は補助的な誘導に過ぎない。
    # copilot は `-p` 非対話で stdin ハングなし（`$null|` は agy 由来の防御として踏襲＝caller 非依存の保険）。
    # copilot の統計行は stderr。出力は変数へ捕捉するので orchestrator の stdout は要約JSONのみ。
    $Launcher = {
        param($Req, $Repo, [bool]$IsWrite, [string]$Model)
        $rid = $Req.RequestId
        # result.json は厳密スキーマ。形状(特に verification/findings/review_focus の
        # オブジェクト配列)を明示しないと improvise され核の検証で弾かれる。
        # 品質条項(implementation のみ)。karpathy-guidelines の要旨を自前の言葉で焼き込む。
        # 外部スキルのコピー配布を避けつつ、全委託に決定論的に効かせる。
        $quality = if ($IsWrite) {
            @"

Quality requirements:
- Make the smallest change that satisfies the objective. No extra features, abstractions, or refactoring.
- Follow the existing code style of the repository.
- State any assumptions you made in the result summary.
"@
        }
        else { '' }
        $prompt = @"
Read .agent-bridge/$rid/task.json in this repository and perform the task described by its "objective", honoring its "constraints" and "acceptance_criteria".
Then write your result as JSON to .agent-bridge/$rid/result.json.tmp and atomically rename it to .agent-bridge/$rid/result.json. Do not write anything outside this repository.
The result JSON MUST conform exactly to this schema (use empty arrays for fields that do not apply):
{
  "schema_version": 1,
  "request_id": "$rid",
  "status": "completed" | "partial" | "failed",
  "summary": "at most 500 characters",
  "changed_files": ["<repo-relative path>"],
  "verification": [{"command": "<string>", "status": "passed" | "failed" | "skipped", "reason": <string or null>, "artifact": <string or null>}],
  "findings": [{"severity": "critical" | "high" | "medium" | "low", "file": <repo-relative path or null>, "line": <int or null>, "title": "<string>", "reason": "<string>", "suggestion": "<string>", "confidence": "high" | "medium" | "low"}],
  "decisions": ["<string>"],
  "risks": ["<string>"],
  "review_focus": [{"file": "<repo-relative path>", "line": <int or null>, "reason": "<string>"}],
  "artifacts": []
}
Rules: request_id must equal "$rid". verification, findings and review_focus are arrays of OBJECTS with exactly the keys shown (never plain strings). changed_files, decisions and risks are arrays of strings. Do not include any field not listed above.$quality
"@
        # 権限フラグ（TaskType で分岐）。ツール名は copilot の kind 記法（`write` / `shell`）。E2E 確定済み。
        if ($IsWrite) {
            $permArgs = @('--allow-all-tools')
        }
        else {
            $permArgs = @('--allow-tool', 'write', '--deny-tool', 'shell')
        }
        # stdin を閉じる($null|)＝防御。出力は変数へ捕捉し、orchestrator の標準出力を要約JSONだけに
        # 保つ。copilot は成功時も統計行を stderr へ出すため、非0終了のときだけ添える
        # ($PSNativeCommandUseErrorActionPreference は既定 False なので自動throwされない)。
        $output = $null | copilot --model $Model -p $prompt -C $Repo --no-color @permArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            $detail = ($output | Out-String).Trim()
            if ($detail.Length -gt 1000) { $detail = $detail.Substring(0, 1000) }
            throw "copilot failed (exit $LASTEXITCODE): $detail"
        }
    }
}

& $Launcher $Request $Repository ($TaskType -eq 'implementation') $Model

$null = Wait-AgentBridgeResult -RequestDirectory $Request.RequestDirectory -TimeoutSeconds $TimeoutSeconds
Read-AgentBridgeResult -RequestDirectory $Request.RequestDirectory | ConvertTo-Json -Depth 10
