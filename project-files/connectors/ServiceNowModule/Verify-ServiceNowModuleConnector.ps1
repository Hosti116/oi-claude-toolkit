<#
    Offline verification of the ServiceNow module connector: static checks on the generated XML, contract checks on
    the module, and runtime checks against a local mock of the Table API (ServiceNowMock.ps1). No real instance.
    The connector functions are loaded FROM THE XML, so the test runs the same code as Identity Manager.
    Run on both engines:
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Verify-ServiceNowModuleConnector.ps1
      pwsh -NoProfile -File .\Verify-ServiceNowModuleConnector.ps1
    Exit code 1 if any check fails.
#>
param([int]$Port = 18091)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$xmlPath = Join-Path $here 'ServiceNowModuleConnector.xml'
$modulePath = Join-Path $here 'ServiceNowTableApi.psm1'
$baseUrl = "http://localhost:$Port"
$script:ok = 0; $script:fail = 0
function Check([string]$Name, [bool]$Condition) { if ($Condition) { $script:ok++; "PASS $Name" } else { $script:fail++; "FAIL $Name" } }
# ServiceNow JSON error body must reach the exception message (the status text alone must not satisfy the check)
function Test-ErrorBody([string]$Message, [string]$Text) { $Message -match ('"message":\s*"' + [regex]::Escape($Text) + '"') }
function Get-ErrorMessage([scriptblock]$Action) { try { & $Action | Out-Null; '' } catch { $_.Exception.Message } }
"Engine: PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"

#region static checks
"--- static"
$engine = (Get-Process -Id $PID).Path
& $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'New-ConnectorXmlFromModule.ps1') -Check | Out-Null
Check 'XML up to date with the module' ($LASTEXITCODE -eq 0)

$withoutBom = @(Get-ChildItem -Path $here -File | Where-Object { $_.Extension -in '.ps1', '.psm1' } | Where-Object {
        $bytes = [IO.File]::ReadAllBytes($_.FullName)
        -not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) })
Check "scripts UTF-8 with BOM $(($withoutBom | ForEach-Object { $_.Name }) -join ',')" ($withoutBom.Count -eq 0)

$def = [xml](Get-Content -LiteralPath $xmlPath -Raw -Encoding UTF8)
$root = $def.PowershellConnectorDefinition
Check 'XML well-formed' ($null -ne $root)

$parameterNames = @{}
$parseErrors = 0
foreach ($cc in $root.Initialization.CustomCommands.CustomCommand)
{
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($cc.'#cdata-section', [ref]$tokens, [ref]$errors)
    $parseErrors += @($errors).Count
    $names = @()
    if ($ast.ParamBlock) { $names = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }) }
    $parameterNames[$cc.Name] = $names
}
Check 'every CDATA parses' ($parseErrors -eq 0)

$referenced = @($def.SelectNodes('//@Command | //@CommandResultOf | //@ToCommand') | ForEach-Object { $_.Value } | Sort-Object -Unique)
$unknown = @($referenced | Where-Object { -not $parameterNames.ContainsKey($_) })
Check "every referenced command is a custom command $($unknown -join ',')" ($unknown.Count -eq 0)

$badMaps = @($def.SelectNodes('//Map') | Where-Object { $parameterNames[$_.ToCommand] -notcontains $_.Parameter } | ForEach-Object { "$($_.ToCommand)/$($_.Parameter)" })
Check "every Map Parameter is a real parameter $($badMaps -join ',')" ($badMaps.Count -eq 0)

$connectItem = $root.Initialization.EnvironmentInitialization.Connect.CommandSequence.Item
$connectionParameters = @($root.ConnectionParameters.ConnectionParameter | ForEach-Object { $_.Name })
$badConnect = @($connectItem.SetParameter | Where-Object { $connectionParameters -notcontains $_.Value -or $parameterNames[$connectItem.Command] -notcontains $_.Param })
Check 'Connect parameters match connection parameters' ($badConnect.Count -eq 0)

$classes = @($root.Schema.Class)
$badClasses = @($classes | Where-Object { -not $_.SelectSingleNode('Properties/Property[@IsUniqueKey="true"]') -or -not $_.SelectSingleNode('Properties/Property[@IsDisplay="true"]') } | ForEach-Object { $_.Name })
Check "every class has a key and a display property $($badClasses -join ',')" ($badClasses.Count -eq 0)
Check 'no Description on Class/Property, no IsAutofill (rejected by the 9.2 wizard)' ($def.SelectNodes('//Class[@Description] | //Property[@Description] | //*[@IsAutofill]').Count -eq 0)
Check 'PredefinedCommands empty' (-not $root.Initialization.PredefinedCommands.HasChildNodes)
#endregion

#region contract checks
"--- contract"
$contract = @('Get-OneIMConnectorManifest', 'Connect-OneIMConnectorSession', 'Disconnect-OneIMConnectorSession',
    'Get-OneIMConnectorObject', 'New-OneIMConnectorObject', 'Set-OneIMConnectorObject', 'Remove-OneIMConnectorObject')
$probe = Import-Module -Name $modulePath -Force -PassThru -DisableNameChecking
$exported = @($probe.ExportedFunctions.Keys)
$manifest = Get-OneIMConnectorManifest
Remove-Module -ModuleInfo $probe -Force
Check 'module exports exactly the contract functions' ((@(Compare-Object $contract $exported)).Count -eq 0)
Check 'manifest ContractVersion 1' ($manifest.ContractVersion -eq 1)
Check 'manifest classes = XML classes' ((@(Compare-Object @($manifest.Classes | ForEach-Object { $_.Name }) @($classes | ForEach-Object { $_.Name }))).Count -eq 0)
#endregion

#region runtime checks against the mock
"--- runtime (mock $baseUrl)"
. (Join-Path $here 'ServiceNowMock.ps1')
$runspace = [runspacefactory]::CreateRunspace(); $runspace.Open()
$mock = [powershell]::Create(); $mock.Runspace = $runspace
[void]$mock.AddScript($ServiceNowMockScript).AddArgument($Port)
$mockHandle = $mock.BeginInvoke()
Start-Sleep -Seconds 2
$mockHeaders = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('admin:secret')) }   # test-only mock value
function Get-MockRequestCount { (Invoke-RestMethod -Uri "$baseUrl/stats" -Headers $mockHeaders -UseBasicParsing).requests }
$tempFolder = Join-Path ([IO.Path]::GetTempPath()) "snow-module-verify-$PID"
$null = New-Item -ItemType Directory -Path $tempFolder -Force

try
{
    foreach ($cc in $root.Initialization.CustomCommands.CustomCommand)
    {
        Set-Item -Path "function:global:$($cc.Name)" -Value ([scriptblock]::Create($cc.'#cdata-section'))
    }
    $password = ConvertTo-SecureString 'secret' -AsPlainText -Force   # test-only mock value
    $connect = @{ InstanceUrl = $baseUrl; Username = 'admin'; Password = $password; Options = 'PageSize=10'; ModuleLocation = $modulePath }

    # module location and contract
    $message = Get-ErrorMessage { $c = $connect.Clone(); $c.ModuleLocation = 'C:\nowhere\missing'; Connect-OneIMServiceNow @c 6>$null }
    Check 'missing module -> clear error' ($message -match 'module not found')

    $moduleText = [IO.File]::ReadAllText($modulePath)
    $fieldLine = '(New-SnowProperty head_count -Type Int)'
    $breakingFolder = Join-Path $tempFolder 'breaking'; $null = New-Item -ItemType Directory -Path $breakingFolder -Force
    $breakingModule = Join-Path $breakingFolder 'ServiceNowTableApi.psm1'
    [IO.File]::WriteAllText($breakingModule, $moduleText.Replace($fieldLine, ''), (New-Object Text.UTF8Encoding $true))
    $message = Get-ErrorMessage { $c = $connect.Clone(); $c.ModuleLocation = $breakingModule; Connect-OneIMServiceNow @c 6>$null }
    Check 'module with a removed property -> connect refused' ($message -match 'not compatible' -and $message -match 'Department\.head_count removed')

    $addingFolder = Join-Path $tempFolder 'adding'; $null = New-Item -ItemType Directory -Path $addingFolder -Force
    $addingModule = Join-Path $addingFolder 'ServiceNowTableApi.psm1'
    [IO.File]::WriteAllText($addingModule, $moduleText.Replace($fieldLine, "$fieldLine`r`n        (New-SnowProperty u_extra_field)"), (New-Object Text.UTF8Encoding $true))
    $c = $connect.Clone(); $c.ModuleLocation = $addingModule
    $warnings = @(Connect-OneIMServiceNow @c 3>&1 6>$null | Where-Object { $_ -is [Management.Automation.WarningRecord] })
    Check 'module with a new property -> connect ok with warning' (($warnings | Out-String) -match 'Department\.u_extra_field')
    Disconnect-OneIMServiceNow 6>$null

    # connection parameters
    $message = Get-ErrorMessage { $c = $connect.Clone(); $c.Password = (ConvertTo-SecureString 'wrong' -AsPlainText -Force); Connect-OneIMServiceNow @c 6>$null 3>$null }
    Check 'bad credentials throw HTTP 401' ($message -match 'HTTP 401')
    Check 'HTTP 401 error body read' (Test-ErrorBody $message 'User Not Authenticated')
    $message = Get-ErrorMessage { $c = $connect.Clone(); $c.InstanceUrl = ''; Connect-OneIMServiceNow @c 6>$null }
    Check 'empty InstanceUrl refused' ($message -match 'InstanceUrl is mandatory')
    $message = Get-ErrorMessage { $c = $connect.Clone(); $c.InstanceUrl = 'http://instance.example.com'; Connect-OneIMServiceNow @c 6>$null }
    Check 'non-https InstanceUrl refused' ($message -match 'https')
    $message = Get-ErrorMessage { $c = $connect.Clone(); $c.Options = 'PageSize=0'; Connect-OneIMServiceNow @c 6>$null }
    Check 'out-of-range option refused' ($message -match 'PageSize must be an integer')
    $message = Get-ErrorMessage { $c = $connect.Clone(); $c.Options = 'Foo=1'; Connect-OneIMServiceNow @c 6>$null }
    Check 'unknown option refused' ($message -match "unknown option 'Foo'")
    $message = Get-ErrorMessage { $c = $connect.Clone(); $c.Options = 'AuthType=OAuth'; Connect-OneIMServiceNow @c 6>$null }
    Check 'unsupported AuthType refused' ($message -match 'not supported')

    # guide convention: ModuleLocation without the .psm1 suffix
    $c = $connect.Clone(); $c.ModuleLocation = $modulePath -replace '\.psm1$', ''
    $output = @(Connect-OneIMServiceNow @c 6>$null)
    Check 'connect ok, emits nothing' ($output.Count -eq 0)
    Check 'module functions visible to the custom commands' ($null -ne (Get-Command Get-OneIMConnectorObject -ErrorAction SilentlyContinue))

    # listing: 25 records, page 10, first list call throttled (429)
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $departments = @(Get-OneIMServiceNowDepartment 6>$null 3>$null)
    Check 'listing pages through 25 records' ($departments.Count -eq 25)
    Check '429 retried with backoff (>=2s)' ($watch.Elapsed.TotalSeconds -ge 2)
    Check 'DateTime typed UTC' ($departments[0].sys_updated_on -is [datetime] -and $departments[0].sys_updated_on.Kind -eq 'Utc' -and $departments[0].sys_updated_on.Year -eq 2026)
    Check 'Int typed' ($departments[2].head_count -is [int] -and $departments[2].head_count -eq 3)
    Check 'missing field -> null' ($null -eq $departments[0].code)
    Check 'empty field -> null' ($null -eq $departments[0].description)
    $users = @(Get-OneIMServiceNowUser 6>$null)
    Check 'Bool typed' ($users[0].active -is [bool] -and $users[0].active -and -not $users[2].active)

    # per-object reload after the listing: served from the cache, no extra request
    $before = Get-MockRequestCount
    $one = Get-OneIMServiceNowDepartment -sys_id $departments[2].sys_id 6>$null
    Check 'reload after listing served from cache' ($one.name -eq 'Dept 3' -and (Get-MockRequestCount) -eq $before)
    $message = Get-ErrorMessage { Get-OneIMServiceNowDepartment -sys_id '../sys_user' 6>$null }
    Check 'invalid sys_id refused' ($message -match 'not a valid sys_id')

    # create (accented name: UTF-8 body on 5.1)
    $accented = 'Test ' + [char]0x00E0 + [char]0x00E8 + [char]0x00F9
    $new = New-OneIMServiceNowDepartment -name $accented -description 'd' -head_count 7 6>$null
    Check 'create returns sys_id' ("$($new.sys_id)".Length -eq 32)
    Check 'create returns typed fields' ($new.name -eq $accented -and $new.head_count -eq 7)

    $message = Get-ErrorMessage { New-OneIMServiceNowDepartment -description 'no name' 6>$null }
    Check 'insert without a mandatory property refused' ($message -match 'mandatory properties missing for Insert: name')

    # partial update, clear, output hygiene
    $output = @(Set-OneIMServiceNowDepartment -sys_id $new.sys_id -description 'changed' 6>$null)
    Check 'Set emits nothing' ($output.Count -eq 0)
    $updated = Get-OneIMServiceNowDepartment -sys_id $new.sys_id 6>$null
    Check 'update changes only bound fields' ($updated.description -eq 'changed' -and $updated.name -eq $accented -and $updated.head_count -eq 7)
    Set-OneIMServiceNowDepartment -sys_id $new.sys_id -description $null 6>$null
    Check 'null clears the field' ($null -eq (Get-OneIMServiceNowDepartment -sys_id $new.sys_id 6>$null).description)
    Set-OneIMServiceNowDepartment -sys_id $departments[4].sys_id -name 'Renamed' 6>$null
    Check 'update invalidates the listing cache' ((Get-OneIMServiceNowDepartment -sys_id $departments[4].sys_id 6>$null).name -eq 'Renamed')
    $message = Get-ErrorMessage { Set-OneIMConnectorObject -Class Department -Key $new.sys_id -Values @{ sys_updated_on = (Get-Date) } 6>$null }
    Check 'write to a Read property refused' ($message -match 'sys_updated_on.*Read')

    # membership row (InsertOnly references)
    $member = New-OneIMServiceNowGroupMember -user $users[0].sys_id -group ('{0:x32}' -f 77) 6>$null
    Check 'membership created with references' ($member.user -eq $users[0].sys_id -and "$($member.sys_id)".Length -eq 32)

    # delete twice, then read
    $output = @(Remove-OneIMServiceNowDepartment -sys_id $new.sys_id 6>$null)
    Check 'Remove emits nothing' ($output.Count -eq 0)
    $message = Get-ErrorMessage { Remove-OneIMServiceNowDepartment -sys_id $new.sys_id 6>$null 3>$null }
    Check 'second delete tolerated' ($message -eq '')
    $message = Get-ErrorMessage { Get-OneIMServiceNowDepartment -sys_id $new.sys_id 6>$null }
    Check 'get deleted -> HTTP 404' ($message -match 'HTTP 404')
    Check 'HTTP 404 error body read' (Test-ErrorBody $message 'No Record found')

    Disconnect-OneIMServiceNow 6>$null
    $message = Get-ErrorMessage { Get-OneIMServiceNowDepartment 6>$null }
    Check 'disconnect closes the session' ($message -match 'not connected')
}
finally
{
    try { Invoke-RestMethod -Uri "$baseUrl/shutdown" -Headers $mockHeaders -UseBasicParsing | Out-Null } catch { Write-Warning "mock shutdown: $($_.Exception.Message)" }
    $null = $mockHandle.AsyncWaitHandle.WaitOne(5000)
    $mock.Dispose(); $runspace.Dispose()
    Get-Module ServiceNowTableApi | Remove-Module -Force
    Remove-Item -LiteralPath $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
}
#endregion

"`n$($script:ok) passed, $($script:fail) failed"
if ($script:fail -gt 0) { exit 1 }
