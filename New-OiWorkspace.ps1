#Requires -Version 7.6
<#
.SYNOPSIS
Creates a One Identity workspace from this toolkit. Existing files are never overwritten.

.PARAMETER EnvironmentType
Written to the Ambiente section of CLAUDE.md. The default is PRODUZIONE: non-production must be a deliberate choice.

.EXAMPLE
pwsh -NoProfile -File New-OiWorkspace.ps1 -Path C:\oi-env-test -EnvironmentType TEST `
    -MarketplaceRepo owner/oi-claude-toolkit -ReferenceRepoUrl https://github.com/owner/oi-reference
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][ValidatePattern('^[\w.-]+/[\w.-]+$')][string]$MarketplaceRepo,
    [ValidateSet('PRODUZIONE', 'LAB', 'TEST', 'DEMO')][string]$EnvironmentType = 'PRODUZIONE',
    [string]$Name,
    [string]$Ref,
    [string]$ReferenceRepoUrl,
    [switch]$SkipSubmodules
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/OiWorkspace.psm1') -Force

$UpstreamSubmodules = [ordered]@{
    'vendor/IdentityManager.PoSh'                 = 'https://github.com/OneIdentity/IdentityManager.PoSh'
    'vendor/IdentityManager.PoSh-Connector-Guide' = 'https://github.com/OneIdentity/IdentityManager.PoSh-Connector-Guide'
    'vendor/SafeguardCustomPlatform'              = 'https://github.com/OneIdentity/SafeguardCustomPlatform'
    'vendor/SafeguardAutomation'                  = 'https://github.com/OneIdentity/SafeguardAutomation'
}
$WorkspaceFolders = 'oim/designer', 'oim/scripts', 'spp/custom-platforms', 'sps', 'sync/connectors', 'secrets', '.sg-state'

function Add-OiSubmodule([string]$Root, [string]$SubmodulePath, [string]$Url) {
    if (Test-Path -LiteralPath (Join-Path $Root $SubmodulePath)) { Write-Host "Submodule ${SubmodulePath}: already there"; return }
    git -C $Root submodule add $Url $SubmodulePath
    if ($LASTEXITCODE -ne 0) { throw "git submodule add failed for $SubmodulePath." }
}

if (-not $SkipSubmodules -and -not $ReferenceRepoUrl) { throw 'Pass -ReferenceRepoUrl, or -SkipSubmodules to add the submodules later.' }

$root = New-Item -ItemType Directory -Force -Path $Path | Select-Object -ExpandProperty FullName
if (-not $Name) { $Name = Split-Path -Leaf $root }
if (-not (Test-Path -LiteralPath (Join-Path $root '.git'))) {
    git -C $root init --quiet --initial-branch=main
    if ($LASTEXITCODE -ne 0) { throw "git init failed in $root." }
}
foreach ($folder in $WorkspaceFolders) { $null = New-Item -ItemType Directory -Force -Path (Join-Path $root $folder) }

$info = Get-OiToolkitInfo -ToolkitRoot $PSScriptRoot
if (-not $Ref) { $Ref = "v$($info.Version)" }
$tokens = @{ '__WORKSPACE_NAME__' = $Name; '__ENV_TYPE__' = $EnvironmentType }
$results = Sync-OiFile -ToolkitRoot $PSScriptRoot -WorkspaceRoot $root -Tokens $tokens
$null = Update-OiSettingsFile -ToolkitRoot $PSScriptRoot -WorkspaceRoot $root -Repo $MarketplaceRepo -Ref $Ref

if (-not $SkipSubmodules) {
    foreach ($submodule in $UpstreamSubmodules.GetEnumerator()) { Add-OiSubmodule $root $submodule.Key $submodule.Value }
    Add-OiSubmodule $root 'docs/reference' $ReferenceRepoUrl
}

$results | Group-Object Action | ForEach-Object { Write-Host ("{0,-18} {1}" -f $_.Name, $_.Count) }
Write-Host "Workspace ready: $root (Tipo: $EnvironmentType). Fill in oi-env.psd1 and the Ambiente section of CLAUDE.md, then start claude there and trust the folder."
