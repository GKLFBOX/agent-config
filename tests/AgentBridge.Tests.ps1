$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param([object]$Actual, [object]$Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "$Message Actual=[$Actual] Expected=[$Expected]"
    }
}

function Assert-LessThan {
    param([double]$Actual, [double]$Expected, [string]$Message)
    if ($Actual -ge $Expected) {
        throw "$Message Actual=[$Actual] ExpectedLessThan=[$Expected]"
    }
}

function Assert-GreaterThan {
    param([double]$Actual, [double]$Expected, [string]$Message)
    if ($Actual -le $Expected) {
        throw "$Message Actual=[$Actual] ExpectedGreaterThan=[$Expected]"
    }
}

function Assert-SetEqual {
    param([object[]]$Actual, [object[]]$Expected, [string]$Message)
    $ActualValues = @($Actual | Sort-Object)
    $ExpectedValues = @($Expected | Sort-Object)
    Assert-Equal $ActualValues.Count $ExpectedValues.Count "$Message count should match"
    for ($Index = 0; $Index -lt $ExpectedValues.Count; $Index++) {
        Assert-Equal $ActualValues[$Index] $ExpectedValues[$Index] "$Message item $Index should match"
    }
}

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$BridgeRoot = Join-Path $RepoRoot 'scripts\agents\agent-bridge'

$TaskSchema = Get-Content -Raw (Join-Path $BridgeRoot 'schemas\task.schema.json') | ConvertFrom-Json
Assert-Equal $TaskSchema.'$schema' 'http://json-schema.org/draft-07/schema#' 'task schema should use draft-07'
Assert-Equal $TaskSchema.type 'object' 'task schema should describe an object'
Assert-Equal $TaskSchema.additionalProperties $false 'task schema should reject additional properties'
Assert-SetEqual $TaskSchema.required @('schema_version', 'request_id', 'task_type', 'repository', 'objective', 'constraints', 'acceptance_criteria', 'review_scope', 'output_path') 'task required fields'
Assert-Equal $TaskSchema.properties.schema_version.const 1 'task schema version should be 1'
Assert-Equal $TaskSchema.properties.task_type.enum.Count 3 'task schema should expose three task types'
Assert-SetEqual $TaskSchema.properties.task_type.enum @('implementation', 'review', 'investigation') 'task types'
Assert-True ($TaskSchema.required -contains 'output_path') 'task output_path should be required'
Assert-Equal $TaskSchema.properties.request_id.type 'string' 'task request_id should be a string'
Assert-Equal $TaskSchema.properties.request_id.pattern '^[0-9]{8}T[0-9]{6}Z-[a-f0-9]{6}$' 'task request_id pattern should match the wire format'
foreach ($PropertyName in @('repository', 'objective', 'output_path')) {
    Assert-Equal $TaskSchema.properties.$PropertyName.type 'string' "task $PropertyName should be a string"
    Assert-Equal $TaskSchema.properties.$PropertyName.minLength 1 "task $PropertyName should be non-empty"
}
foreach ($PropertyName in @('constraints', 'acceptance_criteria', 'review_scope')) {
    Assert-Equal $TaskSchema.properties.$PropertyName.type 'array' "task $PropertyName should be an array"
    Assert-Equal $TaskSchema.properties.$PropertyName.items.type 'string' "task $PropertyName items should be strings"
}

$ResultSchema = Get-Content -Raw (Join-Path $BridgeRoot 'schemas\result.schema.json') | ConvertFrom-Json
Assert-Equal $ResultSchema.'$schema' 'http://json-schema.org/draft-07/schema#' 'result schema should use draft-07'
Assert-Equal $ResultSchema.type 'object' 'result schema should describe an object'
Assert-Equal $ResultSchema.additionalProperties $false 'result schema should reject additional properties'
Assert-SetEqual $ResultSchema.required @('schema_version', 'request_id', 'status', 'summary', 'changed_files', 'verification', 'findings', 'decisions', 'risks', 'review_focus', 'artifacts') 'result required fields'
Assert-Equal $ResultSchema.properties.schema_version.const 1 'result schema version should be 1'
Assert-Equal $ResultSchema.properties.status.enum.Count 3 'result schema should expose three statuses'
Assert-SetEqual $ResultSchema.properties.status.enum @('completed', 'partial', 'failed') 'result statuses'
Assert-Equal $ResultSchema.properties.request_id.type 'string' 'result request_id should be a string'
Assert-Equal $ResultSchema.properties.summary.type 'string' 'result summary should be a string'
Assert-Equal $ResultSchema.properties.summary.maxLength 500 'summary should be limited to 500 characters'
Assert-Equal $ResultSchema.properties.decisions.maxItems 10 'decisions should be limited to 10 items'
Assert-Equal $ResultSchema.properties.risks.maxItems 10 'risks should be limited to 10 items'
Assert-Equal $ResultSchema.properties.review_focus.maxItems 10 'review focus should be limited to 10 items'
Assert-True ($ResultSchema.required -contains 'verification') 'verification should be required'

foreach ($PropertyName in @('changed_files', 'decisions', 'risks', 'artifacts')) {
    Assert-Equal $ResultSchema.properties.$PropertyName.type 'array' "result $PropertyName should be an array"
    Assert-Equal $ResultSchema.properties.$PropertyName.items.type 'string' "result $PropertyName items should be strings"
}

$VerificationSchema = $ResultSchema.properties.verification
Assert-Equal $VerificationSchema.type 'array' 'verification should be an array'
Assert-Equal $VerificationSchema.items.type 'object' 'verification items should be objects'
Assert-Equal $VerificationSchema.items.additionalProperties $false 'verification items should reject additional properties'
Assert-SetEqual $VerificationSchema.items.required @('command', 'status', 'reason', 'artifact') 'verification required fields'
Assert-Equal $VerificationSchema.items.properties.command.type 'string' 'verification command should be a string'
Assert-SetEqual $VerificationSchema.items.properties.status.enum @('passed', 'failed', 'skipped') 'verification statuses'
Assert-SetEqual $VerificationSchema.items.properties.reason.type @('string', 'null') 'verification reason types'
Assert-SetEqual $VerificationSchema.items.properties.artifact.type @('string', 'null') 'verification artifact types'

$FindingsSchema = $ResultSchema.properties.findings
Assert-Equal $FindingsSchema.type 'array' 'findings should be an array'
Assert-Equal $FindingsSchema.items.type 'object' 'finding items should be objects'
Assert-Equal $FindingsSchema.items.additionalProperties $false 'finding items should reject additional properties'
Assert-SetEqual $FindingsSchema.items.required @('severity', 'file', 'line', 'title', 'reason', 'suggestion', 'confidence') 'finding required fields'
Assert-SetEqual $FindingsSchema.items.properties.severity.enum @('critical', 'high', 'medium', 'low') 'finding severities'
Assert-SetEqual $FindingsSchema.items.properties.file.type @('string', 'null') 'finding file types'
Assert-SetEqual $FindingsSchema.items.properties.line.type @('integer', 'null') 'finding line types'
Assert-Equal $FindingsSchema.items.properties.line.minimum 1 'finding line should be positive'
foreach ($PropertyName in @('title', 'reason', 'suggestion')) {
    Assert-Equal $FindingsSchema.items.properties.$PropertyName.type 'string' "finding $PropertyName should be a string"
}
Assert-SetEqual $FindingsSchema.items.properties.confidence.enum @('high', 'medium', 'low') 'finding confidence levels'

$ReviewFocusSchema = $ResultSchema.properties.review_focus
Assert-Equal $ReviewFocusSchema.type 'array' 'review focus should be an array'
Assert-Equal $ReviewFocusSchema.items.type 'object' 'review focus items should be objects'
Assert-Equal $ReviewFocusSchema.items.additionalProperties $false 'review focus items should reject additional properties'
Assert-SetEqual $ReviewFocusSchema.items.required @('file', 'line', 'reason') 'review focus required fields'
Assert-Equal $ReviewFocusSchema.items.properties.file.type 'string' 'review focus file should be a string'
Assert-SetEqual $ReviewFocusSchema.items.properties.line.type @('integer', 'null') 'review focus line types'
Assert-Equal $ReviewFocusSchema.items.properties.line.minimum 1 'review focus line should be positive'
Assert-Equal $ReviewFocusSchema.items.properties.reason.type 'string' 'review focus reason should be a string'

function Assert-ThrowsLike {
    param(
        [scriptblock]$Action,
        [string]$Pattern,
        [string]$Message
    )

    try {
        & $Action
        throw "$Message Expected an exception matching [$Pattern]"
    }
    catch {
        Assert-True ($_.Exception.Message -like $Pattern) "$Message Actual=[$($_.Exception.Message)]"
    }
}

function Copy-TestObject {
    param([object]$InputObject)
    return $InputObject | ConvertTo-Json -Depth 10 | ConvertFrom-Json
}

function New-ValidAgentBridgeTask {
    param(
        [string]$Repository,
        [string]$RequestId
    )

    return [pscustomobject][ordered]@{
        schema_version = 1
        request_id = $RequestId
        task_type = 'implementation'
        repository = $Repository
        objective = 'Implement the requested change'
        constraints = @('Keep compatibility')
        acceptance_criteria = @('Tests pass')
        review_scope = @('scripts')
        output_path = ".agent-bridge\$RequestId\result.json"
    }
}

function New-ValidAgentBridgeResult {
    param([string]$RequestId)

    return [pscustomobject][ordered]@{
        schema_version = 1
        request_id = $RequestId
        status = 'completed'
        summary = 'Implemented and verified the requested change'
        changed_files = @('scripts\agent-bridge\AgentBridge.psm1')
        verification = @(
            [pscustomobject][ordered]@{
                command = 'powershell.exe -File tests\AgentBridge.Tests.ps1'
                status = 'passed'
                reason = $null
                artifact = 'artifacts\test-output.txt'
            }
        )
        findings = @(
            [pscustomobject][ordered]@{
                severity = 'low'
                file = 'scripts\agent-bridge\AgentBridge.psm1'
                line = 1
                title = 'Example finding'
                reason = 'Used to validate the result shape'
                suggestion = 'Keep the validation explicit'
                confidence = 'high'
            }
        )
        decisions = @('Keep Windows PowerShell 5.1 compatibility')
        risks = @('Polling timing can vary')
        review_focus = @(
            [pscustomobject][ordered]@{
                file = 'scripts\agent-bridge\AgentBridge.psm1'
                line = $null
                reason = 'Review result validation'
            }
        )
        artifacts = @('artifacts\test-output.txt')
    }
}

Import-Module (Join-Path $BridgeRoot 'AgentBridge.psm1') -Force
Assert-SetEqual @((Get-Command -Module AgentBridge).Name) @('Resolve-AgentBridgeChildPath', 'Assert-NoAgentBridgeReparsePoint', 'Assert-AgentBridgeTask', 'Assert-AgentBridgeResult', 'New-AgentBridgeRequest', 'Wait-AgentBridgeResult', 'Read-AgentBridgeResult', 'Move-AgentBridgeDirectoryToRecycleBin', 'Move-ExpiredAgentBridgeRequest') 'module exports'
$NormalizedExtendedPath = & (Get-Module AgentBridge) {
    Normalize-AgentBridgeFinalPath -Path '\\?\C:\example\file.json'
}
Assert-Equal $NormalizedExtendedPath 'C:\example\file.json' 'extended-length drive paths should normalize'
$NormalizedExtendedUncPath = & (Get-Module AgentBridge) {
    Normalize-AgentBridgeFinalPath -Path '\\?\UNC\server\share\file.json'
}
Assert-Equal $NormalizedExtendedUncPath '\\server\share\file.json' 'extended-length UNC paths should normalize'
$RecycleFileSystemType = $null
try {
    $RecycleFileSystemType = [Microsoft.VisualBasic.FileIO.FileSystem]
}
catch {
}
Assert-True ($null -ne $RecycleFileSystemType) 'module should load the Windows Recycle Bin API'
$DefaultRecycleMover = & (Get-Module AgentBridge) {
    $script:AgentBridgeRecycleDirectoryMover
}
$DefaultRecycleMoverBlocks = @($DefaultRecycleMover.Ast.FindAll({
    param($Ast)
    $Ast -is [System.Management.Automation.Language.NamedBlockAst]
}, $false))
$DefaultRecycleMoverStatements = @($DefaultRecycleMoverBlocks | ForEach-Object { $_.Statements })
$DefaultRecycleMoverCommands = @($DefaultRecycleMover.Ast.FindAll({
    param($Ast)
    $Ast -is [System.Management.Automation.Language.CommandAst]
}, $true))
$DefaultRecycleMoverInvocations = @($DefaultRecycleMover.Ast.FindAll({
    param($Ast)
    $Ast -is [System.Management.Automation.Language.InvokeMemberExpressionAst]
}, $true))
Assert-Equal $DefaultRecycleMoverStatements.Count 1 'default rollback mover should contain only the Recycle Bin operation'
Assert-Equal $DefaultRecycleMoverCommands.Count 0 'default rollback mover should not contain a direct deletion command'
Assert-Equal $DefaultRecycleMoverInvocations.Count 1 'default rollback mover should not contain an additional direct deletion call'
$DefaultRecycleMoverInvocation = $DefaultRecycleMoverInvocations[0]
Assert-Equal $DefaultRecycleMoverInvocation.Expression.Extent.Text '[Microsoft.VisualBasic.FileIO.FileSystem]' 'default rollback mover should use the Windows Recycle Bin API'
Assert-Equal $DefaultRecycleMoverInvocation.Member.Value 'DeleteDirectory' 'default rollback mover should call the Recycle Bin directory operation'
Assert-Equal $DefaultRecycleMoverInvocation.Arguments.Count 3 'default rollback mover should pass the Recycle Bin options'
Assert-Equal $DefaultRecycleMoverInvocation.Arguments[2].Extent.Text '[Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin' 'default rollback mover should request SendToRecycleBin'

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-bridge-test-" + [guid]::NewGuid().ToString('N'))
$TempTrash = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-bridge-test-trash-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
try {
    $Repository = Join-Path $TempRoot 'repository'
    $RequestId = '20260612T140000Z-a1b2c3'
    $RequestDirectory = Join-Path $Repository ".agent-bridge\$RequestId"
    New-Item -ItemType Directory -Force -Path $RequestDirectory | Out-Null

    $ExpectedChild = [System.IO.Path]::GetFullPath((Join-Path $TempRoot 'src\a.txt'))
    Assert-Equal (Resolve-AgentBridgeChildPath -Root $TempRoot -RelativePath 'src\a.txt') $ExpectedChild 'child path should resolve under root'
    Assert-NoAgentBridgeReparsePoint -Root $TempRoot -Path $TempRoot
    Assert-ThrowsLike { Resolve-AgentBridgeChildPath -Root $TempRoot -RelativePath '.' } 'Path traversal is not allowed:*' 'current-directory traversal should be rejected'
    Assert-ThrowsLike { Resolve-AgentBridgeChildPath -Root $TempRoot -RelativePath 'scripts\..\tests' } 'Path traversal is not allowed:*' 'root-contained parent traversal should be rejected'
    Assert-ThrowsLike { Resolve-AgentBridgeChildPath -Root $TempRoot -RelativePath 'scripts/../tests' } 'Path traversal is not allowed:*' 'forward-slash parent traversal should be rejected'
    Assert-ThrowsLike { Resolve-AgentBridgeChildPath -Root $TempRoot -RelativePath '..\escape.txt' } 'Path escapes allowed root:*' 'traversal should be rejected'
    Assert-ThrowsLike { Resolve-AgentBridgeChildPath -Root $TempRoot -RelativePath (Join-Path $TempRoot 'rooted.txt') } 'Absolute path is not allowed:*' 'rooted child paths should be rejected'
    Assert-ThrowsLike { Assert-NoAgentBridgeReparsePoint -Root $TempRoot -Path (Join-Path $TempRoot '..\escape.txt') } 'Path escapes allowed root:*' 'reparse validation should reject root escapes'
    Assert-NoAgentBridgeReparsePoint -Root $TempRoot -Path (Join-Path $TempRoot 'missing\leaf.txt')

    $ValidTask = New-ValidAgentBridgeTask -Repository ([System.IO.Path]::GetFullPath($Repository)) -RequestId $RequestId
    Assert-AgentBridgeTask -Task $ValidTask -RequestDirectory $RequestDirectory

    foreach ($PropertyName in @('schema_version', 'request_id', 'task_type', 'repository', 'objective', 'constraints', 'acceptance_criteria', 'review_scope', 'output_path')) {
        $Task = Copy-TestObject $ValidTask
        $Task.PSObject.Properties.Remove($PropertyName)
        Assert-ThrowsLike { Assert-AgentBridgeTask -Task $Task -RequestDirectory $RequestDirectory } "Missing required task field: $PropertyName" "missing $PropertyName should be rejected"
    }

    $Task = Copy-TestObject $ValidTask
    $Task | Add-Member -NotePropertyName extra -NotePropertyValue 'not allowed'
    Assert-ThrowsLike { Assert-AgentBridgeTask -Task $Task -RequestDirectory $RequestDirectory } 'Unexpected task field: extra' 'additional fields should be rejected'

    $Task = Copy-TestObject $ValidTask
    $Task.PSObject.Properties.Remove('task_type')
    $Task | Add-Member -NotePropertyName Task_Type -NotePropertyValue 'implementation'
    Assert-ThrowsLike { Assert-AgentBridgeTask -Task $Task -RequestDirectory $RequestDirectory } 'Missing required task field: task_type' 'task property names should be case-sensitive'

    $InvalidValues = @(
        @{ Field = 'schema_version'; Value = 2; Pattern = 'Invalid schema_version:*' },
        @{ Field = 'request_id'; Value = 'invalid-id'; Pattern = 'Invalid request_id:*' },
        @{ Field = 'request_id'; Value = '20260612T140000Z-A1B2C3'; Pattern = 'Invalid request_id:*' },
        @{ Field = 'task_type'; Value = 'build'; Pattern = 'Invalid task_type:*' },
        @{ Field = 'task_type'; Value = 'IMPLEMENTATION'; Pattern = 'Invalid task_type:*' },
        @{ Field = 'repository'; Value = '.\relative'; Pattern = 'Repository must be an absolute path:*' },
        @{ Field = 'objective'; Value = '   '; Pattern = 'Objective must be non-empty' },
        @{ Field = 'constraints'; Value = 'not-an-array'; Pattern = 'Task field must be a string array: constraints' },
        @{ Field = 'acceptance_criteria'; Value = @(1); Pattern = 'Task field must be a string array: acceptance_criteria' },
        @{ Field = 'review_scope'; Value = @('valid', 2); Pattern = 'Task field must be a string array: review_scope' },
        @{ Field = 'output_path'; Value = ".agent-bridge\$RequestId\wrong.json"; Pattern = 'Invalid output_path:*' },
        @{ Field = 'output_path'; Value = ".agent-bridge\$RequestId\sub\..\result.json"; Pattern = 'Invalid output_path:*Path traversal is not allowed:*' }
    )
    foreach ($Invalid in $InvalidValues) {
        $Task = Copy-TestObject $ValidTask
        $Task.($Invalid.Field) = $Invalid.Value
        Assert-ThrowsLike { Assert-AgentBridgeTask -Task $Task -RequestDirectory $RequestDirectory } $Invalid.Pattern "invalid $($Invalid.Field) should be rejected"
    }

    $Task = Copy-TestObject $ValidTask
    $Task.repository = [System.IO.Path]::GetFullPath($TempRoot)
    Assert-ThrowsLike { Assert-AgentBridgeTask -Task $Task -RequestDirectory $RequestDirectory } 'Repository does not match request repository root:*' 'mismatched repository should be rejected'

    New-Item -ItemType Directory -Path (Join-Path $Repository 'scripts') | Out-Null
    $Task = Copy-TestObject $ValidTask
    $Task.repository = Join-Path $Repository 'scripts\..'
    Assert-ThrowsLike { Assert-AgentBridgeTask -Task $Task -RequestDirectory $RequestDirectory } 'Repository path must be normalized:*' 'unnormalized absolute repositories should be rejected'

    $Task = Copy-TestObject $ValidTask
    $Task.request_id = '20260612T140000Z-abcdef'
    $Task.output_path = ".agent-bridge\$($Task.request_id)\result.json"
    Assert-ThrowsLike { Assert-AgentBridgeTask -Task $Task -RequestDirectory $RequestDirectory } 'Repository does not match request repository root:*' 'request IDs should match the request directory'

    $MissingRepositoryTask = Copy-TestObject $ValidTask
    $MissingRepositoryTask.repository = Join-Path $TempRoot 'missing-repository'
    $MissingRequestDirectory = Join-Path $MissingRepositoryTask.repository ".agent-bridge\$RequestId"
    Assert-ThrowsLike { Assert-AgentBridgeTask -Task $MissingRepositoryTask -RequestDirectory $MissingRequestDirectory } 'Repository directory does not exist:*' 'missing repository should be rejected'

    $ReparseTarget = Join-Path $TempRoot 'reparse-target'
    $ReparseRepository = Join-Path $TempRoot 'reparse-repository'
    New-Item -ItemType Directory -Path $ReparseTarget | Out-Null
    New-Item -ItemType Junction -Path $ReparseRepository -Target $ReparseTarget | Out-Null
    Assert-ThrowsLike { Resolve-AgentBridgeChildPath -Root $TempRoot -RelativePath 'reparse-repository\child.txt' } 'Reparse point is not allowed:*' 'existing reparse points should be rejected'

    $AncestorReparseTarget = Join-Path $TempRoot 'ancestor-reparse-target'
    $AncestorReparseLink = Join-Path $TempRoot 'ancestor-reparse-link'
    $RootBelowReparsePoint = Join-Path $AncestorReparseLink 'nested-root'
    New-Item -ItemType Directory -Path (Join-Path $AncestorReparseTarget 'nested-root') -Force | Out-Null
    New-Item -ItemType Junction -Path $AncestorReparseLink -Target $AncestorReparseTarget | Out-Null
    Assert-ThrowsLike { Assert-NoAgentBridgeReparsePoint -Root $RootBelowReparsePoint -Path (Join-Path $RootBelowReparsePoint 'missing.txt') } 'Reparse point is not allowed:*' 'reparse points above root should be rejected'

    $ReparseRequestId = '20260612T140000Z-d4e5f6'
    $ReparseRequestParent = Join-Path $Repository '.agent-bridge'
    $ReparseRequestTarget = Join-Path $TempRoot 'request-target'
    $ReparseRequestDirectory = Join-Path $ReparseRequestParent $ReparseRequestId
    New-Item -ItemType Directory -Path $ReparseRequestTarget | Out-Null
    New-Item -ItemType Junction -Path $ReparseRequestDirectory -Target $ReparseRequestTarget | Out-Null
    $ReparseTask = New-ValidAgentBridgeTask -Repository ([System.IO.Path]::GetFullPath($Repository)) -RequestId $ReparseRequestId
    Assert-ThrowsLike { Assert-AgentBridgeTask -Task $ReparseTask -RequestDirectory $ReparseRequestDirectory } 'Reparse point is not allowed:*' 'reparse request directories should be rejected'

    $RepositoryTarget = Join-Path $TempRoot 'repository-target'
    $RepositoryLink = Join-Path $TempRoot 'repository-link'
    New-Item -ItemType Directory -Path $RepositoryTarget | Out-Null
    New-Item -ItemType Junction -Path $RepositoryLink -Target $RepositoryTarget | Out-Null
    $RepositoryLinkRequest = Join-Path $RepositoryLink ".agent-bridge\$RequestId"
    $RepositoryLinkTask = New-ValidAgentBridgeTask -Repository ([System.IO.Path]::GetFullPath($RepositoryLink)) -RequestId $RequestId
    Assert-ThrowsLike { Assert-AgentBridgeTask -Task $RepositoryLinkTask -RequestDirectory $RepositoryLinkRequest } 'Reparse point is not allowed:*' 'reparse repositories should be rejected'

    $Task = Copy-TestObject $ValidTask
    $Task.constraints = @('constraint') * 101
    Assert-ThrowsLike { Assert-AgentBridgeTask -Task $Task -RequestDirectory $RequestDirectory } 'Task field constraints exceeds runtime item limit of 100' 'oversized task arrays should be rejected'
    $Task = Copy-TestObject $ValidTask
    $Task.objective = 'x' * 10001
    Assert-ThrowsLike { Assert-AgentBridgeTask -Task $Task -RequestDirectory $RequestDirectory } 'Task objective exceeds runtime length limit of 10000 characters' 'oversized task strings should be rejected'

    $ValidResult = New-ValidAgentBridgeResult -RequestId $RequestId
    Assert-AgentBridgeResult -Result $ValidResult -Task $ValidTask -RequestDirectory $RequestDirectory

    foreach ($PropertyName in @('schema_version', 'request_id', 'status', 'summary', 'changed_files', 'verification', 'findings', 'decisions', 'risks', 'review_focus', 'artifacts')) {
        $Result = Copy-TestObject $ValidResult
        $Result.PSObject.Properties.Remove($PropertyName)
        Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } "Missing required result field: $PropertyName" "missing result $PropertyName should be rejected"
    }

    $Result = Copy-TestObject $ValidResult
    $Result | Add-Member -NotePropertyName extra -NotePropertyValue 'not allowed'
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Unexpected result field: extra' 'additional result fields should be rejected'

    $Result = Copy-TestObject $ValidResult
    $Result.PSObject.Properties.Remove('status')
    $Result | Add-Member -NotePropertyName Status -NotePropertyValue 'completed'
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Missing required result field: status' 'result property names should be case-sensitive'

    $InvalidResultValues = @(
        @{ Field = 'schema_version'; Value = 2; Pattern = 'Invalid result schema_version:*' },
        @{ Field = 'request_id'; Value = '20260612T140000Z-ffffff'; Pattern = 'request_id mismatch:*' },
        @{ Field = 'request_id'; Value = '20260612T140000Z-A1B2C3'; Pattern = 'request_id mismatch:*' },
        @{ Field = 'status'; Value = 'done'; Pattern = 'Invalid result status:*' },
        @{ Field = 'status'; Value = 'COMPLETED'; Pattern = 'Invalid result status:*' },
        @{ Field = 'summary'; Value = ('x' * 501); Pattern = 'summary exceeds 500 characters' },
        @{ Field = 'changed_files'; Value = 'not-an-array'; Pattern = 'Result field must be an array: changed_files' },
        @{ Field = 'verification'; Value = 'not-an-array'; Pattern = 'Result field must be an array: verification' },
        @{ Field = 'findings'; Value = 'not-an-array'; Pattern = 'Result field must be an array: findings' },
        @{ Field = 'decisions'; Value = @(1); Pattern = 'Result field must be a string array: decisions' },
        @{ Field = 'risks'; Value = @('risk') * 11; Pattern = 'risks exceeds 10 items' },
        @{ Field = 'review_focus'; Value = @($ValidResult.review_focus[0]) * 11; Pattern = 'review_focus exceeds 10 items' },
        @{ Field = 'artifacts'; Value = 'not-an-array'; Pattern = 'Result field must be an array: artifacts' }
    )
    foreach ($Invalid in $InvalidResultValues) {
        $Result = Copy-TestObject $ValidResult
        $Result.($Invalid.Field) = $Invalid.Value
        Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } $Invalid.Pattern "invalid result $($Invalid.Field) should be rejected"
    }

    $Result = Copy-TestObject $ValidResult
    $Result.decisions = @('decision') * 11
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'decisions exceeds 10 items' 'over-limit decisions should be rejected'

    foreach ($Case in @(
        @{ Field = 'changed_files'; Value = @('scripts\agent-bridge\AgentBridge.psm1') * 1001; Pattern = 'Result field changed_files exceeds runtime item limit of 1000' },
        @{ Field = 'verification'; Value = @($ValidResult.verification[0]) * 101; Pattern = 'Result field verification exceeds runtime item limit of 100' },
        @{ Field = 'artifacts'; Value = @('artifacts\test-output.txt') * 101; Pattern = 'Result field artifacts exceeds runtime item limit of 100' }
    )) {
        $Result = Copy-TestObject $ValidResult
        $Result.($Case.Field) = $Case.Value
        Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } $Case.Pattern "oversized result $($Case.Field) should be rejected"
    }
    $Result = Copy-TestObject $ValidResult
    $Result.findings = @($ValidResult.findings[0]) * 1001
    $ManyFindingsJsonBytes = (New-Object System.Text.UTF8Encoding($false)).GetByteCount(($Result | ConvertTo-Json -Compress -Depth 10))
    Assert-LessThan $ManyFindingsJsonBytes 1048576 '1001 findings test data should remain below the result JSON byte limit'
    Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory

    $Result = Copy-TestObject $ValidResult
    $Result.verification[0].command = 'x' * 4097
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Verification command exceeds runtime length limit of 4096 characters' 'oversized verification commands should be rejected'
    $Result = Copy-TestObject $ValidResult
    $Result.findings[0].reason = 'x' * 4097
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Finding reason exceeds runtime length limit of 4096 characters' 'oversized finding strings should be rejected'

    $Result = Copy-TestObject $ValidResult
    $Result.verification[0].status = 'skipped'
    $Result.verification[0].reason = ''
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Skipped verification requires a non-empty reason' 'skipped verification without a reason should be rejected'

    $Result = Copy-TestObject $ValidResult
    $Result.verification[0].status = 'unknown'
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Invalid verification status:*' 'invalid verification status should be rejected'
    $Result = Copy-TestObject $ValidResult
    $Result.verification[0].status = 'PASSED'
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Invalid verification status:*' 'uppercase verification status should be rejected'

    $Result = Copy-TestObject $ValidResult
    $Result.findings[0].severity = 'urgent'
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Invalid finding severity:*' 'invalid finding severity should be rejected'
    $Result = Copy-TestObject $ValidResult
    $Result.findings[0].severity = 'HIGH'
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Invalid finding severity:*' 'uppercase finding severity should be rejected'

    $Result = Copy-TestObject $ValidResult
    $Result.findings[0].confidence = 'certain'
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Invalid finding confidence:*' 'invalid finding confidence should be rejected'
    $Result = Copy-TestObject $ValidResult
    $Result.findings[0].confidence = 'HIGH'
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Invalid finding confidence:*' 'uppercase finding confidence should be rejected'

    foreach ($Case in @(
        @{ Field = 'changed_files'; Value = @(Join-Path $Repository 'rooted.txt'); Pattern = 'Invalid repository-relative path:*' },
        @{ Field = 'changed_files'; Value = @('scripts\..\outside.txt'); Pattern = 'Invalid repository-relative path:*Path traversal is not allowed:*' },
        @{ Field = 'artifacts'; Value = @('outside.txt'); Pattern = 'Invalid artifact path:*' },
        @{ Field = 'artifacts'; Value = @(Join-Path $RequestDirectory 'artifacts\rooted.txt'); Pattern = 'Invalid artifact path:*Absolute path is not allowed:*' },
        @{ Field = 'artifacts'; Value = @('artifacts\..\outside.txt'); Pattern = 'Invalid artifact path:*Path traversal is not allowed:*' }
    )) {
        $Result = Copy-TestObject $ValidResult
        $Result.($Case.Field) = $Case.Value
        Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } $Case.Pattern "invalid $($Case.Field) path should be rejected"
    }

    $ResultReparseTarget = Join-Path $TempRoot 'result-reparse-target'
    $ResultReparseLink = Join-Path $Repository 'result-reparse-link'
    New-Item -ItemType Directory -Path $ResultReparseTarget | Out-Null
    New-Item -ItemType Junction -Path $ResultReparseLink -Target $ResultReparseTarget | Out-Null
    $Result = Copy-TestObject $ValidResult
    $Result.changed_files = @('result-reparse-link\file.txt')
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Invalid repository-relative path:*Reparse point is not allowed:*' 'repository-relative reparse paths should be rejected'

    $ArtifactReparseTarget = Join-Path $TempRoot 'artifact-reparse-target'
    $ArtifactReparseLink = Join-Path $RequestDirectory 'artifacts\linked'
    New-Item -ItemType Directory -Path $ArtifactReparseTarget | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $RequestDirectory 'artifacts') -Force | Out-Null
    New-Item -ItemType Junction -Path $ArtifactReparseLink -Target $ArtifactReparseTarget | Out-Null
    $Result = Copy-TestObject $ValidResult
    $Result.artifacts = @('artifacts\linked\output.txt')
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Invalid artifact path:*Reparse point is not allowed:*' 'artifact reparse paths should be rejected'

    $Result = Copy-TestObject $ValidResult
    $Result.verification[0].PSObject.Properties.Remove('command')
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Missing required verification field: command' 'missing verification fields should be rejected'
    $Result = Copy-TestObject $ValidResult
    $Result.verification[0].PSObject.Properties.Remove('command')
    $Result.verification[0] | Add-Member -NotePropertyName Command -NotePropertyValue 'test command'
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Missing required verification field: command' 'verification property names should be case-sensitive'
    $Result = Copy-TestObject $ValidResult
    $Result.verification[0] | Add-Member -NotePropertyName extra -NotePropertyValue 'not allowed'
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Unexpected verification field: extra' 'additional verification fields should be rejected'
    $Result = Copy-TestObject $ValidResult
    $Result.verification[0].artifact = 'outside.txt'
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Invalid artifact path:*' 'verification artifacts outside artifacts should be rejected'
    $Result = Copy-TestObject $ValidResult
    $Result.verification[0].artifact = 1
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Invalid artifact path:*' 'non-string verification artifacts should be rejected'

    $Result = Copy-TestObject $ValidResult
    $Result.findings[0].PSObject.Properties.Remove('title')
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Missing required finding field: title' 'missing finding fields should be rejected'
    $Result = Copy-TestObject $ValidResult
    $Result.findings[0].PSObject.Properties.Remove('severity')
    $Result.findings[0] | Add-Member -NotePropertyName Severity -NotePropertyValue 'low'
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Missing required finding field: severity' 'finding property names should be case-sensitive'
    $Result = Copy-TestObject $ValidResult
    $Result.findings[0] | Add-Member -NotePropertyName extra -NotePropertyValue 'not allowed'
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Unexpected finding field: extra' 'additional finding fields should be rejected'
    $Result = Copy-TestObject $ValidResult
    $Result.findings[0].line = 0
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Invalid finding line:*' 'invalid finding line should be rejected'

    $Result = Copy-TestObject $ValidResult
    $Result.review_focus[0].PSObject.Properties.Remove('reason')
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Missing required review_focus field: reason' 'missing review focus fields should be rejected'
    $Result = Copy-TestObject $ValidResult
    $Result.review_focus[0].PSObject.Properties.Remove('file')
    $Result.review_focus[0] | Add-Member -NotePropertyName File -NotePropertyValue 'scripts\agent-bridge\AgentBridge.psm1'
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Missing required review_focus field: file' 'review focus property names should be case-sensitive'
    $Result = Copy-TestObject $ValidResult
    $Result.review_focus[0] | Add-Member -NotePropertyName extra -NotePropertyValue 'not allowed'
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Unexpected review_focus field: extra' 'additional review focus fields should be rejected'
    $Result = Copy-TestObject $ValidResult
    $Result.review_focus[0].file = '..\outside.txt'
    Assert-ThrowsLike { Assert-AgentBridgeResult -Result $Result -Task $ValidTask -RequestDirectory $RequestDirectory } 'Invalid repository-relative path:*' 'review focus traversal should be rejected'

    $WaitRepository = Join-Path $TempRoot 'wait-repository'
    $WaitRequestId = '20260612T145000Z-a1b2c4'
    $WaitRequestDirectory = Join-Path $WaitRepository ".agent-bridge\$WaitRequestId"
    New-Item -ItemType Directory -Path (Join-Path $WaitRequestDirectory 'artifacts') -Force | Out-Null
    $WaitTask = New-ValidAgentBridgeTask -Repository ([System.IO.Path]::GetFullPath($WaitRepository)) -RequestId $WaitRequestId
    $WaitResult = New-ValidAgentBridgeResult -RequestId $WaitRequestId
    $Utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    $TaskSymlinkTarget = Join-Path $WaitRepository 'task-symlink-target'
    New-Item -ItemType Directory -Path $TaskSymlinkTarget | Out-Null
    $TaskSymlinkPath = Join-Path $WaitRequestDirectory 'task.json'
    New-Item -ItemType Junction -Path $TaskSymlinkPath -Target $TaskSymlinkTarget | Out-Null
    Assert-ThrowsLike { Wait-AgentBridgeResult -RequestDirectory $WaitRequestDirectory -TimeoutSeconds 0 -PollMilliseconds 1 } 'Reparse point is not allowed:*task.json' 'wait should reject reparse points at the task file path'
    Move-Item -LiteralPath $TaskSymlinkPath -Destination (Join-Path $WaitRepository 'rejected-task-symlink')

    $InvalidLoadedTask = Copy-TestObject $WaitTask
    $InvalidLoadedTask.PSObject.Properties.Remove('task_type')
    $InvalidLoadedTask | Add-Member -NotePropertyName Task_Type -NotePropertyValue 'implementation'
    [System.IO.File]::WriteAllText((Join-Path $WaitRequestDirectory 'task.json'), ($InvalidLoadedTask | ConvertTo-Json -Depth 10), $Utf8WithoutBom)
    Assert-ThrowsLike { Wait-AgentBridgeResult -RequestDirectory $WaitRequestDirectory -TimeoutSeconds 0 -PollMilliseconds 1 } 'Missing required task field: task_type' 'wait should reject case-mismatched task properties'

    [System.IO.File]::WriteAllText((Join-Path $WaitRequestDirectory 'task.json'), ($WaitTask | ConvertTo-Json -Depth 10), $Utf8WithoutBom)
    [System.IO.File]::WriteAllText((Join-Path $WaitRequestDirectory 'result.json.tmp'), ($WaitResult | ConvertTo-Json -Depth 10), $Utf8WithoutBom)
    Assert-ThrowsLike { Wait-AgentBridgeResult -RequestDirectory $WaitRequestDirectory -TimeoutSeconds 0 -PollMilliseconds 1 } 'Timed out waiting for result.json:*' 'tmp-only result should never complete'

    $ResultSymlinkTarget = Join-Path $WaitRepository 'result-symlink-target'
    New-Item -ItemType Directory -Path $ResultSymlinkTarget | Out-Null
    $ResultSymlinkPath = Join-Path $WaitRequestDirectory 'result.json'
    $ResultReparseJob = Start-Job -ArgumentList $ResultSymlinkPath, $ResultSymlinkTarget -ScriptBlock {
        param($Path, $Target)
        Start-Sleep -Milliseconds 1500
        New-Item -ItemType Junction -Path $Path -Target $Target | Out-Null
    }
    try {
        Assert-ThrowsLike { Wait-AgentBridgeResult -RequestDirectory $WaitRequestDirectory -TimeoutSeconds 4 -PollMilliseconds 50 } 'Reparse point is not allowed:*result.json' 'wait should reject reparse points at the result file path after polling'
    }
    finally {
        Wait-Job -Job $ResultReparseJob -Timeout 5 | Out-Null
        Receive-Job -Job $ResultReparseJob | Out-Null
        Remove-Job -Job $ResultReparseJob -Force
    }
    Move-Item -LiteralPath $ResultSymlinkPath -Destination (Join-Path $WaitRepository 'rejected-result-symlink')

    $OversizedTask = Copy-TestObject $WaitTask
    $OversizedTask.objective = 'x' * 1048576
    [System.IO.File]::WriteAllText((Join-Path $WaitRequestDirectory 'task.json'), ($OversizedTask | ConvertTo-Json -Compress -Depth 10), $Utf8WithoutBom)
    Assert-ThrowsLike { Wait-AgentBridgeResult -RequestDirectory $WaitRequestDirectory -TimeoutSeconds 0 -PollMilliseconds 1 } 'task.json exceeds runtime byte limit of 1048576 bytes' 'oversized task JSON should be rejected before parsing'

    [System.IO.File]::WriteAllText((Join-Path $WaitRequestDirectory 'task.json'), ($WaitTask | ConvertTo-Json -Depth 10), $Utf8WithoutBom)
    $OversizedResult = Copy-TestObject $WaitResult
    $OversizedResult.summary = 'x' * 1048576
    [System.IO.File]::WriteAllText((Join-Path $WaitRequestDirectory 'result.json'), ($OversizedResult | ConvertTo-Json -Compress -Depth 10), $Utf8WithoutBom)
    Assert-ThrowsLike { Wait-AgentBridgeResult -RequestDirectory $WaitRequestDirectory -TimeoutSeconds 0 -PollMilliseconds 1 } 'result.json exceeds runtime byte limit of 1048576 bytes' 'oversized result JSON should be rejected before parsing'

    $InvalidLoadedResult = Copy-TestObject $WaitResult
    $InvalidLoadedResult.PSObject.Properties.Remove('status')
    $InvalidLoadedResult | Add-Member -NotePropertyName Status -NotePropertyValue 'completed'
    [System.IO.File]::WriteAllText((Join-Path $WaitRequestDirectory 'result.json'), ($InvalidLoadedResult | ConvertTo-Json -Depth 10), $Utf8WithoutBom)
    Assert-ThrowsLike { Wait-AgentBridgeResult -RequestDirectory $WaitRequestDirectory -TimeoutSeconds 0 -PollMilliseconds 1 } 'Missing required result field: status' 'wait should reject case-mismatched result properties'

    [System.IO.File]::WriteAllText((Join-Path $WaitRequestDirectory 'result.json'), ($WaitResult | ConvertTo-Json -Depth 10), $Utf8WithoutBom)
    $WaitedResult = Wait-AgentBridgeResult -RequestDirectory $WaitRequestDirectory -TimeoutSeconds 1 -PollMilliseconds 1
    Assert-Equal $WaitedResult.request_id $WaitRequestId 'valid result should be returned'

    $FinalPathMismatchState = [pscustomobject]@{
        CallCount = 0
        StreamWasReadable = $false
        AlternatePath = Join-Path $WaitRequestDirectory 'result.json'
    }
    & (Get-Module AgentBridge) {
        param($State)
        $script:AgentBridgeFinalPathResolver = ({
            param($Stream, $ExpectedPath)
            $State.CallCount++
            $State.StreamWasReadable = $Stream.CanRead
            return $State.AlternatePath
        }).GetNewClosure()
    } $FinalPathMismatchState
    try {
        Assert-ThrowsLike { Wait-AgentBridgeResult -RequestDirectory $WaitRequestDirectory -TimeoutSeconds 1 -PollMilliseconds 1 } 'Opened file final path mismatch:*' 'opened file handles resolving to a different path should be rejected'
    }
    finally {
        Import-Module (Join-Path $BridgeRoot 'AgentBridge.psm1') -Force
    }
    Assert-Equal $FinalPathMismatchState.CallCount 1 'final path mismatch should be detected while opening task.json'
    Assert-True $FinalPathMismatchState.StreamWasReadable 'final path validation should receive an opened readable stream'

    $FinalPathEscapeState = [pscustomobject]@{
        CallCount = 0
        AlternatePath = Join-Path $WaitRepository 'outside-request.json'
    }
    & (Get-Module AgentBridge) {
        param($State)
        $script:AgentBridgeFinalPathResolver = ({
            param($Stream, $ExpectedPath)
            $State.CallCount++
            return $State.AlternatePath
        }).GetNewClosure()
    } $FinalPathEscapeState
    try {
        Assert-ThrowsLike { Wait-AgentBridgeResult -RequestDirectory $WaitRequestDirectory -TimeoutSeconds 1 -PollMilliseconds 1 } 'Opened file final path escapes allowed root (*):*' 'opened file handles resolving outside the request root should be rejected'
    }
    finally {
        Import-Module (Join-Path $BridgeRoot 'AgentBridge.psm1') -Force
    }
    Assert-Equal $FinalPathEscapeState.CallCount 1 'final path root escape should stop at task.json'

    $FinalPathFailureState = [pscustomobject]@{ CallCount = 0 }
    & (Get-Module AgentBridge) {
        param($State)
        $script:AgentBridgeFinalPathResolver = ({
            param($Stream, $ExpectedPath)
            $State.CallCount++
            throw 'Failed to resolve final path for opened file handle: simulated API failure'
        }).GetNewClosure()
    } $FinalPathFailureState
    try {
        Assert-ThrowsLike { Wait-AgentBridgeResult -RequestDirectory $WaitRequestDirectory -TimeoutSeconds 1 -PollMilliseconds 1 } 'Failed to resolve final path for opened file handle (*):*simulated API failure*' 'final path API failures should fail closed'
    }
    finally {
        Import-Module (Join-Path $BridgeRoot 'AgentBridge.psm1') -Force
    }
    Assert-Equal $FinalPathFailureState.CallCount 1 'final path API failure should stop at task.json'

    $FinalPathPrefixState = [pscustomobject]@{ CallCount = 0 }
    & (Get-Module AgentBridge) {
        param($State)
        $script:AgentBridgeFinalPathResolver = ({
            param($Stream, $ExpectedPath)
            $State.CallCount++
            return '\\?\' + $ExpectedPath
        }).GetNewClosure()
    } $FinalPathPrefixState
    try {
        $PrefixedPathResult = Wait-AgentBridgeResult -RequestDirectory $WaitRequestDirectory -TimeoutSeconds 1 -PollMilliseconds 1
        Assert-Equal $PrefixedPathResult.request_id $WaitRequestId 'extended-length final paths should normalize to the expected file'
    }
    finally {
        Import-Module (Join-Path $BridgeRoot 'AgentBridge.psm1') -Force
    }
    Assert-Equal $FinalPathPrefixState.CallCount 2 'normal wait should validate task and result opened handles'

    Assert-ThrowsLike { Wait-AgentBridgeResult -RequestDirectory $WaitRequestDirectory -TimeoutSeconds -1 } 'TimeoutSeconds must be zero or greater' 'negative timeout should be rejected'
    Assert-ThrowsLike { Wait-AgentBridgeResult -RequestDirectory $WaitRequestDirectory -PollMilliseconds 0 } 'PollMilliseconds must be greater than zero' 'zero poll interval should be rejected'

    [System.IO.File]::WriteAllText((Join-Path $WaitRequestDirectory 'result.json'), '{not json', $Utf8WithoutBom)
    Assert-ThrowsLike { Wait-AgentBridgeResult -RequestDirectory $WaitRequestDirectory -TimeoutSeconds 0 -PollMilliseconds 1 } 'Malformed result.json:*' 'malformed result JSON should report a clear error'

    $MissingResultRequestId = '20260612T145500Z-a1b2c5'
    $MissingResultRequestDirectory = Join-Path $WaitRepository ".agent-bridge\$MissingResultRequestId"
    New-Item -ItemType Directory -Path $MissingResultRequestDirectory -Force | Out-Null
    $MissingResultTask = New-ValidAgentBridgeTask -Repository ([System.IO.Path]::GetFullPath($WaitRepository)) -RequestId $MissingResultRequestId
    [System.IO.File]::WriteAllText((Join-Path $MissingResultRequestDirectory 'task.json'), ($MissingResultTask | ConvertTo-Json -Depth 10), $Utf8WithoutBom)
    $TimeoutStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Assert-ThrowsLike { Wait-AgentBridgeResult -RequestDirectory $MissingResultRequestDirectory -TimeoutSeconds 1 -PollMilliseconds 60000 } 'Timed out waiting for result.json:*' 'missing result should time out explicitly'
    $TimeoutStopwatch.Stop()
    Assert-GreaterThan $TimeoutStopwatch.Elapsed.TotalSeconds 0.7 'one-second timeout should not fail immediately'
    Assert-LessThan $TimeoutStopwatch.Elapsed.TotalSeconds 3 'poll interval should not extend the timeout significantly'

    $DelayedResultRequestId = '20260612T145600Z-a1b2c6'
    $DelayedResultRequestDirectory = Join-Path $WaitRepository ".agent-bridge\$DelayedResultRequestId"
    New-Item -ItemType Directory -Path (Join-Path $DelayedResultRequestDirectory 'artifacts') -Force | Out-Null
    $DelayedResultTask = New-ValidAgentBridgeTask -Repository ([System.IO.Path]::GetFullPath($WaitRepository)) -RequestId $DelayedResultRequestId
    $DelayedResult = New-ValidAgentBridgeResult -RequestId $DelayedResultRequestId
    [System.IO.File]::WriteAllText((Join-Path $DelayedResultRequestDirectory 'task.json'), ($DelayedResultTask | ConvertTo-Json -Depth 10), $Utf8WithoutBom)
    $DelayedResultJob = Start-Job -ArgumentList $DelayedResultRequestDirectory, ($DelayedResult | ConvertTo-Json -Depth 10) -ScriptBlock {
        param($Directory, $Json)
        Start-Sleep -Milliseconds 300
        $TemporaryPath = Join-Path $Directory 'result.json.tmp'
        $FinalPath = Join-Path $Directory 'result.json'
        [System.IO.File]::WriteAllText($TemporaryPath, $Json, (New-Object System.Text.UTF8Encoding($false)))
        [System.IO.File]::Move($TemporaryPath, $FinalPath)
    }
    try {
        $DelayedWaitResult = Wait-AgentBridgeResult -RequestDirectory $DelayedResultRequestDirectory -TimeoutSeconds 3 -PollMilliseconds 50
        Assert-Equal $DelayedWaitResult.request_id $DelayedResultRequestId 'wait should return a delayed result before timeout'
    }
    finally {
        Wait-Job -Job $DelayedResultJob -Timeout 5 | Out-Null
        Receive-Job -Job $DelayedResultJob | Out-Null
        Remove-Job -Job $DelayedResultJob -Force
    }

    [System.IO.File]::WriteAllText((Join-Path $WaitRequestDirectory 'result.json'), ($WaitResult | ConvertTo-Json -Depth 10), $Utf8WithoutBom)
    $WaitCliPath = Join-Path $BridgeRoot 'Wait-AgentBridgeResult.ps1'
    $WaitCliProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
    $WaitCliProcessInfo.FileName = 'powershell.exe'
    $WaitCliProcessInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$WaitCliPath`" -RequestDirectory `"$WaitRequestDirectory`" -TimeoutSeconds 1 -PollMilliseconds 1"
    $WaitCliProcessInfo.UseShellExecute = $false
    $WaitCliProcessInfo.CreateNoWindow = $true
    $WaitCliProcessInfo.RedirectStandardOutput = $true
    $WaitCliProcessInfo.RedirectStandardError = $true
    $WaitCliProcess = New-Object System.Diagnostics.Process
    $WaitCliProcess.StartInfo = $WaitCliProcessInfo
    [void]$WaitCliProcess.Start()
    $WaitCliStdout = New-Object System.IO.MemoryStream
    $WaitCliProcess.StandardOutput.BaseStream.CopyTo($WaitCliStdout)
    $WaitCliStderr = $WaitCliProcess.StandardError.ReadToEnd()
    $WaitCliProcess.WaitForExit()
    Assert-Equal $WaitCliProcess.ExitCode 0 "wait CLI should exit successfully. stderr=[$WaitCliStderr]"
    $WaitCliBytes = $WaitCliStdout.ToArray()
    Assert-True (-not (($WaitCliBytes.Length -ge 3) -and ($WaitCliBytes[0] -eq 0xEF) -and ($WaitCliBytes[1] -eq 0xBB) -and ($WaitCliBytes[2] -eq 0xBF))) 'wait CLI stdout should not have a UTF-8 BOM'
    $WaitCliJson = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($WaitCliBytes)
    Assert-Equal @(($WaitCliJson.TrimEnd()) -split "`r?`n").Count 1 'wait CLI should emit one compressed JSON line'
    $WaitCliResult = $WaitCliJson | ConvertFrom-Json
    Assert-Equal $WaitCliResult.request_id $WaitRequestId 'wait CLI JSON should contain the request ID'

    $CreationRepository = Join-Path $TempRoot 'creation-repository'
    New-Item -ItemType Directory -Path $CreationRepository | Out-Null
    $CreatedRequestId = '20260612T150000Z-1a2b3c'
    $CreationBridgeRoot = Join-Path $CreationRepository '.agent-bridge'
    New-Item -ItemType Directory -Path $CreationBridgeRoot | Out-Null
    $DirectoryWatcher = New-Object System.IO.FileSystemWatcher($CreationBridgeRoot)
    $DirectoryWatcher.NotifyFilter = [System.IO.NotifyFilters]::DirectoryName
    $DirectoryWatcher.EnableRaisingEvents = $true
    $CreatedDirectoryEventName = 'AgentBridgeCreated-' + [guid]::NewGuid().ToString('N')
    $RenamedDirectoryEventName = 'AgentBridgeRenamed-' + [guid]::NewGuid().ToString('N')
    Register-ObjectEvent -InputObject $DirectoryWatcher -EventName Created -SourceIdentifier $CreatedDirectoryEventName | Out-Null
    Register-ObjectEvent -InputObject $DirectoryWatcher -EventName Renamed -SourceIdentifier $RenamedDirectoryEventName | Out-Null
    try {
        $CreatedRequest = New-AgentBridgeRequest `
            -Repository (Join-Path $CreationRepository '.') `
            -TaskType 'implementation' `
            -Objective 'Create an agent bridge request' `
            -Constraints @('Keep compatibility') `
            -AcceptanceCriteria @('Tests pass') `
            -ReviewScope @('scripts') `
            -RequestId $CreatedRequestId
        $PublishEvent = Wait-Event -SourceIdentifier $RenamedDirectoryEventName -Timeout 5
        Assert-True ($null -ne $PublishEvent) 'atomic publish should emit a rename event'
        $DirectoryEvents = @(Get-Event | Where-Object {
            $_.SourceIdentifier -in @($CreatedDirectoryEventName, $RenamedDirectoryEventName)
        })
    }
    finally {
        Unregister-Event -SourceIdentifier $CreatedDirectoryEventName
        Unregister-Event -SourceIdentifier $RenamedDirectoryEventName
        Remove-Event -SourceIdentifier $CreatedDirectoryEventName -ErrorAction SilentlyContinue
        Remove-Event -SourceIdentifier $RenamedDirectoryEventName -ErrorAction SilentlyContinue
        $DirectoryWatcher.Dispose()
    }

    $NormalizedCreationRepository = [System.IO.Path]::GetFullPath($CreationRepository)
    $ExpectedCreatedDirectory = Join-Path $NormalizedCreationRepository ".agent-bridge\$CreatedRequestId"
    $CreatedTaskPath = Join-Path $ExpectedCreatedDirectory 'task.json'
    $PublishEvents = @($DirectoryEvents | Where-Object {
        ($_.SourceIdentifier -eq $RenamedDirectoryEventName) -and
        ($_.SourceEventArgs.Name -eq $CreatedRequestId)
    })
    $CreatedFinalDirectoryEvents = @($DirectoryEvents | Where-Object {
        ($_.SourceIdentifier -eq $CreatedDirectoryEventName) -and
        ($_.SourceEventArgs.Name -eq $CreatedRequestId)
    })
    Assert-Equal $CreatedFinalDirectoryEvents.Count 0 'atomic publish should not create the final request directory directly'
    Assert-True ($PublishEvents.Count -eq 1) 'atomic publish should rename a staging directory to the final request ID'
    $PublishedStagingName = $PublishEvents[0].SourceEventArgs.OldName
    Assert-True ($PublishedStagingName -notmatch '^[0-9]{8}T[0-9]{6}Z-[a-f0-9]{6}$') 'atomic publish staging directory should not have a valid request ID name'
    Assert-Equal $CreatedRequest.RequestId $CreatedRequestId 'created request should return the injected request ID'
    Assert-Equal $CreatedRequest.RequestDirectory $ExpectedCreatedDirectory 'created request should return its directory'
    Assert-True (Test-Path -LiteralPath $CreatedTaskPath -PathType Leaf) 'created request should write task.json'
    Assert-True (Test-Path -LiteralPath (Join-Path $ExpectedCreatedDirectory 'artifacts') -PathType Container) 'created request should create artifacts directory'
    Assert-True ($CreatedRequest.Prompt -like '*task.json*') 'prompt should tell Antigravity to read task.json'
    Assert-True ($CreatedRequest.Prompt -like '*result.json.tmp*') 'prompt should mention the temporary result path'
    Assert-True ($CreatedRequest.Prompt -like '*result.json*') 'prompt should mention the final result path'
    Assert-True ($CreatedRequest.Prompt -like '*repository*') 'prompt should prohibit writes outside the repository'

    $TaskBytes = [System.IO.File]::ReadAllBytes($CreatedTaskPath)
    Assert-True (-not (($TaskBytes.Length -ge 3) -and ($TaskBytes[0] -eq 0xEF) -and ($TaskBytes[1] -eq 0xBB) -and ($TaskBytes[2] -eq 0xBF))) 'task.json should not have a UTF-8 BOM'
    $CreatedTask = [System.IO.File]::ReadAllText($CreatedTaskPath, (New-Object System.Text.UTF8Encoding($false))) | ConvertFrom-Json
    Assert-Equal $CreatedTask.schema_version 1 'created task should use schema version 1'
    Assert-Equal $CreatedTask.request_id $CreatedRequestId 'created task should use the request ID'
    Assert-Equal $CreatedTask.task_type 'implementation' 'created task should use the task type'
    Assert-Equal $CreatedTask.repository $NormalizedCreationRepository 'created task should normalize repository'
    Assert-Equal $CreatedTask.objective 'Create an agent bridge request' 'created task should use the objective'
    Assert-SetEqual $CreatedTask.constraints @('Keep compatibility') 'created task constraints'
    Assert-SetEqual $CreatedTask.acceptance_criteria @('Tests pass') 'created task acceptance criteria'
    Assert-SetEqual $CreatedTask.review_scope @('scripts') 'created task review scope'
    Assert-Equal $CreatedTask.output_path ".agent-bridge\$CreatedRequestId\result.json" 'created task should point output_path to result.json'

    [System.IO.File]::WriteAllText($CreatedTaskPath, 'sentinel')
    Assert-ThrowsLike {
        New-AgentBridgeRequest `
            -Repository $CreationRepository `
            -TaskType 'implementation' `
            -Objective 'Do not overwrite' `
            -Constraints @() `
            -AcceptanceCriteria @() `
            -ReviewScope @() `
            -RequestId $CreatedRequestId
    } 'Request directory already exists:*' 'existing request directories should not be overwritten'
    Assert-Equal ([System.IO.File]::ReadAllText($CreatedTaskPath)) 'sentinel' 'existing task.json should remain unchanged'

    $RollbackRepository = Join-Path $TempRoot 'rollback-repository'
    $RollbackTrash = Join-Path $TempRoot 'rollback-trash'
    $RollbackRequestId = '20260612T150500Z-1a2b3e'
    New-Item -ItemType Directory -Path $RollbackRepository, $RollbackTrash | Out-Null
    $RollbackState = [pscustomobject]@{
        PublishSource = $null
        PublishDestination = $null
        RecyclePath = $null
    }
    & (Get-Module AgentBridge) {
        param($State, $Trash)
        $script:AgentBridgePublishDirectoryMover = ({
            param($Source, $Destination)
            $State.PublishSource = $Source
            $State.PublishDestination = $Destination
            New-Item -ItemType Directory -Path $Destination | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $Destination 'sentinel.txt'), 'existing request')
            throw 'simulated publish conflict'
        }).GetNewClosure()
        $script:AgentBridgeRecycleDirectoryMover = ({
            param($Path)
            $State.RecyclePath = $Path
            Move-Item -LiteralPath $Path -Destination (Join-Path $Trash (Split-Path -Leaf $Path))
            throw 'simulated cleanup reporting failure'
        }).GetNewClosure()
    } $RollbackState $RollbackTrash
    try {
        Assert-ThrowsLike {
            New-AgentBridgeRequest `
                -Repository $RollbackRepository `
                -TaskType 'implementation' `
                -Objective 'Test publish rollback' `
                -Constraints @() `
                -AcceptanceCriteria @() `
                -ReviewScope @() `
                -RequestId $RollbackRequestId
        } 'simulated publish conflict' 'publish failure should preserve the original exception'
    }
    finally {
        Import-Module (Join-Path $BridgeRoot 'AgentBridge.psm1') -Force
    }
    Assert-True ($RollbackState.PublishSource -like (Join-Path $RollbackRepository '.agent-bridge\.pending-*')) 'publish failure should originate from a staging directory'
    Assert-Equal $RollbackState.RecyclePath $RollbackState.PublishSource 'publish failure should send the staging directory to rollback cleanup'
    Assert-True (-not (Test-Path -LiteralPath $RollbackState.PublishSource)) 'publish failure should not leave the staging directory in the bridge root'
    Assert-True (Test-Path -LiteralPath (Join-Path $RollbackTrash (Split-Path -Leaf $RollbackState.PublishSource)) -PathType Container) 'publish failure test mover should collect the staging directory'
    Assert-Equal ([System.IO.File]::ReadAllText((Join-Path $RollbackState.PublishDestination 'sentinel.txt'))) 'existing request' 'publish rollback should not damage the existing final request'

    $WriteFailureRepository = Join-Path $TempRoot 'write-failure-repository'
    $WriteFailureTrash = Join-Path $TempRoot 'write-failure-trash'
    $WriteFailureRequestId = '20260612T150700Z-1a2b3f'
    New-Item -ItemType Directory -Path $WriteFailureRepository, $WriteFailureTrash | Out-Null
    $WriteFailureState = [pscustomobject]@{
        WritePath = $null
        PublishCalled = $false
        RecyclePath = $null
    }
    & (Get-Module AgentBridge) {
        param($State, $Trash)
        $script:AgentBridgeTaskWriter = ({
            param($Path, $Contents, $Encoding)
            $State.WritePath = $Path
            throw 'simulated task write failure'
        }).GetNewClosure()
        $script:AgentBridgePublishDirectoryMover = ({
            param($Source, $Destination)
            $State.PublishCalled = $true
            throw 'publish should not run after task write failure'
        }).GetNewClosure()
        $script:AgentBridgeRecycleDirectoryMover = ({
            param($Path)
            $State.RecyclePath = $Path
            Move-Item -LiteralPath $Path -Destination (Join-Path $Trash (Split-Path -Leaf $Path))
        }).GetNewClosure()
    } $WriteFailureState $WriteFailureTrash
    try {
        Assert-ThrowsLike {
            New-AgentBridgeRequest `
                -Repository $WriteFailureRepository `
                -TaskType 'implementation' `
                -Objective 'Test task write rollback' `
                -Constraints @() `
                -AcceptanceCriteria @() `
                -ReviewScope @() `
                -RequestId $WriteFailureRequestId
        } 'simulated task write failure' 'task write failure should preserve the original exception'
    }
    finally {
        Import-Module (Join-Path $BridgeRoot 'AgentBridge.psm1') -Force
    }
    Assert-True ($WriteFailureState.WritePath -like (Join-Path $WriteFailureRepository '.agent-bridge\.pending-*\task.json')) 'task write failure should occur in the staging directory'
    Assert-True (-not $WriteFailureState.PublishCalled) 'task write failure should not attempt publish'
    Assert-Equal $WriteFailureState.RecyclePath (Split-Path -Parent $WriteFailureState.WritePath) 'task write failure should send the staging directory to rollback cleanup'
    Assert-True (-not (Test-Path -LiteralPath $WriteFailureState.RecyclePath)) 'task write failure should not leave the staging directory in the bridge root'
    Assert-True (Test-Path -LiteralPath (Join-Path $WriteFailureTrash (Split-Path -Leaf $WriteFailureState.RecyclePath)) -PathType Container) 'task write failure test mover should collect the staging directory'

    $FailedRequestId = '20260612T151000Z-1a2b3d'
    $FailedRequestDirectory = Join-Path $CreationBridgeRoot $FailedRequestId
    Assert-ThrowsLike {
        New-AgentBridgeRequest `
            -Repository $CreationRepository `
            -TaskType 'implementation' `
            -Objective '   ' `
            -Constraints @() `
            -AcceptanceCriteria @() `
            -ReviewScope @() `
            -RequestId $FailedRequestId
    } 'Objective must be non-empty' 'failed request creation should report validation failure'
    Assert-True (-not (Test-Path -LiteralPath $FailedRequestDirectory)) 'failed request creation should not leave the final request directory'

    $GeneratedRequest = New-AgentBridgeRequest `
        -Repository $CreationRepository `
        -TaskType 'review' `
        -Objective 'Review the change' `
        -Constraints @() `
        -AcceptanceCriteria @() `
        -ReviewScope @()
    Assert-True ($GeneratedRequest.RequestId -match '^[0-9]{8}T[0-9]{6}Z-[a-f0-9]{6}$') 'generated request ID should match the wire format'
    Assert-True (Test-Path -LiteralPath $GeneratedRequest.RequestDirectory -PathType Container) 'generated request directory should exist'

    Assert-ThrowsLike {
        New-AgentBridgeRequest `
            -Repository $CreationRepository `
            -TaskType 'implementation' `
            -Objective 'Reject invalid ID' `
            -Constraints @() `
            -AcceptanceCriteria @() `
            -ReviewScope @() `
            -RequestId '..\invalid'
    } 'Invalid request_id:*' 'invalid injected request IDs should be rejected'

    Assert-ThrowsLike {
        New-AgentBridgeRequest `
            -Repository $CreationRepository `
            -TaskType 'implementation' `
            -Objective 'Reject uppercase ID' `
            -Constraints @() `
            -AcceptanceCriteria @() `
            -ReviewScope @() `
            -RequestId '20260612T171000Z-A1B2C3'
    } 'Invalid request_id:*' 'uppercase injected request IDs should be rejected'

    Assert-ThrowsLike {
        New-AgentBridgeRequest `
            -Repository $CreationRepository `
            -TaskType 'implementation' `
            -Objective 'Reject blank ID' `
            -Constraints @() `
            -AcceptanceCriteria @() `
            -ReviewScope @() `
            -RequestId ''
    } 'Invalid request_id:*' 'blank injected request IDs should be rejected'

    $CliRepository = Join-Path $TempRoot 'cli-repository'
    New-Item -ItemType Directory -Path $CliRepository | Out-Null
    $CliRequestId = '20260612T160000Z-4d5e6f'
    $CliOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $BridgeRoot 'New-AgentBridgeRequest.ps1') `
        -Repository $CliRepository `
        -TaskType investigation `
        -Objective 'Investigate the issue' `
        -Constraints 'Keep compatibility' `
        -AcceptanceCriteria 'Report findings' `
        -ReviewScope 'scripts' `
        -RequestId $CliRequestId
    Assert-Equal $LASTEXITCODE 0 'request CLI should exit successfully'
    Assert-Equal @($CliOutput).Count 1 'request CLI should emit one compressed JSON line'
    $CliResult = $CliOutput | ConvertFrom-Json
    Assert-Equal $CliResult.RequestId $CliRequestId 'request CLI JSON should contain the request ID'
    Assert-True (Test-Path -LiteralPath $CliResult.RequestDirectory -PathType Container) 'request CLI JSON should contain an existing request directory'
    $CliTask = Get-Content -Raw -Encoding UTF8 (Join-Path $CliResult.RequestDirectory 'task.json') | ConvertFrom-Json
    Assert-SetEqual $CliTask.constraints @('Keep compatibility') 'request CLI single-value constraints compatibility'
    Assert-SetEqual $CliTask.acceptance_criteria @('Report findings') 'request CLI single-value acceptance criteria compatibility'
    Assert-SetEqual $CliTask.review_scope @('scripts') 'request CLI single-value review scope compatibility'

    $CliJsonRequestId = '20260612T163000Z-4d5e70'
    $CliScriptPath = Join-Path $BridgeRoot 'New-AgentBridgeRequest.ps1'
    $CliConstraintsJson = '[\"Keep compatibility\",\"Avoid direct deletion\"]'
    $CliAcceptanceCriteriaJson = '[\"Tests pass\",\"Task JSON preserves arrays\"]'
    $CliReviewScopeJson = '[\"scripts\",\"tests\"]'
    $CliJsonProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
    $CliJsonProcessInfo.FileName = 'powershell.exe'
    $CliJsonProcessInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$CliScriptPath`" -Repository `"$CliRepository`" -TaskType implementation -Objective `"Create request with multiple CLI values`" -ConstraintsJson `"$CliConstraintsJson`" -AcceptanceCriteriaJson `"$CliAcceptanceCriteriaJson`" -ReviewScopeJson `"$CliReviewScopeJson`" -RequestId $CliJsonRequestId"
    $CliJsonProcessInfo.UseShellExecute = $false
    $CliJsonProcessInfo.CreateNoWindow = $true
    $CliJsonProcessInfo.RedirectStandardOutput = $true
    $CliJsonProcessInfo.RedirectStandardError = $true
    $CliJsonProcess = New-Object System.Diagnostics.Process
    $CliJsonProcess.StartInfo = $CliJsonProcessInfo
    [void]$CliJsonProcess.Start()
    $CliJsonStdout = $CliJsonProcess.StandardOutput.ReadToEnd()
    $CliJsonStderr = $CliJsonProcess.StandardError.ReadToEnd()
    $CliJsonProcess.WaitForExit()
    Assert-Equal $CliJsonProcess.ExitCode 0 "request CLI JSON-array mode should exit successfully. stderr=[$CliJsonStderr]"
    $CliJsonResult = $CliJsonStdout | ConvertFrom-Json
    $CliJsonTask = Get-Content -Raw -Encoding UTF8 (Join-Path $CliJsonResult.RequestDirectory 'task.json') | ConvertFrom-Json
    Assert-Equal $CliJsonTask.constraints.Count 2 'request CLI JSON-array mode constraints count'
    Assert-Equal $CliJsonTask.constraints[0] 'Keep compatibility' 'request CLI JSON-array mode first constraint'
    Assert-Equal $CliJsonTask.constraints[1] 'Avoid direct deletion' 'request CLI JSON-array mode second constraint'
    Assert-Equal $CliJsonTask.acceptance_criteria.Count 2 'request CLI JSON-array mode acceptance criteria count'
    Assert-Equal $CliJsonTask.acceptance_criteria[0] 'Tests pass' 'request CLI JSON-array mode first acceptance criterion'
    Assert-Equal $CliJsonTask.acceptance_criteria[1] 'Task JSON preserves arrays' 'request CLI JSON-array mode second acceptance criterion'
    Assert-Equal $CliJsonTask.review_scope.Count 2 'request CLI JSON-array mode review scope count'
    Assert-Equal $CliJsonTask.review_scope[0] 'scripts' 'request CLI JSON-array mode first review scope'
    Assert-Equal $CliJsonTask.review_scope[1] 'tests' 'request CLI JSON-array mode second review scope'

    $CliConflictRequestId = '20260612T164000Z-4d5e71'
    $PreviousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $CliConflictOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $CliScriptPath `
            -Repository $CliRepository `
            -TaskType implementation `
            -Objective 'Reject conflicting CLI values' `
            -Constraints 'single value' `
            -ConstraintsJson '[]' `
            -AcceptanceCriteria 'Tests pass' `
            -ReviewScope 'scripts' `
            -RequestId $CliConflictRequestId 2>&1
        $CliConflictExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }
    Assert-Equal $CliConflictExitCode 1 'request CLI should reject conflicting single-value and JSON-array parameters'
    Assert-True (@($CliConflictOutput).Count -gt 0) 'request CLI parameter conflict should report an error'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $CliRepository ".agent-bridge\$CliConflictRequestId"))) 'request CLI parameter conflict should not create a request'

    $JapaneseRepositoryName = [string][char[]]@(0x65E5, 0x672C, 0x8A9E, 0x30EA, 0x30DD, 0x30B8, 0x30C8, 0x30EA)
    $JapaneseObjective = [string][char[]]@(0x65E5, 0x672C, 0x8A9E, 0x306E, 0x76EE, 0x7684)
    $CliUtf8Repository = Join-Path $TempRoot $JapaneseRepositoryName
    New-Item -ItemType Directory -Path $CliUtf8Repository | Out-Null
    $CliUtf8RequestId = '20260612T170000Z-5a6b7c'
    $CliProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
    $CliProcessInfo.FileName = 'powershell.exe'
    $CliProcessInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$CliScriptPath`" -Repository `"$CliUtf8Repository`" -TaskType implementation -Objective `"$JapaneseObjective`" -Constraints compatibility -AcceptanceCriteria pass -ReviewScope scripts -RequestId $CliUtf8RequestId"
    $CliProcessInfo.UseShellExecute = $false
    $CliProcessInfo.CreateNoWindow = $true
    $CliProcessInfo.RedirectStandardOutput = $true
    $CliProcessInfo.RedirectStandardError = $true
    $CliProcess = New-Object System.Diagnostics.Process
    $CliProcess.StartInfo = $CliProcessInfo
    [void]$CliProcess.Start()
    $CliStdout = New-Object System.IO.MemoryStream
    $CliProcess.StandardOutput.BaseStream.CopyTo($CliStdout)
    $CliStderr = $CliProcess.StandardError.ReadToEnd()
    $CliProcess.WaitForExit()
    Assert-Equal $CliProcess.ExitCode 0 "UTF-8 request CLI should exit successfully. stderr=[$CliStderr]"
    $CliBytes = $CliStdout.ToArray()
    Assert-True (-not (($CliBytes.Length -ge 3) -and ($CliBytes[0] -eq 0xEF) -and ($CliBytes[1] -eq 0xBB) -and ($CliBytes[2] -eq 0xBF))) 'request CLI stdout should not have a UTF-8 BOM'
    $StrictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $CliUtf8Json = $StrictUtf8.GetString($CliBytes)
    $CliUtf8Result = $CliUtf8Json | ConvertFrom-Json
    Assert-Equal $CliUtf8Result.RequestId $CliUtf8RequestId 'UTF-8 request CLI JSON should contain the request ID'
    Assert-Equal $CliUtf8Result.RequestDirectory (Join-Path $CliUtf8Repository ".agent-bridge\$CliUtf8RequestId") 'UTF-8 request CLI JSON should preserve non-ASCII path characters'
    $CliUtf8Task = Get-Content -Raw -Encoding UTF8 (Join-Path $CliUtf8Result.RequestDirectory 'task.json') | ConvertFrom-Json
    Assert-Equal $CliUtf8Task.objective $JapaneseObjective 'UTF-8 request CLI should preserve the non-ASCII objective'

    # --- Task 5: Concise Codex Summaries Tests ---
    $SummaryRepository = Join-Path $TempRoot 'summary-repository'
    New-Item -ItemType Directory -Path $SummaryRepository | Out-Null

    # 1. Test implementation summary
    $ImplRequestId = '20260613T000001Z-aaaaaa'
    $ImplRequestDir = Join-Path $SummaryRepository ".agent-bridge\$ImplRequestId"
    $ImplRequest = New-AgentBridgeRequest `
        -Repository $SummaryRepository `
        -TaskType 'implementation' `
        -Objective 'Implement concise summaries' `
        -Constraints @() `
        -AcceptanceCriteria @() `
        -ReviewScope @() `
        -RequestId $ImplRequestId

    $ImplResult = New-ValidAgentBridgeResult -RequestId $ImplRequestId
    New-Item -ItemType Directory -Path (Join-Path $ImplRequestDir 'artifacts') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $ImplRequestDir 'result.json'), ($ImplResult | ConvertTo-Json -Depth 10), $Utf8WithoutBom)

    $ImplSummary = Read-AgentBridgeResult -RequestDirectory $ImplRequestDir
    Assert-Equal $ImplSummary.request_id $ImplRequestId 'impl summary request_id should match'
    Assert-Equal $ImplSummary.task_type 'implementation' 'impl summary task_type should be implementation'
    Assert-Equal $ImplSummary.status 'completed' 'impl summary status should match'
    Assert-Equal $ImplSummary.summary 'Implemented and verified the requested change' 'impl summary text should match'
    Assert-Equal $ImplSummary.verification.Count 1 'impl summary verification count should match'
    Assert-Equal $ImplSummary.risks.Count 1 'impl summary risks count should match'
    Assert-Equal $ImplSummary.changed_files.Count 1 'impl summary changed_files count should match'
    Assert-Equal $ImplSummary.decisions.Count 1 'impl summary decisions count should match'
    Assert-Equal $ImplSummary.review_focus.Count 1 'impl summary review_focus count should match'

    $ImplFields = $ImplSummary.PSObject.Properties.Name
    Assert-True ($ImplFields -contains 'changed_files') 'impl summary should contain changed_files'
    Assert-True ($ImplFields -contains 'decisions') 'impl summary should contain decisions'
    Assert-True ($ImplFields -contains 'review_focus') 'impl summary should contain review_focus'
    Assert-True ($ImplFields -notcontains 'findings') 'impl summary should omit findings'
    Assert-True ($ImplFields -notcontains 'artifacts') 'impl summary should omit artifacts'
    Assert-True ($ImplFields -notcontains 'schema_version') 'impl summary should omit schema_version'

    $ExpectedImplOrder = @('request_id', 'task_type', 'status', 'summary', 'verification', 'risks', 'changed_files', 'decisions', 'review_focus')
    Assert-Equal $ImplFields.Count $ExpectedImplOrder.Count 'impl summary field count should match exact ordered fields'
    for ($i = 0; $i -lt $ExpectedImplOrder.Count; $i++) {
        Assert-Equal $ImplFields[$i] $ExpectedImplOrder[$i] "impl summary field at index $i should be $($ExpectedImplOrder[$i])"
    }

    # 2. Test review summary
    $RevRequestId = '20260613T000002Z-bbbbbb'
    $RevRequestDir = Join-Path $SummaryRepository ".agent-bridge\$RevRequestId"
    $RevRequest = New-AgentBridgeRequest `
        -Repository $SummaryRepository `
        -TaskType 'review' `
        -Objective 'Review concise summaries' `
        -Constraints @() `
        -AcceptanceCriteria @() `
        -ReviewScope @() `
        -RequestId $RevRequestId

    $RevResult = New-ValidAgentBridgeResult -RequestId $RevRequestId
    New-Item -ItemType Directory -Path (Join-Path $RevRequestDir 'artifacts') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $RevRequestDir 'result.json'), ($RevResult | ConvertTo-Json -Depth 10), $Utf8WithoutBom)

    $RevSummary = Read-AgentBridgeResult -RequestDirectory $RevRequestDir
    Assert-Equal $RevSummary.request_id $RevRequestId 'review summary request_id should match'
    Assert-Equal $RevSummary.task_type 'review' 'review summary task_type should be review'
    Assert-Equal $RevSummary.findings.Count 1 'review summary findings count should match'

    $RevFields = $RevSummary.PSObject.Properties.Name
    Assert-True ($RevFields -contains 'findings') 'review summary should contain findings'
    Assert-True ($RevFields -notcontains 'changed_files') 'review summary should omit changed_files'
    Assert-True ($RevFields -notcontains 'decisions') 'review summary should omit decisions'
    Assert-True ($RevFields -notcontains 'review_focus') 'review summary should omit review_focus'
    Assert-True ($RevFields -notcontains 'artifacts') 'review summary should omit artifacts'

    $ExpectedRevOrder = @('request_id', 'task_type', 'status', 'summary', 'verification', 'risks', 'findings')
    Assert-Equal $RevFields.Count $ExpectedRevOrder.Count 'review summary field count should match exact ordered fields'
    for ($i = 0; $i -lt $ExpectedRevOrder.Count; $i++) {
        Assert-Equal $RevFields[$i] $ExpectedRevOrder[$i] "review summary field at index $i should be $($ExpectedRevOrder[$i])"
    }

    # 3. Test investigation summary
    $InvRequestId = '20260613T000003Z-cccccc'
    $InvRequestDir = Join-Path $SummaryRepository ".agent-bridge\$InvRequestId"
    $InvRequest = New-AgentBridgeRequest `
        -Repository $SummaryRepository `
        -TaskType 'investigation' `
        -Objective 'Investigate concise summaries' `
        -Constraints @() `
        -AcceptanceCriteria @() `
        -ReviewScope @() `
        -RequestId $InvRequestId

    $InvResult = New-ValidAgentBridgeResult -RequestId $InvRequestId
    New-Item -ItemType Directory -Path (Join-Path $InvRequestDir 'artifacts') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $InvRequestDir 'result.json'), ($InvResult | ConvertTo-Json -Depth 10), $Utf8WithoutBom)

    $InvSummary = Read-AgentBridgeResult -RequestDirectory $InvRequestDir
    Assert-Equal $InvSummary.request_id $InvRequestId 'investigation summary request_id should match'
    Assert-Equal $InvSummary.task_type 'investigation' 'investigation summary task_type should be investigation'
    Assert-Equal $InvSummary.decisions.Count 1 'investigation summary decisions count should match'
    Assert-Equal $InvSummary.artifacts.Count 1 'investigation summary artifacts count should match'

    $InvFields = $InvSummary.PSObject.Properties.Name
    Assert-True ($InvFields -contains 'decisions') 'investigation summary should contain decisions'
    Assert-True ($InvFields -contains 'artifacts') 'investigation summary should contain artifacts'
    Assert-True ($InvFields -notcontains 'changed_files') 'investigation summary should omit changed_files'
    Assert-True ($InvFields -notcontains 'findings') 'investigation summary should omit findings'
    Assert-True ($InvFields -notcontains 'review_focus') 'investigation summary should omit review_focus'

    $ExpectedInvOrder = @('request_id', 'task_type', 'status', 'summary', 'verification', 'risks', 'decisions', 'artifacts')
    Assert-Equal $InvFields.Count $ExpectedInvOrder.Count 'investigation summary field count should match exact ordered fields'
    for ($i = 0; $i -lt $ExpectedInvOrder.Count; $i++) {
        Assert-Equal $InvFields[$i] $ExpectedInvOrder[$i] "investigation summary field at index $i should be $($ExpectedInvOrder[$i])"
    }

    # 4. Test throws when result is missing (Timeout 0)
    $MissingResultRequestId = '20260613T000004Z-dddddd'
    $MissingResultRequestDir = Join-Path $SummaryRepository ".agent-bridge\$MissingResultRequestId"
    $MissingResultRequest = New-AgentBridgeRequest `
        -Repository $SummaryRepository `
        -TaskType 'implementation' `
        -Objective 'Test missing result' `
        -Constraints @() `
        -AcceptanceCriteria @() `
        -ReviewScope @() `
        -RequestId $MissingResultRequestId
    Assert-ThrowsLike { Read-AgentBridgeResult -RequestDirectory $MissingResultRequestDir } 'Timed out waiting for result.json:*' 'Read-AgentBridgeResult should throw immediately if result is missing'

    # 5. Test CLI wrapper Read-AgentBridgeResult.ps1
    $CliScriptPath = Join-Path $BridgeRoot 'Read-AgentBridgeResult.ps1'
    $CliProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
    $CliProcessInfo.FileName = 'powershell.exe'
    $CliProcessInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$CliScriptPath`" -RequestDirectory `"$ImplRequestDir`""
    $CliProcessInfo.UseShellExecute = $false
    $CliProcessInfo.CreateNoWindow = $true
    $CliProcessInfo.RedirectStandardOutput = $true
    $CliProcessInfo.RedirectStandardError = $true
    $CliProcess = New-Object System.Diagnostics.Process
    $CliProcess.StartInfo = $CliProcessInfo
    [void]$CliProcess.Start()
    $CliStdout = New-Object System.IO.MemoryStream
    $CliProcess.StandardOutput.BaseStream.CopyTo($CliStdout)
    $CliStderr = $CliProcess.StandardError.ReadToEnd()
    $CliProcess.WaitForExit()
    Assert-Equal $CliProcess.ExitCode 0 "Read-AgentBridgeResult CLI should exit successfully. stderr=[$CliStderr]"
    $CliBytes = $CliStdout.ToArray()
    Assert-True (-not (($CliBytes.Length -ge 3) -and ($CliBytes[0] -eq 0xEF) -and ($CliBytes[1] -eq 0xBB) -and ($CliBytes[2] -eq 0xBF))) 'Read-AgentBridgeResult CLI stdout should not have a UTF-8 BOM'
    $StrictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $CliUtf8Json = $StrictUtf8.GetString($CliBytes)
    $CliUtf8Result = $CliUtf8Json | ConvertFrom-Json
    Assert-Equal $CliUtf8Result.request_id $ImplRequestId 'UTF-8 summary CLI JSON should contain the request ID'
    Assert-Equal $CliUtf8Result.task_type 'implementation' 'UTF-8 summary CLI JSON should have correct task type'

    # 6. Test Move-ExpiredAgentBridgeRequest
    $CleanupRepository = Join-Path $TempRoot 'cleanup-repo'
    New-Item -ItemType Directory -Path $CleanupRepository -Force | Out-Null
    $CleanupBridgeDir = Join-Path $CleanupRepository '.agent-bridge'
    New-Item -ItemType Directory -Path $CleanupBridgeDir -Force | Out-Null

    # Create directories
    $ExpiredRequestId1 = '20260601T000000Z-111111'
    $ExpiredDir1 = Join-Path $CleanupBridgeDir $ExpiredRequestId1
    New-Item -ItemType Directory -Path $ExpiredDir1 -Force | Out-Null

    $ExpiredRequestId2 = '20260602T123456Z-abcdef'
    $ExpiredDir2 = Join-Path $CleanupBridgeDir $ExpiredRequestId2
    New-Item -ItemType Directory -Path $ExpiredDir2 -Force | Out-Null

    # Fresh request (less than 7 days, e.g. 1 day ago)
    $FreshRequestId1 = ([DateTime]::UtcNow.AddDays(-1)).ToString('yyyyMMddTHHmmssZ') + '-222222'
    $FreshDir1 = Join-Path $CleanupBridgeDir $FreshRequestId1
    New-Item -ItemType Directory -Path $FreshDir1 -Force | Out-Null

    # Unrelated directory
    $UnrelatedDir = Join-Path $CleanupBridgeDir 'unrelated-dir'
    New-Item -ItemType Directory -Path $UnrelatedDir -Force | Out-Null

    # Invalid request ID pattern directories
    $InvalidPatternDir1 = Join-Path $CleanupBridgeDir '20260601T000000Z-11111'
    New-Item -ItemType Directory -Path $InvalidPatternDir1 -Force | Out-Null

    $InvalidPatternDir2 = Join-Path $CleanupBridgeDir '20260601T000000Z-1111111'
    New-Item -ItemType Directory -Path $InvalidPatternDir2 -Force | Out-Null

    $InvalidPatternDir3 = Join-Path $CleanupBridgeDir '20260601T000000Z-aaaaaG'
    New-Item -ItemType Directory -Path $InvalidPatternDir3 -Force | Out-Null

    # File with a valid name
    $FileWithValidName = Join-Path $CleanupBridgeDir '20260601T000000Z-333333'
    [System.IO.File]::WriteAllText($FileWithValidName, 'dummy')

    # Deterministic non-executing AST contract test for Move-AgentBridgeDirectoryToRecycleBin
    $Func = Get-Command Move-AgentBridgeDirectoryToRecycleBin -ErrorAction Stop
    $Ast = $Func.ScriptBlock.Ast

    $AstState = @{
        DeleteDirectoryCalled = $false
        SendToRecycleBinPassed = $false
        HasDirectDeletion = $false
    }

    $null = $Ast.FindAll({
        param($node)
        # 1. Prohibit standard commands/aliases/binaries for deletion
        if ($node -is [System.Management.Automation.Language.CommandAst]) {
            $CmdName = $node.GetCommandName()
            if ($CmdName -in @('Remove-Item', 'ri', 'rm', 'del', 'erase', 'rd', 'rmdir')) {
                $AstState.HasDirectDeletion = $true
            }
        }
        # 2. Prohibit direct .NET deletion method/member calls (except FileSystem::DeleteDirectory)
        if ($node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -or $node -is [System.Management.Automation.Language.MemberExpressionAst]) {
            $MemberName = $node.Member.Extent.Text
            if ($MemberName -eq 'Delete' -or $MemberName -eq 'DeleteDirectory') {
                $ExpressionText = $node.Expression.Extent.Text
                $IsVBFileSystem = ($ExpressionText -like '*Microsoft.VisualBasic.FileIO.FileSystem*')
                $IsDeleteDirectory = ($MemberName -eq 'DeleteDirectory')
                if (-not ($IsVBFileSystem -and $IsDeleteDirectory)) {
                    $AstState.HasDirectDeletion = $true
                }
            }
        }
        # 3. Prove Microsoft.VisualBasic.FileIO.FileSystem.DeleteDirectory is called with RecycleOption.SendToRecycleBin
        if ($node -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
            $ExpressionText = $node.Expression.Extent.Text
            $MemberText = $node.Member.Extent.Text
            if ($ExpressionText -like '*Microsoft.VisualBasic.FileIO.FileSystem*' -and $MemberText -eq 'DeleteDirectory') {
                $AstState.DeleteDirectoryCalled = $true
                $Arguments = $node.Arguments
                if ($Arguments.Count -ge 3) {
                    $RecycleArg = $Arguments[2].Extent.Text
                    if ($RecycleArg -like '*RecycleOption*SendToRecycleBin*') {
                        $AstState.SendToRecycleBinPassed = $true
                    }
                }
            }
        }
        return $false # Keep searching
    }, $true)

    Assert-True $AstState.DeleteDirectoryCalled 'AST contract test: DeleteDirectory must be called'
    Assert-True $AstState.SendToRecycleBinPassed 'AST contract test: SendToRecycleBin must be passed'
    Assert-True (-not $AstState.HasDirectDeletion) 'AST contract test: direct deletion operations must be absent'

    # Regression test: Move-ExpiredAgentBridgeRequest rejects negative AgeDays and does not invoke mover
    $NegativeAgeMoverCalls = New-Object System.Collections.Generic.List[string]
    $NegativeAgeMover = {
        param([string]$Path)
        [void]$NegativeAgeMoverCalls.Add($Path)
    }.GetNewClosure()

    $ExceptionThrown = $false
    try {
        $null = Move-ExpiredAgentBridgeRequest -Repository $CleanupRepository -AgeDays -1 -Mover $NegativeAgeMover
    }
    catch {
        $ExceptionThrown = $true
        Assert-True ($_ -like '*AgeDays cannot be less than zero*') 'Exception message should indicate negative AgeDays'
    }

    Assert-True $ExceptionThrown 'An exception should be thrown for negative AgeDays'
    Assert-True ($NegativeAgeMoverCalls.Count -eq 0) 'The mover must not be called when AgeDays is negative'

    # Mock mover for checking Move-ExpiredAgentBridgeRequest
    $MovedPaths = New-Object System.Collections.Generic.List[string]
    $TestMover = {
        param([string]$Path)
        [void]$MovedPaths.Add($Path)
    }.GetNewClosure()

    # Run cleanup with mock mover and 7 days age limit
    $Recycled = Move-ExpiredAgentBridgeRequest -Repository $CleanupRepository -AgeDays 7 -Mover $TestMover

    # Assertions
    Assert-Equal $MovedPaths.Count 2 'Two expired directories should have been moved'
    Assert-True ($MovedPaths -contains $ExpiredDir1) 'ExpiredDir1 should be moved'
    Assert-True ($MovedPaths -contains $ExpiredDir2) 'ExpiredDir2 should be moved'
    Assert-True ($MovedPaths -notcontains $FreshDir1) 'FreshDir1 should not be moved'
    Assert-True ($MovedPaths -notcontains $UnrelatedDir) 'UnrelatedDir should not be moved'
    Assert-True ($MovedPaths -notcontains $InvalidPatternDir1) 'InvalidPatternDir1 should not be moved'
    Assert-True ($MovedPaths -notcontains $InvalidPatternDir2) 'InvalidPatternDir2 should not be moved'
    Assert-True ($MovedPaths -notcontains $InvalidPatternDir3) 'InvalidPatternDir3 should not be moved'
    Assert-True ($MovedPaths -notcontains $FileWithValidName) 'FileWithValidName should not be moved'

    # Test CLI wrapper Move-ExpiredAgentBridgeRequest.ps1
    $ExpiredRequestId3 = '20260603T000000Z-333333'
    $ExpiredDir3 = Join-Path $CleanupBridgeDir $ExpiredRequestId3
    New-Item -ItemType Directory -Path $ExpiredDir3 -Force | Out-Null

    $CliScriptPath = Join-Path $BridgeRoot 'Move-ExpiredAgentBridgeRequest.ps1'
    $CliProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
    $CliProcessInfo.FileName = 'powershell.exe'
    $CliProcessInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$CliScriptPath`" -Repository `"$CleanupRepository`" -AgeDays 7"
    $CliProcessInfo.UseShellExecute = $false
    $CliProcessInfo.CreateNoWindow = $true
    $CliProcessInfo.RedirectStandardOutput = $true
    $CliProcessInfo.RedirectStandardError = $true
    $CliProcess = New-Object System.Diagnostics.Process
    $CliProcess.StartInfo = $CliProcessInfo
    [void]$CliProcess.Start()
    $CliStdout = New-Object System.IO.MemoryStream
    $CliProcess.StandardOutput.BaseStream.CopyTo($CliStdout)
    $CliStderr = $CliProcess.StandardError.ReadToEnd()
    $CliProcess.WaitForExit()
    Assert-Equal $CliProcess.ExitCode 0 "Move-ExpiredAgentBridgeRequest CLI should exit successfully. stderr=[$CliStderr]"
    $CliBytes = $CliStdout.ToArray()
    Assert-True (-not (($CliBytes.Length -ge 3) -and ($CliBytes[0] -eq 0xEF) -and ($CliBytes[1] -eq 0xBB) -and ($CliBytes[2] -eq 0xBF))) 'Move-ExpiredAgentBridgeRequest CLI stdout should not have a UTF-8 BOM'
    $StrictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $CliUtf8Json = $StrictUtf8.GetString($CliBytes)
    $CliUtf8Result = $CliUtf8Json | ConvertFrom-Json

    # Assert that $ExpiredDir3 was recycled and returned in the CLI output
    Assert-True (-not (Test-Path -LiteralPath $ExpiredDir3)) 'ExpiredDir3 should be recycled'
    Assert-True ($CliUtf8Result -contains $ExpiredDir3) 'CLI output JSON should contain ExpiredDir3'

    # 7. Comprehensive CLI smoke tests (Task 7 TDD Failing Phase)
    $SmokeRepo = Join-Path $TempRoot 'smoke-repo'
    New-Item -ItemType Directory -Path $SmokeRepo -Force | Out-Null
    $null = & git init $SmokeRepo

    $NewRequestCli = Join-Path $BridgeRoot 'New-AgentBridgeRequest.ps1'
    $WaitResultCli = Join-Path $BridgeRoot 'Wait-AgentBridgeResult.ps1'
    $ReadResultCli = Join-Path $BridgeRoot 'Read-AgentBridgeResult.ps1'
    $MoveExpiredCli = Join-Path $BridgeRoot 'Move-ExpiredAgentBridgeRequest.ps1'

    $RunCli = {
        param([string]$ScriptPath, [string]$Arguments)
        $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
        $ProcessInfo.FileName = 'powershell.exe'
        $ProcessInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" $Arguments"
        $ProcessInfo.UseShellExecute = $false
        $ProcessInfo.CreateNoWindow = $true
        $ProcessInfo.RedirectStandardOutput = $true
        $ProcessInfo.RedirectStandardError = $true
        $Process = New-Object System.Diagnostics.Process
        $Process.StartInfo = $ProcessInfo
        [void]$Process.Start()
        $StdoutStream = New-Object System.IO.MemoryStream
        $Process.StandardOutput.BaseStream.CopyTo($StdoutStream)
        $Stderr = $Process.StandardError.ReadToEnd()
        $Process.WaitForExit()
        $StdoutBytes = $StdoutStream.ToArray()
        if ($StdoutBytes.Length -ge 3 -and $StdoutBytes[0] -eq 0xEF -and $StdoutBytes[1] -eq 0xBB -and $StdoutBytes[2] -eq 0xBF) {
            throw "BOM detected in stdout of $ScriptPath"
        }
        $StrictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
        $Stdout = $StrictUtf8.GetString($StdoutBytes)
        return [PSCustomObject]@{
            ExitCode = $Process.ExitCode
            Stdout = $Stdout
            Stderr = $Stderr
        }
    }

    # Step A: Request creation smoke test
    $NewRequestArgs = "-Repository `"$SmokeRepo`" -TaskType `"investigation`" -Objective `"Smoke test objective`" -ConstraintsJson `"`"[]`"`" -AcceptanceCriteriaJson `"`"[]`"`" -ReviewScopeJson `"`"[]`"`""
    $NewResult = $RunCli.Invoke($NewRequestCli, $NewRequestArgs)
    Assert-Equal $NewResult.ExitCode 0 "New-AgentBridgeRequest.ps1 should exit successfully. stderr=[$($NewResult.Stderr)]"
    $NewJson = $NewResult.Stdout | ConvertFrom-Json
    Assert-True ($NewJson.RequestId -match '^[0-9]{8}T[0-9]{6}Z-[a-f0-9]{6}$') "Request ID should match format. RequestId=[$($NewJson.RequestId)], Stdout=[$($NewResult.Stdout)], Stderr=[$($NewResult.Stderr)]"
    Assert-True (Test-Path -LiteralPath $NewJson.RequestDirectory) "Request directory should exist. RequestDirectory=[$($NewJson.RequestDirectory)]"

    # Step B: Waiting (timeout first, when no result.json is present)
    $WaitTimeoutArgs = "-RequestDirectory `"$($NewJson.RequestDirectory)`" -TimeoutSeconds 1 -PollMilliseconds 100"
    $WaitTimeoutResult = $RunCli.Invoke($WaitResultCli, $WaitTimeoutArgs)
    Assert-GreaterThan $WaitTimeoutResult.ExitCode 0 "Wait-AgentBridgeResult should exit with non-zero on timeout"

    # Step C: Write a valid result and wait successfully
    $ValidResultObj = New-ValidAgentBridgeResult -RequestId $NewJson.RequestId
    $ArtifactsDir = Join-Path $NewJson.RequestDirectory 'artifacts'
    New-Item -ItemType Directory -Path $ArtifactsDir -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $NewJson.RequestDirectory 'result.json'), ($ValidResultObj | ConvertTo-Json -Depth 10), $Utf8WithoutBom)

    $WaitSuccessArgs = "-RequestDirectory `"$($NewJson.RequestDirectory)`" -TimeoutSeconds 5"
    $WaitSuccessResult = $RunCli.Invoke($WaitResultCli, $WaitSuccessArgs)
    Assert-Equal $WaitSuccessResult.ExitCode 0 "Wait-AgentBridgeResult should succeed now. stderr=[$($WaitSuccessResult.Stderr)]"
    $WaitJson = $WaitSuccessResult.Stdout | ConvertFrom-Json
    Assert-Equal $WaitJson.request_id $NewJson.RequestId "Wait result ID should match"

    # Step D: Concise reading
    $ReadArgs = "-RequestDirectory `"$($NewJson.RequestDirectory)`""
    $ReadResult = $RunCli.Invoke($ReadResultCli, $ReadArgs)
    Assert-Equal $ReadResult.ExitCode 0 "Read-AgentBridgeResult should succeed. stderr=[$($ReadResult.Stderr)]"
    $ReadJson = $ReadResult.Stdout | ConvertFrom-Json
    Assert-Equal $ReadJson.request_id $NewJson.RequestId "Read result ID should match"
    $ReadFields = $ReadJson.PSObject.Properties.Name
    Assert-True ($ReadFields -contains 'decisions') "Read result should contain decisions"
    Assert-True ($ReadFields -contains 'artifacts') "Read result should contain artifacts"
    Assert-True ($ReadFields -notcontains 'changed_files') "Read result should not contain changed_files"

    # Step E: No-op cleanup (AgeDays = 7, request is new, so it shouldn't be cleaned up)
    $MoveArgs = "-Repository `"$SmokeRepo`" -AgeDays 7"
    $MoveResult = $RunCli.Invoke($MoveExpiredCli, $MoveArgs)
    Assert-Equal $MoveResult.ExitCode 0 "Move-ExpiredAgentBridgeRequest should succeed. stderr=[$($MoveResult.Stderr)]"
    $MoveJson = $MoveResult.Stdout | ConvertFrom-Json
    $MovedCount = if ($MoveJson -eq $null) { 0 } else { @($MoveJson).Count }
    Assert-Equal $MovedCount 0 "No directories should be moved (no-op cleanup). MoveJson=[$($MoveResult.Stdout)]"
    Assert-True (Test-Path -LiteralPath $NewJson.RequestDirectory) "Request directory should still exist"
}
finally {
    if (Test-Path -LiteralPath $TempRoot) {
        Move-Item -LiteralPath $TempRoot -Destination $TempTrash
    }
}
