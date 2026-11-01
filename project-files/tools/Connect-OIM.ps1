#Requires -Version 7.6
param(
    [string]$AppServer,
    [string[]]$ModulesToAdd = @('QER')
)
$oiEnv = & (Join-Path $PSScriptRoot 'Get-OiEnv.ps1') -Require 'Oim.SecretName'
if (-not $AppServer) { $AppServer = (& (Join-Path $PSScriptRoot 'Get-OiEnv.ps1') -Require 'Oim.AppServer').Oim.AppServer }
Import-Module (Join-Path $PSScriptRoot '..\vendor\IdentityManager.PoSh\PSIdentityManagerUtils') -Force
$cred = Get-Secret -Name $oiEnv.Oim.SecretName
$auth = "Module=DialogUser;User=$($cred.UserName);Password=$($cred.GetNetworkCredential().Password)"
$connectionString = "url=$AppServer"
if ($oiEnv.Oim.AcceptSelfSigned) { $connectionString += ';AcceptSelfSigned=true' }
$Global:OIMSession = New-IdentityManagerSession -ConnectionString $connectionString `
    -AuthenticationString $auth -ModulesToAdd $ModulesToAdd
Write-Host "Connesso a $AppServer" -ForegroundColor Green
