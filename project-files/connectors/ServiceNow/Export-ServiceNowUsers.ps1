<#
.SYNOPSIS
    Exports every sys_user record of a ServiceNow instance to CSV (sys_id, UPN and identity fields), to prepare
    object matching with One Identity Manager. Read-only. Windows PowerShell 5.1 and PowerShell 7.
.DESCRIPTION
    -InstanceUrl is mandatory: no instance is stored in this file. Credentials only via -Credential or
    Get-Credential, never saved. The default UPN field u_upn is a custom field used as an example: set -UpnField
    (and -Fields) to the field that holds the UPN on your instance.
.EXAMPLE
    .\Export-ServiceNowUsers.ps1 -InstanceUrl <instance> -OutFile C:\Temp\snow-users.csv -Query "active=true"
#>
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$InstanceUrl,
    [System.Management.Automation.PSCredential]$Credential,
    [string]$OutFile = (Join-Path $PSScriptRoot ("ServiceNowUsers_{0:yyyyMMdd_HHmmss}.csv" -f (Get-Date))),
    [string[]]$Fields = @("sys_id", "u_upn", "user_name", "email", "first_name", "last_name", "name", "employee_number", "active", "sys_created_on", "sys_updated_on"),
    # field used for the empty/duplicate summary (custom on most instances)
    [ValidateNotNullOrEmpty()][string]$UpnField = "u_upn",
    [string]$Query,
    [ValidateRange(1, 10000)][int]$PageSize = 1000
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$base = $InstanceUrl.Trim().TrimEnd("/")
if ($base -notmatch "^https?://")
{
    if ($base -notmatch "\.") { $base = "$base.service-now.com" }
    $base = "https://$base"
}

if (-not $Credential) { $Credential = Get-Credential -Message "ServiceNow user with read access to sys_user ($base)" }
$pair = "{0}:{1}" -f $Credential.UserName, $Credential.GetNetworkCredential().Password
$headers = @{
    Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
    Accept        = "application/json"
}
$pair = $null

# sys_id is the matching key; stable ordering is required for offset paging
$Fields = @("sys_id") + @($Fields | Where-Object { $_ -ne "sys_id" })
if ($Fields -notcontains $UpnField) { $Fields += $UpnField }
$sysQuery = "ORDERBYsys_id"
if ($Query) { $sysQuery = "$Query^$sysQuery" }

$rows = New-Object System.Collections.Generic.List[object]
$offset = 0
do
{
    $uri = "$base/api/now/table/sys_user?sysparm_fields=$($Fields -join ',')&sysparm_exclude_reference_link=true&sysparm_display_value=false" +
           "&sysparm_limit=$PageSize&sysparm_offset=$offset&sysparm_query=$([uri]::EscapeDataString($sysQuery))"
    $res = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -UseBasicParsing
    $page = @($res.result)
    foreach ($r in $page)
    {
        $row = [ordered]@{}
        foreach ($f in $Fields) { $row[$f] = if ($r.PSObject.Properties[$f]) { "$($r.$f)" } else { "" } }
        $rows.Add([pscustomobject]$row)
    }
    Write-Host ("Read {0} users..." -f $rows.Count)
    $offset += $PageSize
} while ($page.Count -eq $PageSize)

# ';' and UTF-8 with BOM: opens correctly in Excel with Italian settings
# (UTF8 means no BOM on PowerShell 7, with BOM on 5.1)
$csvEncoding = if ($PSVersionTable.PSVersion.Major -ge 6) { "utf8BOM" } else { "UTF8" }
$rows | Export-Csv -Path $OutFile -NoTypeInformation -Delimiter ';' -Encoding $csvEncoding

# summary for matching on the UPN field (case- and trailing-space-insensitive, unlike a case-sensitive matching rule)
$emptyUpn = @($rows | Where-Object { [string]::IsNullOrWhiteSpace($_.$UpnField) }).Count
$dupUpn = @($rows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.$UpnField) } |
    Group-Object { $_.$UpnField.Trim().ToLowerInvariant() } | Where-Object { $_.Count -gt 1 })

Write-Host ""
Write-Host "Users exported   : $($rows.Count)"
Write-Host "Empty $UpnField  : $emptyUpn"
Write-Host "Duplicated $UpnField : $($dupUpn.Count) value(s)"
foreach ($d in $dupUpn) { Write-Host ("  {0} -> {1}" -f $d.Name, (($d.Group | ForEach-Object { $_.sys_id }) -join ', ')) }
Write-Host "File             : $OutFile"
