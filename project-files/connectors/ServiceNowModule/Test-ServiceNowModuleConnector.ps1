<#
    Smoke test of the module connector against a REAL ServiceNow instance - NON-PRODUCTION ONLY.
    Loads the custom commands from the generated XML (same code Identity Manager runs) and the module from ModuleLocation.
    Read-only by default: lists every class and reloads one object per class.
    -WriteTests also creates, updates and deletes one test department.
    Windows PowerShell 5.1 and PowerShell 7. The password is asked interactively and never written anywhere.

    Example: .\Test-ServiceNowModuleConnector.ps1 -InstanceUrl <dev instance> -Username <integration user>
#>
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$InstanceUrl,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Username,
    [SecureString]$Password,
    [string]$Options,
    [string]$ModuleLocation,   # default: ServiceNowTableApi.psm1 next to this script
    [ValidateRange(1, 100)][int]$Show = 3,
    [switch]$WriteTests
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ModuleLocation) { $ModuleLocation = Join-Path $here 'ServiceNowTableApi.psm1' }
if (-not $Password) { $Password = Read-Host -AsSecureString "Password for $Username" }

$def = [xml](Get-Content -LiteralPath (Join-Path $here 'ServiceNowModuleConnector.xml') -Raw -Encoding UTF8)
foreach ($cc in $def.PowershellConnectorDefinition.Initialization.CustomCommands.CustomCommand)
{
    Set-Item -Path "function:global:$($cc.Name)" -Value ([scriptblock]::Create($cc.'#cdata-section'))
}
$prefix = $def.PowershellConnectorDefinition.Initialization.EnvironmentInitialization.Connect.CommandSequence.Item.Command -replace '^Connect-', ''

& "Connect-$prefix" -InstanceUrl $InstanceUrl -Username $Username -Password $Password -Options $Options -ModuleLocation $ModuleLocation
try
{
    foreach ($class in $def.PowershellConnectorDefinition.Schema.Class)
    {
        $get = $class.ReadConfiguration.ListingCommand.Command
        $key = $class.SelectSingleNode('Properties/Property[@IsUniqueKey="true"]').Name
        "--- $($class.Name)"
        $all = @(& $get)
        "$($all.Count) objects"
        $all | Select-Object -First $Show | Format-Table -AutoSize | Out-String -Width 200
        if ($all.Count -gt 0) { & $get -$key $all[0].$key | Format-List | Out-String -Width 200 }
    }

    if ($WriteTests)
    {
        "--- write tests (Department)"
        $new = New-OneIMServiceNowDepartment -name 'OneIM module connector test' -description 'created by Test-ServiceNowModuleConnector.ps1' -head_count 3
        $new | Format-List | Out-String
        Set-OneIMServiceNowDepartment -sys_id $new.sys_id -description 'updated' -head_count 5
        Get-OneIMServiceNowDepartment -sys_id $new.sys_id | Format-List | Out-String
        Remove-OneIMServiceNowDepartment -sys_id $new.sys_id
        Remove-OneIMServiceNowDepartment -sys_id $new.sys_id   # second delete must only warn
    }
}
finally { & "Disconnect-$prefix" }
