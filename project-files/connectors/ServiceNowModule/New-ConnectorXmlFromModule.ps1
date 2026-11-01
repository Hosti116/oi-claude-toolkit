<#
    Generates the PowerShell connector definition XML from a connector module that implements contract v1 (CONTRACT.md).
    The module is the source of truth (logic + manifest); the XML is GENERATED and never edited by hand.
    Not system specific: works with any module that exports the contract functions.

    Runs on Windows PowerShell 5.1 and PowerShell 7. Offline: it only imports the module and reads its manifest.

    Examples
      .\New-ConnectorXmlFromModule.ps1                        # ServiceNowTableApi.psm1 -> ServiceNowModuleConnector.xml
      .\New-ConnectorXmlFromModule.ps1 -Check                 # exit 1 if the XML is not up to date with the module
      .\New-ConnectorXmlFromModule.ps1 -ModulePath D:\drop\ServiceNowTableApi.psm1 -OutFile .\new.xml
#>
[CmdletBinding()]
param(
    # defaults resolved below: Windows PowerShell 5.1 leaves $PSScriptRoot empty in parameter defaults
    [string]$ModulePath,
    [string]$OutFile,
    [switch]$Check
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$scriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ModulePath) { $ModulePath = Join-Path $scriptFolder 'ServiceNowTableApi.psm1' }
if (-not $OutFile) { $OutFile = Join-Path $scriptFolder 'ServiceNowModuleConnector.xml' }

$ContractVersion = 1
$ContractFunctions = @('Get-OneIMConnectorManifest', 'Connect-OneIMConnectorSession', 'Disconnect-OneIMConnectorSession',
    'Get-OneIMConnectorObject', 'New-OneIMConnectorObject', 'Set-OneIMConnectorObject', 'Remove-OneIMConnectorObject')
$DataTypes = @('String', 'Int', 'Bool', 'DateTime')              # guide README.md:411
$AccessModes = @('Read', 'ReadWrite', 'InsertOnly')
$Operations = @('Insert', 'Update', 'Delete')
$IdentifierPattern = '^[A-Za-z][A-Za-z0-9]*$'
$PropertyPattern = '^[A-Za-z_][A-Za-z0-9_]*$'
# property names become parameter names of the generated commands: no automatic variables, no common parameters
$ReservedNames = @('_', 'args', 'input', 'host', 'error', 'matches', 'event', 'eventargs', 'eventsubscriber', 'sender', 'this',
    'true', 'false', 'null', 'home', 'pid', 'profile', 'pwd', 'switch', 'foreach', 'ofs', 'stacktrace', 'psitem', 'lastexitcode',
    'executioncontext', 'myinvocation', 'nestedpromptlevel', 'pscmdlet', 'psboundparameters', 'shellid', 'psculture',
    'psuiculture', 'psversiontable', 'pshome', 'psscriptroot', 'pscommandpath', 'psdebugcontext', 'isglobal',
    'verbose', 'debug', 'erroraction', 'warningaction', 'informationaction', 'errorvariable', 'warningvariable',
    'informationvariable', 'outvariable', 'outbuffer', 'pipelinevariable', 'whatif', 'confirm', 'progressaction')

#region manifest

function Import-ConnectorManifest
{
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Module not found: $Path" }
    $module = Import-Module -Name (Resolve-Path -LiteralPath $Path).Path -Force -PassThru -DisableNameChecking
    try
    {
        $missing = @($ContractFunctions | Where-Object { -not $module.ExportedFunctions.ContainsKey($_) })
        if ($missing.Count) { throw "Module $Path does not implement contract v${ContractVersion}: missing $($missing -join ', ')" }
        Get-OneIMConnectorManifest
    }
    finally { Remove-Module -ModuleInfo $module -Force }
}

function Get-MemberValue
{
    # manifest objects come from a third party: read members defensively (StrictMode-safe)
    param([object]$Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { return $Object[$Name] }
    $member = $Object.PSObject.Properties[$Name]
    if ($member) { return $member.Value }
    $null
}

function Test-PropertyDefinition
{
    param([Parameter(Mandatory = $true)][string]$ClassName, [object]$Property, [string[]]$ClassNames)
    $name = [string](Get-MemberValue $Property 'Name')
    $where = "$ClassName.$name"
    if ($name -notmatch $PropertyPattern) { "${ClassName}: property name '$name' must match $PropertyPattern" }
    if ($ReservedNames -contains $name.ToLowerInvariant()) { "${where}: reserved PowerShell name, rename it" }
    if ($DataTypes -notcontains (Get-MemberValue $Property 'Type')) { "${where}: Type must be one of $($DataTypes -join ', ')" }
    if ($AccessModes -notcontains (Get-MemberValue $Property 'Access')) { "${where}: Access must be one of $($AccessModes -join ', ')" }
    $reference = Get-MemberValue $Property 'Reference'
    if ($reference -and $ClassNames -notcontains $reference) { "${where}: Reference '$reference' is not a class of the manifest" }
}

function Test-ClassDefinition
{
    param([object]$Class, [string[]]$ClassNames)
    $name = [string](Get-MemberValue $Class 'Name')
    if ($name -notmatch $IdentifierPattern) { "class name '$name' must match $IdentifierPattern" }
    $properties = @(Get-MemberValue $Class 'Properties')
    if ($properties.Count -eq 0) { "${name}: no properties" }
    $propertyNames = @($properties | ForEach-Object { [string](Get-MemberValue $_ 'Name') })
    @($propertyNames | Group-Object | Where-Object { $_.Count -gt 1 }) | ForEach-Object { "${name}: duplicate property '$($_.Name)'" }
    foreach ($property in $properties) { Test-PropertyDefinition -ClassName $name -Property $property -ClassNames $ClassNames }

    $key = Get-MemberValue $Class 'Key'
    $keyProperty = $properties | Where-Object { (Get-MemberValue $_ 'Name') -eq $key }
    if (-not $keyProperty) { "${name}: Key '$key' is not a property" }
    elseif ((Get-MemberValue $keyProperty 'Type') -ne 'String' -or (Get-MemberValue $keyProperty 'Access') -ne 'Read') { "${name}: Key '$key' must be Type String, Access Read" }
    if ($propertyNames -notcontains (Get-MemberValue $Class 'Display')) { "${name}: Display '$(Get-MemberValue $Class 'Display')' is not a property" }
    $revision = Get-MemberValue $Class 'Revision'
    if ($revision -and $propertyNames -notcontains $revision) { "${name}: Revision '$revision' is not a property" }

    $classOperations = @(Get-MemberValue $Class 'Operations' | Where-Object { $_ })
    @($classOperations | Where-Object { $Operations -notcontains $_ }) | ForEach-Object { "${name}: unknown operation '$_' (allowed: $($Operations -join ', '))" }
    $writable = @($properties | Where-Object { (Get-MemberValue $_ 'Access') -ne 'Read' })
    if ($classOperations -contains 'Insert' -and $writable.Count -eq 0) { "${name}: Insert without writable properties" }
    if ($classOperations -contains 'Update' -and -not ($properties | Where-Object { (Get-MemberValue $_ 'Access') -eq 'ReadWrite' })) { "${name}: Update without ReadWrite properties" }
}

function Test-ConnectorManifest
{
    param([Parameter(Mandatory = $true)][object]$Manifest)
    $errors = New-Object System.Collections.Generic.List[string]
    if ((Get-MemberValue $Manifest 'ContractVersion') -ne $ContractVersion) { $errors.Add("ContractVersion must be $ContractVersion (got '$(Get-MemberValue $Manifest 'ContractVersion')')") }
    if ((Get-MemberValue $Manifest 'Id') -notmatch $IdentifierPattern) { $errors.Add("Id must match $IdentifierPattern") }
    if (-not (Get-MemberValue $Manifest 'Version')) { $errors.Add('Version is empty') }
    $classes = @(Get-MemberValue $Manifest 'Classes')
    if ($classes.Count -eq 0) { $errors.Add('no classes') }
    $classNames = @($classes | ForEach-Object { [string](Get-MemberValue $_ 'Name') })
    @($classNames | Group-Object | Where-Object { $_.Count -gt 1 }) | ForEach-Object { $errors.Add("duplicate class '$($_.Name)'") }
    foreach ($class in $classes) { foreach ($message in @(Test-ClassDefinition -Class $class -ClassNames $classNames)) { $errors.Add($message) } }
    if ($errors.Count) { throw "Manifest of $ModulePath is not valid:`n - $($errors -join "`n - ")" }
}

#endregion

#region XML text

function ConvertTo-XmlText { param([string]$Text) [Security.SecurityElement]::Escape($Text) }

function Get-ClassModel
{
    # normalized view of one manifest class, with the generated command names
    param([Parameter(Mandatory = $true)][object]$Class, [Parameter(Mandatory = $true)][string]$Prefix)
    $name = Get-MemberValue $Class 'Name'
    $properties = @(Get-MemberValue $Class 'Properties' | ForEach-Object {
            [PSCustomObject]@{
                Name = [string](Get-MemberValue $_ 'Name'); Type = [string](Get-MemberValue $_ 'Type'); Access = [string](Get-MemberValue $_ 'Access')
                Mandatory = [bool](Get-MemberValue $_ 'Mandatory'); Reference = Get-MemberValue $_ 'Reference'
            } })
    $operations = @(Get-MemberValue $Class 'Operations' | Where-Object { $_ } | Sort-Object)
    [PSCustomObject]@{
        Name = $name; Key = [string](Get-MemberValue $Class 'Key'); Display = [string](Get-MemberValue $Class 'Display')
        Revision = Get-MemberValue $Class 'Revision'; Operations = $operations; Properties = $properties
        Get = "Get-$Prefix$name"; New = "New-$Prefix$name"; Set = "Set-$Prefix$name"; Remove = "Remove-$Prefix$name"
        InsertProperties = @($properties | Where-Object { $operations -contains 'Insert' -and $_.Access -ne 'Read' })
        UpdateProperties = @($properties | Where-Object { $operations -contains 'Update' -and $_.Access -eq 'ReadWrite' })
    }
}

function New-CustomCommandXml
{
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][string]$Code, [string]$Comment)
    $lines = @()
    if ($Comment) { $lines += "            <!-- $(ConvertTo-XmlText $Comment) -->" }
    $lines += "            <CustomCommand Name=`"$Name`">"
    $lines += '            <![CDATA['
    $lines += ($Code.Trim("`r", "`n") -split "`r?`n" | ForEach-Object { "                $_".TrimEnd() })
    $lines += '            ]]>'
    $lines += '            </CustomCommand>'
    $lines += ''
    $lines
}

function New-ClassCommandsXml
{
    # thin per-class wrappers: the connector maps properties to parameters by name, so each class needs its own
    # parameter list; all logic stays in the module
    param([Parameter(Mandatory = $true)][PSObject]$Model)
    $c = $Model
    New-CustomCommandXml -Name $c.Get -Comment "===== $($c.Name) =====" -Code @"
# without $($c.Key): listing (all properties); with $($c.Key): one object
param([string]`$$($c.Key))
Get-OneIMConnectorObject -Class '$($c.Name)' -Key `$$($c.Key)
"@
    if ($c.Operations -contains 'Insert')
    {
        $params = ($c.InsertProperties | ForEach-Object { "`$$($_.Name)" }) -join ', '
        New-CustomCommandXml -Name $c.New -Code @"
param($params)
New-OneIMConnectorObject -Class '$($c.Name)' -Values `$PSBoundParameters
"@
    }
    if ($c.Operations -contains 'Update')
    {
        $params = (@("[string]`$$($c.Key)") + @($c.UpdateProperties | ForEach-Object { "`$$($_.Name)" })) -join ', '
        New-CustomCommandXml -Name $c.Set -Code @"
# only bound parameters are sent; `$null clears the field
param($params)
`$null = Set-OneIMConnectorObject -Class '$($c.Name)' -Key `$$($c.Key) -Values `$PSBoundParameters
"@
    }
    if ($c.Operations -contains 'Delete')
    {
        New-CustomCommandXml -Name $c.Remove -Code @"
param([string]`$$($c.Key))
`$null = Remove-OneIMConnectorObject -Class '$($c.Name)' -Key `$$($c.Key)
"@
    }
}

function Get-ExpectedSchemaCode
{
    # what this XML was generated from: checked against the loaded module on every connect
    param([Parameter(Mandatory = $true)][object[]]$Models)
    $lines = @('@{')
    foreach ($c in $Models)
    {
        $properties = ($c.Properties | ForEach-Object { "'$($_.Name)' = '$($_.Type)/$($_.Access)'" }) -join '; '
        $lines += "    '$($c.Name)' = @{ Key = '$($c.Key)'; Operations = '$($c.Operations -join ',')'; Properties = @{ $properties } }"
    }
    $lines += '}'
    $lines -join "`n"
}

function New-ConnectCommandsXml
{
    param([Parameter(Mandatory = $true)][string]$Prefix, [Parameter(Mandatory = $true)][object[]]$Models)
    $functions = ($ContractFunctions | ForEach-Object { "'$_'" }) -join ', '
    $expected = Get-ExpectedSchemaCode -Models $Models
    New-CustomCommandXml -Name "Test-${Prefix}Module" -Comment 'module manifest vs this XML: removed/changed classes or properties stop the connect, new ones are only logged' -Code @"
param([Parameter(Mandatory=`$true)][object]`$Manifest)
`$expected = $expected
`$actual = @{}
foreach (`$class in @(`$Manifest.Classes))
{
    `$properties = @{}
    foreach (`$p in @(`$class.Properties)) { `$properties[`$p.Name] = "`$(`$p.Type)/`$(`$p.Access)" }
    `$actual[`$class.Name] = @{ Key = `$class.Key; Operations = (@(`$class.Operations | Where-Object { `$_ } | Sort-Object) -join ','); Properties = `$properties }
}
`$breaking = New-Object System.Collections.Generic.List[string]
`$added = New-Object System.Collections.Generic.List[string]
foreach (`$name in `$expected.Keys)
{
    if (-not `$actual.ContainsKey(`$name)) { `$breaking.Add("class `$name removed"); continue }
    `$e = `$expected[`$name]; `$a = `$actual[`$name]
    if (`$e.Key -ne `$a.Key) { `$breaking.Add("`$name key `$(`$e.Key) -> `$(`$a.Key)") }
    if (`$e.Operations -ne `$a.Operations) { `$breaking.Add("`$name operations '`$(`$e.Operations)' -> '`$(`$a.Operations)'") }
    foreach (`$p in `$e.Properties.Keys)
    {
        if (-not `$a.Properties.ContainsKey(`$p)) { `$breaking.Add("`$name.`$p removed") }
        elseif (`$a.Properties[`$p] -ne `$e.Properties[`$p]) { `$breaking.Add("`$name.`$p `$(`$e.Properties[`$p]) -> `$(`$a.Properties[`$p])") }
    }
    foreach (`$p in `$a.Properties.Keys) { if (-not `$e.Properties.ContainsKey(`$p)) { `$added.Add("`$name.`$p") } }
}
foreach (`$name in `$actual.Keys) { if (-not `$expected.ContainsKey(`$name)) { `$added.Add("class `$name") } }
if (`$breaking.Count)
{
    throw "Connector module is not compatible with this connector XML: `$(`$breaking -join '; '). Regenerate the XML with New-ConnectorXmlFromModule.ps1, load it in the connection and update the schema."
}
if (`$added.Count)
{
    Write-Warning "Connector module offers `$(`$added.Count) classes/properties not in this XML (`$(`$added -join ', ')): regenerate the XML and update the schema to use them."
}
"@
    New-CustomCommandXml -Name "Connect-$Prefix" -Comment 'imports the connector module from ModuleLocation, checks the contract, then connects' -Code @"
param([string]`$InstanceUrl, [string]`$Username, [SecureString]`$Password, [string]`$Options, [string]`$ModuleLocation)

if ([string]::IsNullOrWhiteSpace(`$ModuleLocation)) { throw "Connection parameter ModuleLocation is empty: set the full path of the connector module (.psm1)" }
`$path = `$ModuleLocation.Trim().Trim('"')
if (`$path -notmatch '\.psm1$') { `$path = "`$path.psm1" }   # guide convention: path without the suffix
if (-not (Test-Path -LiteralPath `$path -PathType Leaf))
{
    throw "Connector module not found: '`$path' on `$env:COMPUTERNAME (user `$env:USERNAME). It must exist at this path on every Job server and admin client that uses the connection."
}
# -Global: visible to the other custom commands; -Force: reloaded on every connect, so a new module applies to the next sync
Import-Module -Name `$path -Global -Force -DisableNameChecking -ErrorAction Stop
foreach (`$fn in @($functions))
{
    if (-not (Get-Command `$fn -ErrorAction SilentlyContinue)) { throw "Module '`$path' does not implement contract v${ContractVersion}: `$fn is missing" }
}
`$manifest = Get-OneIMConnectorManifest
if (`$manifest.ContractVersion -ne $ContractVersion) { throw "Module '`$path' implements contract `$(`$manifest.ContractVersion), this XML needs contract ${ContractVersion}" }
Test-${Prefix}Module -Manifest `$manifest
Write-Host "Connector module `$path (`$(`$manifest.Id) `$(`$manifest.Version), contract `$(`$manifest.ContractVersion)) on `$env:COMPUTERNAME, PowerShell `$(`$PSVersionTable.PSVersion)"
`$null = Connect-OneIMConnectorSession -InstanceUrl `$InstanceUrl -Username `$Username -Password `$Password -Options `$Options
"@
    New-CustomCommandXml -Name "Disconnect-$Prefix" -Code @"
if (Get-Command Disconnect-OneIMConnectorSession -ErrorAction SilentlyContinue) { `$null = Disconnect-OneIMConnectorSession }
"@
}

function New-PropertyXml
{
    param([Parameter(Mandatory = $true)][PSObject]$Model, [Parameter(Mandatory = $true)][PSObject]$Property, [Parameter(Mandatory = $true)][hashtable]$KeyByClass)
    $c = $Model; $p = $Property
    $isKey = $p.Name -eq $c.Key
    $insert = @($c.InsertProperties | Where-Object { $_.Name -eq $p.Name }).Count -gt 0
    $update = @($c.UpdateProperties | Where-Object { $_.Name -eq $p.Name }).Count -gt 0

    $attributes = "Name=`"$($p.Name)`" DataType=`"$($p.Type)`""
    if ($isKey -or $p.Mandatory) { $attributes += ' IsMandatory="true"' }
    if ($isKey) { $attributes += ' IsUniqueKey="true"' }
    if ($p.Name -eq $c.Display) { $attributes += ' IsDisplay="true"' }
    if ($p.Name -eq $c.Revision) { $attributes += ' IsRevision="true"' }
    if ($isKey -or (-not $insert -and -not $update)) { $attributes += ' AccessConstraint="ReadOnly"' }
    elseif ($insert -and -not $update) { $attributes += ' AccessConstraint="ReadAndInsertOnly"' }

    $lines = @("                <Property $attributes>")
    if ($p.Reference)
    {
        $lines += '                    <ReferenceTargets>'
        $lines += "                        <ReferenceTarget Class=`"$($p.Reference)`" Property=`"$($KeyByClass[$p.Reference])`" />"
        $lines += '                    </ReferenceTargets>'
    }
    $lines += '                    <ReturnBindings>'
    $lines += "                        <Bind CommandResultOf=`"$($c.Get)`" Path=`"$($p.Name)`" />"
    if ($c.Operations -contains 'Insert') { $lines += "                        <Bind CommandResultOf=`"$($c.New)`" Path=`"$($p.Name)`" />" }
    $lines += '                    </ReturnBindings>'

    $maps = @()
    if ($isKey)
    {
        $maps += "<Map ToCommand=`"$($c.Get)`" Parameter=`"$($p.Name)`" />"
        if ($c.Operations -contains 'Update') { $maps += "<Map ToCommand=`"$($c.Set)`" Parameter=`"$($p.Name)`" />" }
        if ($c.Operations -contains 'Delete') { $maps += "<Map ToCommand=`"$($c.Remove)`" Parameter=`"$($p.Name)`" />" }
    }
    if ($insert) { $maps += "<Map ToCommand=`"$($c.New)`" Parameter=`"$($p.Name)`" />" }
    if ($update) { $maps += "<Map ToCommand=`"$($c.Set)`" Parameter=`"$($p.Name)`" />" }
    if ($maps.Count)
    {
        $lines += '                    <CommandMappings>'
        $lines += ($maps | ForEach-Object { "                        $_" })
        $lines += '                    </CommandMappings>'
    }
    if ($insert -or $update)
    {
        $lines += '                    <ModifiedBy>'
        if ($insert) { $lines += "                        <ModBy Command=`"$($c.New)`" Method=`"Insert`" />" }
        if ($update) { $lines += "                        <ModBy Command=`"$($c.Set)`" Method=`"Update`" />" }
        $lines += '                    </ModifiedBy>'
    }
    $lines += '                </Property>'
    $lines
}

function New-ClassSchemaXml
{
    param([Parameter(Mandatory = $true)][PSObject]$Model, [Parameter(Mandatory = $true)][hashtable]$KeyByClass)
    $c = $Model
    $lines = @("        <Class Name=`"$($c.Name)`">", '            <Properties>')
    foreach ($p in $c.Properties) { $lines += New-PropertyXml -Model $c -Property $p -KeyByClass $KeyByClass }
    $lines += '            </Properties>'
    $lines += '            <ReadConfiguration>'
    $lines += '                <!-- the listing returns every property: the module serves the per-object reload from its listing cache -->'
    $lines += "                <ListingCommand Command=`"$($c.Get)`" />"
    $lines += '                <CommandSequence>'
    $lines += "                    <Item Command=`"$($c.Get)`" Order=`"1`" />"
    $lines += '                </CommandSequence>'
    $lines += '            </ReadConfiguration>'
    if ($c.Operations.Count)
    {
        $lines += '            <MethodConfiguration>'
        if ($c.Operations -contains 'Insert') { $lines += '                <Method Name="Insert">', '                    <CommandSequence>', "                        <Item Command=`"$($c.New)`" Order=`"1`" />", '                    </CommandSequence>', '                </Method>' }
        if ($c.Operations -contains 'Update') { $lines += '                <Method Name="Update">', '                    <CommandSequence>', "                        <Item Command=`"$($c.Set)`" Order=`"1`" Condition=`"ModificationExists`" />", '                    </CommandSequence>', '                </Method>' }
        if ($c.Operations -contains 'Delete') { $lines += '                <Method Name="Delete">', '                    <CommandSequence>', "                        <Item Command=`"$($c.Remove)`" Order=`"1`" />", '                    </CommandSequence>', '                </Method>' }
        $lines += '            </MethodConfiguration>'
    }
    $lines += '        </Class>'
    $lines += ''
    $lines
}

function New-ConnectorXml
{
    param([Parameter(Mandatory = $true)][object]$Manifest, [Parameter(Mandatory = $true)][string]$ModuleFileName)
    $prefix = "OneIM$($Manifest.Id)"
    $models = @($Manifest.Classes | ForEach-Object { Get-ClassModel -Class $_ -Prefix $prefix })
    $keyByClass = @{}
    foreach ($m in $models) { $keyByClass[$m.Name] = $m.Key }
    $description = ConvertTo-XmlText "$($Manifest.Description) - module $ModuleFileName $($Manifest.Version)"

    $lines = @(
        '<?xml version="1.0" encoding="utf-8" ?>'
        "<!-- GENERATED by New-ConnectorXmlFromModule.ps1 from $ModuleFileName (version $($Manifest.Version), contract $ContractVersion). Do not edit by hand: change the module and regenerate. -->"
        "<PowershellConnectorDefinition Id=`"$($Manifest.Id)`" Version=`"$($Manifest.Version)`" Description=`"$description`">"
        ''
        '    <PluginAssemblies/>'
        ''
        '    <ConnectionParameters>'
        '        <ConnectionParameter Name="InstanceUrl" Description="Target system address (mandatory; format defined by the connector module)" />'
        '        <ConnectionParameter Name="Username" Description="Account or client id used by the connector module" />'
        '        <ConnectionParameter Name="Password" Description="Secret used by the connector module (password or client secret)" IsSensibleData="true" />'
        '        <ConnectionParameter Name="Options" Description="Module options Name=Value;Name=Value (see the module README); empty = defaults" />'
        "        <ConnectionParameter Name=`"ModuleLocation`" Description=`"Full path of $ModuleFileName, identical on every Job server and admin client`" />"
        '    </ConnectionParameters>'
        ''
        '    <Initialization>'
        '        <!--'
        "            All logic is in the connector module (ModuleLocation), imported by Connect-$prefix on every connect."
        '            The commands below only forward to the module. RULE: write to the output stream only what the connector must read.'
        '        -->'
        '        <CustomCommands>'
        ''
    )
    $lines += New-ConnectCommandsXml -Prefix $prefix -Models $models
    foreach ($m in $models) { $lines += New-ClassCommandsXml -Model $m }
    $lines += @(
        '        </CustomCommands>'
        ''
        '        <!-- module functions are called only from custom commands (README layout with Import-Module in the sequence failed in the 9.2 wizard) -->'
        '        <PredefinedCommands/>'
        ''
        '        <EnvironmentInitialization>'
        '            <Connect>'
        '                <CommandSequence>'
        "                    <Item Command=`"Connect-$prefix`" Order=`"1`">"
        '                        <SetParameter Param="InstanceUrl" Source="ConnectionParameter" Value="InstanceUrl" />'
        '                        <SetParameter Param="Username" Source="ConnectionParameter" Value="Username" />'
        '                        <SetParameter Param="Password" Source="ConnectionParameter" Value="Password" ConversionMethod="ToSecureString" />'
        '                        <SetParameter Param="Options" Source="ConnectionParameter" Value="Options" />'
        '                        <SetParameter Param="ModuleLocation" Source="ConnectionParameter" Value="ModuleLocation" />'
        '                    </Item>'
        '                </CommandSequence>'
        '            </Connect>'
        '            <Disconnect>'
        '                <CommandSequence>'
        "                    <Item Command=`"Disconnect-$prefix`" Order=`"1`" />"
        '                </CommandSequence>'
        '            </Disconnect>'
        '        </EnvironmentInitialization>'
        '    </Initialization>'
        ''
        '    <Schema>'
        ''
    )
    foreach ($m in $models) { $lines += New-ClassSchemaXml -Model $m -KeyByClass $keyByClass }
    $lines += '    </Schema>'
    $lines += '</PowershellConnectorDefinition>'
    ($lines -join "`r`n") + "`r`n"
}

#endregion

$manifest = Import-ConnectorManifest -Path $ModulePath
Test-ConnectorManifest -Manifest $manifest
$xml = New-ConnectorXml -Manifest $manifest -ModuleFileName (Split-Path -Leaf $ModulePath)
$null = [xml]$xml   # well-formed or throw

if ($Check)
{
    $current = ''
    if (Test-Path -LiteralPath $OutFile) { $current = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $OutFile).Path) }
    if ($current -ceq $xml) { Write-Host "XML up to date with $(Split-Path -Leaf $ModulePath)"; exit 0 }
    Write-Host "XML NOT up to date with $(Split-Path -Leaf $ModulePath): run New-ConnectorXmlFromModule.ps1, then load the XML in the connection and update the schema"
    exit 1
}

$target = [IO.Path]::GetFullPath($OutFile)
if (Test-Path -LiteralPath $target) { Copy-Item -LiteralPath $target -Destination "$target.bak" -Force }
[IO.File]::WriteAllText($target, $xml, (New-Object Text.UTF8Encoding $false))
$classCount = @($manifest.Classes).Count
Write-Host "Generated $target from $(Split-Path -Leaf $ModulePath) $($manifest.Version): $classCount classes"
