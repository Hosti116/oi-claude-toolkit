<#
    Standalone smoke test for the CustomCommands in ServiceNowConnector.xml (Windows PowerShell 5.1 and PowerShell 7).
    Run outside Identity Manager to debug, only against a non-production instance.
    Reads every class defined in the XML; with -WriteTests also creates/updates/deletes a test department.
    Example: .\Test-ServiceNowConnector.ps1 -InstanceUrl <instance> -Username <integration user> -WriteTests
#>
param(
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$InstanceUrl,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Username,
    [SecureString]$Password = (Read-Host -AsSecureString "Password"),
    [switch]$WriteTests,  # also runs create/update/delete on a test department
    # module layout: -XmlFile ServiceNowConnector.Module.xml (ModuleLocation defaults to the .psm1 next to this script)
    [string]$XmlFile = "ServiceNowConnector.xml",
    [string]$ModuleLocation = (Join-Path $PSScriptRoot "ServiceNowConnector.psm1")
)

$VerbosePreference = "Continue"
# load the CustomCommands straight from the connector XML (same code OIM runs)
$def = [xml](Get-Content (Join-Path $PSScriptRoot $XmlFile) -Raw -Encoding UTF8)
foreach ($cc in $def.PowershellConnectorDefinition.Initialization.CustomCommands.CustomCommand)
{
    Set-Item -Path "function:global:$($cc.Name)" -Value ([scriptblock]::Create($cc.'#cdata-section'))
}

$connect = @{ InstanceUrl = $InstanceUrl; Username = $Username; Password = $Password }
if ($def.PowershellConnectorDefinition.ConnectionParameters.ConnectionParameter | Where-Object { $_.Name -eq "ModuleLocation" }) { $connect.ModuleLocation = $ModuleLocation }
Connect-OneIMSnow @connect

foreach ($class in $def.PowershellConnectorDefinition.Schema.Class)
{
    $get = $class.ReadConfiguration.ListingCommand.Command
    $listProps = $class.ReadConfiguration.ListingCommand.SetParameter.Value -split ","
    "--- $($class.Name): list ---"
    $all = @(& $get -PropertiesToRequest $listProps)
    "$($all.Count) records"
    $all | Select-Object -First 5 | Format-Table
    if ($all.Count -gt 0)
    {
        "--- $($class.Name): single (all fields) ---"
        & $get -sys_id $all[0].sys_id | Format-List
    }
}

if ($WriteTests)
{
    "--- create ---"
    $new = New-OneIMSnowDepartment -name "OneIM test dept" -description "created by smoke test" -head_count 3
    $new | Format-List
    "--- update ---"
    Set-OneIMSnowDepartment -sys_id $new.sys_id -description "updated" -head_count 5
    Get-OneIMSnowDepartment -sys_id $new.sys_id | Format-List
    "--- delete (twice: second must not fail) ---"
    Remove-OneIMSnowDepartment -sys_id $new.sys_id
    Remove-OneIMSnowDepartment -sys_id $new.sys_id
}

Disconnect-OneIMSnow
