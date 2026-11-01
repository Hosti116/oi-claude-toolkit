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

# Settings first: a missing marketplace must stop the update before any file changes.
$null = Update-OiSettingsFile -ToolkitRoot $PSScriptRoot -WorkspaceRoot $root -Repo $MarketplaceRepo -Ref $Ref -DryRun:$DryRun
# A seed file recreated here gets the safe type: the original value is gone, and non-production must be declared.
$tokens = @{ '__WORKSPACE_NAME__' = (Split-Path -Leaf $root); '__ENV_TYPE__' = 'PRODUZIONE' }
$results = Sync-OiFile -ToolkitRoot $PSScriptRoot -WorkspaceRoot $root -Tokens $tokens -DryRun:$DryRun

$results | Where-Object Action -in 'Create', 'Update', 'LocalChange', 'NoLongerInToolkit'
