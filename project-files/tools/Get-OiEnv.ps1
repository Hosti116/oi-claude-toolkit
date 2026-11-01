#Requires -Version 7.6
<#
.SYNOPSIS
Returns the environment settings from oi-env.psd1 at the workspace root.

.PARAMETER Require
Dotted setting names that must have a value, for example Oim.AppServer. A missing one stops the caller.
#>
[CmdletBinding()]
param(
    [string[]]$Require = @(),
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$settingsFile = Join-Path $RepoRoot 'oi-env.psd1'
if (-not (Test-Path -LiteralPath $settingsFile)) {
    throw "Missing $settingsFile. Create it from the oi-claude-toolkit template (project-files/oi-env.template.psd1)."
}
$settings = Import-PowerShellDataFile -LiteralPath $settingsFile

foreach ($name in $Require) {
    $value = $settings
    foreach ($part in $name.Split('.')) {
        $value = if ($value -is [hashtable] -and $value.ContainsKey($part)) { $value[$part] } else { $null }
    }
    if ($null -eq $value -or "$value" -eq '') { throw "Setting '$name' is empty in $settingsFile." }
}

$settings
