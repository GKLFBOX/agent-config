$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName Microsoft.VisualBasic

if ($null -eq ('AgentBridge.NativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace AgentBridge
{
    public static class NativeMethods
    {
        [DllImport("kernel32.dll", EntryPoint = "GetFinalPathNameByHandleW", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        private static extern uint GetFinalPathNameByHandleW(
            SafeFileHandle hFile,
            StringBuilder lpszFilePath,
            uint cchFilePath,
            uint dwFlags);

        public static string GetFinalPath(SafeFileHandle handle)
        {
            var capacity = 512;
            while (true)
            {
                var builder = new StringBuilder(capacity);
                var length = GetFinalPathNameByHandleW(handle, builder, (uint)builder.Capacity, 0);
                if (length == 0)
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }
                if (length < builder.Capacity)
                {
                    return builder.ToString();
                }
                if (length > 32767)
                {
                    throw new InvalidOperationException("GetFinalPathNameByHandleW returned an invalid path length: " + length);
                }
                capacity = checked((int)length + 1);
            }
        }
    }
}
'@
}

Set-Variable -Name AgentBridgeMaxTaskJsonBytes -Value 1048576 -Option Constant -Scope Script
Set-Variable -Name AgentBridgeMaxResultJsonBytes -Value 1048576 -Option Constant -Scope Script
Set-Variable -Name AgentBridgeMaxTaskArrayItems -Value 100 -Option Constant -Scope Script
Set-Variable -Name AgentBridgeMaxChangedFiles -Value 1000 -Option Constant -Scope Script
Set-Variable -Name AgentBridgeMaxVerificationItems -Value 100 -Option Constant -Scope Script
Set-Variable -Name AgentBridgeMaxArtifacts -Value 100 -Option Constant -Scope Script
Set-Variable -Name AgentBridgeMaxPathLength -Value 1024 -Option Constant -Scope Script
Set-Variable -Name AgentBridgeMaxGeneralStringLength -Value 4096 -Option Constant -Scope Script
Set-Variable -Name AgentBridgeMaxTaskObjectiveLength -Value 10000 -Option Constant -Scope Script

$script:AgentBridgePublishDirectoryMover = {
    param([string]$Source, [string]$Destination)
    [System.IO.Directory]::Move($Source, $Destination)
}

$script:AgentBridgeTaskWriter = {
    param([string]$Path, [string]$Contents, [System.Text.Encoding]$Encoding)
    [System.IO.File]::WriteAllText($Path, $Contents, $Encoding)
}

$script:AgentBridgeRecycleDirectoryMover = {
    param([string]$Path)
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
        $Path,
        [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
        [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
    )
}

$script:AgentBridgeFinalPathResolver = {
    param($Stream, [string]$ExpectedPath)
    Get-AgentBridgeFinalPathByHandle -SafeFileHandle $Stream.SafeFileHandle
}

function Get-AgentBridgeFullPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'Path must be non-empty'
    }

    $FullPath = [System.IO.Path]::GetFullPath($Path)
    $PathRoot = [System.IO.Path]::GetPathRoot($FullPath)
    if ($FullPath.Equals($PathRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $PathRoot
    }

    return $FullPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
}

function Test-AgentBridgePathWithinRoot {
    param(
        [string]$Root,
        [string]$Path
    )

    if ($Path.Equals($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $RootPrefix = $Root.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) +
        [System.IO.Path]::DirectorySeparatorChar
    return $Path.StartsWith($RootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-AgentBridgePathSegments {
    param([string]$Path)

    $Separators = [char[]]@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    return $Path.Split($Separators, [System.StringSplitOptions]::RemoveEmptyEntries)
}

function Normalize-AgentBridgeFinalPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'Final path for opened file handle is empty'
    }

    if ($Path.StartsWith('\\?\UNC\', [System.StringComparison]::OrdinalIgnoreCase)) {
        $Path = '\\' + $Path.Substring(8)
    }
    elseif ($Path.StartsWith('\\?\', [System.StringComparison]::OrdinalIgnoreCase)) {
        $Path = $Path.Substring(4)
    }

    return Get-AgentBridgeFullPath -Path $Path
}

function Get-AgentBridgeFinalPathByHandle {
    param($SafeFileHandle)

    try {
        return [AgentBridge.NativeMethods]::GetFinalPath($SafeFileHandle)
    }
    catch {
        throw "GetFinalPathNameByHandleW failed: $($_.Exception.Message)"
    }
}

function Assert-AgentBridgeOpenedFilePath {
    param(
        $Stream,
        [string]$ExpectedPath,
        [string]$Root,
        [string]$Name
    )

    try {
        $RawFinalPath = & $script:AgentBridgeFinalPathResolver $Stream $ExpectedPath
        $FinalPath = Normalize-AgentBridgeFinalPath -Path $RawFinalPath
    }
    catch {
        throw "Failed to resolve final path for opened file handle ($Name): $($_.Exception.Message)"
    }

    $NormalizedRoot = Get-AgentBridgeFullPath -Path $Root
    $NormalizedExpectedPath = Get-AgentBridgeFullPath -Path $ExpectedPath
    if (-not (Test-AgentBridgePathWithinRoot -Root $NormalizedRoot -Path $FinalPath)) {
        throw "Opened file final path escapes allowed root ($Name): $FinalPath"
    }
    if (-not $FinalPath.Equals($NormalizedExpectedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Opened file final path mismatch: $Name. Expected: $NormalizedExpectedPath Actual: $FinalPath"
    }
}

function Test-AgentBridgeExactString {
    param(
        [string]$Actual,
        [string]$Expected
    )

    return [string]::Equals($Actual, $Expected, [System.StringComparison]::Ordinal)
}

function Test-AgentBridgeExactStringInSet {
    param(
        [string]$Actual,
        [string[]]$Expected
    )

    foreach ($Value in $Expected) {
        if (Test-AgentBridgeExactString -Actual $Actual -Expected $Value) {
            return $true
        }
    }
    return $false
}

function Assert-AgentBridgeRuntimeStringLength {
    param(
        [string]$Value,
        [string]$Name,
        [int]$MaximumLength
    )

    if ($Value.Length -gt $MaximumLength) {
        throw "$Name exceeds runtime length limit of $MaximumLength characters"
    }
}

function Assert-AgentBridgeRuntimeItemCount {
    param(
        [System.Array]$Value,
        [string]$Name,
        [int]$MaximumItems
    )

    if ($Value.Count -gt $MaximumItems) {
        throw "$Name exceeds runtime item limit of $MaximumItems"
    }
}

function Assert-NoAgentBridgeReparsePoint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $NormalizedRoot = Get-AgentBridgeFullPath -Path $Root
    $NormalizedPath = Get-AgentBridgeFullPath -Path $Path
    if (-not (Test-AgentBridgePathWithinRoot -Root $NormalizedRoot -Path $NormalizedPath)) {
        throw "Path escapes allowed root: $Path"
    }

    $FileSystemRoot = [System.IO.Path]::GetPathRoot($NormalizedPath)
    $Components = @($FileSystemRoot)
    $CurrentPath = $FileSystemRoot
    $RelativePath = $NormalizedPath.Substring($FileSystemRoot.Length)
    foreach ($Component in Get-AgentBridgePathSegments -Path $RelativePath) {
        $CurrentPath = Join-Path $CurrentPath $Component
        $Components += $CurrentPath
    }

    foreach ($ComponentPath in $Components) {
        if (-not (Test-Path -LiteralPath $ComponentPath)) {
            break
        }

        $Item = Get-Item -LiteralPath $ComponentPath -Force
        if (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse point is not allowed: $ComponentPath"
        }
    }
}

function Resolve-AgentBridgeChildPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        throw "Absolute path is not allowed: $RelativePath"
    }

    $NormalizedRoot = Get-AgentBridgeFullPath -Path $Root
    $ResolvedPath = Get-AgentBridgeFullPath -Path (Join-Path $NormalizedRoot $RelativePath)
    if (-not (Test-AgentBridgePathWithinRoot -Root $NormalizedRoot -Path $ResolvedPath)) {
        throw "Path escapes allowed root: $RelativePath"
    }
    foreach ($Segment in Get-AgentBridgePathSegments -Path $RelativePath) {
        if (($Segment -eq '.') -or ($Segment -eq '..')) {
            throw "Path traversal is not allowed: $RelativePath"
        }
    }

    Assert-NoAgentBridgeReparsePoint -Root $NormalizedRoot -Path $ResolvedPath
    return $ResolvedPath
}

function Assert-AgentBridgeTask {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Task,

        [Parameter(Mandatory = $true)]
        [string]$RequestDirectory
    )

    $RequiredFields = @(
        'schema_version',
        'request_id',
        'task_type',
        'repository',
        'objective',
        'constraints',
        'acceptance_criteria',
        'review_scope',
        'output_path'
    )
    $TaskFields = @($Task.PSObject.Properties.Name)
    foreach ($Field in $RequiredFields) {
        if (-not (Test-AgentBridgeExactStringInSet -Actual $Field -Expected $TaskFields)) {
            throw "Missing required task field: $Field"
        }
    }
    foreach ($Field in $TaskFields) {
        if (-not (Test-AgentBridgeExactStringInSet -Actual $Field -Expected $RequiredFields)) {
            throw "Unexpected task field: $Field"
        }
    }

    if (($Task.schema_version -isnot [byte]) -and
        ($Task.schema_version -isnot [int16]) -and
        ($Task.schema_version -isnot [int32]) -and
        ($Task.schema_version -isnot [int64])) {
        throw "Invalid schema_version: $($Task.schema_version)"
    }
    if ($Task.schema_version -ne 1) {
        throw "Invalid schema_version: $($Task.schema_version)"
    }

    if (($Task.request_id -isnot [string]) -or
        ($Task.request_id -cnotmatch '^[0-9]{8}T[0-9]{6}Z-[a-f0-9]{6}$')) {
        throw "Invalid request_id: $($Task.request_id)"
    }

    if (($Task.task_type -isnot [string]) -or
        (-not (Test-AgentBridgeExactStringInSet -Actual $Task.task_type -Expected @('implementation', 'review', 'investigation')))) {
        throw "Invalid task_type: $($Task.task_type)"
    }

    if (($Task.repository -isnot [string]) -or
        [string]::IsNullOrWhiteSpace($Task.repository)) {
        throw "Repository must be an absolute path: $($Task.repository)"
    }
    Assert-AgentBridgeRuntimeStringLength -Value $Task.repository -Name 'Task repository' -MaximumLength $script:AgentBridgeMaxPathLength
    if (-not [System.IO.Path]::IsPathRooted($Task.repository)) {
        throw "Repository must be an absolute path: $($Task.repository)"
    }
    $FullRepositoryPath = [System.IO.Path]::GetFullPath($Task.repository)
    if (-not $Task.repository.Equals($FullRepositoryPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Repository path must be normalized: $($Task.repository)"
    }
    $Repository = Get-AgentBridgeFullPath -Path $Task.repository
    if (-not (Test-Path -LiteralPath $Repository -PathType Container)) {
        throw "Repository directory does not exist: $Repository"
    }
    $RepositoryRoot = [System.IO.Path]::GetPathRoot($Repository)
    Assert-NoAgentBridgeReparsePoint -Root $RepositoryRoot -Path $Repository

    if (($Task.objective -isnot [string]) -or [string]::IsNullOrWhiteSpace($Task.objective)) {
        throw 'Objective must be non-empty'
    }
    Assert-AgentBridgeRuntimeStringLength -Value $Task.objective -Name 'Task objective' -MaximumLength $script:AgentBridgeMaxTaskObjectiveLength

    foreach ($Field in @('constraints', 'acceptance_criteria', 'review_scope')) {
        $Value = $Task.$Field
        if ($Value -isnot [System.Array]) {
            throw "Task field must be a string array: $Field"
        }
        Assert-AgentBridgeRuntimeItemCount -Value $Value -Name "Task field $Field" -MaximumItems $script:AgentBridgeMaxTaskArrayItems
        foreach ($Item in $Value) {
            if ($Item -isnot [string]) {
                throw "Task field must be a string array: $Field"
            }
            Assert-AgentBridgeRuntimeStringLength -Value $Item -Name "Task field $Field item" -MaximumLength $script:AgentBridgeMaxGeneralStringLength
        }
    }

    if (-not [System.IO.Path]::IsPathRooted($RequestDirectory)) {
        throw "Request directory must be an absolute path: $RequestDirectory"
    }
    $NormalizedRequestDirectory = Get-AgentBridgeFullPath -Path $RequestDirectory
    $ExpectedRequestDirectory = Resolve-AgentBridgeChildPath -Root $Repository -RelativePath ".agent-bridge\$($Task.request_id)"
    if (-not $NormalizedRequestDirectory.Equals($ExpectedRequestDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Repository does not match request repository root: $Repository"
    }
    Assert-NoAgentBridgeReparsePoint -Root $Repository -Path $NormalizedRequestDirectory

    if (($Task.output_path -isnot [string]) -or [string]::IsNullOrWhiteSpace($Task.output_path)) {
        throw "Invalid output_path: $($Task.output_path)"
    }
    Assert-AgentBridgeRuntimeStringLength -Value $Task.output_path -Name 'Task output_path' -MaximumLength $script:AgentBridgeMaxPathLength
    try {
        $OutputPath = Resolve-AgentBridgeChildPath -Root $Repository -RelativePath $Task.output_path
    }
    catch {
        throw "Invalid output_path: $($Task.output_path). $($_.Exception.Message)"
    }
    $ExpectedOutputPath = Get-AgentBridgeFullPath -Path (Join-Path $NormalizedRequestDirectory 'result.json')
    if (-not $OutputPath.Equals($ExpectedOutputPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Invalid output_path: $($Task.output_path)"
    }
}

function Test-AgentBridgeInteger {
    param([object]$Value)

    return (($Value -is [byte]) -or
        ($Value -is [int16]) -or
        ($Value -is [int32]) -or
        ($Value -is [int64]))
}

function Assert-AgentBridgeObjectShape {
    param(
        [object]$Value,
        [string]$Name,
        [string[]]$RequiredFields
    )

    if ($Value -isnot [pscustomobject]) {
        throw "$Name must be an object"
    }

    $Fields = @($Value.PSObject.Properties.Name)
    foreach ($Field in $RequiredFields) {
        if (-not (Test-AgentBridgeExactStringInSet -Actual $Field -Expected $Fields)) {
            throw "Missing required $Name field: $Field"
        }
    }
    foreach ($Field in $Fields) {
        if (-not (Test-AgentBridgeExactStringInSet -Actual $Field -Expected $RequiredFields)) {
            throw "Unexpected $Name field: $Field"
        }
    }
}

function Assert-AgentBridgeStringArray {
    param(
        [object]$Value,
        [string]$Field
    )

    if ($Value -isnot [System.Array]) {
        throw "Result field must be an array: $Field"
    }
    foreach ($Item in $Value) {
        if ($Item -isnot [string]) {
            throw "Result field must be a string array: $Field"
        }
    }
}

function Assert-AgentBridgeRepositoryRelativePath {
    param(
        [object]$Value,
        [string]$Repository
    )

    if (($Value -isnot [string]) -or [string]::IsNullOrWhiteSpace($Value)) {
        throw "Invalid repository-relative path: $Value"
    }
    Assert-AgentBridgeRuntimeStringLength -Value $Value -Name 'Repository-relative path' -MaximumLength $script:AgentBridgeMaxPathLength
    try {
        [void](Resolve-AgentBridgeChildPath -Root $Repository -RelativePath $Value)
    }
    catch {
        throw "Invalid repository-relative path: $Value. $($_.Exception.Message)"
    }
}

function Assert-AgentBridgeArtifactPath {
    param(
        [object]$Value,
        [string]$RequestDirectory
    )

    if (($Value -isnot [string]) -or [string]::IsNullOrWhiteSpace($Value)) {
        throw "Invalid artifact path: $Value"
    }
    Assert-AgentBridgeRuntimeStringLength -Value $Value -Name 'Artifact path' -MaximumLength $script:AgentBridgeMaxPathLength
    try {
        $ArtifactRoot = Resolve-AgentBridgeChildPath -Root $RequestDirectory -RelativePath 'artifacts'
        $ArtifactPath = Resolve-AgentBridgeChildPath -Root $RequestDirectory -RelativePath $Value
        if ($ArtifactPath.Equals($ArtifactRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-AgentBridgePathWithinRoot -Root $ArtifactRoot -Path $ArtifactPath)) {
            throw 'Artifact path must be below artifacts/'
        }
    }
    catch {
        throw "Invalid artifact path: $Value. $($_.Exception.Message)"
    }
}

function Assert-AgentBridgeResult {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Result,

        [Parameter(Mandatory = $true)]
        [object]$Task,

        [string]$RequestDirectory
    )

    $RequiredFields = @(
        'schema_version',
        'request_id',
        'status',
        'summary',
        'changed_files',
        'verification',
        'findings',
        'decisions',
        'risks',
        'review_focus',
        'artifacts'
    )
    Assert-AgentBridgeObjectShape -Value $Result -Name 'result' -RequiredFields $RequiredFields

    if (-not (Test-AgentBridgeInteger -Value $Result.schema_version) -or $Result.schema_version -ne 1) {
        throw "Invalid result schema_version: $($Result.schema_version)"
    }
    if (($Result.request_id -isnot [string]) -or
        (-not (Test-AgentBridgeExactString -Actual $Result.request_id -Expected $Task.request_id))) {
        throw "request_id mismatch: $($Result.request_id)"
    }
    if (($Result.status -isnot [string]) -or
        (-not (Test-AgentBridgeExactStringInSet -Actual $Result.status -Expected @('completed', 'partial', 'failed')))) {
        throw "Invalid result status: $($Result.status)"
    }
    if ($Result.summary -isnot [string]) {
        throw 'Result summary must be a string'
    }
    if ($Result.summary.Length -gt 500) {
        throw 'summary exceeds 500 characters'
    }

    if (-not $PSBoundParameters.ContainsKey('RequestDirectory')) {
        $RequestDirectory = Join-Path $Task.repository ".agent-bridge\$($Task.request_id)"
    }
    Assert-AgentBridgeTask -Task $Task -RequestDirectory $RequestDirectory
    $Repository = Get-AgentBridgeFullPath -Path $Task.repository
    $NormalizedRequestDirectory = Get-AgentBridgeFullPath -Path $RequestDirectory

    Assert-AgentBridgeStringArray -Value $Result.changed_files -Field 'changed_files'
    Assert-AgentBridgeRuntimeItemCount -Value $Result.changed_files -Name 'Result field changed_files' -MaximumItems $script:AgentBridgeMaxChangedFiles
    foreach ($Path in $Result.changed_files) {
        Assert-AgentBridgeRepositoryRelativePath -Value $Path -Repository $Repository
    }

    if ($Result.verification -isnot [System.Array]) {
        throw 'Result field must be an array: verification'
    }
    Assert-AgentBridgeRuntimeItemCount -Value $Result.verification -Name 'Result field verification' -MaximumItems $script:AgentBridgeMaxVerificationItems
    foreach ($Verification in $Result.verification) {
        Assert-AgentBridgeObjectShape -Value $Verification -Name 'verification' -RequiredFields @('command', 'status', 'reason', 'artifact')
        if ($Verification.command -isnot [string]) {
            throw 'Verification command must be a string'
        }
        Assert-AgentBridgeRuntimeStringLength -Value $Verification.command -Name 'Verification command' -MaximumLength $script:AgentBridgeMaxGeneralStringLength
        if (($Verification.status -isnot [string]) -or
            (-not (Test-AgentBridgeExactStringInSet -Actual $Verification.status -Expected @('passed', 'failed', 'skipped')))) {
            throw "Invalid verification status: $($Verification.status)"
        }
        if (($null -ne $Verification.reason) -and ($Verification.reason -isnot [string])) {
            throw 'Verification reason must be a string or null'
        }
        if ($Verification.reason -is [string]) {
            Assert-AgentBridgeRuntimeStringLength -Value $Verification.reason -Name 'Verification reason' -MaximumLength $script:AgentBridgeMaxGeneralStringLength
        }
        if ((Test-AgentBridgeExactString -Actual $Verification.status -Expected 'skipped') -and
            (($Verification.reason -isnot [string]) -or [string]::IsNullOrWhiteSpace($Verification.reason))) {
            throw 'Skipped verification requires a non-empty reason'
        }
        if ($null -ne $Verification.artifact) {
            Assert-AgentBridgeArtifactPath -Value $Verification.artifact -RequestDirectory $NormalizedRequestDirectory
        }
    }

    if ($Result.findings -isnot [System.Array]) {
        throw 'Result field must be an array: findings'
    }
    foreach ($Finding in $Result.findings) {
        Assert-AgentBridgeObjectShape -Value $Finding -Name 'finding' -RequiredFields @('severity', 'file', 'line', 'title', 'reason', 'suggestion', 'confidence')
        if (($Finding.severity -isnot [string]) -or
            (-not (Test-AgentBridgeExactStringInSet -Actual $Finding.severity -Expected @('critical', 'high', 'medium', 'low')))) {
            throw "Invalid finding severity: $($Finding.severity)"
        }
        if ($null -ne $Finding.file) {
            Assert-AgentBridgeRepositoryRelativePath -Value $Finding.file -Repository $Repository
        }
        if (($null -ne $Finding.line) -and
            (-not (Test-AgentBridgeInteger -Value $Finding.line) -or $Finding.line -lt 1)) {
            throw "Invalid finding line: $($Finding.line)"
        }
        foreach ($Field in @('title', 'reason', 'suggestion')) {
            if ($Finding.$Field -isnot [string]) {
                throw "Finding $Field must be a string"
            }
            Assert-AgentBridgeRuntimeStringLength -Value $Finding.$Field -Name "Finding $Field" -MaximumLength $script:AgentBridgeMaxGeneralStringLength
        }
        if (($Finding.confidence -isnot [string]) -or
            (-not (Test-AgentBridgeExactStringInSet -Actual $Finding.confidence -Expected @('high', 'medium', 'low')))) {
            throw "Invalid finding confidence: $($Finding.confidence)"
        }
    }

    foreach ($Field in @('decisions', 'risks')) {
        Assert-AgentBridgeStringArray -Value $Result.$Field -Field $Field
        if (@($Result.$Field).Count -gt 10) {
            throw "$Field exceeds 10 items"
        }
        foreach ($Item in $Result.$Field) {
            Assert-AgentBridgeRuntimeStringLength -Value $Item -Name "Result field $Field item" -MaximumLength $script:AgentBridgeMaxGeneralStringLength
        }
    }

    if ($Result.review_focus -isnot [System.Array]) {
        throw 'Result field must be an array: review_focus'
    }
    if (@($Result.review_focus).Count -gt 10) {
        throw 'review_focus exceeds 10 items'
    }
    foreach ($ReviewFocus in $Result.review_focus) {
        Assert-AgentBridgeObjectShape -Value $ReviewFocus -Name 'review_focus' -RequiredFields @('file', 'line', 'reason')
        Assert-AgentBridgeRepositoryRelativePath -Value $ReviewFocus.file -Repository $Repository
        if (($null -ne $ReviewFocus.line) -and
            (-not (Test-AgentBridgeInteger -Value $ReviewFocus.line) -or $ReviewFocus.line -lt 1)) {
            throw "Invalid review_focus line: $($ReviewFocus.line)"
        }
        if ($ReviewFocus.reason -isnot [string]) {
            throw 'Review_focus reason must be a string'
        }
        Assert-AgentBridgeRuntimeStringLength -Value $ReviewFocus.reason -Name 'Review_focus reason' -MaximumLength $script:AgentBridgeMaxGeneralStringLength
    }

    Assert-AgentBridgeStringArray -Value $Result.artifacts -Field 'artifacts'
    Assert-AgentBridgeRuntimeItemCount -Value $Result.artifacts -Name 'Result field artifacts' -MaximumItems $script:AgentBridgeMaxArtifacts
    foreach ($Artifact in $Result.artifacts) {
        Assert-AgentBridgeArtifactPath -Value $Artifact -RequestDirectory $NormalizedRequestDirectory
    }
}

function Read-AgentBridgeJsonFile {
    param(
        [string]$Path,
        [string]$Root,
        [string]$Name,
        [int]$MaximumBytes
    )

    Assert-NoAgentBridgeReparsePoint -Root $Root -Path $Path
    $Stream = New-Object System.IO.FileStream(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read
    )
    try {
        # Holding the file open without delete/write sharing narrows replacement races.
        Assert-AgentBridgeOpenedFilePath -Stream $Stream -ExpectedPath $Path -Root $Root -Name $Name
        Assert-NoAgentBridgeReparsePoint -Root $Root -Path $Path
        if ($Stream.Length -gt $MaximumBytes) {
            throw "$Name exceeds runtime byte limit of $MaximumBytes bytes"
        }

        $Memory = New-Object System.IO.MemoryStream
        try {
            $Buffer = New-Object byte[] 8192
            $TotalBytes = 0
            while (($BytesRead = $Stream.Read($Buffer, 0, $Buffer.Length)) -gt 0) {
                $TotalBytes += $BytesRead
                if ($TotalBytes -gt $MaximumBytes) {
                    throw "$Name exceeds runtime byte limit of $MaximumBytes bytes"
                }
                $Memory.Write($Buffer, 0, $BytesRead)
            }
            $Bytes = $Memory.ToArray()
        }
        finally {
            $Memory.Dispose()
        }
    }
    finally {
        $Stream.Dispose()
    }

    try {
        $Json = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($Bytes)
        return $Json | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Malformed ${Name}: $($_.Exception.Message)"
    }
}

function Wait-AgentBridgeResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestDirectory,

        [int]$TimeoutSeconds = 300,

        [int]$PollMilliseconds = 250
    )

    if ($TimeoutSeconds -lt 0) {
        throw 'TimeoutSeconds must be zero or greater'
    }
    if ($PollMilliseconds -le 0) {
        throw 'PollMilliseconds must be greater than zero'
    }

    $NormalizedRequestDirectory = Get-AgentBridgeFullPath -Path $RequestDirectory
    $TaskPath = Join-Path $NormalizedRequestDirectory 'task.json'
    Assert-NoAgentBridgeReparsePoint -Root $NormalizedRequestDirectory -Path $TaskPath
    if (-not (Test-Path -LiteralPath $TaskPath -PathType Leaf)) {
        throw "task.json does not exist: $NormalizedRequestDirectory"
    }
    $Task = Read-AgentBridgeJsonFile `
        -Path $TaskPath `
        -Root $NormalizedRequestDirectory `
        -Name 'task.json' `
        -MaximumBytes $script:AgentBridgeMaxTaskJsonBytes
    Assert-AgentBridgeTask -Task $Task -RequestDirectory $NormalizedRequestDirectory

    $ResultPath = Resolve-AgentBridgeChildPath -Root $NormalizedRequestDirectory -RelativePath 'result.json'
    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        if (Test-Path -LiteralPath $ResultPath) {
            Assert-NoAgentBridgeReparsePoint -Root $NormalizedRequestDirectory -Path $ResultPath
            if (-not (Test-Path -LiteralPath $ResultPath -PathType Leaf)) {
                throw "result.json is not a file: $ResultPath"
            }
            break
        }

        $RemainingMilliseconds = ($TimeoutSeconds * 1000.0) - $Stopwatch.Elapsed.TotalMilliseconds
        if ($RemainingMilliseconds -le 0) {
            throw "Timed out waiting for result.json: $NormalizedRequestDirectory"
        }
        $SleepMilliseconds = [Math]::Min([double]$PollMilliseconds, [Math]::Ceiling($RemainingMilliseconds))
        Start-Sleep -Milliseconds ([int]$SleepMilliseconds)
    }

    $Result = Read-AgentBridgeJsonFile `
        -Path $ResultPath `
        -Root $NormalizedRequestDirectory `
        -Name 'result.json' `
        -MaximumBytes $script:AgentBridgeMaxResultJsonBytes
    Assert-AgentBridgeResult -Result $Result -Task $Task -RequestDirectory $NormalizedRequestDirectory
    return $Result
}

function Read-AgentBridgeResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestDirectory
    )

    $NormalizedRequestDirectory = Get-AgentBridgeFullPath -Path $RequestDirectory
    $TaskPath = Join-Path $NormalizedRequestDirectory 'task.json'
    if (-not (Test-Path -LiteralPath $TaskPath -PathType Leaf)) {
        throw "task.json does not exist: $NormalizedRequestDirectory"
    }

    $Task = Read-AgentBridgeJsonFile `
        -Path $TaskPath `
        -Root $NormalizedRequestDirectory `
        -Name 'task.json' `
        -MaximumBytes $script:AgentBridgeMaxTaskJsonBytes

    $Result = Wait-AgentBridgeResult -RequestDirectory $NormalizedRequestDirectory -TimeoutSeconds 0

    $Summary = [pscustomobject][ordered]@{
        request_id = $Result.request_id
        task_type = $Task.task_type
        status = $Result.status
        summary = $Result.summary
        verification = $Result.verification
        risks = $Result.risks
    }

    if ($Task.task_type -eq 'implementation') {
        $Summary | Add-Member -NotePropertyName 'changed_files' -NotePropertyValue $Result.changed_files
        $Summary | Add-Member -NotePropertyName 'decisions' -NotePropertyValue $Result.decisions
        $Summary | Add-Member -NotePropertyName 'review_focus' -NotePropertyValue $Result.review_focus
    }
    elseif ($Task.task_type -eq 'review') {
        $Summary | Add-Member -NotePropertyName 'findings' -NotePropertyValue $Result.findings
    }
    elseif ($Task.task_type -eq 'investigation') {
        $Summary | Add-Member -NotePropertyName 'decisions' -NotePropertyValue $Result.decisions
        $Summary | Add-Member -NotePropertyName 'artifacts' -NotePropertyValue $Result.artifacts
    }

    return $Summary
}


function New-AgentBridgeRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [ValidateSet('implementation', 'review', 'investigation')]
        [string]$TaskType,

        [Parameter(Mandatory = $true)]
        [string]$Objective,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Constraints,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$AcceptanceCriteria,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$ReviewScope,

        [string]$RequestId
    )

    $NormalizedRepository = Get-AgentBridgeFullPath -Path $Repository
    if (-not (Test-Path -LiteralPath $NormalizedRepository -PathType Container)) {
        throw "Repository directory does not exist: $NormalizedRepository"
    }
    $RepositoryRoot = [System.IO.Path]::GetPathRoot($NormalizedRepository)
    Assert-NoAgentBridgeReparsePoint -Root $RepositoryRoot -Path $NormalizedRepository

    if (-not $PSBoundParameters.ContainsKey('RequestId')) {
        $RandomBytes = New-Object byte[] 3
        $RandomNumberGenerator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $RandomNumberGenerator.GetBytes($RandomBytes)
        }
        finally {
            $RandomNumberGenerator.Dispose()
        }
        $RandomSuffix = ([System.BitConverter]::ToString($RandomBytes)).Replace('-', '').ToLowerInvariant()
        $RequestId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '-' + $RandomSuffix
    }
    if ($RequestId -cnotmatch '^[0-9]{8}T[0-9]{6}Z-[a-f0-9]{6}$') {
        throw "Invalid request_id: $RequestId"
    }

    $BridgeRoot = Resolve-AgentBridgeChildPath -Root $NormalizedRepository -RelativePath '.agent-bridge'
    $RequestDirectory = Resolve-AgentBridgeChildPath -Root $NormalizedRepository -RelativePath ".agent-bridge\$RequestId"
    if (Test-Path -LiteralPath $RequestDirectory) {
        throw "Request directory already exists: $RequestDirectory"
    }

    $Task = [pscustomobject][ordered]@{
        schema_version = 1
        request_id = $RequestId
        task_type = $TaskType
        repository = $NormalizedRepository
        objective = $Objective
        constraints = @($Constraints)
        acceptance_criteria = @($AcceptanceCriteria)
        review_scope = @($ReviewScope)
        output_path = ".agent-bridge\$RequestId\result.json"
    }
    Assert-AgentBridgeTask -Task $Task -RequestDirectory $RequestDirectory

    New-Item -ItemType Directory -Path $BridgeRoot -Force | Out-Null
    Assert-NoAgentBridgeReparsePoint -Root $NormalizedRepository -Path $BridgeRoot

    $StagingName = '.pending-' + [guid]::NewGuid().ToString('N')
    $StagingDirectory = Resolve-AgentBridgeChildPath -Root $NormalizedRepository -RelativePath ".agent-bridge\$StagingName"
    New-Item -ItemType Directory -Path $StagingDirectory | Out-Null

    try {
        Assert-NoAgentBridgeReparsePoint -Root $NormalizedRepository -Path $StagingDirectory
        New-Item -ItemType Directory -Path (Join-Path $StagingDirectory 'artifacts') | Out-Null

        $TaskJson = $Task | ConvertTo-Json -Depth 10
        $Utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
        & $script:AgentBridgeTaskWriter (Join-Path $StagingDirectory 'task.json') $TaskJson $Utf8WithoutBom

        & $script:AgentBridgePublishDirectoryMover $StagingDirectory $RequestDirectory
    }
    catch {
        $OperationError = $_
        try {
            if (Test-Path -LiteralPath $StagingDirectory -PathType Container) {
                & $script:AgentBridgeRecycleDirectoryMover $StagingDirectory
            }
        }
        catch {
            # Preserve the staging operation failure even if rollback cannot reach the Recycle Bin.
        }
        throw $OperationError
    }

    $Prompt = 'Read task.json. Write the result to result.json.tmp, then rename it to result.json. Do not write outside the repository.'
    return [pscustomobject][ordered]@{
        RequestId = $RequestId
        RequestDirectory = $RequestDirectory
        Prompt = $Prompt
    }
}

function Move-AgentBridgeDirectoryToRecycleBin {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
        $Path,
        [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
        [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
    )
}

function Move-ExpiredAgentBridgeRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [int]$AgeDays = 7,

        [scriptblock]$Mover
    )

    if ($AgeDays -lt 0) {
        throw "AgeDays cannot be less than zero: $AgeDays"
    }

    $NormalizedRepository = Get-AgentBridgeFullPath -Path $Repository
    if (-not (Test-Path -LiteralPath $NormalizedRepository -PathType Container)) {
        throw "Repository directory does not exist: $NormalizedRepository"
    }
    $RepositoryRoot = [System.IO.Path]::GetPathRoot($NormalizedRepository)
    Assert-NoAgentBridgeReparsePoint -Root $RepositoryRoot -Path $NormalizedRepository

    $BridgeRoot = Join-Path $NormalizedRepository '.agent-bridge'
    if (-not (Test-Path -LiteralPath $BridgeRoot -PathType Container)) {
        return @()
    }
    Assert-NoAgentBridgeReparsePoint -Root $NormalizedRepository -Path $BridgeRoot

    # Strict valid request-name filtering: pattern matching yyyyMMddTHHmmssZ-xxxxxx
    $RequestPattern = '^[0-9]{8}T[0-9]{6}Z-[a-f0-9]{6}$'

    # Get all child directories of .agent-bridge
    $Children = Get-ChildItem -LiteralPath $BridgeRoot
    $RecycledPaths = New-Object System.Collections.Generic.List[string]

    $LimitDate = [DateTime]::UtcNow.AddDays(-$AgeDays)

    foreach ($Child in $Children) {
        # Only process directories
        if (-not $Child.PSIsContainer) {
            continue
        }

        # Check strict valid request-name filtering
        if ($Child.Name -cnotmatch $RequestPattern) {
            continue
        }

        # Parse the date from the directory name (the first 16 characters, e.g. yyyyMMddTHHmmssZ)
        $DateStr = $Child.Name.Substring(0, 16)
        try {
            $RequestDate = [DateTime]::ParseExact(
                $DateStr,
                "yyyyMMdd'T'HHmmss'Z'",
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
            )
        }
        catch {
            # If for some reason parsing fails despite regex match, ignore or skip
            continue
        }

        if ($RequestDate -lt $LimitDate) {
            $TargetPath = $Child.FullName
            Assert-NoAgentBridgeReparsePoint -Root $BridgeRoot -Path $TargetPath

            # Execute mover: use injectable mover or default
            if ($PSBoundParameters.ContainsKey('Mover')) {
                & $Mover $TargetPath
            }
            else {
                Move-AgentBridgeDirectoryToRecycleBin -Path $TargetPath
            }
            [void]$RecycledPaths.Add($TargetPath)
        }
    }

    return $RecycledPaths.ToArray()
}

Export-ModuleMember -Function Resolve-AgentBridgeChildPath, Assert-NoAgentBridgeReparsePoint, Assert-AgentBridgeTask, Assert-AgentBridgeResult, New-AgentBridgeRequest, Wait-AgentBridgeResult, Read-AgentBridgeResult, Move-AgentBridgeDirectoryToRecycleBin, Move-ExpiredAgentBridgeRequest
