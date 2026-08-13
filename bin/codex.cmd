@echo off
setlocal
:: <!-- agent-config: generated mirror --> source of truth: agent-config repo bin/codex.cmd
:: The marker sits on a label line, not a `rem` line: cmd parses `<` on a rem
:: line as input redirection and prints
:: "'!--' is not recognized as an internal or external command".
:: Label lines are not parsed for redirection.
::
:: ASCII only. cmd reads this file in the OEM code page (CP932 here), so any
:: non-ASCII byte is mis-decoded and can be executed as a command.
::
:: codex shim for cmd.exe and PowerShell.
::
:: %LOCALAPPDATA%\Programs\OpenAI\Codex\bin is a junction created by the
:: standalone installer (openai/codex PR #17022 changed it from a real
:: directory to a junction). Windows refuses to traverse a junction created
:: by a non-admin user from a process that has the Redirection Trust
:: Mitigation enabled, failing with WinError 448 / 0xC00004BE
:: ("untrusted mount point"). Claude Code's shell is such a process, so
:: `codex` cannot be resolved through that PATH entry.
::
:: This shim reads the junction target instead of traversing it, then runs
:: the resolved executable directly. Reading reparse metadata is allowed;
:: only traversal is blocked. Resolving at run time keeps the shim working
:: across codex updates, which repoint `current` to a new release directory.

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "CODEX_LINK=%USERPROFILE%\.codex\packages\standalone\current"
set "CODEX_PACKAGE_DIR="

:: %PS% is left unquoted on purpose: cmd mishandles a quoted program path as
:: the first token inside a `for /f` backquote command. The System32 path
:: contains no spaces, so quoting is unnecessary.
:: PowerShell's stderr is discarded so a resolution failure reports only this
:: shim's own message instead of stacking a raw PowerShell error on top of it.
for /f "usebackq delims=" %%p in (`%PS% -NoProfile -NonInteractive -Command "(Get-Item -LiteralPath (Join-Path $env:USERPROFILE '.codex\packages\standalone\current') -Force).Target" 2^>nul`) do set "CODEX_PACKAGE_DIR=%%p"

if not defined CODEX_PACKAGE_DIR goto :unresolved
if not exist "%CODEX_PACKAGE_DIR%\bin\codex.exe" goto :missing

"%CODEX_PACKAGE_DIR%\bin\codex.exe" %*
exit /b %ERRORLEVEL%

:unresolved
echo codex shim: cannot resolve junction target of "%CODEX_LINK%" 1>&2
exit /b 1

:missing
echo codex shim: codex.exe not found under "%CODEX_PACKAGE_DIR%\bin" 1>&2
exit /b 1
