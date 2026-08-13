<#
.SYNOPSIS
公開ツリーへ公開前監査の決定的チェックを当てる。

.DESCRIPTION
観点ごとに PASS / 要確認 / 情報 を出す。
判断が要る観点（コミットメッセージ、README、.gitignore、grepヒットの残置可否）は扱わない。
終了コードは 0=全PASS、1=要確認あり、2=実行不能。
#>
[CmdletBinding()]
param(
    [string]$RepoPath = '.',
    [Parameter(Mandatory)][string]$Allowlist,
    [string]$Denylist
)

$ErrorActionPreference = 'Stop'

$script:Results = @()

function Add-Result {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('PASS', '要確認', '情報', 'スキップ')][string]$Status,
        [string[]]$Detail = @()
    )
    $script:Results += [pscustomobject]@{ Name = $Name; Status = $Status; Detail = @($Detail) }
}

function Exit-Unavailable {
    param([Parameter(Mandatory)][string]$Reason)
    Write-Output "[実行不能] $Reason"
    exit 2
}

# git の終了コードを判定に使うため、stderr は捨てて stdout だけを返す。
function Invoke-Git {
    # AllowEmptyString は git grep -Il '' の空パターンを渡すために要る。
    param([Parameter(Mandatory)][AllowEmptyString()][string[]]$Arguments)
    $out = & git -C $script:Repo @Arguments 2>$null
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = @($out) }
}

# Windows のコマンドライン長には上限がある。ファイル数が多い repo でも渡せるよう分割する。
function Split-ArgumentBatch {
    param(
        [Parameter(Mandatory)][string[]]$Items,
        [int]$MaxLength = 16000
    )
    $batches = @()
    $current = @()
    $length = 0
    foreach ($item in $Items) {
        if ($current.Count -gt 0 -and ($length + $item.Length + 3) -gt $MaxLength) {
            $batches += , $current
            $current = @()
            $length = 0
        }
        $current += $item
        $length += $item.Length + 3
    }
    if ($current.Count -gt 0) { $batches += , $current }
    return $batches
}

# 走査対象は作業ツリー全体ではなく「追跡済み＋未追跡かつ無視されていない」。
# 新規 git init して git add . したときに入る集合と一致する。
function Test-Secret {
    if (-not (Get-Command gitleaks -ErrorAction SilentlyContinue)) {
        Exit-Unavailable 'gitleaks が見つからない'
    }

    $files = @((Invoke-Git -Arguments @('ls-files', '--cached', '--others', '--exclude-standard')).Lines)
    if ($files.Count -eq 0) {
        Add-Result -Name '秘密情報' -Status 'PASS'
        return
    }

    $detail = @()
    Push-Location -LiteralPath $script:Repo
    try {
        foreach ($batch in (Split-ArgumentBatch -Items $files)) {
            $out = & gitleaks dir @batch --redact --no-banner 2>&1
            switch ($LASTEXITCODE) {
                0       { }
                1       { $detail += @($out | ForEach-Object { $_.ToString() }) }
                default { Exit-Unavailable "gitleaks の実行に失敗した (終了コード $LASTEXITCODE)" }
            }
        }
    } finally {
        Pop-Location
    }

    if ($detail.Count -gt 0) {
        Add-Result -Name '秘密情報' -Status '要確認' -Detail $detail
    } else {
        Add-Result -Name '秘密情報' -Status 'PASS'
    }
}

# git grep は「ヒットあり」で0、「ヒットなし」で1を返す。2以上は走査の失敗。
function Invoke-GrepCheck {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    $result = Invoke-Git -Arguments $Arguments
    switch ($result.ExitCode) {
        0       { Add-Result -Name $Name -Status '要確認' -Detail $result.Lines }
        1       { Add-Result -Name $Name -Status 'PASS' }
        default { Exit-Unavailable "$Name の走査に失敗した (git grep 終了コード $($result.ExitCode))" }
    }
}

# 先頭の \b を外すと https:/ を拾う。
function Test-LocalPath {
    Invoke-GrepCheck -Name 'ローカルパス' -Arguments @('grep', '-nIE', '\b[A-Za-z]:[\\/]|/home/|/Users/|~/')
}

function Test-PersonalIdentifier {
    if (-not $Denylist) {
        Add-Result -Name '個人識別子' -Status 'スキップ' -Detail @('-Denylist が未指定')
        return
    }
    # git -C で作業ディレクトリが変わるため絶対パスへ直す。
    $denylistPath = (Resolve-Path -LiteralPath $Denylist).Path
    Invoke-GrepCheck -Name '個人識別子' -Arguments @('grep', '-nIf', $denylistPath)
}

function Get-AllowlistEntry {
    param([Parameter(Mandatory)][string]$Path)
    Get-Content -LiteralPath $Path |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne '' -and -not $_.StartsWith('#') } |
        ForEach-Object { $_.TrimEnd('/') }
}

function Test-AllowlistDiff {
    $entries = @(Get-AllowlistEntry -Path $Allowlist)
    $tracked = @((Invoke-Git -Arguments @('ls-files')).Lines)

    $unexpected = @($tracked | Where-Object {
        $file = $_
        -not @($entries | Where-Object { $file -eq $_ -or $file.StartsWith("$_/") }).Count
    })
    $missing = @($entries | Where-Object {
        $entry = $_
        -not @($tracked | Where-Object { $_ -eq $entry -or $_.StartsWith("$entry/") }).Count
    })

    $detail = @()
    $detail += $unexpected | ForEach-Object { "allowlist にない: $_" }
    $detail += $missing    | ForEach-Object { "写し漏れ: $_" }

    if ($detail.Count -gt 0) {
        Add-Result -Name 'allowlistとの差分' -Status '要確認' -Detail $detail
    } else {
        Add-Result -Name 'allowlistとの差分' -Status 'PASS'
    }
}

# git ls-files -i は該当ありでも0を返す。出力の有無で判定する。
function Test-IgnoredButTracked {
    $result = Invoke-Git -Arguments @('ls-files', '-i', '-c', '--exclude-standard')
    if ($result.Lines.Count -gt 0) {
        Add-Result -Name '無視漏れ' -Status '要確認' -Detail $result.Lines
    } else {
        Add-Result -Name '無視漏れ' -Status 'PASS'
    }
}

function Test-LargeOrBinaryFile {
    $tracked = @((Invoke-Git -Arguments @('ls-files')).Lines)
    # git grep -Il '' はテキストファイルだけを列挙する。差分がバイナリになる。
    $textFiles = @((Invoke-Git -Arguments @('grep', '-Il', '')).Lines)

    $detail = @()
    foreach ($file in $tracked) {
        $item = Get-Item -LiteralPath (Join-Path $script:Repo $file) -ErrorAction SilentlyContinue
        if ($item -and $item.Length -gt 1MB) {
            $detail += ("1MB超: {0} ({1:N0} bytes)" -f $file, $item.Length)
        }
    }
    $detail += $tracked | Where-Object { $textFiles -notcontains $_ } | ForEach-Object { "バイナリ: $_" }

    if ($detail.Count -gt 0) {
        Add-Result -Name '巨大ファイル・バイナリ' -Status '要確認' -Detail $detail
    } else {
        Add-Result -Name '巨大ファイル・バイナリ' -Status 'PASS'
    }
}

function Add-AuthorInfo {
    $result = Invoke-Git -Arguments @('log', '--all', '--format=%an <%ae>%n%cn <%ce>')
    Add-Result -Name '全コミットの著者' -Status '情報' -Detail @($result.Lines | Sort-Object -Unique)
}

function Add-HistoryInfo {
    $branches = @((Invoke-Git -Arguments @('branch', '-a')).Lines | ForEach-Object { $_.Trim() })
    $tags     = @((Invoke-Git -Arguments @('tag')).Lines)
    $remotes  = @((Invoke-Git -Arguments @('remote', '-v')).Lines)
    $count    = (Invoke-Git -Arguments @('rev-list', '--all', '--count')).Lines -join ''

    Add-Result -Name '履歴の広がり' -Status '情報' -Detail @(
        "コミット総数: $count"
        "ブランチ: $($branches -join ', ')"
        "タグ: $($tags -join ', ')"
        "remote: $($remotes -join ' / ')"
    )
}

function Write-Report {
    foreach ($result in $script:Results) {
        Write-Output "[$($result.Status)] $($result.Name)"
        foreach ($line in $result.Detail) { Write-Output "    $line" }
    }
}

try {
    $script:Repo = (Resolve-Path -LiteralPath $RepoPath -ErrorAction Stop).Path
} catch {
    Exit-Unavailable "RepoPath が見つからない: $RepoPath"
}

& git -C $script:Repo rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) { Exit-Unavailable "git リポジトリではない: $script:Repo" }

if (-not (Test-Path -LiteralPath $Allowlist)) { Exit-Unavailable "allowlist が見つからない: $Allowlist" }
if ($Denylist -and -not (Test-Path -LiteralPath $Denylist)) { Exit-Unavailable "denylist が見つからない: $Denylist" }

Test-Secret
Test-LocalPath
Test-PersonalIdentifier
Test-AllowlistDiff
Test-IgnoredButTracked
Test-LargeOrBinaryFile
Add-AuthorInfo
Add-HistoryInfo

Write-Report
if (@($script:Results | Where-Object { $_.Status -eq '要確認' }).Count -gt 0) { exit 1 }
exit 0
