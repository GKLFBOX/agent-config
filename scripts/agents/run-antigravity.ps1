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
    # 既定 Launcher: リポジトリ直下で agy を起動。stdout は使わず result.json をファイルで受ける。
    # 英語プロンプト固定。write の追加フラグ(--add-dir/--yolo)は E2E(Task 4)で確定するまで付けない。
    # 【必須】非対話実行では stdin を閉じる($null|)。開いたままだと agy -p は起動直後フリーズする
    # (Qiita fallout/5097f0575b58f4c69b81 / agy issue #76 系。ConPTY は不要)。
    $Launcher = {
        param($Req, $Repo, [bool]$IsWrite, [string]$Model)
        $rid = $Req.RequestId
        # result.json は厳密スキーマ。agy に形状(特に verification/findings/review_focus の
        # オブジェクト配列)を明示しないと文字列配列等で improvise し検証で弾かれる(E2Eで確認)。
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
        Push-Location $Repo
        try {
            # stdin を閉じる($null|)＝フリーズ回避。出力は変数へ捕捉し、orchestrator の標準出力を
            # Read-AgentBridgeResult の要約JSONだけに保つ。無効なモデルIDは result.json が出ないまま
            # 終わるため、非0終了を検知して出力を添える($PSNativeCommandUseErrorActionPreference は
            # 既定 False なので自動throwされない)。
            $output = $null | agy --model $Model -p $prompt 2>&1
            if ($LASTEXITCODE -ne 0) {
                $detail = ($output | Out-String).Trim()
                if ($detail.Length -gt 1000) { $detail = $detail.Substring(0, 1000) }
                throw "agy failed (exit $LASTEXITCODE): $detail"
            }
        }
        finally {
            Pop-Location
        }
    }
}

& $Launcher $Request $Repository ($TaskType -eq 'implementation') $Model

$null = Wait-AgentBridgeResult -RequestDirectory $Request.RequestDirectory -TimeoutSeconds $TimeoutSeconds
Read-AgentBridgeResult -RequestDirectory $Request.RequestDirectory | ConvertTo-Json -Depth 10
