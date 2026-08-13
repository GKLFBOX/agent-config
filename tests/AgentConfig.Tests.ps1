BeforeAll {
    $RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    Import-Module (Join-Path $RepoRoot 'scripts/lib/AgentConfig.psm1') -Force
    # symlink 作成が可能か（管理者/開発者モード）を判定。不可ならリンク系テストはスキップ。
    $script:CanSymlink = $false
    try {
        $t = New-Item -ItemType File (Join-Path $TestDrive 'sl_src.txt')
        New-Item -ItemType SymbolicLink -Path (Join-Path $TestDrive 'sl_lnk.txt') -Target $t.FullName -ErrorAction Stop | Out-Null
        $script:CanSymlink = $true
    } catch { $script:CanSymlink = $false }
}

Describe 'Get-AgentConfigTargets' {
    It 'Claude の4ターゲットを含む' {
        $targets = Get-AgentConfigTargets -RepoRoot $RepoRoot
        @($targets | Where-Object Name -like 'claude-*').Count | Should -Be 4
        ($targets | Where-Object Name -eq 'claude-CLAUDE.md').DestinationPath |
            Should -Be (Join-Path $env:USERPROFILE '.claude/CLAUDE.md')
        ($targets | Where-Object Name -eq 'claude-skills').LinkType | Should -Be 'SymbolicLink'
        ($targets | Where-Object Name -eq 'claude-skills').SourcePath |
            Should -Be (Join-Path $RepoRoot 'skills')
    }
    It 'Vaultミラーターゲットはコピー方式（Drive同期と両立）' {
        $m = (Get-AgentConfigTargets -RepoRoot $RepoRoot) | Where-Object Name -eq 'vault-rules-mirror'
        $m | Should -Not -BeNullOrEmpty
        $m.SourcePath | Should -Be (Join-Path $RepoRoot 'skills/external-memory-rules')
        $m.Method     | Should -Be 'Copy'
        $m.DestinationPath | Should -Match '[\\/]System[\\/]external-memory-rules$'
    }
    It 'Homeノートは単一ファイルのコピーミラー（CopyFile）' {
        $m = (Get-AgentConfigTargets -RepoRoot $RepoRoot) | Where-Object Name -eq 'vault-home'
        $m | Should -Not -BeNullOrEmpty
        $m.SourcePath | Should -Be (Join-Path $RepoRoot 'vault/Home.md')
        $m.Method     | Should -Be 'CopyFile'
        $m.DestinationPath | Should -Match 'Home\.md$'
    }
    It 'symlink系ターゲットの Method は SymbolicLink' {
        ($targets = Get-AgentConfigTargets -RepoRoot $RepoRoot) | Out-Null
        ($targets | Where-Object Name -eq 'claude-skills').Method | Should -Be 'SymbolicLink'
    }
    It '全15ターゲットを返す' {
        $t = Get-AgentConfigTargets -RepoRoot $RepoRoot
        $t.Count | Should -Be 15
    }
    It 'AgentBridge は scripts/agents を ~/.agent-bridge へ symlink で配る' {
        $m = (Get-AgentConfigTargets -RepoRoot $RepoRoot) | Where-Object Name -eq 'agent-bridge'
        $m | Should -Not -BeNullOrEmpty
        $m.SourcePath | Should -Be (Join-Path $RepoRoot 'scripts/agents')
        $m.DestinationPath | Should -Be (Join-Path $env:USERPROFILE '.agent-bridge')
        $m.Method | Should -Be 'SymbolicLink'
        $m.LinkType | Should -Be 'SymbolicLink'
    }
    It 'codex シムは実ファイルコピー（CopyFile）で ~/.local/bin へ配る' {
        $targets = Get-AgentConfigTargets -RepoRoot $RepoRoot
        $cmd = $targets | Where-Object Name -eq 'codex-shim-cmd'
        $sh  = $targets | Where-Object Name -eq 'codex-shim-posix'

        $cmd | Should -Not -BeNullOrEmpty
        $sh  | Should -Not -BeNullOrEmpty
        $cmd.SourcePath | Should -Be (Join-Path $RepoRoot 'bin/codex.cmd')
        $sh.SourcePath  | Should -Be (Join-Path $RepoRoot 'bin/codex')
        $cmd.DestinationPath | Should -Match '[\\/]\.local[\\/]bin[\\/]codex\.cmd$'
        $sh.DestinationPath  | Should -Match '[\\/]\.local[\\/]bin[\\/]codex$'
        # symlink で配ると、シムが回避しようとしている reparse point 走査拒否に自分が引っかかる
        $cmd.Method | Should -Be 'CopyFile'
        $sh.Method  | Should -Be 'CopyFile'
    }
    It 'POSIXシムは改行が LF に固定される（CRLF だと shebang が壊れる）' {
        # core.autocrlf=true の環境では、属性を付けないと checkout で CRLF 化し
        # `#!/bin/sh\r` になって Git Bash が実行できなくなる。
        $attr = & git -C $RepoRoot check-attr eol -- bin/codex
        $attr | Should -Match 'eol: lf$'
    }
    It 'シムはASCIIのみで書かれる（cmd は OEM コードページで読むため）' {
        # 非ASCIIバイトは CP932 として誤デコードされ、コマンドとして実行されうる。
        foreach ($f in @('bin/codex.cmd','bin/codex')) {
            $nonAscii = [IO.File]::ReadAllBytes((Join-Path $RepoRoot $f)) | Where-Object { $_ -gt 127 }
            @($nonAscii).Count | Should -Be 0 -Because "$f に非ASCIIバイトがある"
        }
    }
    It 'cmdシムのマーカーはラベル行に置く（rem 行だと < がリダイレクト扱いになる）' {
        $lines = Get-Content (Join-Path $RepoRoot 'bin/codex.cmd')
        $markerLine = $lines | Where-Object { $_ -match '<!-- agent-config: generated mirror' }
        $markerLine | Should -Not -BeNullOrEmpty
        $markerLine | Should -Match '^::'
    }
    It 'cmdシムはCODEX_HOMEを上書きしない' {
        $content = Get-Content (Join-Path $RepoRoot 'bin/codex.cmd') -Raw
        $content | Should -Not -Match '(?m)^set "CODEX_HOME='
    }
    It 'シム本文が生成物マーカーを持つ（uninstall が管理下と判定できる）' {
        foreach ($f in @('bin/codex.cmd','bin/codex')) {
            (Get-Content (Join-Path $RepoRoot $f) -Raw) | Should -Match '<!-- agent-config: generated mirror'
        }
    }
    It 'Codex の4ターゲット（AGENTS.md・skills・plugin・marketplace）はsymlink配置' {
        $t = Get-AgentConfigTargets -RepoRoot $RepoRoot |
            Where-Object { $_.Name -like 'codex-*' -and $_.Name -notlike 'codex-shim-*' }
        $t.Name | Should -Be @('codex-AGENTS.md', 'codex-skills', 'codex-agent-file-backup', 'codex-agents-marketplace')
        # 公式 USER スコープ ~/.agents/skills（skills CLI 管理の実体 dir）と共存させるためネスト配置
        ($t | Where-Object Name -eq 'codex-skills').DestinationPath |
            Should -Be (Join-Path $env:USERPROFILE '.agents/skills/agent-config')
        ($t | Where-Object Name -eq 'codex-AGENTS.md').SourcePath | Should -Be (Join-Path $RepoRoot 'AGENTS.md')
        $t.Method | Should -Be @('SymbolicLink', 'SymbolicLink', 'SymbolicLink', 'SymbolicLink')
    }
    It 'Codex plugin ターゲットが ~/plugins/agent-file-backup を指す' {
        $t = Get-AgentConfigTargets -RepoRoot $RepoRoot |
            Where-Object Name -eq 'codex-agent-file-backup'
        $t.SourcePath | Should -Be (Join-Path $RepoRoot 'codex/plugins/agent-file-backup')
        $t.DestinationPath | Should -Be (Join-Path $env:USERPROFILE 'plugins/agent-file-backup')
    }
    It 'personal マーケットプレイス定義が ~/.agents/plugins/marketplace.json を指す' {
        # config.toml の agent-file-backup@personal の解決元。旧リポ削除後も @personal を保つため管理する。
        $t = Get-AgentConfigTargets -RepoRoot $RepoRoot |
            Where-Object Name -eq 'codex-agents-marketplace'
        $t.SourcePath | Should -Be (Join-Path $RepoRoot 'codex/agents-plugins/marketplace.json')
        $t.DestinationPath | Should -Be (Join-Path $env:USERPROFILE '.agents/plugins/marketplace.json')
    }
    It 'Antigravity の GEMINI.md symlink を含む' {
        $t = Get-AgentConfigTargets -RepoRoot $RepoRoot | Where-Object Name -eq 'gemini-GEMINI.md'
        $t.Name | Should -Be 'gemini-GEMINI.md'
        $t.DestinationPath | Should -Be (Join-Path $env:USERPROFILE '.gemini/GEMINI.md')
    }
    It 'Copilot の指示ファイル symlink を含む' {
        $t = Get-AgentConfigTargets -RepoRoot $RepoRoot | Where-Object Name -eq 'copilot-instructions'
        $t.Name | Should -Be 'copilot-instructions'
        $t.DestinationPath | Should -Be (Join-Path $env:USERPROFILE '.copilot/copilot-instructions.md')
    }
    It '全ターゲットの SourcePath が実在する' {
        (Get-AgentConfigTargets -RepoRoot $RepoRoot) |
            ForEach-Object { Test-Path $_.SourcePath | Should -BeTrue }
    }
}

Describe 'Test-AgentConfigLink' {
    It '通常ファイルは false' {
        $f = Join-Path $TestDrive 'plain.txt'; Set-Content $f 'x'
        Test-AgentConfigLink -Path $f -ExpectedTarget $f | Should -BeFalse
    }
    It '存在しないパスは false' {
        Test-AgentConfigLink -Path (Join-Path $TestDrive 'nope') -ExpectedTarget 'x' | Should -BeFalse
    }
}

Describe 'Backup-ExistingItem' {
    It '通常ファイルを backups/<name>/ へ退避する' {
        $src = Join-Path $TestDrive 'orig.txt'; Set-Content $src 'data'
        $backupRoot = Join-Path $TestDrive 'backups/run1'
        $moved = Backup-ExistingItem -Path $src -BackupRoot $backupRoot -TargetName 'orig'
        Test-Path $src | Should -BeFalse
        Test-Path $moved | Should -BeTrue
        Get-Content $moved | Should -Be 'data'
    }
}

Describe 'Remove-AgentConfigLink' {
    It '管理外パスの削除を拒否して throw する' {
        $f = Join-Path $TestDrive 'managed.txt'; Set-Content $f 'x'
        { Remove-AgentConfigLink -Path $f -ExpectedTarget 'other' } | Should -Throw
    }
}

Describe 'New/Test/Remove リンク往復（要 symlink 権限）' {
    It 'リンクを作成し Test が true、Remove で消える' {
        if (-not $script:CanSymlink) { Set-ItResult -Skipped -Because 'symlink 権限なし（非昇格）'; return }
        $src = Join-Path $TestDrive 'src.txt'; Set-Content $src 'hello'
        $dst = Join-Path $TestDrive 'sub/dst.txt'
        New-AgentConfigLink -SourcePath $src -DestinationPath $dst -LinkType 'SymbolicLink'
        Test-AgentConfigLink -Path $dst -ExpectedTarget $src -ExpectedLinkType 'SymbolicLink' | Should -BeTrue
        Remove-AgentConfigLink -Path $dst -ExpectedTarget $src
        Test-Path $dst | Should -BeFalse
    }
}

Describe 'Copy ミラー (Sync/Test/Remove)（昇格不要）' {
    It 'Sync で実体コピーとマーカーを作成し Test が true' {
        $src = Join-Path $TestDrive 'csrc'; New-Item -ItemType Directory $src | Out-Null
        Set-Content (Join-Path $src 'core.md') 'rule-a'
        Set-Content (Join-Path $src 'index.md') 'idx'
        $dst = Join-Path $TestDrive 'cdst'
        Sync-AgentConfigCopy -SourcePath $src -DestinationPath $dst
        ((Get-Item $dst).Attributes -band [System.IO.FileAttributes]::ReparsePoint) | Should -Be 0
        Test-Path (Join-Path $dst 'core.md')       | Should -BeTrue
        Test-Path (Join-Path $dst '_GENERATED.md') | Should -BeTrue
        Test-AgentConfigCopy -SourcePath $src -DestinationPath $dst | Should -BeTrue
    }
    It 'コピー先の改変を Test がドリフト検出する' {
        $src = Join-Path $TestDrive 'd2src'; New-Item -ItemType Directory $src | Out-Null
        Set-Content (Join-Path $src 'core.md') 'rule-a'
        $dst = Join-Path $TestDrive 'd2dst'
        Sync-AgentConfigCopy -SourcePath $src -DestinationPath $dst
        Set-Content (Join-Path $dst 'core.md') 'tampered'
        Test-AgentConfigCopy -SourcePath $src -DestinationPath $dst | Should -BeFalse
    }
    It 'Sync は正本から消えたファイルを除去する' {
        $src = Join-Path $TestDrive 'd3src'; New-Item -ItemType Directory $src | Out-Null
        Set-Content (Join-Path $src 'core.md') 'a'; Set-Content (Join-Path $src 'old.md') 'b'
        $dst = Join-Path $TestDrive 'd3dst'
        Sync-AgentConfigCopy -SourcePath $src -DestinationPath $dst
        Remove-Item (Join-Path $src 'old.md')
        Sync-AgentConfigCopy -SourcePath $src -DestinationPath $dst
        Test-Path (Join-Path $dst 'old.md') | Should -BeFalse
    }
    It 'Remove はマーカー無しディレクトリの削除を拒否する' {
        $dst = Join-Path $TestDrive 'd4dst'; New-Item -ItemType Directory $dst | Out-Null
        Set-Content (Join-Path $dst 'user.md') 'x'
        { Remove-AgentConfigCopy -DestinationPath $dst } | Should -Throw
    }
    It 'Remove はマーカー有りのミラーを削除する' {
        $src = Join-Path $TestDrive 'd5src'; New-Item -ItemType Directory $src | Out-Null
        Set-Content (Join-Path $src 'core.md') 'a'
        $dst = Join-Path $TestDrive 'd5dst'
        Sync-AgentConfigCopy -SourcePath $src -DestinationPath $dst
        Remove-AgentConfigCopy -DestinationPath $dst
        Test-Path $dst | Should -BeFalse
    }
}

Describe '委託受け専用ファイル' {
    It 'gemini/GEMINI.md が必須の安全文言を含む' {
        $c = Get-Content (Join-Path $RepoRoot 'gemini/GEMINI.md') -Raw -Encoding utf8
        $c | Should -Match 'commit'
        $c | Should -Match 'ごみ箱'
        $c | Should -Match '再委託'
        $c | Should -Match 'task\.json'
    }
    It 'copilot/copilot-instructions.md が必須の安全文言を含む' {
        $c = Get-Content (Join-Path $RepoRoot 'copilot/copilot-instructions.md') -Raw -Encoding utf8
        $c | Should -Match 'commit'
        $c | Should -Match 'ごみ箱'
        $c | Should -Match '再委託'
        $c | Should -Match 'task\.json'
    }
}

Describe '管理外コピー先の退避ガード（昇格不要）' {
    BeforeAll {
        $script:GuardRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agentconfig-guard-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:GuardRoot | Out-Null
    }
    AfterAll {
        if (Test-Path -LiteralPath $script:GuardRoot) {
            $trash = Join-Path ([System.IO.Path]::GetTempPath()) 'agentconfig-guard-trash'
            New-Item -ItemType Directory -Force -Path $trash | Out-Null
            Move-Item -LiteralPath $script:GuardRoot -Destination (Join-Path $trash (Split-Path -Leaf $script:GuardRoot))
        }
    }
    It '管理外の実体ファイルは退避され、内容が保全される' {
        $dst = Join-Path $script:GuardRoot 'user-wrapper.cmd'
        $backupRoot = Join-Path $script:GuardRoot 'backups-unmanaged'
        Set-Content -LiteralPath $dst -Value '@echo user own wrapper'

        $bp = Backup-UnmanagedCopyTarget -Method CopyFile -DestinationPath $dst -BackupRoot $backupRoot -TargetName 'fixture'

        $bp | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $dst | Should -BeFalse
        (Get-Content -LiteralPath $bp -Raw).Trim() | Should -Be '@echo user own wrapper'
    }
    It '管理下（マーカーあり）のファイルは退避しない' {
        $dst = Join-Path $script:GuardRoot 'managed.cmd'
        $backupRoot = Join-Path $script:GuardRoot 'backups-managed'
        Set-Content -LiteralPath $dst -Value ':: <!-- agent-config: generated mirror --> x'

        Backup-UnmanagedCopyTarget -Method CopyFile -DestinationPath $dst -BackupRoot $backupRoot -TargetName 'fixture' |
            Should -BeNullOrEmpty
        Test-Path -LiteralPath $dst | Should -BeTrue
    }
    It '存在しない配置先では何もしない' {
        $dst = Join-Path $script:GuardRoot 'absent.cmd'
        Backup-UnmanagedCopyTarget -Method CopyFile -DestinationPath $dst -BackupRoot (Join-Path $script:GuardRoot 'b3') -TargetName 'fixture' |
            Should -BeNullOrEmpty
    }
    It 'sync-vault-mirror.ps1 が退避ガードを呼ぶ' {
        # Vault以外（~/.local/bin の codex シム）も配るため、管理外の上書きを防ぐ必要がある。
        $script = Get-Content (Join-Path $RepoRoot 'scripts/sync-vault-mirror.ps1') -Raw
        $script | Should -Match 'Backup-UnmanagedCopyTarget'
    }
    It 'install.ps1 が退避ガードを呼ぶ' {
        $script = Get-Content (Join-Path $RepoRoot 'scripts/install.ps1') -Raw
        $script | Should -Match 'Backup-UnmanagedCopyTarget'
    }
}

Describe 'CopyFile 単一ファイルミラー (Sync/Test/Remove)（昇格不要）' {
    BeforeAll { $marker = '<!-- agent-config: generated mirror' }

    It 'Sync で単一ファイルを親ごと作成しコピー、Test が true' {
        $src = Join-Path $TestDrive 'fsrc.md'
        Set-Content -LiteralPath $src -Value "$marker -->`n# doc`n本文" -Encoding UTF8
        $dst = Join-Path $TestDrive 'fsub/fdst.md'
        Sync-AgentConfigCopyFile -SourcePath $src -DestinationPath $dst
        Test-Path -LiteralPath $dst | Should -BeTrue
        ((Get-Item -LiteralPath $dst).Attributes -band [System.IO.FileAttributes]::ReparsePoint) | Should -Be 0
        Test-AgentConfigCopyFile -SourcePath $src -DestinationPath $dst | Should -BeTrue
    }
    It 'コピー先の改変を Test がドリフト検出する' {
        $src = Join-Path $TestDrive 'f2src.md'
        Set-Content -LiteralPath $src -Value "$marker -->`n# doc" -Encoding UTF8
        $dst = Join-Path $TestDrive 'f2dst.md'
        Sync-AgentConfigCopyFile -SourcePath $src -DestinationPath $dst
        Set-Content -LiteralPath $dst -Value 'tampered' -Encoding UTF8
        Test-AgentConfigCopyFile -SourcePath $src -DestinationPath $dst | Should -BeFalse
    }
    It 'Remove はマーカー無しファイルの削除を拒否する' {
        $dst = Join-Path $TestDrive 'f3dst.md'
        Set-Content -LiteralPath $dst -Value '# user file' -Encoding UTF8
        { Remove-AgentConfigCopyFile -DestinationPath $dst } | Should -Throw
        Test-Path -LiteralPath $dst | Should -BeTrue
    }
    It 'Remove はマーカー有りのミラーを削除する' {
        $src = Join-Path $TestDrive 'f4src.md'
        Set-Content -LiteralPath $src -Value "$marker -->`n# doc" -Encoding UTF8
        $dst = Join-Path $TestDrive 'f4dst.md'
        Sync-AgentConfigCopyFile -SourcePath $src -DestinationPath $dst
        Remove-AgentConfigCopyFile -DestinationPath $dst
        Test-Path -LiteralPath $dst | Should -BeFalse
    }
}

Describe 'uninstall.ps1 end-to-end (fixture, child process)' {
    BeforeEach {
        $script:OriginalTestRoot = $env:AGENT_CONFIG_TEST_ROOT
        $script:OriginalFailureMode = $env:AGENT_CONFIG_TEST_FAILURE_MODE
        $script:FixtureRoot = Join-Path $TestDrive ("fixture_" + [guid]::NewGuid().ToString('N'))
        $fixtureScriptsDir = Join-Path $script:FixtureRoot 'fixtureRepo/scripts'
        $fixtureLibDir = Join-Path $fixtureScriptsDir 'lib'
        New-Item -ItemType Directory -Force -Path $fixtureLibDir | Out-Null
        Copy-Item -LiteralPath (Join-Path $RepoRoot 'scripts/uninstall.ps1') -Destination (Join-Path $fixtureScriptsDir 'uninstall.ps1')
        Set-Content -LiteralPath (Join-Path $fixtureLibDir 'AgentConfig.psm1') -Encoding UTF8 -Value @'
$ErrorActionPreference = 'Stop'

function Get-AgentConfigTargets {
    param([Parameter(Mandatory)][string]$RepoRoot)
    $root = $env:AGENT_CONFIG_TEST_ROOT
    $targets = @()
    if ($env:AGENT_CONFIG_TEST_FAILURE_MODE -eq '1') {
        $targets += [pscustomobject]@{ Name='fixture-unmanaged'; SourcePath=(Join-Path $root 'src-unmanaged.md'); DestinationPath=(Join-Path $root 'unmanaged.md'); LinkType=$null; Method='CopyFile' }
    }
    $targets += [pscustomobject]@{ Name='fixture-managed'; SourcePath=(Join-Path $root 'src-managed.md'); DestinationPath=(Join-Path $root 'managed.md'); LinkType=$null; Method='CopyFile' }
    return $targets
}

function Remove-AgentConfigCopyFile {
    param([Parameter(Mandatory)][string]$DestinationPath)
    if ((Split-Path -Leaf $DestinationPath) -eq 'unmanaged.md') {
        throw "Refusing to remove non-managed path: $DestinationPath"
    }
    Remove-Item -LiteralPath $DestinationPath -Force
}

Export-ModuleMember -Function Get-AgentConfigTargets, Remove-AgentConfigCopyFile
'@
        $script:FixtureScriptPath = Join-Path $fixtureScriptsDir 'uninstall.ps1'
        $script:TargetRoot = Join-Path $script:FixtureRoot 'targets'
        New-Item -ItemType Directory -Force -Path $script:TargetRoot | Out-Null
    }

    AfterEach {
        $env:AGENT_CONFIG_TEST_ROOT = $script:OriginalTestRoot
        $env:AGENT_CONFIG_TEST_FAILURE_MODE = $script:OriginalFailureMode
    }

    It 'unmanaged target fails without being deleted, does not block later managed target, and exits 1' {
        $env:AGENT_CONFIG_TEST_ROOT = $script:TargetRoot
        $env:AGENT_CONFIG_TEST_FAILURE_MODE = '1'

        $unmanagedPath = Join-Path $script:TargetRoot 'unmanaged.md'
        $managedPath = Join-Path $script:TargetRoot 'managed.md'
        Set-Content -LiteralPath $unmanagedPath -Value 'unmanaged content' -Encoding UTF8
        Set-Content -LiteralPath $managedPath -Value 'managed content' -Encoding UTF8

        $output = & pwsh -NoProfile -NonInteractive -File $script:FixtureScriptPath 2>&1
        $exitCode = $LASTEXITCODE

        Test-Path -LiteralPath $unmanagedPath | Should -BeTrue
        Test-Path -LiteralPath $managedPath | Should -BeFalse
        $exitCode | Should -Be 1

        $outputStr = Out-String -InputObject $output
        $outputStr | Should -Match 'fixture-unmanaged'
        $outputStr | Should -Match 'Refusing to remove non-managed path'
    }

    It 'successful run with only a managed CopyFile destination removes the target and exits 0' {
        $env:AGENT_CONFIG_TEST_ROOT = $script:TargetRoot

        $managedPath = Join-Path $script:TargetRoot 'managed.md'
        Set-Content -LiteralPath $managedPath -Value 'managed content' -Encoding UTF8

        $output = & pwsh -NoProfile -NonInteractive -File $script:FixtureScriptPath 2>&1
        $exitCode = $LASTEXITCODE

        Test-Path -LiteralPath $managedPath | Should -BeFalse
        $exitCode | Should -Be 0
    }
}
