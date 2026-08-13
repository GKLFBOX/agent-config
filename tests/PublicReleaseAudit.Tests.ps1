BeforeAll {
    $script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    $script:Script   = Join-Path $script:RepoRoot 'skills/public-release-audit/scripts/Invoke-PublicReleaseAudit.ps1'
    $script:Pwsh     = (Get-Process -Id $PID).Path
    $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("pra-test-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:TempRoot | Out-Null

    function New-TestRepo {
        param([hashtable]$Files = @{}, [string]$GitIgnore)
        $path = Join-Path $script:TempRoot ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $path | Out-Null
        if ($GitIgnore) { Set-Content -LiteralPath (Join-Path $path '.gitignore') -Value $GitIgnore -Encoding utf8 }
        foreach ($name in $Files.Keys) {
            $full = Join-Path $path $name
            New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
            Set-Content -LiteralPath $full -Value $Files[$name] -Encoding utf8
        }
        git -C $path init -q
        git -C $path add -A -f
        git -C $path -c user.email='t@example.com' -c user.name='Test User' commit -qm 'init'
        return $path
    }

    function New-ListFile {
        param([string[]]$Lines)
        $path = Join-Path $script:TempRoot ([guid]::NewGuid().ToString('N') + '.txt')
        Set-Content -LiteralPath $path -Value $Lines -Encoding utf8
        return $path
    }

    function Invoke-Audit {
        param([string]$RepoPath, [string]$Allowlist, [string]$Denylist)
        $argv = @('-NoProfile', '-File', $script:Script, '-RepoPath', $RepoPath, '-Allowlist', $Allowlist)
        if ($Denylist) { $argv += @('-Denylist', $Denylist) }
        $out = & $script:Pwsh @argv 2>&1
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = ($out | Out-String) }
    }
}

AfterAll {
    Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# -Skip は discovery 段で評価されるため、BeforeAll の外で判定する。
$script:HasGitleaks = $null -ne (Get-Command gitleaks -ErrorAction SilentlyContinue)

Describe '引数と前提' {
    It 'allowlist が無ければ終了コード2で止まる' {
        $repo = New-TestRepo -Files @{ 'README.md' = '# x' }
        $r = Invoke-Audit -RepoPath $repo -Allowlist (Join-Path $script:TempRoot 'no-such-file.txt')
        $r.ExitCode | Should -Be 2
        $r.Text | Should -Match '\[実行不能\]'
    }

    It 'git リポジトリでなければ終了コード2で止まる' {
        $plain = Join-Path $script:TempRoot ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $plain | Out-Null
        $allow = New-ListFile -Lines @('README.md')
        $r = Invoke-Audit -RepoPath $plain -Allowlist $allow
        $r.ExitCode | Should -Be 2
    }

    It 'RepoPath が存在しなければ終了コード2で止まる' {
        $allow = New-ListFile -Lines @('README.md')
        $r = Invoke-Audit -RepoPath (Join-Path $script:TempRoot 'missing-dir') -Allowlist $allow
        $r.ExitCode | Should -Be 2
    }
}

Describe 'allowlistとの差分' {
    It '一致していれば PASS で終了コード0' {
        $repo  = New-TestRepo -Files @{ 'README.md' = '# x'; 'src/app.js' = 'const a = 1' }
        $allow = New-ListFile -Lines @('# 公開対象', 'README.md', 'src')
        $r = Invoke-Audit -RepoPath $repo -Allowlist $allow
        $r.Text | Should -Match '\[PASS\] allowlistとの差分'
        $r.ExitCode | Should -Be 0
    }

    It 'allowlist にないファイルが追跡されていれば要確認' {
        $repo  = New-TestRepo -Files @{ 'README.md' = '# x'; 'secret-notes.md' = 'memo' }
        $allow = New-ListFile -Lines @('README.md')
        $r = Invoke-Audit -RepoPath $repo -Allowlist $allow
        $r.Text | Should -Match '\[要確認\] allowlistとの差分'
        $r.Text | Should -Match 'allowlist にない: secret-notes\.md'
        $r.ExitCode | Should -Be 1
    }

    It 'allowlist にあるのに追跡されていなければ写し漏れとして出す' {
        $repo  = New-TestRepo -Files @{ 'README.md' = '# x' }
        $allow = New-ListFile -Lines @('README.md', 'LICENSE')
        $r = Invoke-Audit -RepoPath $repo -Allowlist $allow
        $r.Text | Should -Match '写し漏れ: LICENSE'
        $r.ExitCode | Should -Be 1
    }

    It 'ディレクトリの行は配下すべてを許可する' {
        $repo  = New-TestRepo -Files @{ 'src/a.js' = '1'; 'src/nested/b.js' = '2' }
        $allow = New-ListFile -Lines @('src/')
        $r = Invoke-Audit -RepoPath $repo -Allowlist $allow
        $r.Text | Should -Match '\[PASS\] allowlistとの差分'
    }
}

Describe 'ローカルパス' {
    It 'Windows のローカルパスを拾う' {
        $repo  = New-TestRepo -Files @{ 'README.md' = 'open E:\home\repos\thing' }
        $allow = New-ListFile -Lines @('README.md')
        $r = Invoke-Audit -RepoPath $repo -Allowlist $allow
        $r.Text | Should -Match '\[要確認\] ローカルパス'
        $r.ExitCode | Should -Be 1
    }

    It 'URL スキームを誤検出しない' {
        $repo  = New-TestRepo -Files @{ 'README.md' = 'see https://example.com/x and http://example.org' }
        $allow = New-ListFile -Lines @('README.md')
        $r = Invoke-Audit -RepoPath $repo -Allowlist $allow
        $r.Text | Should -Match '\[PASS\] ローカルパス'
    }

    It 'POSIX のホームディレクトリを拾う' {
        $repo  = New-TestRepo -Files @{ 'README.md' = 'cd /Users/someone/work' }
        $allow = New-ListFile -Lines @('README.md')
        $r = Invoke-Audit -RepoPath $repo -Allowlist $allow
        $r.Text | Should -Match '\[要確認\] ローカルパス'
    }
}

Describe '個人識別子' {
    It '-Denylist 未指定ならスキップする' {
        $repo  = New-TestRepo -Files @{ 'README.md' = '# x' }
        $allow = New-ListFile -Lines @('README.md')
        $r = Invoke-Audit -RepoPath $repo -Allowlist $allow
        $r.Text | Should -Match '\[スキップ\] 個人識別子'
        $r.ExitCode | Should -Be 0
    }

    It 'denylist の語を拾う' {
        $repo  = New-TestRepo -Files @{ 'README.md' = 'contact: privateuser@example.com' }
        $allow = New-ListFile -Lines @('README.md')
        $deny  = New-ListFile -Lines @('privateuser')
        $r = Invoke-Audit -RepoPath $repo -Allowlist $allow -Denylist $deny
        $r.Text | Should -Match '\[要確認\] 個人識別子'
        $r.ExitCode | Should -Be 1
    }

    It 'denylist に該当が無ければ PASS' {
        $repo  = New-TestRepo -Files @{ 'README.md' = '# x' }
        $allow = New-ListFile -Lines @('README.md')
        $deny  = New-ListFile -Lines @('privateuser')
        $r = Invoke-Audit -RepoPath $repo -Allowlist $allow -Denylist $deny
        $r.Text | Should -Match '\[PASS\] 個人識別子'
    }
}

Describe '無視漏れ' {
    It '.gitignore 済みのファイルが追跡されていれば要確認' {
        $repo  = New-TestRepo -Files @{ 'README.md' = '# x'; 'build.log' = 'log' } -GitIgnore 'build.log'
        $allow = New-ListFile -Lines @('README.md', 'build.log', '.gitignore')
        $r = Invoke-Audit -RepoPath $repo -Allowlist $allow
        $r.Text | Should -Match '\[要確認\] 無視漏れ'
        $r.Text | Should -Match 'build\.log'
        $r.ExitCode | Should -Be 1
    }

    It '無視漏れが無ければ PASS' {
        $repo  = New-TestRepo -Files @{ 'README.md' = '# x' } -GitIgnore 'build.log'
        $allow = New-ListFile -Lines @('README.md', '.gitignore')
        $r = Invoke-Audit -RepoPath $repo -Allowlist $allow
        $r.Text | Should -Match '\[PASS\] 無視漏れ'
    }
}

Describe '巨大ファイル・バイナリ' {
    It 'バイナリファイルを挙げる' {
        $repo  = New-TestRepo -Files @{ 'README.md' = '# x' }
        [System.IO.File]::WriteAllBytes((Join-Path $repo 'logo.bin'), [byte[]](0, 1, 2, 0, 3))
        git -C $repo add -A
        git -C $repo -c user.email='t@example.com' -c user.name='Test User' commit -qm 'bin'
        $allow = New-ListFile -Lines @('README.md', 'logo.bin')
        $r = Invoke-Audit -RepoPath $repo -Allowlist $allow
        $r.Text | Should -Match 'バイナリ: logo\.bin'
        $r.ExitCode | Should -Be 1
    }

    It '1MB超のファイルを挙げる' {
        $repo  = New-TestRepo -Files @{ 'README.md' = '# x' }
        Set-Content -LiteralPath (Join-Path $repo 'big.txt') -Value ('a' * 1200000) -Encoding utf8
        git -C $repo add -A
        git -C $repo -c user.email='t@example.com' -c user.name='Test User' commit -qm 'big'
        $allow = New-ListFile -Lines @('README.md', 'big.txt')
        $r = Invoke-Audit -RepoPath $repo -Allowlist $allow
        $r.Text | Should -Match '1MB超: big\.txt'
    }

    It '該当が無ければ PASS' {
        $repo  = New-TestRepo -Files @{ 'README.md' = '# x' }
        $allow = New-ListFile -Lines @('README.md')
        $r = Invoke-Audit -RepoPath $repo -Allowlist $allow
        $r.Text | Should -Match '\[PASS\] 巨大ファイル・バイナリ'
    }
}

Describe '秘密情報' {
    It '秘密情報が無ければ PASS' -Skip:(-not $script:HasGitleaks) {
        $repo  = New-TestRepo -Files @{ 'README.md' = '# x' }
        $allow = New-ListFile -Lines @('README.md')
        $r = Invoke-Audit -RepoPath $repo -Allowlist $allow
        $r.Text | Should -Match '\[PASS\] 秘密情報'
    }

    It 'トークンらしき文字列を拾う' -Skip:(-not $script:HasGitleaks) {
        $token = 'ghp_' + ('0123456789' * 3) + 'abcdef'
        $repo  = New-TestRepo -Files @{ 'README.md' = "token = `"$token`"" }
        $allow = New-ListFile -Lines @('README.md')
        $r = Invoke-Audit -RepoPath $repo -Allowlist $allow
        $r.Text | Should -Match '\[要確認\] 秘密情報'
        $r.ExitCode | Should -Be 1
    }
}

Describe '情報項目' {
    It '著者を重複なく出す' {
        $repo  = New-TestRepo -Files @{ 'README.md' = '# x' }
        $allow = New-ListFile -Lines @('README.md')
        $r = Invoke-Audit -RepoPath $repo -Allowlist $allow
        $r.Text | Should -Match '\[情報\] 全コミットの著者'
        $r.Text | Should -Match 'Test User <t@example\.com>'
    }

    It '履歴の広がりを出す' {
        $repo  = New-TestRepo -Files @{ 'README.md' = '# x' }
        $allow = New-ListFile -Lines @('README.md')
        $r = Invoke-Audit -RepoPath $repo -Allowlist $allow
        $r.Text | Should -Match '\[情報\] 履歴の広がり'
        $r.Text | Should -Match 'コミット総数: 1'
    }

    It '情報項目だけでは終了コードを1にしない' {
        $repo  = New-TestRepo -Files @{ 'README.md' = '# x' }
        $allow = New-ListFile -Lines @('README.md')
        $r = Invoke-Audit -RepoPath $repo -Allowlist $allow
        $r.ExitCode | Should -Be 0
    }
}

Describe 'スキル資材' {
    BeforeAll {
        $script:SkillDir  = Join-Path $script:RepoRoot 'skills/public-release-audit'
        $script:SkillText = Get-Content -LiteralPath (Join-Path $script:SkillDir 'SKILL.md') -Raw -ErrorAction SilentlyContinue
    }

    It 'SKILL.md が name と description を持つ' {
        # \r? はCRLFでcheckoutされた場合に $ が \r の手前で外れるのを防ぐ。
        $script:SkillText | Should -Match '(?m)^name: public-release-audit\r?$'
        $script:SkillText | Should -Match '(?m)^description: .+'
    }

    It '3段の手順を持つ' {
        $script:SkillText | Should -Match 'allowlist'
        $script:SkillText | Should -Match '公開ツリー'
        $script:SkillText | Should -Match 'Invoke-PublicReleaseAudit\.ps1'
    }

    It '判断が要る4観点を列挙している' {
        $script:SkillText | Should -Match 'コミットメッセージ'
        $script:SkillText | Should -Match 'README'
        $script:SkillText | Should -Match '\.gitignore'
        $script:SkillText | Should -Match 'ヒット'
    }

    It 'denylist.example がコメント行を持つ' {
        $deny = Get-Content -LiteralPath (Join-Path $script:SkillDir 'denylist.example') -Raw
        $deny | Should -Match '(?m)^#'
    }
}

Describe 'AGENTS.md の公開原則' {
    It '公開に関する原則を持つ' {
        $agents = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'AGENTS.md') -Raw
        $agents | Should -Match '公開に関する原則'
        $agents | Should -Match 'public-release-audit'
    }
}
