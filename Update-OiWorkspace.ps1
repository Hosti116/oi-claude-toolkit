#Requires -Version 7.6
<#
.SYNOPSIS
Updates a workspace from this toolkit checkout. Files changed locally are kept and reported, never overwritten.

.PARAMETER Ref
Marketplace ref written to .claude/settings.json. Default: the tag of this toolkit version.

.PARAMETER DryRun
Reports what would change and writes nothing.

.EXAMPLE
pwsh -NoProfile -File Update-OiWorkspace.ps1 -Path C:\oi-env-test -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [string]$Ref,
    [ValidatePattern('^[\w.-]+/[\w.-]+$')][string]$MarketplaceRepo,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/OiWorkspace.psm1') -Force

if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "Workspace not found: $Path" }
$root = (Resolve-Path -LiteralPath $Path).Path
$info = Get-OiToolkitInfo -ToolkitRoot $PSScriptRoot
if (-not $Ref) { $Ref = "v$($info.Version)" }

$results = Sync-OiFile -ToolkitRoot $PSScriptRoot -WorkspaceRoot $root -DryRun:$DryRun
$null = Update-OiSettingsFile -ToolkitRoot $PSScriptRoot -WorkspaceRoot $root -Repo $MarketplaceRepo -Ref $Ref -DryRun:$DryRun

$results | Where-Object Action -in 'Create', 'Update', 'LocalChange', 'NoLongerInToolkit'
