$ErrorActionPreference = 'Stop'

function Get-AgentConfigTargets {
    param([Parameter(Mandatory)][string]$RepoRoot)
    # 外部記憶Vaultのルート（ミラーの配置先。実体パスはここ1箇所のみ）
    $VaultRoot = '<vault-root>'
    $all = @(
        [pscustomobject]@{ Name='claude-CLAUDE.md';   SourcePath=(Join-Path $RepoRoot 'claude/CLAUDE.md');    DestinationPath=(Join-Path $env:USERPROFILE '.claude/CLAUDE.md');    LinkType='SymbolicLink'; Method='SymbolicLink' },
        [pscustomobject]@{ Name='claude-settings.json'; SourcePath=(Join-Path $RepoRoot 'claude/settings.json'); DestinationPath=(Join-Path $env:USERPROFILE '.claude/settings.json'); LinkType='SymbolicLink'; Method='SymbolicLink' },
        [pscustomobject]@{ Name='claude-hooks';        SourcePath=(Join-Path $RepoRoot 'claude/hooks');        DestinationPath=(Join-Path $env:USERPROFILE '.claude/hooks');        LinkType='SymbolicLink'; Method='SymbolicLink' },
        [pscustomobject]@{ Name='claude-skills';       SourcePath=(Join-Path $RepoRoot 'skills');              DestinationPath=(Join-Path $env:USERPROFILE '.claude/skills');       LinkType='SymbolicLink'; Method='SymbolicLink' },
        # Vaultミラーはコピー方式。VaultがGoogle Drive同期下にあり、symlink/junction（リパースポイント）が同期エラーになるため。
        [pscustomobject]@{ Name='vault-rules-mirror';  SourcePath=(Join-Path $RepoRoot 'skills/external-memory-rules'); DestinationPath=(Join-Path $VaultRoot 'System/external-memory-rules'); LinkType=$null; Method='Copy' },
        # HomeノートはVault直下の単一ファイル。ルールと同じく正本はリポジトリ、Vault側は生成コピー（手編集禁止）。
        [pscustomobject]@{ Name='vault-home';          SourcePath=(Join-Path $RepoRoot 'vault/Home.md'); DestinationPath=(Join-Path $VaultRoot 'Home.md'); LinkType=$null; Method='CopyFile' },
        # Todoノートは組み込み検索の埋め込みだけを持つ。Project横断の未完了タスクはここで見る。
        [pscustomobject]@{ Name='vault-todo';          SourcePath=(Join-Path $RepoRoot 'vault/Todo.md'); DestinationPath=(Join-Path $VaultRoot 'Todo.md'); LinkType=$null; Method='CopyFile' },
        # Codex は「Claude の1レイヤー下の司令塔」。正本 AGENTS.md と skills を共有する。
        # skills の配置先は公式 USER スコープ ~/.agents/skills。skills CLI 管理の実体 dir のため
        # 直下置換ではなく agent-config サブディレクトリへのネスト1リンクで共存させる。
        [pscustomobject]@{ Name='codex-AGENTS.md';  SourcePath=(Join-Path $RepoRoot 'AGENTS.md');  DestinationPath=(Join-Path $env:USERPROFILE '.codex/AGENTS.md');             LinkType='SymbolicLink'; Method='SymbolicLink' },
        [pscustomobject]@{ Name='codex-skills';     SourcePath=(Join-Path $RepoRoot 'skills');     DestinationPath=(Join-Path $env:USERPROFILE '.agents/skills/agent-config');  LinkType='SymbolicLink'; Method='SymbolicLink' },
        # 自作 Codex plugin。config.toml の agent-file-backup@personal 登録は配置先パス不変のため触らない。
        [pscustomobject]@{ Name='codex-agent-file-backup'; SourcePath=(Join-Path $RepoRoot 'codex/plugins/agent-file-backup'); DestinationPath=(Join-Path $env:USERPROFILE 'plugins/agent-file-backup'); LinkType='SymbolicLink'; Method='SymbolicLink' },
        # personal マーケットプレイス定義。config.toml の agent-file-backup@personal の解決元。
        # 旧リポの symlink だったため、旧リポ削除で @personal が壊れる。agent-config が引き取る。
        [pscustomobject]@{ Name='codex-agents-marketplace'; SourcePath=(Join-Path $RepoRoot 'codex/agents-plugins/marketplace.json'); DestinationPath=(Join-Path $env:USERPROFILE '.agents/plugins/marketplace.json'); LinkType='SymbolicLink'; Method='SymbolicLink' },
        # codex シム。standalone installer が置く %LOCALAPPDATA%\Programs\OpenAI\Codex\bin は
        # 非管理者作成のジャンクションで、Redirection Trust Mitigation が有効なプロセス
        # （Claude Code のシェル等）からは WinError 448 で辿れず codex が解決できない。
        # シムはジャンクションを辿らず参照先を読み取って実体を起動する。
        # symlink で配ると同じ走査拒否に自分が引っかかるため、必ず実ファイルコピーにする。
        # companion は $SHELL(/bin/bash.exe) 経由で spawn するため拡張子なしの対も要る。
        [pscustomobject]@{ Name='codex-shim-cmd';   SourcePath=(Join-Path $RepoRoot 'bin/codex.cmd'); DestinationPath=(Join-Path $env:USERPROFILE '.local/bin/codex.cmd'); LinkType=$null; Method='CopyFile' },
        [pscustomobject]@{ Name='codex-shim-posix'; SourcePath=(Join-Path $RepoRoot 'bin/codex');     DestinationPath=(Join-Path $env:USERPROFILE '.local/bin/codex');     LinkType=$null; Method='CopyFile' },
        # Antigravity / Copilot は委託受け専用の最小指示ファイルのみ（スキル配布なし）
        [pscustomobject]@{ Name='gemini-GEMINI.md'; SourcePath=(Join-Path $RepoRoot 'gemini/GEMINI.md'); DestinationPath=(Join-Path $env:USERPROFILE '.gemini/GEMINI.md'); LinkType='SymbolicLink'; Method='SymbolicLink' },
        [pscustomobject]@{ Name='copilot-instructions'; SourcePath=(Join-Path $RepoRoot 'copilot/copilot-instructions.md'); DestinationPath=(Join-Path $env:USERPROFILE '.copilot/copilot-instructions.md'); LinkType='SymbolicLink'; Method='SymbolicLink' },
        # 委託runnerの起動口。scripts/agents は自己完結（外部参照は $PSScriptRoot のみ）なので
        # ディレクトリごとリンクで足りる。コピーにすると再install忘れで古いrunnerが黙って使われる。
        [pscustomobject]@{ Name='agent-bridge'; SourcePath=(Join-Path $RepoRoot 'scripts/agents'); DestinationPath=(Join-Path $env:USERPROFILE '.agent-bridge'); LinkType='SymbolicLink'; Method='SymbolicLink' }
    )
    return $all
}

function Get-LinkTarget {
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    if (-not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { return $null }
    return $item.Target
}

function Test-AgentConfigLink {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedTarget,
        [ValidateSet('SymbolicLink','Junction')][string]$ExpectedLinkType
    )
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $false }
    if (-not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { return $false }
    if ($ExpectedLinkType -and $item.LinkType -ne $ExpectedLinkType) { return $false }
    $target = $item.Target
    if ($null -eq $target) { return $false }
    $rt = [System.IO.Path]::GetFullPath($target)
    $re = [System.IO.Path]::GetFullPath($ExpectedTarget)
    return [string]::Equals($rt, $re, [System.StringComparison]::OrdinalIgnoreCase)
}

function Backup-ExistingItem {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$TargetName
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $dest = Join-Path $BackupRoot $TargetName
    if (Test-Path -LiteralPath $dest) { throw "Backup destination already exists: $dest" }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $leaf = Split-Path -Leaf $Path
    $backupPath = Join-Path $dest $leaf
    Move-Item -LiteralPath $Path -Destination $backupPath
    return $backupPath
}

function Backup-UnmanagedCopyTarget {
    # コピー配布の前に、管理下でない実体が配置先にあれば退避する。
    # 管理下（マーカーあり）・リパースポイント・不在なら何もしない。
    # 退避したパスを返す（退避しなければ $null）。
    # Vault配下は生成コピー専用だが、~/.local/bin のようなユーザー領域へも配るため、
    # 利用者の既存ファイルを無条件に上書きしないこのガードが要る。
    param(
        [Parameter(Mandatory)][ValidateSet('Copy','CopyFile')][string]$Method,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$TargetName
    )
    $item = Get-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return $null }
    $isManaged = if ($Method -eq 'Copy') {
        Test-Path -LiteralPath (Join-Path $DestinationPath $script:MirrorMarkerName)
    } else {
        Test-AgentConfigCopyFileManaged -DestinationPath $DestinationPath
    }
    if ($isManaged) { return $null }
    return (Backup-ExistingItem -Path $DestinationPath -BackupRoot $BackupRoot -TargetName $TargetName)
}

function New-AgentConfigLink {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [ValidateSet('SymbolicLink','Junction')][string]$LinkType='SymbolicLink'
    )
    if (-not (Test-Path -LiteralPath $SourcePath)) { throw "Source path does not exist: $SourcePath" }
    $parent = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    New-Item -ItemType $LinkType -Path $DestinationPath -Target $SourcePath | Out-Null
}

function Remove-AgentConfigLink {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedTarget
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if (-not (Test-AgentConfigLink -Path $Path -ExpectedTarget $ExpectedTarget)) {
        throw "Refusing to remove non-managed path: $Path"
    }
    Remove-Item -LiteralPath $Path -Force
}

# --- コピー方式ミラー（Google Drive 同期と両立。symlink を使わない実体コピー） ---

$script:MirrorMarkerName = '_GENERATED.md'
$script:MirrorNotice = @"
# 生成物（手編集禁止）

このフォルダは外部記憶ルールの**生成コピー**です。Vault が Google Drive 同期下にあり
symlink が同期エラーになるため、実体コピーでミラーしています。直接編集しないでください。

- 正本: agent-config リポジトリ ``skills/external-memory-rules/``
- 再同期（昇格不要）: ``./scripts/sync-vault-mirror.ps1``
- 配置の確認: ``./scripts/status.ps1``
"@

function Get-AgentConfigFileHash {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Test-AgentConfigCopy {
    # 同期済み（ドリフト無し）なら $true。dest が実体ディレクトリかつマーカーを持ち、
    # source の全 *.md が一致し、source に無い *.md が dest に残っていないこと。
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )
    $item = Get-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $false }
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $DestinationPath $script:MirrorMarkerName))) { return $false }
    $srcNames = @(Get-ChildItem -LiteralPath $SourcePath -Filter *.md -File | Select-Object -ExpandProperty Name)
    foreach ($name in $srcNames) {
        $d = Join-Path $DestinationPath $name
        if (-not (Test-Path -LiteralPath $d)) { return $false }
        if ((Get-AgentConfigFileHash (Join-Path $SourcePath $name)) -ne (Get-AgentConfigFileHash $d)) { return $false }
    }
    foreach ($name in @(Get-ChildItem -LiteralPath $DestinationPath -Filter *.md -File | Select-Object -ExpandProperty Name)) {
        if ($name -eq $script:MirrorMarkerName) { continue }
        if ($srcNames -notcontains $name) { return $false }
    }
    return $true
}

function Sync-AgentConfigCopy {
    # source の *.md を dest へ実体コピーし、マーカーを書く。source に無い *.md は除去。
    # dest が古い symlink（リパースポイント）ならリンクのみ削除してから実体ディレクトリ化。
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )
    if (-not (Test-Path -LiteralPath $SourcePath)) { throw "Source path does not exist: $SourcePath" }
    $item = Get-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
    if ($null -ne $item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        [System.IO.Directory]::Delete($DestinationPath, $false)  # リンクのみ削除（対象は消さない）
        $item = $null
    }
    if ($null -eq $item) {
        New-Item -ItemType Directory -Force -Path $DestinationPath | Out-Null
    } elseif (-not $item.PSIsContainer) {
        throw "Destination exists and is not a directory: $DestinationPath"
    }
    $srcFiles = Get-ChildItem -LiteralPath $SourcePath -Filter *.md -File
    foreach ($f in $srcFiles) {
        Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $DestinationPath $f.Name) -Force
    }
    $srcNames = @($srcFiles | Select-Object -ExpandProperty Name)
    foreach ($d in Get-ChildItem -LiteralPath $DestinationPath -Filter *.md -File) {
        if ($d.Name -eq $script:MirrorMarkerName) { continue }
        if ($srcNames -notcontains $d.Name) { Remove-Item -LiteralPath $d.FullName -Force }
    }
    Set-Content -LiteralPath (Join-Path $DestinationPath $script:MirrorMarkerName) -Value $script:MirrorNotice -Encoding UTF8
}

function Remove-AgentConfigCopy {
    # 管理下のミラー（マーカーを持つ実体ディレクトリ）のみ削除。古い symlink はリンクのみ削除。
    param([Parameter(Mandatory)][string]$DestinationPath)
    if (-not (Test-Path -LiteralPath $DestinationPath)) { return }
    $item = Get-Item -LiteralPath $DestinationPath -Force
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        [System.IO.Directory]::Delete($DestinationPath, $false); return
    }
    if (-not (Test-Path -LiteralPath (Join-Path $DestinationPath $script:MirrorMarkerName))) {
        throw "Refusing to remove non-managed directory (no marker): $DestinationPath"
    }
    Remove-Item -LiteralPath $DestinationPath -Recurse -Force
}

# --- CopyFile 方式ミラー（Vault直下などの単一ファイル。Google Drive 同期と両立） ---
# フォルダ用 Copy と異なり別マーカーファイルを置けないため、生成物の目印は
# ファイル本文に埋め込んだマーカー行（先頭の HTML コメント）で判定する。

$script:MirrorFileMarker = '<!-- agent-config: generated mirror'

function Test-AgentConfigCopyFileManaged {
    # dest が管理下のミラー（マーカー行を含む実体ファイル）なら $true。
    param([Parameter(Mandatory)][string]$DestinationPath)
    if (-not (Test-Path -LiteralPath $DestinationPath -PathType Leaf)) { return $false }
    $item = Get-Item -LiteralPath $DestinationPath -Force
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return $false }
    $content = Get-Content -LiteralPath $DestinationPath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { return $false }
    return $content.Contains($script:MirrorFileMarker)
}

function Test-AgentConfigCopyFile {
    # 同期済み（ドリフト無し）なら $true。dest が実体ファイルで source とハッシュ一致。
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )
    if (-not (Test-Path -LiteralPath $DestinationPath -PathType Leaf)) { return $false }
    $item = Get-Item -LiteralPath $DestinationPath -Force
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return $false }
    return (Get-AgentConfigFileHash $SourcePath) -eq (Get-AgentConfigFileHash $DestinationPath)
}

function Sync-AgentConfigCopyFile {
    # source ファイルを dest へ実体コピー（上書き）。親ディレクトリは自動作成。
    # dest が古い symlink（リパースポイント）ならリンクのみ削除してから実体コピー。
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) { throw "Source file does not exist: $SourcePath" }
    $item = Get-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
    if ($null -ne $item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        Remove-Item -LiteralPath $DestinationPath -Force  # リンクのみ削除（対象は消さない）
    }
    $parent = Split-Path -Parent $DestinationPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
}

function Remove-AgentConfigCopyFile {
    # 管理下のミラー（マーカー行を持つ実体ファイル）のみ削除。古い symlink はリンクのみ削除。
    param([Parameter(Mandatory)][string]$DestinationPath)
    if (-not (Test-Path -LiteralPath $DestinationPath)) { return }
    $item = Get-Item -LiteralPath $DestinationPath -Force
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        Remove-Item -LiteralPath $DestinationPath -Force; return
    }
    if (-not (Test-AgentConfigCopyFileManaged -DestinationPath $DestinationPath)) {
        throw "Refusing to remove non-managed file (no marker): $DestinationPath"
    }
    Remove-Item -LiteralPath $DestinationPath -Force
}

Export-ModuleMember -Function Get-AgentConfigTargets, Get-LinkTarget, Test-AgentConfigLink, Backup-ExistingItem, Backup-UnmanagedCopyTarget, New-AgentConfigLink, Remove-AgentConfigLink, Test-AgentConfigCopy, Sync-AgentConfigCopy, Remove-AgentConfigCopy, Test-AgentConfigCopyFile, Sync-AgentConfigCopyFile, Remove-AgentConfigCopyFile, Test-AgentConfigCopyFileManaged
